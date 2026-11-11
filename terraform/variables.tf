variable "aws_region" {
  description = "AWS region for the infrastructure"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project resource name prefix"
  type        = string
  default     = "aws-3-tier-ha-webapp"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR range for the project VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of Availability Zones to use"
  type        = number
  default     = 3

  validation {
    condition     = var.availability_zone_count >= 2 && var.availability_zone_count <= 3
    error_message = "Use two or three Availability Zones."
  }
}

variable "web_instance_type" {
  description = "EC2 instance type for the web tier"
  type        = string
  default     = "t3.micro"
}

variable "app_instance_type" {
  description = "EC2 instance type for the application tier"
  type        = string
  default     = "t3.micro"
}

variable "web_min_size" {
  description = "Minimum web EC2 instance count"
  type        = number
  default     = 1
}

variable "web_desired_capacity" {
  description = "Initial desired web EC2 instance count"
  type        = number
  default     = 3
}

variable "web_max_size" {
  description = "Maximum web EC2 instance count"
  type        = number
  default     = 6
}

variable "app_min_size" {
  description = "Minimum application EC2 instance count"
  type        = number
  default     = 1
}

variable "app_desired_capacity" {
  description = "Initial desired application EC2 instance count"
  type        = number
  default     = 3
}

variable "app_max_size" {
  description = "Maximum application EC2 instance count"
  type        = number
  default     = 6
}

variable "app_port" {
  description = "Port used by the Node.js application"
  type        = number
  default     = 4000
}

variable "db_port" {
  description = "Port used by MySQL"
  type        = number
  default     = 3306
}

variable "db_name" {
  description = "Name of the application database"
  type        = string
  default     = "webappdb"
}

variable "db_instance_class" {
  description = "RDS MySQL instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_multi_az" {
  description = "Enable RDS Multi-AZ standby deployment"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Optional registered domain name; leave empty until available"
  type        = string
  default     = ""
}

variable "enable_edge_services" {
  description = "Enable optional CloudFront and WAF resources"
  type        = bool
  default     = false
}
