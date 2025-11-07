#!/usr/bin/env python3
"""
AWS Batch Cost Calculator

Calculate estimated costs for running batch jobs on AWS.
Usage: python calculator.py --jobs 2 --duration 30 --vcpu 2 --memory 4096
"""

import argparse
from typing import Dict, Tuple


class AWSBatchCostCalculator:
    """Calculate AWS Batch costs based on job parameters."""
    
    # Pricing (us-east-1, as of Nov 2025)
    EC2_PRICING = {
        't3.small': {'vcpu': 2, 'memory': 2048, 'on_demand': 0.0208, 'spot': 0.0062},
        't3.medium': {'vcpu': 2, 'memory': 4096, 'on_demand': 0.0416, 'spot': 0.0125},
        't3.large': {'vcpu': 2, 'memory': 8192, 'on_demand': 0.0832, 'spot': 0.0250},
        't3.xlarge': {'vcpu': 4, 'memory': 16384, 'on_demand': 0.1664, 'spot': 0.0499},
        'c5.large': {'vcpu': 2, 'memory': 4096, 'on_demand': 0.085, 'spot': 0.0255},
        'c5.xlarge': {'vcpu': 4, 'memory': 8192, 'on_demand': 0.17, 'spot': 0.051},
        'c5.2xlarge': {'vcpu': 8, 'memory': 16384, 'on_demand': 0.34, 'spot': 0.102},
        'r5.large': {'vcpu': 2, 'memory': 16384, 'on_demand': 0.126, 'spot': 0.0378},
        'r5.xlarge': {'vcpu': 4, 'memory': 32768, 'on_demand': 0.252, 'spot': 0.0756},
    }
    
    # Storage pricing (per GB-month)
    ECR_STORAGE = 0.10
    S3_STORAGE = 0.023
    CLOUDWATCH_LOGS = 0.50
    
    # NAT Gateway pricing
    NAT_GATEWAY_HOURLY = 0.045
    NAT_DATA_PROCESSING = 0.045  # per GB
    
    # VPC Endpoint pricing
    VPC_ENDPOINT_HOURLY = 0.01
    VPC_ENDPOINT_DATA = 0.01  # per GB
    
    def __init__(self, jobs_per_day: int, duration_minutes: int, 
                 vcpu: int, memory_mb: int):
        """
        Initialize calculator.
        
        Args:
            jobs_per_day: Number of jobs run per day
            duration_minutes: Average job duration in minutes
            vcpu: Number of vCPUs required
            memory_mb: Memory required in MB
        """
        self.jobs_per_day = jobs_per_day
        self.duration_minutes = duration_minutes
        self.vcpu = vcpu
        self.memory_mb = memory_mb
        self.instance_type = self._select_instance_type()
        
    def _select_instance_type(self) -> str:
        """Select the smallest instance type that meets requirements."""
        for instance_type, specs in self.EC2_PRICING.items():
            if specs['vcpu'] >= self.vcpu and specs['memory'] >= self.memory_mb:
                return instance_type
        # Default to largest if none match
        return 'c5.2xlarge'
    
    def calculate_compute_cost(self, use_spot: bool = True) -> Tuple[float, float]:
        """
        Calculate monthly and annual compute costs.
        
        Args:
            use_spot: Use spot instances (default: True)
            
        Returns:
            Tuple of (monthly_cost, annual_cost)
        """
        instance = self.EC2_PRICING[self.instance_type]
        hourly_rate = instance['spot'] if use_spot else instance['on_demand']
        
        # Calculate hours per month
        hours_per_month = (self.jobs_per_day * self.duration_minutes / 60) * 30
        
        monthly_cost = hours_per_month * hourly_rate
        annual_cost = monthly_cost * 12
        
        return monthly_cost, annual_cost
    
    def calculate_storage_cost(self, ecr_gb: float = 2, s3_gb: float = 100, 
                               log_gb: float = 5) -> Tuple[float, float]:
        """
        Calculate storage costs.
        
        Args:
            ecr_gb: ECR image storage in GB (default: 2)
            s3_gb: S3 storage in GB (default: 100)
            log_gb: CloudWatch logs in GB per month (default: 5)
            
        Returns:
            Tuple of (monthly_cost, annual_cost)
        """
        monthly_cost = (
            ecr_gb * self.ECR_STORAGE +
            s3_gb * self.S3_STORAGE +
            log_gb * self.CLOUDWATCH_LOGS
        )
        annual_cost = monthly_cost * 12
        
        return monthly_cost, annual_cost
    
    def calculate_network_cost(self, use_vpc_endpoints: bool = True,
                               data_transfer_gb: float = 50) -> Tuple[float, float]:
        """
        Calculate network costs.
        
        Args:
            use_vpc_endpoints: Use VPC endpoints instead of NAT (default: True)
            data_transfer_gb: Data transferred per month in GB (default: 50)
            
        Returns:
            Tuple of (monthly_cost, annual_cost)
        """
        if use_vpc_endpoints:
            # VPC Endpoint for S3 (gateway endpoint - free) + ECR interface endpoint
            monthly_cost = 7.0 + (data_transfer_gb * self.VPC_ENDPOINT_DATA)
        else:
            # NAT Gateway
            hours_per_month = 730  # Average hours in a month
            monthly_cost = (
                hours_per_month * self.NAT_GATEWAY_HOURLY +
                data_transfer_gb * self.NAT_DATA_PROCESSING
            )
        
        annual_cost = monthly_cost * 12
        return monthly_cost, annual_cost
    
    def calculate_total_cost(self, use_spot: bool = True,
                           use_vpc_endpoints: bool = True,
                           ecr_gb: float = 2,
                           s3_gb: float = 100,
                           log_gb: float = 5,
                           data_transfer_gb: float = 50) -> Dict:
        """
        Calculate total AWS Batch costs with breakdown.
        
        Returns:
            Dictionary with cost breakdown
        """
        compute_monthly, compute_annual = self.calculate_compute_cost(use_spot)
        storage_monthly, storage_annual = self.calculate_storage_cost(
            ecr_gb, s3_gb, log_gb
        )
        network_monthly, network_annual = self.calculate_network_cost(
            use_vpc_endpoints, data_transfer_gb
        )
        
        total_monthly = compute_monthly + storage_monthly + network_monthly
        total_annual = compute_annual + storage_annual + network_annual
        
        return {
            'configuration': {
                'instance_type': self.instance_type,
                'vcpu': self.vcpu,
                'memory_mb': self.memory_mb,
                'jobs_per_day': self.jobs_per_day,
                'duration_minutes': self.duration_minutes,
                'use_spot': use_spot,
                'use_vpc_endpoints': use_vpc_endpoints,
            },
            'costs': {
                'compute': {
                    'monthly': compute_monthly,
                    'annual': compute_annual,
                },
                'storage': {
                    'monthly': storage_monthly,
                    'annual': storage_annual,
                },
                'network': {
                    'monthly': network_monthly,
                    'annual': network_annual,
                },
                'total': {
                    'monthly': total_monthly,
                    'annual': total_annual,
                },
            },
            'savings_vs_onpremise': {
                'monthly': 260 - total_monthly,
                'annual': 3120 - total_annual,
                'percentage': ((260 - total_monthly) / 260) * 100,
            }
        }
    
    def print_report(self, **kwargs):
        """Print a formatted cost report."""
        result = self.calculate_total_cost(**kwargs)
        
        print("=" * 70)
        print("AWS BATCH COST ESTIMATE")
        print("=" * 70)
        print()
        
        print("CONFIGURATION:")
        print("-" * 70)
        config = result['configuration']
        print(f"  Instance Type:     {config['instance_type']}")
        print(f"  vCPU:              {config['vcpu']}")
        print(f"  Memory:            {config['memory_mb']} MB")
        print(f"  Jobs per Day:      {config['jobs_per_day']}")
        print(f"  Duration:          {config['duration_minutes']} minutes")
        print(f"  Spot Instances:    {'Yes' if config['use_spot'] else 'No'}")
        print(f"  VPC Endpoints:     {'Yes' if config['use_vpc_endpoints'] else 'No'}")
        print()
        
        print("COST BREAKDOWN:")
        print("-" * 70)
        costs = result['costs']
        
        print(f"  Compute:")
        print(f"    Monthly:         ${costs['compute']['monthly']:>8.2f}")
        print(f"    Annual:          ${costs['compute']['annual']:>8.2f}")
        print()
        
        print(f"  Storage:")
        print(f"    Monthly:         ${costs['storage']['monthly']:>8.2f}")
        print(f"    Annual:          ${costs['storage']['annual']:>8.2f}")
        print()
        
        print(f"  Network:")
        print(f"    Monthly:         ${costs['network']['monthly']:>8.2f}")
        print(f"    Annual:          ${costs['network']['annual']:>8.2f}")
        print()
        
        print("-" * 70)
        print(f"  TOTAL MONTHLY:     ${costs['total']['monthly']:>8.2f}")
        print(f"  TOTAL ANNUAL:      ${costs['total']['annual']:>8.2f}")
        print("=" * 70)
        print()
        
        print("SAVINGS vs ON-PREMISE:")
        print("-" * 70)
        savings = result['savings_vs_onpremise']
        print(f"  Monthly Savings:   ${savings['monthly']:>8.2f}")
        print(f"  Annual Savings:    ${savings['annual']:>8.2f}")
        print(f"  Percentage:        {savings['percentage']:>7.1f}%")
        print("=" * 70)


def main():
    """Main entry point for CLI."""
    parser = argparse.ArgumentParser(
        description='Calculate AWS Batch costs for your workload'
    )
    
    parser.add_argument(
        '--jobs',
        type=int,
        default=2,
        help='Number of jobs per day (default: 2)'
    )
    
    parser.add_argument(
        '--duration',
        type=int,
        default=30,
        help='Job duration in minutes (default: 30)'
    )
    
    parser.add_argument(
        '--vcpu',
        type=int,
        default=2,
        help='Number of vCPUs required (default: 2)'
    )
    
    parser.add_argument(
        '--memory',
        type=int,
        default=4096,
        help='Memory required in MB (default: 4096)'
    )
    
    parser.add_argument(
        '--no-spot',
        action='store_true',
        help='Use on-demand instances instead of spot'
    )
    
    parser.add_argument(
        '--no-vpc-endpoints',
        action='store_true',
        help='Use NAT Gateway instead of VPC endpoints'
    )
    
    parser.add_argument(
        '--ecr-gb',
        type=float,
        default=2,
        help='ECR storage in GB (default: 2)'
    )
    
    parser.add_argument(
        '--s3-gb',
        type=float,
        default=100,
        help='S3 storage in GB (default: 100)'
    )
    
    parser.add_argument(
        '--log-gb',
        type=float,
        default=5,
        help='CloudWatch logs in GB per month (default: 5)'
    )
    
    parser.add_argument(
        '--data-transfer-gb',
        type=float,
        default=50,
        help='Data transfer in GB per month (default: 50)'
    )
    
    args = parser.parse_args()
    
    calculator = AWSBatchCostCalculator(
        jobs_per_day=args.jobs,
        duration_minutes=args.duration,
        vcpu=args.vcpu,
        memory_mb=args.memory
    )
    
    calculator.print_report(
        use_spot=not args.no_spot,
        use_vpc_endpoints=not args.no_vpc_endpoints,
        ecr_gb=args.ecr_gb,
        s3_gb=args.s3_gb,
        log_gb=args.log_gb,
        data_transfer_gb=args.data_transfer_gb
    )


if __name__ == '__main__':
    main()

