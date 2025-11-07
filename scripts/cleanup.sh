#!/bin/bash
# =============================================================================
# AWS Batch Cleanup Script
# =============================================================================
# Clean up AWS Batch resources
#
# Usage:
#   ./cleanup.sh [terraform|cloudformation] [options]
#
# WARNING: This will delete all resources created by the deployment!
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
PROJECT_NAME="${PROJECT_NAME:-batch-jobs}"

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

confirm_action() {
    echo -e "\n${RED}WARNING: This will delete all AWS Batch resources!${NC}"
    echo -e "${YELLOW}This action cannot be undone!${NC}\n"
    echo -e "Type 'DELETE' to confirm: "
    read -r confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
}

cleanup_terraform() {
    print_header "Cleaning up Terraform Resources"
    
    cd "$PROJECT_ROOT/terraform"
    
    if [ ! -f "terraform.tfstate" ]; then
        print_warning "No Terraform state found"
        return
    fi
    
    print_info "Destroying Terraform infrastructure..."
    terraform destroy -auto-approve
    
    print_success "Terraform resources destroyed"
}

cleanup_cloudformation() {
    print_header "Cleaning up CloudFormation Resources"
    
    local stack_name="${PROJECT_NAME}-${ENVIRONMENT}-stack"
    
    # Check if stack exists
    if ! aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" &> /dev/null; then
        print_warning "Stack not found: $stack_name"
        return
    fi
    
    print_info "Deleting CloudFormation stack: $stack_name"
    aws cloudformation delete-stack \
        --stack-name "$stack_name" \
        --region "$AWS_REGION"
    
    print_info "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete \
        --stack-name "$stack_name" \
        --region "$AWS_REGION"
    
    print_success "CloudFormation stack deleted"
}

cleanup_ecr_images() {
    print_header "Cleaning up ECR Images"
    
    local repo_name="${PROJECT_NAME}-${ENVIRONMENT}"
    
    # Check if repository exists
    if ! aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --region "$AWS_REGION" &> /dev/null; then
        print_warning "ECR repository not found: $repo_name"
        return
    fi
    
    print_info "Listing images in repository: $repo_name"
    local image_count=$(aws ecr list-images \
        --repository-name "$repo_name" \
        --region "$AWS_REGION" \
        --query 'length(imageIds)' \
        --output text)
    
    if [ "$image_count" -eq 0 ]; then
        print_info "No images to delete"
        return
    fi
    
    print_warning "Found $image_count images"
    echo -e "Delete all images? (yes/no): "
    read -r delete_images
    
    if [ "$delete_images" = "yes" ]; then
        print_info "Deleting all images..."
        
        # Get all image IDs
        local image_ids=$(aws ecr list-images \
            --repository-name "$repo_name" \
            --region "$AWS_REGION" \
            --query 'imageIds[*]' \
            --output json)
        
        if [ "$image_ids" != "[]" ]; then
            aws ecr batch-delete-image \
                --repository-name "$repo_name" \
                --region "$AWS_REGION" \
                --image-ids "$image_ids" &> /dev/null
            
            print_success "All images deleted"
        fi
    fi
}

cancel_running_jobs() {
    print_header "Cancelling Running Jobs"
    
    local job_queue="${PROJECT_NAME}-${ENVIRONMENT}-job-queue"
    
    # Get running jobs
    local running_jobs=$(aws batch list-jobs \
        --job-queue "$job_queue" \
        --job-status RUNNING \
        --region "$AWS_REGION" \
        --query 'jobSummaryList[*].jobId' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$running_jobs" ]; then
        print_info "No running jobs found"
        return
    fi
    
    print_warning "Found running jobs"
    echo -e "Cancel all running jobs? (yes/no): "
    read -r cancel_jobs
    
    if [ "$cancel_jobs" = "yes" ]; then
        for job_id in $running_jobs; do
            print_info "Cancelling job: $job_id"
            aws batch terminate-job \
                --job-id "$job_id" \
                --reason "Cleanup script" \
                --region "$AWS_REGION"
        done
        print_success "All running jobs cancelled"
    fi
}

cleanup_logs() {
    print_header "Cleaning up CloudWatch Logs"
    
    local log_group="/aws/batch/${PROJECT_NAME}-${ENVIRONMENT}"
    
    # Check if log group exists
    if ! aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" \
        --region "$AWS_REGION" &> /dev/null; then
        print_warning "Log group not found: $log_group"
        return
    fi
    
    echo -e "Delete CloudWatch log group? (yes/no): "
    read -r delete_logs
    
    if [ "$delete_logs" = "yes" ]; then
        print_info "Deleting log group: $log_group"
        aws logs delete-log-group \
            --log-group-name "$log_group" \
            --region "$AWS_REGION" 2>/dev/null || true
        print_success "Log group deleted"
    fi
}

print_usage() {
    cat << EOF
Usage: $0 [method] [options]

Methods:
    terraform           Clean up Terraform-deployed resources
    cloudformation      Clean up CloudFormation-deployed resources
    all                 Clean up everything (tries both methods)
    
Options:
    --skip-confirmation Skip confirmation prompt (dangerous!)
    --keep-logs         Keep CloudWatch logs
    --keep-images       Keep ECR images

Environment Variables:
    AWS_REGION          AWS region (default: us-east-1)
    ENVIRONMENT         Environment name (default: prod)
    PROJECT_NAME        Project name (default: batch-jobs)

Examples:
    $0 terraform
    $0 cloudformation
    $0 all
    $0 terraform --skip-confirmation

EOF
}

# Parse arguments
METHOD="${1:-}"
SKIP_CONFIRMATION=false
KEEP_LOGS=false
KEEP_IMAGES=false

shift || true

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --keep-images)
            KEEP_IMAGES=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Main script
if [ -z "$METHOD" ]; then
    print_usage
    exit 1
fi

if [ "$SKIP_CONFIRMATION" = false ]; then
    confirm_action
fi

# Cancel running jobs first
cancel_running_jobs

# Clean up based on method
case "$METHOD" in
    terraform)
        [ "$KEEP_IMAGES" = false ] && cleanup_ecr_images
        cleanup_terraform
        [ "$KEEP_LOGS" = false ] && cleanup_logs
        ;;
    cloudformation)
        [ "$KEEP_IMAGES" = false ] && cleanup_ecr_images
        cleanup_cloudformation
        [ "$KEEP_LOGS" = false ] && cleanup_logs
        ;;
    all)
        [ "$KEEP_IMAGES" = false ] && cleanup_ecr_images
        cleanup_terraform 2>/dev/null || true
        cleanup_cloudformation 2>/dev/null || true
        [ "$KEEP_LOGS" = false ] && cleanup_logs
        ;;
    *)
        print_error "Unknown method: $METHOD"
        print_usage
        exit 1
        ;;
esac

print_header "Cleanup Complete!"
print_success "All resources have been cleaned up"

