variable "region" {
    type = string
    description = "AWS Region"
    default = "af-south-1"
}

variable "instance_name" {
    type = string
    description = "EC2 MySQL Instance"
    default = "My MySQL EC2 Instance"
}

variable "instance_type" {
    type = string
    description = "EC2 Instance Type"
    default = "t3.micro"
}

variable "vpc_cidr" {
    type = string
    description = "IP range for custom VPC"
    default = "10.0.0.0/16"
}

variable "private_subnet_cidr" {
  type = string
  description = "Private subnet IP range"
  default = "10.0.10.0/24"
}

variable "public_subnet_cidr" {
  type = string
  description = "Public subnet IP range"
  default = "10.0.1.0/24"
}

variable "availability_zone" {
  type = string
  description = "Availability zone for VPC"
  default = "af-south-1b"
}

variable "security_group" {
    type = string
    description = "Security group with only egress rule"
    default = "MYSQL Security Group"
}

variable "iam_role" {
    type = string
    description = "IAM role for EC2 SSM"
    default = "ec2_ssm_role"
}

variable "internet_gateway" {
  type = string
  description = "Internet gateway for MySQL"
}
