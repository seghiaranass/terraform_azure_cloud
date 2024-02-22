# Set the Azure provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}
# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {} #Features block is required
}

# Create resource group
resource "azurerm_resource_group" "linux-dev-rg" {
    name        = "linuxDev"
    location    = "eastus"
    tags        = {
        environment = "dev"
    }
}



# Create virtual network
resource "azurerm_virtual_network" "dev-vnet" {
  name                = "dev-network"
  resource_group_name = azurerm_resource_group.linux-dev-rg.name
  location            = azurerm_resource_group.linux-dev-rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}
# Create subnet within our virtual network. Best practice as a separate resource
resource "azurerm_subnet" "dev-subnet" {
  name                 = "subnet1"
  resource_group_name  = azurerm_resource_group.linux-dev-rg.name
  virtual_network_name = azurerm_virtual_network.dev-vnet.name
  address_prefixes     = ["10.123.1.0/24"]
}
# Create our Network Security Group (NSG)
resource "azurerm_network_security_group" "dev-nsg" {
  name                = "dev-nsg"
  location            = azurerm_resource_group.linux-dev-rg.location
  resource_group_name = azurerm_resource_group.linux-dev-rg.name
  tags = {
    environment = "dev"
  }
}
# Create our Network Security Rule separate of our NSG
resource "azurerm_network_security_rule" "dev-rule" {
  name                        = "dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.linux-dev-rg.name
  network_security_group_name = azurerm_network_security_group.dev-nsg.name
}
# Create the NSG association
resource "azurerm_subnet_network_security_group_association" "dev-nsga" {
  subnet_id                 = azurerm_subnet.dev-subnet.id
  network_security_group_id = azurerm_network_security_group.dev-nsg.id
}
# Create public ip for linux VMs
resource "azurerm_public_ip" "dev-ip" {
  count               = 5 # Create 10 public IPs
  name                = "dev-ip-${count.index}"
  resource_group_name = azurerm_resource_group.linux-dev-rg.name
  location            = azurerm_resource_group.linux-dev-rg.location
  allocation_method   = "Dynamic"
  tags = {
    environment = "dev"
  }
}
# Create Linux public NICs
resource "azurerm_network_interface" "dev-nic" {
  count               = 5 # Create 10 NICs
  name                = "dev-nic-${count.index}"
  location            = azurerm_resource_group.linux-dev-rg.location
  resource_group_name = azurerm_resource_group.linux-dev-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.dev-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.dev-ip[count.index].id
  }
  tags = {
    environment = "dev"
  }
}



# Create Linux Virtual Machines
resource "azurerm_linux_virtual_machine" "dev-vm" {
  count                 = 5 # Create 10 VMs
  name                  = "dev-vm-${count.index}"
  resource_group_name   = azurerm_resource_group.linux-dev-rg.name
  location              = azurerm_resource_group.linux-dev-rg.location
  size                  = "Standard_D2s_v3"
  admin_username        = "debian"
  network_interface_ids = [azurerm_network_interface.dev-nic[count.index].id]

  custom_data  = filebase64("${path.module}/customdata.tpl")
  admin_ssh_key {
    username   = "debian"
    public_key = file("./azurekey.pub")
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18_04-lts-gen2"
    version   = "latest"
  }
}
