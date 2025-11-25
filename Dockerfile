{
  "properties": {
    "displayName": "Require deletion_protection Tag for Resource Groups",
    "description": "Ensures a deletion_protection tag is applied to all Resource Groups and its value is either Enabled or Disabled.",
    "policyType": "Custom",
    "mode": "All",
    "metadata": {
      "category": "Tags"
    },
    "version": "1.0.0",
    "parameters": {
      "allowedDeletionProtectionValues": {
        "type": "Array",
        "metadata": {
          "displayName": "Allowed deletion_protection values",
          "description": "Allowed values for the deletion_protection tag."
        },
        "allowedValues": [
          "Enabled",
          "Disabled"
        ],
        "defaultValue": [
          "Enabled",
          "Disabled"
        ]
      }
    },
    "policyRule": {
      "if": {
        "allOf": [
          {
            "field": "type",
            "equals": "Microsoft.Resources/subscriptions/resourceGroups"
          },
          {
            "field": "tags['deletion_protection']",
            "notIn": "[parameters('allowedDeletionProtectionValues')]"
          },
          {
            "not": {
              "field": "name",
              "like": "AzureBackupRG_*"
            }
          },
          {
            "not": {
              "field": "name",
              "like": "cloud-shell-storage-*"
            }
          },
          {
            "not": {
              "field": "name",
              "like": "databricks-rg-*"
            }
          },
          {
            "not": {
              "field": "name",
              "like": "Default-ActivityLogAlerts*"
            }
          },
          {
            "not": {
              "field": "name",
              "like": "DefaultResourceGroup-*"
            }
          },
          {
            "not": {
              "field": "name",
              "like": "MC_*"
            }
          },
          {
            "not": {
              "field": "name",
              "like": "NetworkWatcherRG"
            }
          },
          {
            "not": {
              "field": "name",
              "like": "VstsRG-*"
            }
          }
        ]
      },
      "then": {
        "effect": "deny"
      }
    }
  }
}



The request content was invalid and could not be deserialized: 'Could not find member 'properties' on object of type 'PolicyDefinitionProperties'. Path 'properties.properties', line 12, position 17.'.

