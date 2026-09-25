locals {
  # MetalLB only shares one address between Services that agree on this key.
  shared_ip_key = "traefik"
}
