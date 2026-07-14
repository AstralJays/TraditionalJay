terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "name_prefix" {
  type    = string
  default = "traditionaljay"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for the VM admin user"
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
  type      = string
  default   = ""
  sensitive = true
}

variable "upwind_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "upwind_agent_extra_config" {
  type    = string
  default = "scanner-v2=true"
}

resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-rg"
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.name_prefix}-vnet"
  address_space       = ["10.40.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "main" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.40.1.0/24"]
}

resource "azurerm_public_ip" "main" {
  name                = "${var.name_prefix}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "main" {
  name                = "${var.name_prefix}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "App"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "main" {
  name                = "${var.name_prefix}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

locals {
  cloud_init = <<-EOF
    #cloud-config
    package_update: true
    packages: [git, openjdk-11-jdk, maven, curl, ca-certificates]
    runcmd:
      - export REPO_URL='${var.repo_url}' REPO_REF='${var.repo_ref}' UPWIND_CLIENT_ID='${var.upwind_client_id}' UPWIND_CLIENT_SECRET='${var.upwind_client_secret}' UPWIND_AGENT_EXTRA_CONFIG='${var.upwind_agent_extra_config}'
      - git clone --depth 1 --branch ${var.repo_ref} ${var.repo_url} /tmp/tj
      - chmod +x /tmp/tj/scripts/install-vm.sh /tmp/tj/scripts/install-upwind-sensor.sh
      - REPO_URL='${var.repo_url}' REPO_REF='${var.repo_ref}' UPWIND_CLIENT_ID='${var.upwind_client_id}' UPWIND_CLIENT_SECRET='${var.upwind_client_secret}' UPWIND_AGENT_EXTRA_CONFIG='${var.upwind_agent_extra_config}' /tmp/tj/scripts/install-vm.sh
  EOF
}

resource "azurerm_linux_virtual_machine" "main" {
  name                = var.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B2s"
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(local.cloud_init)

  tags = {
    Project = "TraditionalJay"
    CVE     = "CVE-2021-44228"
  }
}

output "public_ip" {
  value = azurerm_public_ip.main.ip_address
}

output "application_url" {
  value = "http://${azurerm_public_ip.main.ip_address}:8080"
}

output "security_url" {
  value = "http://${azurerm_public_ip.main.ip_address}:8080/security"
}
