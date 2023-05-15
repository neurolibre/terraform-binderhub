output "public_ip" {
  value = openstack_networking_floatingip_v2.fip_1.address
}

output "admin_user" {
  value = var.admin_user
}

output "docker_registry" {
  value = var.docker_registry
}

output "docker_id" {
  value = var.docker_id
}

output "docker_password" {
  value = var.docker_password
}

