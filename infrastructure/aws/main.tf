terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "traditionaljay"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ssh_ingress_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR allowed to SSH (22). Tighten for real workshops."
}

variable "app_ingress_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "repo_url" {
  type    = string
  default = "https://github.com/AstralJays/TraditionalJay.git"
}

variable "repo_ref" {
  type    = string
  default = "main"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "app" {
  name_prefix = "${var.name_prefix}-"
  description = "TraditionalJay HTTP + SSH"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "App"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.app_ingress_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-sg" }
}

locals {
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    export REPO_URL='${var.repo_url}'
    export REPO_REF='${var.repo_ref}'
    curl -fsSL "${var.repo_url}/raw/${var.repo_ref}/scripts/install-vm.sh" -o /tmp/install-vm.sh || true
    if [[ ! -s /tmp/install-vm.sh ]]; then
      apt-get update -y && apt-get install -y git
      git clone --depth 1 --branch "${var.repo_ref}" "${var.repo_url}" /tmp/tj
      cp /tmp/tj/scripts/install-vm.sh /tmp/install-vm.sh
    fi
    chmod +x /tmp/install-vm.sh
    REPO_URL='${var.repo_url}' REPO_REF='${var.repo_ref}' /tmp/install-vm.sh
  EOF
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data              = local.user_data

  tags = {
    Name    = var.name_prefix
    Project = "TraditionalJay"
    CVE     = "CVE-2021-44228"
  }
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "application_url" {
  value = "http://${aws_instance.app.public_ip}:8080"
}

output "security_url" {
  value = "http://${aws_instance.app.public_ip}:8080/security"
}
