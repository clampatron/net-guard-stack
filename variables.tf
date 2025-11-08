variable "subscription_id" {
  type = string
}

variable "location" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "excluded_principals" {
  type    = list(string)
  default = []
}

variable "excluded_actions" {
  type = list(string)
  default = [
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.Network/virtualNetworks/subnets/joinViaServiceEndpoint/action",
    "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
    "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
  ]
}

variable "action_on_unmanage" {
  type = object({
    managementGroups = optional(string, "detach")
    resourceGroups   = optional(string, "detach")
    resources        = optional(string, "detach")
  })

  default = {
    managementGroups = "detach"
    resourceGroups   = "detach"
    resources        = "detach"
  }
}

variable "stack_api_version" {
  type    = string
  default = "2024-03-01"
}

variable "network_api_version" {
  type    = string
  default = "2023-09-01"
}

variable "network_plan" {
  type = map(object({
    vnets = map(object({
      address_space = list(string)
      location      = optional(string)
      subnets = map(object({
        # NOTE: Only the FIRST entry is used; additional entries are ignored by design.
        address_prefixes                      = list(string)
        route_table_name                      = string
        private_endpoint_network_policies     = optional(string)
        private_link_service_network_policies = optional(string)
        service_endpoints                     = optional(list(string))
        nsg_name                              = optional(string)
        nat_gateway_name                      = optional(string)
        delegations = optional(map(object({
          service_name = string
          actions      = optional(list(string))
        })))
      }))
    }))

    route_tables = map(object({
      disable_bgp_route_propagation = optional(bool)
      routes = map(object({
        address_prefix = string
        next_hop_type  = string
        next_hop_ip    = optional(string)
      }))
    }))

    nsgs = optional(map(object({
      security_rules = map(object({
        priority                     = number
        direction                    = string
        access                       = string
        protocol                     = string
        source_address_prefixes      = optional(list(string))
        destination_address_prefixes = optional(list(string))
        source_address_prefix        = optional(string)
        destination_address_prefix   = optional(string)
        source_port_ranges           = optional(list(string))
        destination_port_ranges      = optional(list(string))
        source_port_range            = optional(string)
        destination_port_range       = optional(string)
        description                  = optional(string)
      }))
    })), {})

    nat_gateways = optional(map(object({
      idle_timeout_in_minutes = optional(number)
      public_ip_ids           = optional(list(string))
      public_ip_count         = optional(number)
    })), {})
  }))
}
