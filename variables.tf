variable "region" {
  type        = string
  description = "AWS Region"
  default     = "af-south-1"
}

variable "instance_name" {
  type        = string
  description = "EC2 Instance"
  default     = "My EC2 Instance"
}

variable "instance_type" {
  type        = string
  description = "EC2 Instance Type"
  default     = "t3.micro"
}

variable "vpc_cidr" {
  type        = string
  description = "IP range for custom VPC"
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidr" {
  type        = string
  description = "Private subnet IP range"
  default     = "10.0.10.0/24"
}

variable "public_subnet_cidr" {
  type        = string
  description = "Public subnet IP range for NAT Gateway"
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  type        = string
  description = "Availability zone for VPC"
  default     = "af-south-1b"
}

variable "enable_internet_access" {
  type        = bool
  description = "Temporarily enable internet access for updates"
  default     = false
}



