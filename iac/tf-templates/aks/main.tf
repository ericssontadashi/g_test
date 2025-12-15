data "azurerm_resource_group" "rg" {
  name = "rg-${var.tags["project"]}-${var.tags["environment"]}-${var.tags["region"]}"
}

resource "azurerm_subnet" "network" {
  name                 = "snet-${var.tags["project"]}-aks-${var.tags["environment"]}-${var.tags["region"]}"
  resource_group_name  = "rg-${var.tags["project"]}-network-${var.tags["environment"]}-${var.tags["region"]}"
  virtual_network_name = "vnet-${var.tags["project"]}-${var.tags["environment"]}-${var.tags["region"]}"
  address_prefixes     = [var.subnet["address_prefixes"]]
}

data "azurerm_private_dns_zone" "dns" {
  provider            = azurerm.network
  name                = "privatelink.${var.tags["region_full"]}.azmk8s.io"
  resource_group_name = "rg-${var.tags["project"]}-network-prd-bs"
}

data "azurerm_nat_gateway" "ng" {
  count               = var.k8s_configuration.outbound_type == "userAssignedNATGateway" ? 1 : 0
  name                = "ng-${var.tags["project"]}-${var.tags["environment"]}-${var.tags["region"]}"
  resource_group_name = azurerm_subnet.network.resource_group_name
}

resource "azurerm_subnet_nat_gateway_association" "nga" {
  count          = var.k8s_configuration.outbound_type == "userAssignedNATGateway" ? 1 : 0
  subnet_id      = azurerm_subnet.network.id
  nat_gateway_id = data.azurerm_nat_gateway.ng[0].id
  depends_on = [
    azurerm_subnet.network
  ]
}

data "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.tags["project"]}-aks-${var.tags["environment"]}-${var.tags["region"]}"
  resource_group_name = "rg-${var.tags["project"]}-network-${var.tags["environment"]}-${var.tags["region"]}"
}

resource "azurerm_subnet_network_security_group_association" "nsg" {
  subnet_id                 = azurerm_subnet.network.id
  network_security_group_id = data.azurerm_network_security_group.nsg.id
}

data "azurerm_user_assigned_identity" "aks"{
  name = "id-${var.tags["project"]}-${var.tags["environment"]}-${var.tags["region"]}"
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_kubernetes_cluster" "k8s" {
  location             = var.tags["region_full"]
  name                 = "aks-${var.tags["project"]}-${var.tags["environment"]}-${var.tags["region"]}-${var.tags["version"]}"
  resource_group_name  = data.azurerm_resource_group.rg.name
  kubernetes_version   = var.k8s_configuration.orchestrator_version

  dns_prefix_private_cluster          = "aks-${var.tags["project"]}-${var.tags["type"]}-${var.tags["environment"]}"
  private_cluster_enabled             = true
  private_dns_zone_id                 = data.azurerm_private_dns_zone.dns.id
  private_cluster_public_fqdn_enabled = true
  tags                                = merge(var.tags, var.time_tags)

  default_node_pool {
    enable_auto_scaling          = true
    orchestrator_version          = var.k8s_configuration.orchestrator_version
    min_count                    = var.system_pool["system_min"]
    max_count                    = var.system_pool["system_max"]
    name                         = "system${var.tags["environment"]}"
    temporary_name_for_rotation  = "system${var.tags["environment"]}tmp"
    os_disk_type                 = "Managed"
    vm_size                      = var.system_pool["vm_size"]
    type                         = "VirtualMachineScaleSets"
    vnet_subnet_id               = azurerm_subnet.network.id
    max_pods                     = 250
    node_labels = {
      "type" = "system"
    }
    only_critical_addons_enabled = true
    zones                        = var.k8s_configuration.zones
    tags                         = var.tags
  }

  network_profile {
    network_plugin    = "kubenet"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    outbound_type     = var.k8s_configuration.outbound_type
    
    dynamic "nat_gateway_profile" {
      for_each = var.nat_gateway_profile != null ? ["true"] : []
      content {
        idle_timeout_in_minutes = var.nat_gateway_profile.idle_timeout_in_minutes
      }
    }
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.aks.id]
  }

  depends_on = [
    data.azurerm_resource_group.rg
  ]

  lifecycle {
    ignore_changes = [ default_node_pool[0].upgrade_settings ]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = var.user_node_pools

  name                  = format("%s%s",each.key,var.tags["environment"])
  kubernetes_cluster_id = azurerm_kubernetes_cluster.k8s.id
  orchestrator_version  = var.k8s_configuration.orchestrator_version
  vm_size               = each.value.vm_size
  zones                 = var.k8s_configuration.zones
  max_pods              = each.value.max_pods
  os_disk_type          = each.value.os_disk_type
  os_type               = "Linux"
  mode                  = "User"
  enable_auto_scaling   = each.value.enable_auto_scaling
  enable_node_public_ip = false
  enable_host_encryption= false
  fips_enabled          = false
  min_count             = each.value.enable_auto_scaling == true ? each.value.min_count : null
  max_count             = each.value.enable_auto_scaling == true ? each.value.max_count : null
  node_count            = each.value.enable_auto_scaling == false ? each.value.node_count : null
  node_taints           = each.value.node_taints
  vnet_subnet_id        = azurerm_subnet.network.id
  tags                  = var.tags
  node_labels = {
    "type" = each.value.label
  }
    depends_on = [
      azurerm_kubernetes_cluster.k8s
  ]
  lifecycle {
    ignore_changes = [ upgrade_settings ]
  }
}