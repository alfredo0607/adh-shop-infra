# Network stack.
#
# Separated from the application stack on purpose: the network changes rarely
# and the application changes constantly, so they have very different blast
# radii. A mistake while deploying the API should not be able to touch routing.
#
# Other stacks consume these outputs through terraform_remote_state rather than
# by rebuilding resource names as strings. A duplicated name is a contract kept
# by human memory: rename one side and the other keeps applying cleanly while
# pointing at something that no longer exists.

module "vpc" {
  source = "../../modules/vpc"

  name       = var.project
  region     = var.region
  cidr_block = var.vpc_cidr

  # Public: the container host. Must answer on 80/443 and receive the
  # HTTP-01 challenge from Let's Encrypt.
  public_subnet_cidrs = var.public_subnet_cidrs

  # Private: the Redis cache. No route to the internet gateway at all.
  private_subnet_cidrs = var.private_subnet_cidrs

  enable_flow_logs = var.enable_flow_logs
}
