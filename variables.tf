variable "region" {
  type        = string
  description = "AWS Region"
  default     = "af-south-1"
}

variable "instance_name" {
  type        = string
  description = "EC2 MySQL Instance"
  default     = "My MySQL EC2 Instance"
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

variable "mysql_private_subnet" {
  type        = string
  description = "Private subnet IP range"
  default     = "10.0.10.0/24"
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



