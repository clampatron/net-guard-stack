# Net Guard Deployment Stack (net-guard-stack)

**Author:** Andrew Clarke

> This README reflects the **uploaded v1.0 baseline** exactly. No code changes have been made.

## Module path

This repo wires the stack module at:

```
./modules/deployment-net-guard-stack
```

## Quick start

You can configure the stack using **one of two approaches** (no code edits required beyond commenting/uncommenting the module wiring):

1. **Auto TFVARS** (recommended for pipelines): keep your configuration in `*.auto.tfvars` or `.auto.tfvars.json`. Terraform auto-loads these.
2. **Locals** (inline): use a `locals.tf` (values) and a companion `main.locals.tf` that wires the module from `local.*`.

> Toggle between these by commenting/uncommenting the corresponding module block in your root `.tf` files. The baseline is shipped as-is; choose the style you prefer without changing the module code.

## Providers & versions

- Found `versions.tf`; keep it authoritative for provider versions.
- Found `providers.tf`; provider blocks are defined.

## Inputs overview

- Root variables defined at `variables.tf`.

Key inputs you’ll typically set (via auto.tfvars or locals):

- `subscription_id` — target subscription
- `location` — stack home region (e.g., `uksouth`)
- `name_prefix` — prefix for the Deployment Stack resource name
- `excluded_principals` — break‑glass object IDs
- `excluded_actions` — allowed join actions (NIC attach, service endpoints, private endpoints)
- `action_on_unmanage` — recommended: `detach` for mgmt groups/RGs/resources
- `network_plan` — declarative map of RG → VNets → Subnets → UDRs/Routes (optionally NSGs, NAT Gateways, Delegations)

## Usage

Initialize and apply:

```bash
terraform init -upgrade
terraform apply -auto-approve
```

## Behavior & guard rails

- The Deployment Stack applies **denyWriteAndDelete** to stack‑owned resources, blocking out‑of‑band writes/deletes.
- **Day‑2 operations** are preserved via `excluded_actions` (subnet joins), so NIC attach, service endpoints and private endpoints continue to work.
- **Subnet ↔ Route Table association** is enforced as part of desired state.
- **Unmanage** is safe: `detach` avoids deletes when removing the stack.

## Data model (network_plan)

The `network_plan` map drives everything (RG → Route Tables/Routes → VNets → Subnets).
Typical configurable elements include:

- **Route Tables**: routes and `disable_bgp_route_propagation`
- **VNets**: address space
- **Subnets**: single `addressPrefix`, UDR association, optional `service_endpoints`,
  `private_endpoint_network_policies`, `private_link_service_network_policies`, `delegations`, `nsg_name`, `nat_gateway_name`
- **NSGs**: rules (singular or plural address/port fields supported)
- **NAT Gateways**: attach existing PIPs or specify a count to auto‑create Standard static PIPs

> Note: ARM/ARM‑via‑Stack expects **singular** `addressPrefix` per subnet; if the input allows a list, only the **first** item is used.

## Out of scope

- VNet Peering, Service Endpoint Policies, and Private Link Service resource creation
- Cross‑RG associations (associations are resolved within the same RG)
- Multiple address prefixes per subnet

## Troubleshooting

- **ResourceGroupNotFound** on cold start: ensure the RG creation is modeled before the RG‑scoped nested deployment and/or an explicit dependency is present (the v1.0 baseline templates generally handle ordering, but transient races can occur if the RG is deleted out‑of‑band mid‑apply). Re‑apply is typically sufficient.
- **Deny assignment blocks portal edits**: make changes via Terraform, or use `excluded_principals` / `excluded_actions` temporarily (remove afterward).
- **Private Endpoint creation blocked**: ensure the target subnet sets `private_endpoint_network_policies = "Disabled"` in the plan; creation of the PE resource is out of scope.
