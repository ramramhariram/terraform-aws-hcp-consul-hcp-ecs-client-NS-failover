# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
/*
resource "consul_config_entry" "service_intentions_deny" {
  name = "*"
  kind = "service-intentions"

  config_json = jsonencode({
    Sources = [
      {
        Name   = "*"
        Namespace = "az1"
        Action = "deny"
      }
    ]
  })
}

resource "consul_config_entry" "service_intentions_product_api" {
  name = "product-api"
  kind = "service-intentions"

  config_json = jsonencode({
    Sources = [
      {
        Name       = "public-api"
        Namespace = "az1"
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      },
    ]
  })
}

resource "consul_config_entry" "service_intentions_product_db" {
  name = "product-db"
  kind = "service-intentions"

  config_json = jsonencode({
    Sources = [
      {
        Name       = "product-api"
        Namespace = "az1"
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      },
    ]
  })
}

resource "consul_config_entry" "service_intentions_payment_api" {
  name = "payment-api"
  kind = "service-intentions"

  config_json = jsonencode({
    Sources = [
      {
        Name       = "public-api"
        Namespace = "az1"
        Action     = "allow"
        Precedence = 9
        Type       = "consul"
      },
    ]
  })
}
*/

resource "consul_intention" "all" {
  source_name      = "*"
  source_namespace = "az1"
  destination_name = "*"
  destination_namespace = "az1"
  action           = "allow"
}

#adding second intention for AZ2/namespace
resource "consul_intention" "all2" {
  source_name      = "*"
  source_namespace = "az1"
  destination_name = "*"
  destination_namespace = "az2"
  action           = "allow"
}

#adding second intention for AZ2/namespace
resource "consul_intention" "all3" {
  source_name      = "*"
  source_namespace = "az2"
  destination_name = "*"
  destination_namespace = "az2"
  action           = "allow"
}

