# Changelog

## [v1.1.0] - 2025-11-09

### Added
- **Cross‑RG UDR association**: `route_table_rg` on subnets. If omitted and the route table name is **unique** in the plan, the owning RG is **auto‑resolved**.
- **Cross‑RG NSG association**: `nsg_rg` on subnets for associating to NSGs in other RGs.
- **Configurable** `action_on_unmanage` with sensible defaults (`detach` for all scopes).

### Changed
- Subnet association IDs (UDR/NSG) now use **absolute ARM IDs** for reliability.
- Explicit **RG‑scoped dependsOn** for `rt-*`, `nsg-*`, and `net-*` nested deployments to eliminate race conditions.

### Fixed
- Incorrect `dependsOn` for Resource Group prerequisites that could cause `ResourceGroupNotFound` on fresh applies.
