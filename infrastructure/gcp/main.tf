terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "name_prefix" {
  type    = string
  default = "traditionaljay"
}

variable "repo_url" {
  type    = string
  default = "https://github.com/AstralJays/TraditionalJay.git"
}

variable "repo_ref" {
  type    = string
  default = "main"
}

resource "google_compute_network" "main" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.name_prefix}-subnet"
  ip_cidr_range = "10.50.0.0/24"
  region        = var.region
  network       = google_compute_network.main.id
}

resource "google_compute_firewall" "app" {
  name    = "${var.name_prefix}-allow-app"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22", "8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["traditionaljay"]
}

locals {
  startup = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    export REPO_URL='${var.repo_url}'
    export REPO_REF='${var.repo_ref}'
    apt-get update -y
    apt-get install -y git
    git clone --depth 1 --branch "${var.repo_ref}" "${var.repo_url}" /tmp/tj
    chmod +x /tmp/tj/scripts/install-vm.sh
    REPO_URL='${var.repo_url}' REPO_REF='${var.repo_ref}' /tmp/tj/scripts/install-vm.sh
  EOF
}

resource "google_compute_instance" "app" {
  name         = var.name_prefix
  machine_type = "e2-small"
  zone         = var.zone
  tags         = ["traditionaljay"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    access_config {}
  }

  metadata_startup_script = local.startup

  labels = {
    project = "traditionaljay"
    cve     = "cve-2021-44228"
  }
}

output "public_ip" {
  value = google_compute_instance.app.network_interface[0].access_config[0].nat_ip
}

output "application_url" {
  value = "http://${google_compute_instance.app.network_interface[0].access_config[0].nat_ip}:8080"
}

output "security_url" {
  value = "http://${google_compute_instance.app.network_interface[0].access_config[0].nat_ip}:8080/security"
}
