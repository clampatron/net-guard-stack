# Net Guard Deployment Stack (net-guard-stack)

**Author:** Andrew Clarke

Deploy a subscription‑scope **Deployment Stack** that owns your network baseline from a declarative `network_plan` (RG → Route Tables/NSGs → VNets/Subnets). The stack enforces guard‑rails (`denyWriteAndDelete` with safe exceptions) and **always** binds Subnet ↔ Route Table.

---

## What’s new (v1.1.0)

- **Cross‑RG UDR association** via `route_table_rg` on each subnet. If omitted and the route table name is **unique** in the plan, we **auto‑resolve** the owning RG by name.
- **Cross‑RG NSG association** via `nsg_rg` on each subnet (back‑compat: if omitted, the NSG is assumed local to the subnet’s RG).
- **Correct RG dependencies** for all RG‑scoped nested deployments (no more race on resource group creation).
- **Absolute ARM IDs** for Subnet→UDR and Subnet→NSG links (avoids symbolic resolution issues).
- **Configurable** `action_on_unmanage` (defaults to `detach` for `managementGroups`, `resourceGroups`, and `resources`).

> These changes preserve previous behaviour when the new fields are not used.

---

## Module path

```
./modules/deployment-net-guard-stack
```

## Quick start

Configure with **one** of these patterns (no code changes to the module required):

1. **Auto TFVARS** (recommended for pipelines): put your config in `*.auto.tfvars` or `*.auto.tfvars.json`.
2. **Locals** (inline): place values in `locals.tf` and wire the module from `local.*` in your root module.

> Toggle by commenting/uncommenting the corresponding module block in your root `.tf` files.

## Providers & versions

- `hashicorp/azurerm` **>= 3.114.0**
- `azure/azapi` **>= 2.0.0**

Keep your `versions.tf` authoritative.

## Inputs (overview)

Root variables (see `variables.tf` for full schema):

- `subscription_id` *(string)* — target subscription ID
- `location` *(string, default `uksouth`)* — region for the stack and regional resources
- `name_prefix` *(string)* — prefix for the Deployment Stack name
- `excluded_principals` *(list(string))* — break‑glass object IDs
- `excluded_actions` *(list(string))* — safe day‑2 actions (joins, service endpoints, private endpoints)
- `action_on_unmanage` *(object)* — defaults to `detach` for `managementGroups`, `resourceGroups`, `resources`
- `network_plan` *(map(object))* — declarative model: RG → Route Tables/NSGs → VNets/Subnets (+ optional NAT, Delegations)

## Data model (network_plan)

Each **resource group** entry can define **route tables**, **NSGs**, **VNets**, and optional **NAT Gateways**.

### Route Tables
- `disable_bgp_route_propagation` *(bool, optional)*
- `routes` *(map)*: `{ address_prefix, next_hop_type, next_hop_ip? }`

### NSGs
- `security_rules` *(map)* with standard fields. Either singular or plural address/port fields are supported.

### VNets
- `address_space` *(list(string))*

### Subnets
- `address_prefixes` *(list(string))* — **ARM requires a single `addressPrefix`; the module uses the first item**
- `route_table_name` *(string)* — required
- `route_table_rg` *(string, optional)* — set for **cross‑RG** UDR association; if omitted and the RT name is **unique** in the plan, the owning RG is auto‑resolved
- `nsg_name` *(string, optional)* — associate an NSG
- `nsg_rg` *(string, optional)* — set for **cross‑RG** NSG association; if omitted, the NSG is assumed to be in the same RG as the vNet/subnet
- `service_endpoints` *(list(string), optional)* — e.g., `["Microsoft.Storage"]`
- `private_endpoint_network_policies` *(string, optional)* — `"Disabled"` to allow Private Endpoints
- `private_link_service_network_policies` *(string, optional)*
- `delegations` *(map, optional)* — `{ service_name, actions? }`
- `nat_gateway_name` *(string, optional)* — attach an existing or same-RG NAT Gateway (module can create one if modeled under the RG)

## Orchestration (how the stack deploys)

1. **Resource Groups** (subscription scope)  
2. **Route Tables** (RG‑scoped nested deployments)  
3. **NSGs** (RG‑scoped nested deployments)  
4. **VNets/Subnets** (RG‑scoped nested deployments) with explicit `dependsOn` for RT/NSG phases  
   - Subnet associations use **absolute ARM IDs** for UDR/NSG targets
   - NAT Gateways are created/attached before subnets that reference them

This ordering avoids race conditions and guarantees associations can resolve across RG boundaries.

## Example

```hcl
module "net_guard_stack" {
  source = "./modules/deployment-net-guard-stack"

  subscription_id = var.subscription_id
  location        = var.location
  name_prefix     = var.name_prefix

  excluded_principals = var.excluded_principals
  excluded_actions    = var.excluded_actions

  network_plan = {{
    "rg-demo-core-uks-01" = {{
      route_tables = {{
        "rt-core-01" = {{
          routes = {{
            "default" = {{
              address_prefix = "0.0.0.0/0"
              next_hop_type  = "VirtualAppliance"
              next_hop_ip    = "10.42.0.4"
            }}
          }}
        }}
      }}
      nsgs = {{
        "nsg-core-01" = {{
          security_rules = {{
            "allow-ssh" = {{
              priority  = 100
              direction = "Inbound"
              access    = "Allow"
              protocol  = "Tcp"
              source_address_prefixes      = ["*"]
              destination_address_prefixes = ["*"]
              destination_port_ranges      = ["22"]
            }}
          }}
        }}
      }}
      vnets = {{
        "core-vnet-01" = {{
          address_space = ["10.42.0.0/16"]
          subnets = {{
            "snet-app-01" = {{
              address_prefixes = ["10.42.1.0/24"]
              route_table_name = "rt-core-01"
              nsg_name         = "nsg-core-01"
            }}
            "snet-db-01" = {{
              address_prefixes = ["10.42.2.0/24"]
              route_table_name = "rt-core-02"      # cross‑RG UDR association
              route_table_rg   = "rg-demo-core-uks-02"
            }}
          }}
        }}
      }}
    }}

    "rg-demo-core-uks-02" = {{
      route_tables = {{
        "rt-core-02" = {{ routes = {{}} }}
      }}
      nsgs = {{
        "nsg-core-02" = {{ security_rules = {{}} }}
      }}
      vnets = {{
        "vnet-core-20" = {{
          address_space = ["10.50.0.0/16"]
          subnets = {{
            "default" = {{
              address_prefixes = ["10.50.1.0/24"]
              route_table_name = "rt-core-02"      # local UDR association
              nsg_name         = "nsg-core-01"     # cross‑RG NSG association
              nsg_rg           = "rg-demo-core-uks-01"
            }}
          }}
        }}
      }}
    }}
  }}
}
```

## Behaviour & guard rails

- A **deny assignment** is applied to stack‑managed resources: `denyWriteAndDelete`.
- **Day‑2 operations** (joins) are preserved via `excluded_actions` (NIC attach, service endpoints, private endpoints).
- **Safe unmanage**: `action_on_unmanage` defaults to `detach` to avoid deletions if the stack is removed.
- **Idempotent**: Missing resources are created; existing ones are adopted/updated to desired state.

## Out of scope / caveats

- VNet peering, Service Endpoint Policies, and Private Link **Service** creation (we only set subnet flags to allow hosting).
- Multiple `addressPrefix` values per subnet aren’t supported by ARM; only the **first** value in `address_prefixes` is used.
- NAT Gateway cross‑RG association isn’t modeled (attach NATs from the same RG).

## Troubleshooting

- **ResourceGroupNotFound** on first apply: ensure RG nested deployments depend on the RG resource (this module does). Re‑apply if you deleted RGs out‑of‑band mid‑apply.
- **Deny assignment blocks portal edits**: make changes via Terraform, or use temporary `excluded_principals` / `excluded_actions` and remove after the change.
- **Private Endpoint creation blocked**: set `private_endpoint_network_policies = "Disabled"` on the target subnet. Creation of the PE resource is out‑of‑scope.

---

## Usage snippet

```bash
terraform init -upgrade
terraform apply -auto-approve
```
