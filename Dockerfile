moduke main.tf
# Local to generate resource group name with convention
locals {
  # Use subscription name if provided, otherwise fall back to subscription ID, or use custom name
  subscription_identifier = var.subscription_name != "" ? replace(lower(var.subscription_name), " ", "-") : var.subscription_id
  auto_rg_name            = var.resource_group_name != "" ? var.resource_group_name : "rg-log-alerts-${local.subscription_identifier}"
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
  subscription_lookup_keys = distinct(compact([
    var.subscription_key != "" ? var.subscription_key : "",
    local.subscription_identifier,
    trimspace(var.subscription_name),
    lower(trimspace(var.subscription_name)),
    var.subscription_id
  ]))
  excluded_rg_names  = distinct(flatten([for key in local.subscription_lookup_keys : lookup(var.excluded_rgs_by_subscription, key, [])]))
  excluded_rg_scopes = [for rg_name in local.excluded_rg_names : "/subscriptions/${var.subscription_id}/resourceGroups/${rg_name}"]
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
      "alertType"    = var.alert_type
      "scope"        = "subscription"
      "subscription" = var.subscription_id
      "severity"     = var.severity
      "operation"    = var.operation_name
      "timestamp"    = timestamp()
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

resource "azurerm_monitor_alert_processing_rule_suppression" "excluded_resource_groups" {
  count               = length(local.excluded_rg_scopes) > 0 ? 1 : 0
  name                = substr(replace("apr-suppress-activitylog-${local.subscription_identifier}", "_", "-"), 0, 80)
  resource_group_name = local.final_rg_name
  scopes              = local.excluded_rg_scopes

  condition {
    monitor_service {
      operator = "Equals"
      values   = ["ActivityLog Administrative"]
    }
  }

  schedule {
    recurrence {
      daily {
        start_time = "00:00:00"
        end_time   = "23:59:59"
      }
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [
    azurerm_monitor_activity_log_alert.this
  ]
}


module variables.tf
variable "alert_name" {
  description = "Name of the activity log alert"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name where alert will be created. If empty, will auto-generate as 'rg-log-alerts-{subscription_name}'"
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID to monitor"
  type        = string
}

variable "subscription_name" {
  description = "Azure subscription name (used for resource group naming). If empty, subscription_id will be used"
  type        = string
  default     = ""
}

variable "create_resource_group" {
  description = "Whether to create the resource group. Set to true only for the first alert in each subscription"
  type        = bool
  default     = false
}

variable "operation_name" {
  description = "Azure operation name to monitor"
  type        = string
}

variable "description" {
  description = "Alert description"
  type        = string
}

variable "action_group_id" {
  description = "Action group ID for notifications"
  type        = string
}

variable "alert_type" {
  description = "Type of alert for webhook properties"
  type        = string
}

variable "tags" {
  description = "Tags to apply to the alert"
  type        = map(string)
  default     = {}
}

variable "enabled" {
  description = "Whether the alert is enabled"
  type        = bool
  default     = true
}

variable "severity" {
  description = "Alert severity level"
  type        = string
  default     = "medium"
}

variable "category" {
  description = "Azure activity log category"
  type        = string
  default     = "Administrative"
}

variable "level" {
  description = "Azure activity log level"
  type        = string
  default     = "Informational"
}

variable "excluded_rgs_by_subscription" {
  description = "Map: subscription key -> list of resource group names to suppress notifications for"
  type        = map(list(string))
  default     = {}
}

variable "subscription_key" {
  description = "Subscription key used in excluded_rgs_by_subscription map (e.g., 'datacloud-prod'). If not provided, will try to match using subscription_name or subscription_id"
  type        = string
  default     = ""
}

calling stack main.tf
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
        subscription_key  = sub_key
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
  alert_name                   = each.value.alert_name
  resource_group_name          = azurerm_resource_group.alerts_rg_actuary_prod.name
  create_resource_group        = false
  location                     = var.location
  subscription_id              = each.value.subscription_id
  subscription_name            = each.value.subscription_name
  subscription_key             = each.value.subscription_key
  operation_name               = each.value.operation_name
  description                  = each.value.description
  action_group_id              = azurerm_monitor_action_group.email_alerts.id
  alert_type                   = each.value.alert_type
  severity                     = each.value.severity
  tags                         = local.default_tags
  excluded_rgs_by_subscription = local.excluded_rgs_by_subscription
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
  alert_name                   = each.value.alert_name
  resource_group_name          = azurerm_resource_group.alerts_rg_datacloud_prod_04.name
  create_resource_group        = false
  location                     = var.location
  subscription_id              = each.value.subscription_id
  subscription_name            = each.value.subscription_name
  subscription_key             = each.value.subscription_key
  operation_name               = each.value.operation_name
  description                  = each.value.description
  action_group_id              = azurerm_monitor_action_group.email_alerts.id
  alert_type                   = each.value.alert_type
  severity                     = each.value.severity
  tags                         = local.default_tags
  excluded_rgs_by_subscription = local.excluded_rgs_by_subscription
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
  alert_name                   = each.value.alert_name
  resource_group_name          = azurerm_resource_group.alerts_rg_datacloud_prod.name
  create_resource_group        = false
  location                     = var.location
  subscription_id              = each.value.subscription_id
  subscription_name            = each.value.subscription_name
  subscription_key             = each.value.subscription_key
  operation_name               = each.value.operation_name
  description                  = each.value.description
  action_group_id              = azurerm_monitor_action_group.email_alerts.id
  alert_type                   = each.value.alert_type
  severity                     = each.value.severity
  tags                         = local.default_tags
  excluded_rgs_by_subscription = local.excluded_rgs_by_subscription
}
module "alerts_cloudops_subscription" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"

  for_each = local.alerts_per_subscription["cloudops-subscription"]
  providers = {
    azurerm = azurerm.cloudops-subscription
  }
  alert_name                   = each.value.alert_name
  resource_group_name          = azurerm_resource_group.alerts_rg_cloudops_subscription.name
  create_resource_group        = false
  location                     = var.location
  subscription_id              = each.value.subscription_id
  subscription_name            = each.value.subscription_name
  subscription_key             = each.value.subscription_key
  operation_name               = each.value.operation_name
  description                  = each.value.description
  action_group_id              = azurerm_monitor_action_group.email_alerts.id
  alert_type                   = each.value.alert_type
  severity                     = each.value.severity
  tags                         = local.default_tags
  excluded_rgs_by_subscription = local.excluded_rgs_by_subscription
}

# Create activity log alerts for insait-prod
module "alerts_insait_prod" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"

  for_each = local.alerts_per_subscription["insait-prod"]
  providers = {
    azurerm = azurerm.insait-prod
  }
  alert_name                   = each.value.alert_name
  resource_group_name          = azurerm_resource_group.alerts_rg_insait_prod.name
  create_resource_group        = false
  location                     = var.location
  subscription_id              = each.value.subscription_id
  subscription_name            = each.value.subscription_name
  subscription_key             = each.value.subscription_key
  operation_name               = each.value.operation_name
  description                  = each.value.description
  action_group_id              = azurerm_monitor_action_group.email_alerts.id
  alert_type                   = each.value.alert_type
  severity                     = each.value.severity
  tags                         = local.default_tags
  excluded_rgs_by_subscription = local.excluded_rgs_by_subscription
}

# Create activity log alerts for prod-subscription
module "alerts_prod_subscription" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"

  for_each = local.alerts_per_subscription["prod-subscription"]
  providers = {
    azurerm = azurerm.prod-subscription
  }
  alert_name                   = each.value.alert_name
  resource_group_name          = azurerm_resource_group.alerts_rg_prod_subscription.name
  create_resource_group        = false
  location                     = var.location
  subscription_id              = each.value.subscription_id
  subscription_name            = each.value.subscription_name
  subscription_key             = each.value.subscription_key
  operation_name               = each.value.operation_name
  description                  = each.value.description
  action_group_id              = azurerm_monitor_action_group.email_alerts.id
  alert_type                   = each.value.alert_type
  severity                     = each.value.severity
  tags                         = local.default_tags
  excluded_rgs_by_subscription = local.excluded_rgs_by_subscription
}

# Create activity log alerts for sap-prod
module "alerts_sap_prod" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"

  for_each = local.alerts_per_subscription["sap-prod"]
  providers = {
    azurerm = azurerm.sap-prod
  }
  alert_name                   = each.value.alert_name
  resource_group_name          = azurerm_resource_group.alerts_rg_sap_prod.name
  create_resource_group        = false
  location                     = var.location
  subscription_id              = each.value.subscription_id
  subscription_name            = each.value.subscription_name
  subscription_key             = each.value.subscription_key
  operation_name               = each.value.operation_name
  description                  = each.value.description
  action_group_id              = azurerm_monitor_action_group.email_alerts.id
  alert_type                   = each.value.alert_type
  severity                     = each.value.severity
  tags                         = local.default_tags
  excluded_rgs_by_subscription = local.excluded_rgs_by_subscription
}

# Create activity log alerts for solugen-prod
module "alerts_solugen_prod" {
  source = "git::ssh://git@gitlab.harel-office.com/cloudops/Terraform/azure/modules.git//LogAlert?ref=master"

  for_each = local.alerts_per_subscription["solugen-prod"]
  providers = {
    azurerm = azurerm.solugen-prod
  }
  alert_name                   = each.value.alert_name
  resource_group_name          = azurerm_resource_group.alerts_rg_solugen_prod.name
  create_resource_group        = false
  location                     = var.location
  subscription_id              = each.value.subscription_id
  subscription_name            = each.value.subscription_name
  subscription_key             = each.value.subscription_key
  operation_name               = each.value.operation_name
  description                  = each.value.description
  action_group_id              = azurerm_monitor_action_group.email_alerts.id
  alert_type                   = each.value.alert_type
  severity                     = each.value.severity
  tags                         = local.default_tags
  excluded_rgs_by_subscription = local.excluded_rgs_by_subscription
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

# Alert Processing Rule Suppression - One per subscription with excluded resource groups
resource "azurerm_monitor_alert_processing_rule_suppression" "datacloud_prod" {
  provider            = azurerm.datacloud-prod
  name                = "apr-suppress-activitylog-datacloud-prod-subscription"
  resource_group_name = azurerm_resource_group.alerts_rg_datacloud_prod.name
  scopes = [
    for rg_name in local.excluded_rgs_by_subscription["datacloud-prod"] :
    "/subscriptions/${local.prod_subscriptions["datacloud-prod"].subscription_id}/resourceGroups/${rg_name}"
  ]

  condition {
    monitor_service {
      operator = "Equals"
      values   = ["ActivityLog Administrative"]
    }
  }

  schedule {
    recurrence {
      daily {
        start_time = "00:00:00"
        end_time   = "23:59:59"
      }
    }
  }

  tags = local.default_tags

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [
    module.alerts_datacloud_prod
  ]
}

resource "azurerm_monitor_alert_processing_rule_suppression" "datacloud_prod_04" {
  provider            = azurerm.datacloud-prod-04
  name                = "apr-suppress-activitylog-datacloud-prod-04-subscription"
  resource_group_name = azurerm_resource_group.alerts_rg_datacloud_prod_04.name
  scopes = [
    for rg_name in local.excluded_rgs_by_subscription["datacloud-prod-04"] :
    "/subscriptions/${local.prod_subscriptions["datacloud-prod-04"].subscription_id}/resourceGroups/${rg_name}"
  ]

  condition {
    monitor_service {
      operator = "Equals"
      values   = ["ActivityLog Administrative"]
    }
  }

  schedule {
    recurrence {
      daily {
        start_time = "00:00:00"
        end_time   = "23:59:59"
      }
    }
  }

  tags = local.default_tags

  lifecycle {
    ignore_changes = [tags]
  }

  depends_on = [
    module.alerts_datacloud_prod_04
  ]
}



calling stack locals.tf
locals {
  # Production subscriptions configuration
  prod_subscriptions = {
    "actuary-prod-subscription" = {
      subscription_id   = "redacted"
      subscription_name = "rdcated"
      environment       = "Production"
    }
    # "datacloud-prod-01" = {
    #   subscription_id = "as9"
    #   subscription_name = "Datascription"
    #   environment     = "Production"
    # }
    # "datacloud-prod-02" = {
    #   subscription_id = "839bef13as43025a56"
    #   subscription_name = "DataCloud asription"
    #   environment     = "Production"
    # }
    # "datacloud-prod-03" = {
    #   subscription_id = "2f745cas10ea613"
    #   subscription_name = "Dataasion"
    #   environment     = "Production"
    # }
    "datacloud-prod-04" = {
      subscription_id   = "9cas6358e"
      subscription_name = "DataCasscription"
      environment       = "Production"
    }
    # "datacloud-prod-05" = {
    #   subscription_id = "b161e8c6-fad5-4830-88e9-b098e44160cb"
    #   subscription_name = "DataCloud Production 5 Subscription"
    #   environment     = "Production"
    # }
    "datacloud-prod" = {
      subscription_id   = "bc0c9bd1-3c14-40bf-8078-d612bd7eaf29"
      subscription_name = "DataCloud Prod Subscription"
      environment       = "Production"
    }
    "cloudops-subscription" = {
      subscription_id   = "f4caa135-a7fe-4be3-958b-9bf4d15690d4"
      subscription_name = "CloudOps Prod Subscription"
      environment       = "Production"

  }

  # Azure operations to monitor with detailed configuration
  monitored_operations = {
    "vm" = {
      operation_name = "Microsoft.Compute/virtualMachines/delete"
      alert_type     = "VM.Delete"
      description    = "Alert when Virtual Machines are deleted"
      severity       = "high"
    }
    "storage" = {
      operation_name = "Microsoft.Storage/storageAccounts/delete"
      alert_type     = "Storage.Delete"
      description    = "Alert when Storage Accounts are deleted"
      severity       = "high"
    }
    "vnet" = {
      operation_name = "Microsoft.Network/virtualNetworks/delete"
      alert_type     = "VNET.Delete"
      description    = "Alert when Virtual Networks are deleted"
      severity       = "high"
    }
    "subnet" = {
      operation_name = "Microsoft.Network/virtualNetworks/subnets/delete"
      alert_type     = "Subnet.Delete"
      description    = "Alert when Subnets are deleted"
      severity       = "medium"
    }
    "sql-server" = {
      operation_name = "Microsoft.Sql/servers/delete"
      alert_type     = "SQL.Delete"
      description    = "Alert when SQL Servers are deleted"
      severity       = "critical"
    }
    "database" = {
      operation_name = "Microsoft.Sql/servers/databases/delete"
      alert_type     = "Database.Delete"
      description    = "Alert when SQL Databases are deleted"
      severity       = "high"
    }
    "route-table" = {
      operation_name = "Microsoft.Network/routeTables/delete"
      alert_type     = "RouteTable.Delete"
      description    = "Alert when Route Tables are deleted"
      severity       = "medium"
    }
    "databricks" = {
      operation_name = "Microsoft.Databricks/workspaces/delete"
      alert_type     = "Databricks.Delete"
      description    = "Alert when Databricks Workspaces are deleted"
      severity       = "high"
    }
    "data-factory" = {
      operation_name = "Microsoft.DataFactory/factories/delete"
      alert_type     = "DataFactory.Delete"
      description    = "Alert when Data Factory instances are deleted"
      severity       = "high"
    }
    "key-vault" = {
      operation_name = "Microsoft.KeyVault/vaults/delete"
      alert_type     = "KeyVault.Delete"
      description    = "Alert when Key Vaults are deleted"
      severity       = "critical"
    }
    "nsg" = {
      operation_name = "Microsoft.Network/networkSecurityGroups/delete"
      alert_type     = "NSG.Delete"
      description    = "Alert when Network Security Groups are deleted"
      severity       = "high"
    }
    "app-service" = {
      operation_name = "Microsoft.Web/sites/delete"
      alert_type     = "AppService.Delete"
      description    = "Alert when App Services are deleted"
      severity       = "medium"
    }
    "load-balancer" = {
      operation_name = "Microsoft.Network/loadBalancers/delete"
      alert_type     = "LoadBalancer.Delete"
      description    = "Alert when Load Balancers are deleted"
      severity       = "high"
    }
    "public-ip" = {
      operation_name = "Microsoft.Network/publicIPAddresses/delete"
      alert_type     = "PublicIP.Delete"
      description    = "Alert when Public IPs are deleted"
      severity       = "medium"
    }
    "app-gateway" = {
      operation_name = "Microsoft.Network/applicationGateways/delete"
      alert_type     = "AppGateway.Delete"
      description    = "Alert when Application Gateways are deleted"
      severity       = "high"
    }
    "resource-group" = {
      operation_name = "Microsoft.Resources/subscriptions/resourceGroups/delete"
      alert_type     = "ResourceGroup.Delete"
      description    = "CRITICAL: Alert when Resource Groups are deleted"
      severity       = "critical"
    }
  }

  # Default tags
  default_tags = {
    Environment = var.tag_env
    Owner       = var.tag_owner
    CostCenter  = var.tag_cost_center
    Project     = var.tag_project
    TF          = var.tag_git_location
    Purpose     = "Deletion Monitoring"
    ManagedBy   = "Terraform"
  }

  excluded_rgs_by_subscription = {
    "datacloud-prod" = [
      "redcated",
      "HRredcated2"
    ]
    "datacloud-prod-04" = [
      "redcated",
      "reddcated"
    ]
  }
}

calliung stack vrabies.tf
variable "primary_email" {
  description = "Primary email address for deletion alerts"
  type        = string
}


variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "alert_name_prefix" {
  description = "Prefix for alert resource names"
  type        = string
  default     = "prod-deletion"
}

variable "action_group_name" {
  description = "Name of the action group"
  type        = string
  default     = "prod-deletion-alerts"
}

variable "action_group_resource_group_name" {
  description = "Resource group name for the action group"
  type        = string
  default     = "HRL-RG-prod-alerts"
}

variable "action_group_short_name" {
  description = "Short name for action group (max 12 chars)"
  type        = string
  default     = "proddel"
}

# Tag variables
variable "tag_env" {
  description = "Environment tag value"
  type        = string
  default     = "Prod"
}

variable "tag_owner" {
  description = "Owner tag value"
  type        = string
  default     = "IT-Operations"
}

variable "tag_cost_center" {
  description = "Cost Center tag value"
  type        = string
  default     = "CloudOps"
}

variable "tag_project" {
  description = "Project tag value"
  type        = string
  default     = "Azure-Monitoring"
}

variable "tag_git_location" {
  description = "Git repository location"
  type        = string
  default     = "gitops-repos/Azure/terraform/projects/azureproddeletionalerts"
}


