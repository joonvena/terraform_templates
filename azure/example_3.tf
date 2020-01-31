provider "azurerm" {}

resource "azurerm_resource_group" "rgroup" {
    name                        = "k8s-test"
    location                    = var.location
}

resource "azurerm_public_ip" "k8sip" {
    name			= "k8s-ingress-public-ip"
    location			= var.location
    resource_group_name		= azurerm_resource_group.rgroup.name
    allocation_method		= "Static"
}

resource "azurerm_kubernetes_cluster" "k8scluster" {
    name                        = "testcluster"
    location                    = var.location
    resource_group_name         = azurerm_resource_group.rgroup.name
    dns_prefix                  = "master"

    default_node_pool {
        name                    = "default"
        node_count              = 1
        vm_size                 = "Standard_D2_v2"
    }

    service_principal {
        client_id               = "11d9cb6f-042b-4df9-b25a-e9efa0c50977"
        client_secret           = "9c887d80-3bd2-45b5-85db-4975a8874742"
    }

    tags = {
        Environment = "Development"
    }
}

output "client-certificate" {
    value = azurerm_kubernetes_cluster.k8scluster.kube_config.0.client_certificate
}

output "kube-config" {
    value = azurerm_kubernetes_cluster.k8scluster.kube_config_raw
}

data "azurerm_public_ip" "ip_address" {
    name			= azurerm_public_ip.k8sip.ip_address
    resource_group_name		= azurerm_resource_group.rgroup.name

    depends_on			= [azurerm_public_ip.k8sip]
}

output "ip_address" {
    value = data.azurerm_public_ip.ip_address
}
