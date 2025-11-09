Module main.tf
# Local to generate resource group name with convention
locals {
  # Use subscription name if provided, otherwise fall back to subscription ID, or use custom name
  subscription_identifier = var.subscription_name != "" ? replace(lower(var.subscription_name), " ", "-") : var.subscription_id
  auto_rg_name = var.resource_group_name != "" ? var.resource_group_name : "rg-log-alerts-${local.subscription_identifier}"
}

# Create resource group only if requested
resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = local.auto_rg_name
  location = var.location
  tags     = var.tags
  
  lifecycle {
    ignore_changes = [tags]
  }
}

# Use the provided resource group name if not creating, otherwise use the created one
locals {
  final_rg_name = var.create_resource_group ? azurerm_resource_group.this[0].name : local.auto_rg_name
}

resource "azurerm_monitor_activity_log_alert" "this" {
  name                = var.alert_name
  resource_group_name = local.final_rg_name
  location            = var.location
  scopes              = ["/subscriptions/${var.subscription_id}"]
  description         = var.description
  enabled             = var.enabled

  criteria {
    category       = var.category
    operation_name = var.operation_name
    level          = var.level
  }

  action {
    action_group_id = var.action_group_id
    webhook_properties = {
      "alertType"     = var.alert_type
      "scope"         = "subscription"
      "subscription"  = var.subscription_id
      "severity"      = var.severity
      "operation"     = var.operation_name
      "timestamp"     = timestamp()
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags,
      action[0].webhook_properties
    ]
  }

  depends_on = [
    azurerm_resource_group.this
  ]
}



# module call main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
      configuration_aliases = [
        azurerm.actuary-prod-subscription,
        # azurerm.datacloud-prod-01,
        # azurerm.datacloud-prod-02,
        # azurerm.datacloud-prod-03,
        azurerm.datacloud-prod-04,
        # azurerm.datacloud-prod-05,
        azurerm.datacloud-prod,
        azurerm.insait-prod,
        azurerm.prod-subscription,
        azurerm.cloudops-subscription,
        azurerm.sap-prod,
        azurerm.solugen-prod,
        # azurerm.vdihorizon-prod,
      ]
    }
  }
}

# Action Group for notifications (created in CloudOps subscription)
resource "azurerm_monitor_action_group" "email_alerts" {
  name                = var.action_group_name
  resource_group_name = var.action_group_resource_group_name
  location            = "global"
  short_name          = var.action_group_short_name

  email_receiver {
    name          = "primary-alert"
    email_address = var.primary_email
  }

  tags = local.default_tags
}

# Create resource groups for alerts (one per subscription)
resource "azurerm_resource_group" "alerts_rg_actuary_prod" {
  provider = azurerm.actuary-prod-subscription
  name     = "rg-log-alerts-${replace(lower(local.prod_subscriptions["actuary-prod-subscription"].subscription_name), " ", "-")}"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_resource_group" "alerts_rg_cloudops_subscription" {
  provider = azurerm.cloudops-subscription
  name     = "rg-log-alerts-${replace(lower(local.prod_subscriptions["cloudops-subscription"].subscription_name), " ", "-")}"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_resource_group" "alerts_rg_datacloud_prod_04" {
  provider = azurerm.datacloud-prod-04
  name     = "rg-log-alerts-${replace(lower(local.prod_subscriptions["datacloud-prod-04"].subscription_name), " ", "-")}"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_resource_group" "alerts_rg_datacloud_prod" {
  provider = azurerm.datacloud-prod
  name     = "rg-log-alerts-${replace(lower(local.prod_subscriptions["datacloud-prod"].subscription_name), " ", "-")}"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_resource_group" "alerts_rg_insait_prod" {
  provider = azurerm.insait-prod
  name     = "rg-log-alerts-${replace(lower(local.prod_subscriptions["insait-prod"].subscription_name), " ", "-")}"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_resource_group" "alerts_rg_prod_subscription" {
  provider = azurerm.prod-subscription
  name     = "rg-log-alerts-${replace(lower(local.prod_subscriptions["prod-subscription"].subscription_name), " ", "-")}"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_resource_group" "alerts_rg_sap_prod" {
  provider = azurerm.sap-prod
  name     = "rg-log-alerts-${replace(lower(local.prod_subscriptions["sap-prod"].subscription_name), " ", "-")}"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_resource_group" "alerts_rg_solugen_prod" {
  provider = azurerm.solugen-prod
  name     = "rg-log-alerts-${replace(lower(local.prod_subscriptions["solugen-prod"].subscription_name), " ", "-")}"
  location = var.location
  tags     = local.default_tags
}

# Alert combinations per subscription
locals {
  # Group operations by subscription for easier module creation
  alerts_per_subscription = {
    for sub_key, sub_value in local.prod_subscriptions : sub_key => {
      for op_key, op_value in local.monitored_operations :
      op_key => {
        alert_name        = "${var.alert_name_prefix}-${sub_key}-${op_key}"
        subscription_id   = sub_value.subscription_id
        subscription_name = sub_value.subscription_name
        operation_name    = op_value.operation_name
        description       = "${op_value.description} in ${sub_value.subscription_name}"
        alert_type        = op_value.alert_type
        severity          = op_value.severity
      }
    }
  }
}

# Create activity log alerts for actuary-prod-subscription
module "alerts_actuary_prod" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
  for_each = local.alerts_per_subscription["actuary-prod-subscription"]
  providers = {
    azurerm = azurerm.actuary-prod-subscription
  }
  alert_name            = each.value.alert_name
  resource_group_name   = azurerm_resource_group.alerts_rg_actuary_prod.name
  create_resource_group = false
  location              = var.location
  subscription_id       = each.value.subscription_id
  subscription_name     = each.value.subscription_name
  operation_name        = each.value.operation_name
  description           = each.value.description
  action_group_id       = azurerm_monitor_action_group.email_alerts.id
  alert_type            = each.value.alert_type
  severity              = each.value.severity
  tags                  = local.default_tags
}

# Create activity log alerts for datacloud-prod-01
# module "alerts_datacloud_prod_01" {
#   source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
#   for_each = local.alerts_per_subscription["datacloud-prod-01"]
#   providers = {
#     azurerm = azurerm.datacloud-prod-01
#   }
#   alert_name          = each.value.alert_name
#   
#   location            = var.location
#   subscription_id     = each.value.subscription_id
#   operation_name      = each.value.operation_name
#   description         = each.value.description
#   action_group_id     = azurerm_monitor_action_group.email_alerts.id
#   alert_type          = each.value.alert_type
#   severity            = each.value.severity
#   tags                = local.default_tags
# }

# Create activity log alerts for datacloud-prod-02
# module "alerts_datacloud_prod_02" {
#   source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
#   for_each = local.alerts_per_subscription["datacloud-prod-02"]
#   providers = {
#     azurerm = azurerm.datacloud-prod-02
#   }
#   alert_name          = each.value.alert_name
#   
#   location            = var.location
#   subscription_id     = each.value.subscription_id
#   operation_name      = each.value.operation_name
#   description         = each.value.description
#   action_group_id     = azurerm_monitor_action_group.email_alerts.id
#   alert_type          = each.value.alert_type
#   severity            = each.value.severity
#   tags                = local.default_tags
# }

# Create activity log alerts for datacloud-prod-03
# module "alerts_datacloud_prod_03" {
#   source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
#   for_each = local.alerts_per_subscription["datacloud-prod-03"]
#   providers = {
#     azurerm = azurerm.datacloud-prod-03
#   }
#   alert_name          = each.value.alert_name
#   
#   location            = var.location
#   subscription_id     = each.value.subscription_id
#   operation_name      = each.value.operation_name
#   description         = each.value.description
#   action_group_id     = azurerm_monitor_action_group.email_alerts.id
#   alert_type          = each.value.alert_type
#   severity            = each.value.severity
#   tags                = local.default_tags
# }

# Create activity log alerts for datacloud-prod-04
module "alerts_datacloud_prod_04" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
  for_each = local.alerts_per_subscription["datacloud-prod-04"]
  providers = {
    azurerm = azurerm.datacloud-prod-04
  }
  alert_name            = each.value.alert_name
  resource_group_name   = azurerm_resource_group.alerts_rg_datacloud_prod_04.name
  create_resource_group = false
  location              = var.location
  subscription_id       = each.value.subscription_id
  subscription_name     = each.value.subscription_name
  operation_name        = each.value.operation_name
  description           = each.value.description
  action_group_id       = azurerm_monitor_action_group.email_alerts.id
  alert_type            = each.value.alert_type
  severity              = each.value.severity
  tags                  = local.default_tags
}

# Create activity log alerts for datacloud-prod-05
# module "alerts_datacloud_prod_05" {
#   source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
#   for_each = local.alerts_per_subscription["datacloud-prod-05"]
#   providers = {
#     azurerm = azurerm.datacloud-prod-05
#   }
#   alert_name          = each.value.alert_name
#   
#   location            = var.location
#   subscription_id     = each.value.subscription_id
#   operation_name      = each.value.operation_name
#   description         = each.value.description
#   action_group_id     = azurerm_monitor_action_group.email_alerts.id
#   alert_type          = each.value.alert_type
#   severity            = each.value.severity
#   tags                = local.default_tags
# }

# Create activity log alerts for datacloud-prod
module "alerts_datacloud_prod" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
  for_each = local.alerts_per_subscription["datacloud-prod"]
  providers = {
    azurerm = azurerm.datacloud-prod
  }
  alert_name            = each.value.alert_name
  resource_group_name   = azurerm_resource_group.alerts_rg_datacloud_prod.name
  create_resource_group = false
  location              = var.location
  subscription_id       = each.value.subscription_id
  subscription_name     = each.value.subscription_name
  operation_name        = each.value.operation_name
  description           = each.value.description
  action_group_id       = azurerm_monitor_action_group.email_alerts.id
  alert_type            = each.value.alert_type
  severity              = each.value.severity
  tags                  = local.default_tags
}
module "alerts_cloudops_subscription" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"

  for_each = local.alerts_per_subscription["cloudops-subscription"]
  providers = {
    azurerm = azurerm.cloudops-subscription
  }
  alert_name            = each.value.alert_name
  resource_group_name   = azurerm_resource_group.alerts_rg_cloudops_subscription.name
  create_resource_group = false
  location              = var.location
  subscription_id       = each.value.subscription_id
  subscription_name     = each.value.subscription_name
  operation_name        = each.value.operation_name
  description           = each.value.description
  action_group_id       = azurerm_monitor_action_group.email_alerts.id
  alert_type            = each.value.alert_type
  severity              = each.value.severity
  tags                  = local.default_tags
}

# Create activity log alerts for insait-prod
module "alerts_insait_prod" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
  for_each = local.alerts_per_subscription["insait-prod"]
  providers = {
    azurerm = azurerm.insait-prod
  }
  alert_name            = each.value.alert_name
  resource_group_name   = azurerm_resource_group.alerts_rg_insait_prod.name
  create_resource_group = false
  location              = var.location
  subscription_id       = each.value.subscription_id
  subscription_name     = each.value.subscription_name
  operation_name        = each.value.operation_name
  description           = each.value.description
  action_group_id       = azurerm_monitor_action_group.email_alerts.id
  alert_type            = each.value.alert_type
  severity              = each.value.severity
  tags                  = local.default_tags
}

# Create activity log alerts for prod-subscription
module "alerts_prod_subscription" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
  for_each = local.alerts_per_subscription["prod-subscription"]
  providers = {
    azurerm = azurerm.prod-subscription
  }
  alert_name            = each.value.alert_name
  resource_group_name   = azurerm_resource_group.alerts_rg_prod_subscription.name
  create_resource_group = false
  location              = var.location
  subscription_id       = each.value.subscription_id
  subscription_name     = each.value.subscription_name
  operation_name        = each.value.operation_name
  description           = each.value.description
  action_group_id       = azurerm_monitor_action_group.email_alerts.id
  alert_type            = each.value.alert_type
  severity              = each.value.severity
  tags                  = local.default_tags
}

# Create activity log alerts for sap-prod
module "alerts_sap_prod" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
  for_each = local.alerts_per_subscription["sap-prod"]
  providers = {
    azurerm = azurerm.sap-prod
  }
  alert_name            = each.value.alert_name
  resource_group_name   = azurerm_resource_group.alerts_rg_sap_prod.name
  create_resource_group = false
  location              = var.location
  subscription_id       = each.value.subscription_id
  subscription_name     = each.value.subscription_name
  operation_name        = each.value.operation_name
  description           = each.value.description
  action_group_id       = azurerm_monitor_action_group.email_alerts.id
  alert_type            = each.value.alert_type
  severity              = each.value.severity
  tags                  = local.default_tags
}

# Create activity log alerts for solugen-prod
module "alerts_solugen_prod" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
  for_each = local.alerts_per_subscription["solugen-prod"]
  providers = {
    azurerm = azurerm.solugen-prod
  }
  alert_name            = each.value.alert_name
  resource_group_name   = azurerm_resource_group.alerts_rg_solugen_prod.name
  create_resource_group = false
  location              = var.location
  subscription_id       = each.value.subscription_id
  subscription_name     = each.value.subscription_name
  operation_name        = each.value.operation_name
  description           = each.value.description
  action_group_id       = azurerm_monitor_action_group.email_alerts.id
  alert_type            = each.value.alert_type
  severity              = each.value.severity
  tags                  = local.default_tags
}

# Create activity log alerts for vdihorizon-prod
# module "alerts_vdihorizon_prod" {
#   source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"
  
#   for_each = local.alerts_per_subscription["vdihorizon-prod"]
#   providers = {
#     azurerm = azurerm.vdihorizon-prod
#   }
#   alert_name          = each.value.alert_name
#   
#   location            = var.location
#   subscription_id     = each.value.subscription_id
#   operation_name      = each.value.operation_name
#   description         = each.value.description
#   action_group_id     = azurerm_monitor_action_group.email_alerts.id
#   alert_type          = each.value.alert_type
#   severity            = each.value.severity
#   tags                = local.default_tags
# }





