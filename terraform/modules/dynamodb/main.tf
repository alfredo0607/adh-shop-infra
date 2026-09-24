# Single-table design. One table serves every access pattern through overloaded
# generic keys, which is the idiomatic DynamoDB approach and avoids the
# cross-table transactions a table-per-entity layout would force.

resource "aws_dynamodb_table" "this" {
  name = var.name

  # On demand. Traffic here is unpredictable and low, and provisioned capacity
  # would mean either paying for idle throughput or throttling under a spike.
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "PK"
  range_key = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  # Listing products, and a customer's transactions in time order.
  #
  # Declared with key_schema rather than the hash_key/range_key pair: those are
  # deprecated inside a secondary index as of AWS provider 6.x.
  global_secondary_index {
    name            = "GSI1"
    projection_type = "ALL"

    key_schema {
      attribute_name = "GSI1PK"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "GSI1SK"
      key_type       = "RANGE"
    }
  }

  # Abandoned stock reservations and spent idempotency keys clean themselves up.
  # Without this, a customer who closes the browser mid-checkout holds inventory
  # forever.
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  # Deleting the table that holds transactions must never be a side effect of a
  # refactor.
  deletion_protection_enabled = var.deletion_protection

  tags = var.tags
}
