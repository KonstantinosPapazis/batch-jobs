#!/bin/bash
# =============================================================================
# AWS Batch Job Submission Script
# =============================================================================
# Submit jobs to AWS Batch with custom parameters
#
# Usage:
#   ./submit-job.sh <job-definition> <job-queue> [job-name] [options]
#
# Examples:
#   ./submit-job.sh my-job default-queue
#   ./submit-job.sh my-job default-queue my-custom-job-name
#   ./submit-job.sh my-job default-queue "" --vcpu 2 --memory 4096
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
WAIT_FOR_COMPLETION="${WAIT_FOR_COMPLETION:-false}"

print_error() {
    echo -e "${RED}✗ $1${NC}" >&2
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

print_usage() {
    cat << EOF
Usage: $0 <job-definition> <job-queue> [job-name] [options]

Required Arguments:
    job-definition      Name or ARN of the job definition
    job-queue           Name or ARN of the job queue

Optional Arguments:
    job-name            Custom job name (default: auto-generated)

Options:
    --vcpu <num>        Override vCPU count
    --memory <mb>       Override memory in MB
    --env KEY=VALUE     Add environment variable (can be repeated)
    --param KEY=VALUE   Add parameter (can be repeated)
    --timeout <sec>     Job timeout in seconds
    --depends-on <id>   Job dependency (can be repeated)
    --array-size <n>    Array job size
    --wait              Wait for job completion

Environment Variables:
    AWS_REGION          AWS region (default: us-east-1)
    WAIT_FOR_COMPLETION Wait for job completion (default: false)

Examples:
    # Simple job submission
    $0 my-job-def my-queue

    # With custom resources
    $0 my-job-def my-queue custom-name --vcpu 4 --memory 8192

    # With environment variables
    $0 my-job-def my-queue "" --env INPUT_PATH=s3://bucket/input --env OUTPUT_PATH=s3://bucket/output

    # Array job
    $0 my-job-def my-queue "" --array-size 10

    # Wait for completion
    $0 my-job-def my-queue "" --wait

EOF
}

# Parse arguments
if [ $# -lt 2 ]; then
    print_usage
    exit 1
fi

JOB_DEFINITION="$1"
JOB_QUEUE="$2"
JOB_NAME="${3:-job-$(date +%Y%m%d-%H%M%S)}"

shift 2
[ -n "$3" ] && shift

# Job configuration
ENVIRONMENT_VARS=()
PARAMETERS=()
DEPENDS_ON=()
VCPU=""
MEMORY=""
TIMEOUT=""
ARRAY_SIZE=""

# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        --vcpu)
            VCPU="$2"
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --env)
            ENVIRONMENT_VARS+=("$2")
            shift 2
            ;;
        --param)
            PARAMETERS+=("$2")
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --depends-on)
            DEPENDS_ON+=("$2")
            shift 2
            ;;
        --array-size)
            ARRAY_SIZE="$2"
            shift 2
            ;;
        --wait)
            WAIT_FOR_COMPLETION="true"
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Build job submission command
print_info "Preparing job submission..."
print_info "  Job Definition: $JOB_DEFINITION"
print_info "  Job Queue: $JOB_QUEUE"
print_info "  Job Name: $JOB_NAME"

# Build JSON for container overrides
CONTAINER_OVERRIDES="{"

# Add resource requirements if specified
if [ -n "$VCPU" ] || [ -n "$MEMORY" ]; then
    CONTAINER_OVERRIDES+="\"resourceRequirements\":["
    if [ -n "$VCPU" ]; then
        CONTAINER_OVERRIDES+="{\"type\":\"VCPU\",\"value\":\"$VCPU\"}"
        print_info "  vCPU: $VCPU"
    fi
    if [ -n "$MEMORY" ]; then
        [ -n "$VCPU" ] && CONTAINER_OVERRIDES+=","
        CONTAINER_OVERRIDES+="{\"type\":\"MEMORY\",\"value\":\"$MEMORY\"}"
        print_info "  Memory: ${MEMORY}MB"
    fi
    CONTAINER_OVERRIDES+="]"
fi

# Add environment variables if specified
if [ ${#ENVIRONMENT_VARS[@]} -gt 0 ]; then
    [ "$CONTAINER_OVERRIDES" != "{" ] && CONTAINER_OVERRIDES+=","
    CONTAINER_OVERRIDES+="\"environment\":["
    first=true
    for env_var in "${ENVIRONMENT_VARS[@]}"; do
        IFS='=' read -r key value <<< "$env_var"
        if [ "$first" = false ]; then
            CONTAINER_OVERRIDES+=","
        fi
        CONTAINER_OVERRIDES+="{\"name\":\"$key\",\"value\":\"$value\"}"
        print_info "  Env: $key=$value"
        first=false
    done
    CONTAINER_OVERRIDES+="]"
fi

CONTAINER_OVERRIDES+="}"

# Build parameters JSON if specified
PARAMETERS_JSON="{"
if [ ${#PARAMETERS[@]} -gt 0 ]; then
    first=true
    for param in "${PARAMETERS[@]}"; do
        IFS='=' read -r key value <<< "$param"
        if [ "$first" = false ]; then
            PARAMETERS_JSON+=","
        fi
        PARAMETERS_JSON+="\"$key\":\"$value\""
        print_info "  Parameter: $key=$value"
        first=false
    done
fi
PARAMETERS_JSON+="}"

# Build dependencies JSON if specified
DEPENDS_ON_JSON="["
if [ ${#DEPENDS_ON[@]} -gt 0 ]; then
    first=true
    for dep in "${DEPENDS_ON[@]}"; do
        if [ "$first" = false ]; then
            DEPENDS_ON_JSON+=","
        fi
        DEPENDS_ON_JSON+="{\"jobId\":\"$dep\"}"
        print_info "  Depends on: $dep"
        first=false
    done
fi
DEPENDS_ON_JSON+="]"

# Build array properties if specified
ARRAY_JSON=""
if [ -n "$ARRAY_SIZE" ]; then
    ARRAY_JSON="{\"size\":$ARRAY_SIZE}"
    print_info "  Array size: $ARRAY_SIZE"
fi

# Build the AWS CLI command
CMD="aws batch submit-job"
CMD+=" --job-name \"$JOB_NAME\""
CMD+=" --job-queue \"$JOB_QUEUE\""
CMD+=" --job-definition \"$JOB_DEFINITION\""
CMD+=" --region \"$AWS_REGION\""

# Add optional parameters
if [ "$CONTAINER_OVERRIDES" != "{}" ]; then
    CMD+=" --container-overrides '$CONTAINER_OVERRIDES'"
fi

if [ "$PARAMETERS_JSON" != "{}" ]; then
    CMD+=" --parameters '$PARAMETERS_JSON'"
fi

if [ "$DEPENDS_ON_JSON" != "[]" ]; then
    CMD+=" --depends-on '$DEPENDS_ON_JSON'"
fi

if [ -n "$ARRAY_JSON" ]; then
    CMD+=" --array-properties '$ARRAY_JSON'"
fi

if [ -n "$TIMEOUT" ]; then
    CMD+=" --timeout attemptDurationSeconds=$TIMEOUT"
    print_info "  Timeout: ${TIMEOUT}s"
fi

# Submit the job
print_info "Submitting job..."

JOB_ID=$(eval "$CMD --query 'jobId' --output text")

if [ -z "$JOB_ID" ]; then
    print_error "Failed to submit job"
    exit 1
fi

print_success "Job submitted successfully!"
print_success "Job ID: $JOB_ID"

# Print useful commands
echo ""
print_info "Useful commands:"
echo "  # Check job status"
echo "  aws batch describe-jobs --jobs $JOB_ID --region $AWS_REGION"
echo ""
echo "  # View logs (after job starts)"
echo "  aws logs tail /aws/batch/your-log-group --follow --region $AWS_REGION"
echo ""
echo "  # Cancel job"
echo "  aws batch terminate-job --job-id $JOB_ID --reason 'Cancelled by user' --region $AWS_REGION"

# Wait for completion if requested
if [ "$WAIT_FOR_COMPLETION" = "true" ]; then
    echo ""
    print_info "Waiting for job to complete..."
    
    while true; do
        # Get job status
        STATUS=$(aws batch describe-jobs \
            --jobs "$JOB_ID" \
            --region "$AWS_REGION" \
            --query 'jobs[0].status' \
            --output text)
        
        STATUS_REASON=$(aws batch describe-jobs \
            --jobs "$JOB_ID" \
            --region "$AWS_REGION" \
            --query 'jobs[0].statusReason' \
            --output text 2>/dev/null || echo "")
        
        echo -ne "\r  Status: $STATUS    "
        
        case "$STATUS" in
            SUCCEEDED)
                echo ""
                print_success "Job completed successfully!"
                
                # Get job details
                EXIT_CODE=$(aws batch describe-jobs \
                    --jobs "$JOB_ID" \
                    --region "$AWS_REGION" \
                    --query 'jobs[0].container.exitCode' \
                    --output text 2>/dev/null || echo "N/A")
                
                print_info "Exit code: $EXIT_CODE"
                exit 0
                ;;
            FAILED)
                echo ""
                print_error "Job failed!"
                
                if [ -n "$STATUS_REASON" ]; then
                    print_error "Reason: $STATUS_REASON"
                fi
                
                # Get exit code if available
                EXIT_CODE=$(aws batch describe-jobs \
                    --jobs "$JOB_ID" \
                    --region "$AWS_REGION" \
                    --query 'jobs[0].container.exitCode' \
                    --output text 2>/dev/null || echo "N/A")
                
                print_error "Exit code: $EXIT_CODE"
                exit 1
                ;;
            SUBMITTED|PENDING|RUNNABLE|STARTING|RUNNING)
                # Continue waiting
                ;;
            *)
                echo ""
                print_warning "Unexpected status: $STATUS"
                ;;
        esac
        
        sleep 10
    done
fi

