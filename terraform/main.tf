# The company network and its security groups. The policy itself (roles,
# flows, IP-range rules) is in network-policy.tf.

module "network" {
  source = "./modules/network"

  name_prefix        = var.company_name
  vpc_cidr           = var.vpc_cidr
  availability_zone  = var.availability_zone
  subnets            = var.subnets
  enable_nat_gateway = var.enable_nat_gateway
}

module "security_groups" {
  source = "./modules/security-groups"

  name_prefix  = var.company_name
  vpc_id       = module.network.vpc_id
  roles        = local.roles
  flows        = local.flows
  cidr_ingress = local.cidr_ingress
  cidr_egress  = local.cidr_egress
}