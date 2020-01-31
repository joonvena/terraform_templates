provider "azurerm" {
  
}

#############################################
# Create Resource Group If Doesn't Exists.
#############################################
resource "azurerm_resource_group" "rgroup" {
    name                    = "MSP_Application"
    location                = "westeurope"
}

###########################
# Create Virtual Network
###########################
resource "azurerm_virtual_network" "mspnetwork" {
    name                    = "mspVnet"
    address_space           = ["10.0.0.0/16"]
    location                = "westeurope"
    resource_group_name     = azurerm_resource_group.rgroup.name
}

####################
# Create Subnet
####################
resource "azurerm_subnet" "mspsubnet" {
    name                    = "mspSubnet"
    resource_group_name     = azurerm_resource_group.rgroup.name
    virtual_network_name    = azurerm_virtual_network.mspnetwork.name
    address_prefix          = "10.0.1.0/24"
}

##################################################
# Assign Public IP-Adress To Application Server
##################################################
resource "azurerm_public_ip" "msp_public_ip" {
    name                    = "mspPublicIP"
    location                = "westeurope"
    resource_group_name     = azurerm_resource_group.rgroup.name
    allocation_method       = "Static"
}

###########################
# Create Security Group 
###########################
resource "azurerm_network_security_group" "msp_nsg" {
    name                    = "mspNetworkSecurityGroup"
    location                = "westeurope"
    resource_group_name     = azurerm_resource_group.rgroup.name

    security_rule {
        name                        = "SSH"
        priority                    = 1001
        direction                   = "Inbound"
        access                      = "Allow"
        protocol                    = "Tcp"
        source_port_range           = "*"
        destination_port_range      = "22"
        source_address_prefix       = "*"
        destination_address_prefix  = "*"
    }

    security_rule {
        name                        = "Backend"
        priority                    = 200
        direction                   = "Inbound"
        access                      = "Allow"
        protocol                    = "Tcp"
        source_port_range           = "*"
        destination_port_ranges     = ["443", "8080"]
        source_address_prefix       = "Internet"
        destination_address_prefix  = "*"
    }

}

################
# Create NIC
################
resource "azurerm_network_interface" "mspnic" {
    name                            = "mspNIC"
    location                        = "westeurope"
    resource_group_name             = azurerm_resource_group.rgroup.name
    network_security_group_id       = azurerm_network_security_group.msp_nsg.id

    ip_configuration {
        name                            = "nicIPConfiguration"
        subnet_id                       = azurerm_subnet.mspsubnet.id
        private_ip_address_allocation   = "Dynamic"
        public_ip_address_id            = azurerm_public_ip.msp_public_ip.id
    }
}

#########################################################
# Use Random Module To Generate ID For Storage Account
#########################################################
resource "random_id" "randomId" {
    keepers = {
        resource_group = azurerm_resource_group.rgroup.name
    }
    byte_length = 8
}

##################################################################################
# Create Storage Account To Store Boot Diagnostic Files From Application Server
##################################################################################
resource "azurerm_storage_account" "mspstorageaccount" {
    name                                = "diag${random_id.randomId.hex}"
    resource_group_name                 = azurerm_resource_group.rgroup.name
    location                            = "westeurope"
    account_replication_type            = "LRS"
    account_tier                        = "Standard"
}

##################################################
# Create Storage Account For Frontend Hosting
##################################################
resource "azurerm_storage_account" "frontendstorageaccount" {
    name                                = "mspfrontenddev"
    resource_group_name                 = azurerm_resource_group.rgroup.name
    location                            = "westeurope"
    account_replication_type            = "LRS"
    account_tier                        = "Standard"
    account_kind			= "StorageV2"

    provisioner "local-exec" {
        command = "az storage blob service-properties update --account-name ${azurerm_storage_account.frontendstorageaccount.name} --static-website --index-document index.html --404-document 404.html"
    }
}

#################################################
# Get Tenant ID For Key Vault
#################################################
data "azurerm_client_config" "current" {}

#################################################
# Define Key Vault To Store Server Certificates
################################################
resource "azurerm_key_vault" "mspkeyvault" {
    name                                = "mspkeyvault2020"
    location                            = "westeurope"
    resource_group_name                 = azurerm_resource_group.rgroup.name
    tenant_id                           = data.azurerm_client_config.current.tenant_id
    enabled_for_deployment		= "true"
    sku_name                            = "standard"

    access_policy {
        tenant_id = data.azurerm_client_config.current.tenant_id
        object_id = data.azurerm_client_config.current.object_id

        key_permissions = [
            "get",
            "list",
            "create",
            "delete",
        ]

        secret_permissions = [
            "get",
            "list",
            "set",
            "delete",
        ]

        certificate_permissions = [
            "get",
            "list",
            "create",
            "import",
            "delete",
        ]
    }
}

#######################################
# Create Server Certificates
#######################################
resource "azurerm_key_vault_certificate" "msphttps" {
    name                                = "msphttps"
    key_vault_id                        = azurerm_key_vault.mspkeyvault.id

    certificate_policy {
        issuer_parameters {
            name = "Self"
        }
        key_properties {
            exportable      = "true"
            key_size        = 2048
            key_type        = "RSA"
            reuse_key       = "true" 
        }
        lifetime_action {
            action {
                action_type = "AutoRenew"
            }

            trigger {
                days_before_expiry = 30
            }
        }

        secret_properties {
            content_type = "application/x-pkcs12"
        }

        x509_certificate_properties {
            key_usage = [
                "cRLSign",
                "dataEncipherment",
                "digitalSignature",
                "keyAgreement",
                "keyCertSign",
                "keyEncipherment",
            ]

            subject = "CN=CLIGetDefaultPolicy"
            validity_in_months = 12
        }
    }
}

###################################
# Define Application Server
##################################
resource "azurerm_virtual_machine" "appserver" {
    name                                = "mspAppServer"
    location                            = "westeurope"
    resource_group_name                 = azurerm_resource_group.rgroup.name
    network_interface_ids               = [azurerm_network_interface.mspnic.id]
    vm_size                             = "Standard_B2s"

    # Add Boot Disk To VM
    storage_os_disk {
        name                            = "mspOSDisk"
        caching                         = "ReadWrite"
        create_option                   = "FromImage"
        managed_disk_type               = "Premium_LRS"
    }

    # Define OS
    storage_image_reference {
        publisher                       = "Canonical"
        offer                           = "UbuntuServer"
        sku                             = "16.04.0-LTS"
        version                         = "latest"
    }

    # Define Name For The Machine And Admin Credentials
    os_profile {
        computer_name                   = "mspAppServer"
        admin_username                  = var.username
        custom_data			= file("customdata.txt")
    }

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
           path		= "/home/${var.username}/.ssh/authorized_keys"
           key_data	= file("ssh_keys/pub.key.pub")
        }
    }

    os_profile_secrets {
        source_vault_id = azurerm_key_vault.mspkeyvault.id
        vault_certificates {
            certificate_url = azurerm_key_vault_certificate.msphttps.secret_id
        }
    }

    boot_diagnostics {
        enabled                         = "true"
        storage_uri                     = azurerm_storage_account.mspstorageaccount.primary_blob_endpoint
    } 
}


##################################
# Define Database Server
##################################
resource "azurerm_sql_server" "mspdbserver" {
    name                                = "mspsqlserver"
    resource_group_name                 = azurerm_resource_group.rgroup.name
    location                            = "westeurope"
    version                             = "12.0"
    administrator_login                 = var.db_username
    administrator_login_password        = var.db_password
}

##################################
# Define Database In DB Server
##################################
resource "azurerm_sql_database" "mspdatabase" {
    name                                = "mspdb"
    resource_group_name                 = azurerm_resource_group.rgroup.name
    location                            = "westeurope"
    edition                             = "Standard"
    server_name                         = azurerm_sql_server.mspdbserver.name
    requested_service_objective_name    = "S0"
}

#######################################
# Define Firewall Rules For DB Server
#######################################
resource "azurerm_sql_firewall_rule" "mspdbfirewall" {
    name                                = "AllowAccessForAzureResources"
    resource_group_name                 = azurerm_resource_group.rgroup.name
    server_name                         = azurerm_sql_server.mspdbserver.name
    start_ip_address                    = "0.0.0.0"
    end_ip_address                      = "0.0.0.0"
}


##########################################################################
# Get Public IP To Run Updates And Transfer Ansible Playbooks To Server
##########################################################################
data "azurerm_public_ip" "publicip" {
    name                                = azurerm_public_ip.msp_public_ip.name
    resource_group_name                 = azurerm_resource_group.rgroup.name
    
    depends_on                          = [azurerm_virtual_machine.appserver]
}

output "publicip" {
  value = data.azurerm_public_ip.publicip.ip_address
}

##########################################
# Get SQL Server URL
#########################################
data "azurerm_sql_server" "dburl" {
     name				= azurerm_sql_server.mspdbserver.name
     resource_group_name		= azurerm_resource_group.rgroup.name

     depends_on				= [azurerm_sql_server.mspdbserver]
}

output "serverurl" {
  value = data.azurerm_sql_server.dburl.id
}
