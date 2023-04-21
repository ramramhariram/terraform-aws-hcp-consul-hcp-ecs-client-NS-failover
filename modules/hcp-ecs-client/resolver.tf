resource "consul_config_entry" "service_resolver" {
  kind = "service-resolver"
  name = "product-db"
  config_json = jsonencode({
  "apiVersion": "consul.hashicorp.com/v1alpha1",
  "kind": "ServiceResolver",
  "metadata": null,
  "name": "product-db",
  "namespace": "az1",
  "spec": null,
  "connectTimeout": "15s",
  "failover": null,
  "*": null,
  "targets": [
    {
      "namespace": "az2"
    },
    {
      "namespace": "az3"
    }
  ]
})
}