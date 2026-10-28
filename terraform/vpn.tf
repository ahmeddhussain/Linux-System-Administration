# Replies to VPN clients must travel back through gw01. This route sends all
# traffic for the VPN address space from the private subnets to gw01's
# network interface.
resource "aws_route" "vpn_clients" {
  route_table_id         = module.network.private_route_table_id
  destination_cidr_block = var.vpn_cidr
  network_interface_id   = module.hosts["gw01"].primary_network_interface_id
}