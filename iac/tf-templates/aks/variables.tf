variable "tenant_id" {
    default = ""
}

variable "provider_config" {
  type = map(any)
  default = {
    subscription_id = ""
  }
}

variable "provider_dns" {
  type = map(any)
  default = {
    subscription_id = ""
  }
}

variable "system_pool" {
  type = map(any)
  default = {
    vm_size = ""
    system_min = 1
    system_max = 1
  }
}

variable "user_node_pools" {
  default = {
    akspodinfra = {
      enable_auto_scaling = true
      min_count           = 0
      max_count           = 0
      vm_size             = ""
      os_disk_type        = "Managed"
      max_pods            = 250
      label               = "user"
      node_taints         = []
    }
  }
}

variable "subnet" {
  default = {
    address_prefixes = "x.x.x.x/24"
  }
}

variable "k8s_configuration" {
  type = object({
    zones = list(string)
    orchestrator_version = string
    outbound_type = optional(string, "userAssignedNATGateway")
  })
  default = {
    zones = ["1","2","3"]
    orchestrator_version = ""
    outbound_type = "userAssignedNATGateway"
  }
}

variable "nat_gateway_profile" {
  description = "List of objects with HTTP listeners configurations and custom error configurations."
  type = object({
    idle_timeout_in_minutes = number
  })
  default = null
}

variable "tags" {
  type = map(any)
  default = {
    "environment"     = ""
    "organization"    = ""
    "project"         = ""
    "terraform"       = true
    "type"            = ""
    "version"         = "v1"
    "region"          = "eu2"
    "region_full"     = "eastus2"
    "location"        = "East US2"
  }
}

variable "time_tags" {
  type = map(any)
  default = {
  }
}