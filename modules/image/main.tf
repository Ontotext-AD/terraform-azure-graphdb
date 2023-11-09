# TODO: We have to refer somehow to our shared image gallery when used from another tenant
# TF does not support this currently https://github.com/hashicorp/terraform-provider-azurerm/issues/17672#issuecomment-1290008487
data "azurerm_resource_group" "image" {
  name = "Packer-RG"
}

# TODO: Support for multiple architectures
data "azurerm_shared_image_version" "graphdb" {
  name                = "latest"
  image_name          = "${var.graphdb_version}-x86_64"
  gallery_name        = "GraphDB"
  resource_group_name = data.azurerm_resource_group.image.name
}
