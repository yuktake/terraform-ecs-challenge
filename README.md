# Deploy Project Order

1. practice-terraform-vpn (Create VPC)
2. practice-terraform-ecs -> ecs_flask_api_infra (Create ECR / SSM Parameters)
3. practice-terraform-db (Create RDS(Aurora) / EC2 For Bastion via SSM from local)
4. practice-terraform-ecs -> ecs_flask_api (Create ECS / ALB / VPC Endpoint / IAM)

# Deploy Procedure

## init project
> terraform init -backend-config=backend.tfvars

## confirm plan
> terraform plan

## deploy resource
> terraform apply

## delete resource
> terraform destroy