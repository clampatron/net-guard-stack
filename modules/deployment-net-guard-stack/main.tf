###############################################################################
# Net Guard Deployment Stack - corrected main.tf
# - RG-scoped dependsOn for rt/nsg phases
# - Absolute ARM IDs for subnet→NSG and subnet→UDR associations
# - coalesce(...) to avoid nulls
###############################################################################

locals {
  rg_resources = [
    for rg_name, rg in var.network_plan : {
      type       = "Microsoft.Resources/resourceGroups"
      apiVersion = "2021-04-01"
      name       = rg_name
      location   = var.location
    }
  ]

  rt_phase_deployments = [
    for rg_name, rg in var.network_plan : {
      type          = "Microsoft.Resources/deployments"
      apiVersion    = "2021-04-01"
      name          = "rt-${rg_name}"
      resourceGroup = rg_name

      dependsOn = [
        format("[resourceId('Microsoft.Resources/resourceGroups','%s')]", rg_name)
      ]

      properties = {
        mode = "Incremental"
        template = {
          "$schema"        = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
          "contentVersion" = "1.0.0.0"
          "resources" = [
            for rt_name, rt in rg.route_tables : {
              type       = "Microsoft.Network/routeTables"
              apiVersion = var.network_api_version
              name       = rt_name
              location   = var.location
              properties = {
                disableBgpRoutePropagation = try(rt.disable_bgp_route_propagation, false)
                routes = [
                  for r_name, r in rt.routes : {
                    name       = r_name
                    properties = merge(
                      {
                        addressPrefix = r.address_prefix
                        nextHopType   = r.next_hop_type
                      },
                      r.next_hop_ip != null ? { nextHopIpAddress = r.next_hop_ip } : {}
                    )
                  }
                ]
              }
            }
          ]
        }
      }
    }
  ]

  rt_phase_depends_all = [
    for rg_name in tolist(keys(var.network_plan)) :
    format(
      "[resourceId('%s','%s','Microsoft.Resources/deployments','%s')]",
      var.subscription_id,
      rg_name,
      "rt-${rg_name}"
    )
  ]

  nsg_phase_deployments = [
    for rg_name, rg in var.network_plan : {
      type          = "Microsoft.Resources/deployments"
      apiVersion    = "2021-04-01"
      name          = "nsg-${rg_name}"
      resourceGroup = rg_name

      dependsOn = [
        format("[resourceId('Microsoft.Resources/resourceGroups','%s')]", rg_name)
      ]

      properties = {
        mode = "Incremental"
        template = {
          "$schema"        = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
          "contentVersion" = "1.0.0.0"
          "resources" = [
            for nsg_name, nsg in try(rg.nsgs, {}) : {
              type       = "Microsoft.Network/networkSecurityGroups"
              apiVersion = var.network_api_version
              name       = nsg_name
              location   = var.location
              properties = {
                securityRules = [
                  for rule_name, rule in nsg.security_rules : {
                    name       = rule_name
                    properties = merge(
                      {
                        priority  = rule.priority
                        direction = rule.direction
                        access    = rule.access
                        protocol  = rule.protocol
                      },
                      try({ sourceAddressPrefixes      = rule.source_address_prefixes }, {}),
                      try({ destinationAddressPrefixes = rule.destination_address_prefixes }, {}),
                      try({ sourceAddressPrefix        = rule.source_address_prefix }, {}),
                      try({ destinationAddressPrefix   = rule.destination_address_prefix }, {}),
                      try({ sourcePortRanges           = rule.source_port_ranges }, {}),
                      try({ destinationPortRanges      = rule.destination_port_ranges }, {}),
                      try({ sourcePortRange            = rule.source_port_range }, {}),
                      try({ destinationPortRange       = rule.destination_port_range }, {}),
                      try({ description                = rule.description }, {})
                    )
                  }
                ]
              }
            }
          ]
        }
      }
    }
  ]

  nsg_phase_depends_all = [
    for rg_name in tolist(keys(var.network_plan)) :
    format(
      "[resourceId('%s','%s','Microsoft.Resources/deployments','%s')]",
      var.subscription_id,
      rg_name,
      "nsg-${rg_name}"
    )
  ]

  net_phase_deployments = [
    for rg_name, rg in var.network_plan : {
      type          = "Microsoft.Resources/deployments"
      apiVersion    = "2021-04-01"
      name          = "net-${rg_name}"
      resourceGroup = rg_name

      dependsOn = concat(
        [
          format("[resourceId('Microsoft.Resources/resourceGroups','%s')]", rg_name)
        ],
        local.rt_phase_depends_all,
        local.nsg_phase_depends_all
      )

      properties = {
        mode = "Incremental"
        template = {
          "$schema"        = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
          "contentVersion" = "1.0.0.0"
          "resources" = concat(

            # NAT public IPs (optional)
            flatten([
              for nat_name, nat in try(rg.nat_gateways, {}) : [
                for idx in range(try(nat.public_ip_count, 0)) : {
                  type       = "Microsoft.Network/publicIPAddresses"
                  apiVersion = var.network_api_version
                  name       = format("%s-pip-%02d", nat_name, idx + 1)
                  location   = var.location
                  sku        = { name = "Standard" }
                  properties = { publicIPAllocationMethod = "Static" }
                }
              ]
            ]),

            # NAT Gateways (optional)
            [
              for nat_name, nat in try(rg.nat_gateways, {}) : {
                type       = "Microsoft.Network/natGateways"
                apiVersion = var.network_api_version
                name       = nat_name
                location   = var.location
                sku        = { name = "Standard" }
                properties = {
                  idleTimeoutInMinutes = try(nat.idle_timeout_in_minutes, 4)
                  publicIpAddresses = concat(
                    try([ for id in nat.public_ip_ids : { id = id } ], []),
                    [
                      for idx in range(try(nat.public_ip_count, 0)) : {
                        id = format(
                          "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Network/publicIPAddresses/%s",
                          var.subscription_id,
                          rg_name,
                          format("%s-pip-%02d", nat_name, idx + 1)
                        )
                      }
                    ]
                  )
                }
                dependsOn = [
                  for idx in range(try(nat.public_ip_count, 0)) :
                  format(
                    "[resourceId('%s','%s','Microsoft.Network/publicIPAddresses','%s')]",
                    var.subscription_id,
                    rg_name,
                    format("%s-pip-%02d", nat_name, idx + 1)
                  )
                ]
              }
            ],

            # VNet & Subnets
            [
              for vnet_name, vnet in rg.vnets : {
                type       = "Microsoft.Network/virtualNetworks"
                apiVersion = var.network_api_version
                name       = vnet_name
                location   = var.location

                dependsOn  = [
                  for nat_name in distinct([for sn_name, sn in vnet.subnets : try(sn.nat_gateway_name, null)]) :
                  format(
                    "[resourceId('%s','%s','Microsoft.Network/natGateways','%s')]",
                    var.subscription_id,
                    rg_name,
                    nat_name
                  ) if nat_name != null
                ]

                properties = {
                  addressSpace = {
                    addressPrefixes = vnet.address_space
                  }
                  subnets = [
                    for sn_name, sn in vnet.subnets : {
                      name       = sn_name
                      properties = merge(
                        {
                          addressPrefix = sn.address_prefixes[0]
                        },

                        try({ privateEndpointNetworkPolicies      = sn.private_endpoint_network_policies }, {}),
                        try({ privateLinkServiceNetworkPolicies  = sn.private_link_service_network_policies }, {}),
                        try({
                          serviceEndpoints = [
                            for s in sn.service_endpoints : {
                              service   = s
                              locations = [var.location]
                            }
                          ]
                        }, {}),

                        sn.nsg_name != null ? {
                          networkSecurityGroup = {
                            id = format(
                              "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Network/networkSecurityGroups/%s",
                              var.subscription_id,
                              coalesce(try(sn.nsg_rg, null), rg_name),
                              sn.nsg_name
                            )
                          }
                        } : {},

                        try({
                          natGateway = {
                            id = format(
                              "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Network/natGateways/%s",
                              var.subscription_id,
                              rg_name,
                              sn.nat_gateway_name
                            )
                          }
                        }, {}),

                        try({
                          delegations = [
                            for del_name, del in sn.delegations : {
                              name       = del_name
                              properties = merge(
                                { serviceName = del.service_name },
                                try({ actions = del.actions }, {})
                              )
                            }
                          ]
                        }, {}),

                        {
                        routeTable = {
                          id = format(
                            "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Network/routeTables/%s",
                            var.subscription_id,
                            coalesce(
                              try(sn.route_table_rg, null),
                              contains(try(keys(rg.route_tables), []), sn.route_table_name) ? rg_name
                                : lookup(local.rt_owner_by_name, sn.route_table_name, null)
                            ),
                            sn.route_table_name
                          )
                        }

                        }
                      )
                    }
                  ]
                }
              }
            ]
          )
        }
      }
    }
  ]
  # Index route table ownership by name (unique only) so we can auto-resolve cross-RG refs
  rt_pairs = flatten([
    for rg_name, rg in var.network_plan : [
      for rt_name, _ in rg.route_tables : {
        name = rt_name
        rg   = rg_name
      }
    ]
  ])

  rt_names = distinct([for p in local.rt_pairs : p.name])

  # Only keep names that are unique across the whole plan
  rt_owner_by_name = {
    for n in local.rt_names :
    n => element([for p in local.rt_pairs : p.rg if p.name == n], 0)
    if length([for p in local.rt_pairs : p if p.name == n]) == 1
  }

  stack_template = {
    "$schema"        = "https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentTemplate.json#"
    "contentVersion" = "1.0.0.0"
    "resources"      = concat(
      local.rg_resources,
      local.rt_phase_deployments,
      local.nsg_phase_deployments,
      local.net_phase_deployments
    )
  }
}

# Optional preflight existence (external cross-RG) — left out for brevity in this correction pass

resource "azapi_resource" "deployment_stack" {
  type      = "Microsoft.Resources/deploymentStacks@${var.stack_api_version}"
  name      = "${var.name_prefix}-net-guard-stack"
  parent_id = "/subscriptions/${var.subscription_id}"
  location  = var.location

  body = {
    properties = {
      description      = "Net Guard Deployment Stack (subscription baseline with guard rails)"
      actionOnUnmanage = var.action_on_unmanage
      denySettings = {
        mode               = "denyWriteAndDelete"
        applyToChildScopes = true
        excludedPrincipals = var.excluded_principals
        excludedActions    = var.excluded_actions
      }
      template   = local.stack_template
      parameters = {}
    }
  }
}

output "deployment_stack_id" {
  value = azapi_resource.deployment_stack.id
}

output "stack_name" {
  value = azapi_resource.deployment_stack.name
}
