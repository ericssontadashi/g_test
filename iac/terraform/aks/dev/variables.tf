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
    vm_size = "Standard_D2as_v5"
    system_min = 1
    system_max = 2
  }
}

variable "user_node_pools" {
  default = {
    
  }
}

variable "subnet" {
  default = {
    address_prefixes = "10.84.0.0/26"
  }
}

variable "k8s_configuration" {
  default = {
    zones = ["1","2","3"]
    orchestrator_version = "1.29.7"
  }
}

variable "tags" {
  type = map(any)
  default = {
    "bu"              = ""
    "environment"     = "dev"
    "journey"         = "n/a"
    "organization"    = ""
    "project"         = ""
    "provider"        = "azure"
    "terraform"       = true
    "type"            = ""
    "version"         = "1"
    "region"          = "eu"
    "region_full"     = "eastus"
    "system"          = ""
    "location"        = "East US"
  }
}

variable "time_tags" {
  type = map(any)
  default = {
  }
}