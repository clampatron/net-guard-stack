module "net_guard_stack" {
  source = "./modules/deployment-net-guard-stack"

  subscription_id = var.subscription_id
  location        = var.location
  name_prefix     = var.name_prefix

  excluded_principals = var.excluded_principals
  excluded_actions    = var.excluded_actions
  action_on_unmanage  = var.action_on_unmanage

  stack_api_version   = var.stack_api_version
  network_api_version = var.network_api_version

  network_plan = var.network_plan
}
