module "dynamodb" {
  source = "../../modules/dynamodb"
  name   = "${var.project}-store"
}
