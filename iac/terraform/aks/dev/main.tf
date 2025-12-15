module "aks" {
    source                = "../../../tf-templates/aks"
    provider_config       = var.provider_config
    provider_dns          = var.provider_dns
    tenant_id             = var.tenant_id
    system_pool           = var.system_pool
    user_node_pools       = var.user_node_pools
    subnet                = var.subnet
    k8s_configuration     = var.k8s_configuration
    tags                  = var.tags
    time_tags             = var.time_tags
}