terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "cicd_rg" {
  name     = "RCG-CICD"
  location = "Canada East"
}

# Existing Azure SSH Public Key
data "azurerm_ssh_public_key" "existing_key" {
  name                = "mujahed-key"
  resource_group_name = "NetworkWatcherRG"
}

# Virtual Network
resource "azurerm_virtual_network" "cicd_vnet" {
  name                = "VNet-CICD"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.cicd_rg.location
  resource_group_name = azurerm_resource_group.cicd_rg.name
}

# Subnet
resource "azurerm_subnet" "cicd_subnet" {
  name                 = "Subnet-CICD"
  resource_group_name  = azurerm_resource_group.cicd_rg.name
  virtual_network_name = azurerm_virtual_network.cicd_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "cicd_nsg" {
  name                = "NSG-CICD"
  location            = azurerm_resource_group.cicd_rg.location
  resource_group_name = azurerm_resource_group.cicd_rg.name

  # SSH - Port 22
  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }

  # Spring Boot - Port 8080
  security_rule {
    name                       = "Allow-SpringBoot-8080"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }
}

# Public IP
resource "azurerm_public_ip" "cicd_public_ip" {
  name                = "PublicIP-CICD"
  location            = azurerm_resource_group.cicd_rg.location
  resource_group_name = azurerm_resource_group.cicd_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Network Interface
resource "azurerm_network_interface" "cicd_nic" {
  name                = "NIC-CICD"
  location            = azurerm_resource_group.cicd_rg.location
  resource_group_name = azurerm_resource_group.cicd_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.cicd_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.cicd_public_ip.id
  }
}

# Attach NSG to NIC
resource "azurerm_network_interface_security_group_association" "cicd_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.cicd_nic.id
  network_security_group_id = azurerm_network_security_group.cicd_nsg.id
}

# Ubuntu VM
resource "azurerm_linux_virtual_machine" "cicd_vm" {
  name                = "vm-CICD"
  computer_name       = "vm-CICD"
  resource_group_name = azurerm_resource_group.cicd_rg.name
  location            = azurerm_resource_group.cicd_rg.location

  size           = "Standard_B2ats_v2"
  admin_username = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.cicd_nic.id
  ]

  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = data.azurerm_ssh_public_key.existing_key.public_key
  }

  os_disk {
    name                 = "OSDisk-CICD"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  boot_diagnostics {}
}

# Outputs
output "vm_name" {
  value = azurerm_linux_virtual_machine.cicd_vm.name
}

output "public_ip" {
  value = azurerm_public_ip.cicd_public_ip.ip_address
}

output "private_ip" {
  value = azurerm_network_interface.cicd_nic.private_ip_address
}

output "application_url" {
  value = "http://${azurerm_public_ip.cicd_public_ip.ip_address}:8080"
}

output "ssh_command" {
  value = "ssh azureuser@${azurerm_public_ip.cicd_public_ip.ip_address}"
}
