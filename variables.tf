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

