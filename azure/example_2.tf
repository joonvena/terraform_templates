####################################################
# CodeSnippet Web Application Azure Infrastructure
####################################################

provider "azurerm" {}

resource "azurerm_resource_group" "rgroup" {
    name                            = "CodeSnippet_Web_Application"
    location                        = var.location 
}

# Random module to generate random id's
resource "random_id" "randomId" {
    keepers = {
        resource_group = azurerm_resource_group.rgroup.name
    }
    byte_length = 8
}

resource "azurerm_storage_account" "frontend" {
    name                            = "diag${random_id.randomId.hex}"
    resource_group_name             = azurerm_resource_group.rgroup.name
    location                        = var.location
    account_replication_type        = "LRS"
    account_tier                    = "Standard"
    account_kind                    = "StorageV2"

    # Terraform tries to change account_kind from Storage > StorageV2 despites its defined as StorageV2. This lifecycle policy prevents it
    lifecycle {
      ignore_changes = [
        account_kind,
      ]
    }

    # Currently you cant configure storage to host websites through Terraform. Remove this when the functionality is added to Terraform.
    provisioner "local-exec" {
        command = "az storage blob service-properties update --account-name ${azurerm_storage_account.frontend.name} --static-website --index-document index.html --404-document index.html"
    }  
}

resource "azurerm_storage_account" "backend" {
    name                            = "diag${random_id.randomId.hex}"
    resource_group_name             = azurerm_resource_group.rgroup.name
    location                        = var.location
    account_replication_type        = "LRS"
    account_tier                    = "Standard"
    account_kind		    = "Storage"
}

resource "azurerm_app_service_plan" "backend" {
    name                            = "codesnippet-backend-service-plan"
    location                        = var.location
    resource_group_name             = azurerm_resource_group.rgroup.name
    kind                            = "FunctionApp"

    sku {
        tier = "Dynamic"
        size = "Y1"
    }
}

resource "azurerm_function_app" "backend" {
    name                            = "codesnippet-backend-function-app"
    location                        = var.location
    resource_group_name             = azurerm_resource_group.rgroup.name
    app_service_plan_id             = azurerm_app_service_plan.backend.id
    storage_connection_string       = azurerm_storage_account.backend.primary_connection_string
}

# Define DB
resource "random_integer" "ri" {
    min = 10000
    max = 99999
}

resource "azurerm_cosmosdb_account" "dbaccount" {
    name                                = "codesnippet-application-db-${random_integer.ri.result}"
    location                            = var.location
    resource_group_name                 = azurerm_resource_group.rgroup.name
    offer_type                          = "Standard"
    kind                                = "MongoDB"

    enable_automatic_failover           = true
    
    consistency_policy {
        consistency_level               = "BoundedStaleness"
        max_interval_in_seconds         = 10
        max_staleness_prefix            = 200
    }

    geo_location {
        location                        = var.location
        failover_priority               = 0
    }
}

resource "azurerm_cosmosdb_mongo_database" "mongodb" {
    name                                = "codesnippet-app-db"
    resource_group_name                 = azurerm_resource_group.rgroup.name
    account_name                        = azurerm_cosmosdb_account.dbaccount.name
    throughput                          = 400
}

resource "azurerm_cosmosdb_mongo_collection" "snippetcollection" {
    name                                = "codesnippets"
    resource_group_name                 = azurerm_resource_group.rgroup.name
    account_name			= azurerm_cosmosdb_account.dbaccount.name
    database_name			= azurerm_cosmosdb_mongo_database.mongodb.name

    default_ttl_seconds                  = "777"
    shard_key				= "_id"
}
