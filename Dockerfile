create a module in a similar private network style for azure containr app that will pull images from a private, on premise harbor registry

resource "azurerm_windows_web_app" "this" {
count = var.os == "Windows" ? 1 : 0
name = var.name
resource_group_name = var.resource_group_name
location = var.location
service_plan_id = var.service_plan_id
public_network_access_enabled = "false"

site_config {
# ftps_state = lookup(var.site_config, "ftps_state", null)
# scm_type = lookup(var.site_config, "scm_type", null)
}

}

resource "azurerm_linux_web_app" "this" {
count = var.os == "Linux" ? 1 : 0
name = var.name
resource_group_name = var.resource_group_name
location = var.location
service_plan_id = var.service_plan_id
vnet_image_pull_enabled = true
public_network_access_enabled = "false"
site_config {
# linux_fx_version = lookup(var.site_config, "linux_fx_version", lookup(var.site_config, "runtime", null))
# ftps_state = lookup(var.site_config, "ftps_state", null)
# scm_type = lookup(var.site_config, "scm_type", null)
}

application_stack {
docker_registry_url = var.docker_registry_url
docker_image_name = var.docker_image_name
docker_registry_username = var.docker_registry_username
docker_registry_password = var.docker_registry_password
}
}

resource "azurerm_app_service_virtual_network_swift_connection" "vnet_integration" {
app_service_id = var.os == "Windows" ? azurerm_windows_web_app.this[0].id : azurerm_linux_web_app.this[0].id
subnet_id = var.azurerm_network_interface_outbound
}

resource "azurerm_private_endpoint" "endpoint" {
name = var.private_endpoint_name
resource_group_name = var.resource_group_network_name
location = var.location
subnet_id = var.azurerm_network_interface_inbound

private_service_connection {
name = var.private_endpoint_name
private_connection_resource_id = var.os == "Windows" ? azurerm_windows_web_app.this[0].id : azurerm_linux_web_app.this[0].id
is_manual_connection = false
subresource_names = ["sites"]
}

private_dns_zone_group {
name = var.name
private_dns_zone_ids = var.dns_zones
}
}
