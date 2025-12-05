# Network Interface for Test VM
resource "azurerm_network_interface" "testvm" {
  name                = "nic-testvm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Windows VM for testing
resource "azurerm_windows_virtual_machine" "testvm" {
  name                = "vm-test-win"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = "Standard_D2s_v3"
  admin_username      = var.test_vm_admin_username
  admin_password      = var.test_vm_admin_password

  network_interface_ids = [
    azurerm_network_interface.testvm.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-10"
    sku       = "win10-21h2-pro"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# NSG for Test VM subnet (optional - firewall handles filtering)
resource "azurerm_network_security_group" "testvm" {
  name                = "nsg-testvm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Allow RDP from your IP (update with your public IP)
  security_rule {
    name                       = "AllowRDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*" # Replace with your public IP for security
    destination_address_prefix = "*"
  }
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "testvm" {
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.testvm.id
}
