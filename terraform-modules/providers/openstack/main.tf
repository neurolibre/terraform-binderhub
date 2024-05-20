data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
}

# Define a network, only if not using Compute Canada
resource "openstack_networking_subnet_v2" "subnet" {
  count = var.is_computecanada ? 0 : 1

  name        = "subnet"
  network_id  = openstack_networking_network_v2.network_1[0].id
  ip_version  = 4
  cidr        = "10.0.1.0/24"
  enable_dhcp = true
}

# Define a subnet within the network, only if not using Compute Canada
resource "openstack_networking_network_v2" "network_1" {
  count = var.is_computecanada ? 0 : 1
  name = "${var.project_name}-network"
}


data "template_file" "kubeadm_master" {
  template = file("${path.module}/../../../cloud-init/kubeadm/master.yaml")

  vars = {
    admin_user      = var.admin_user
    project_name    = var.project_name
    nb_nodes        = var.nb_nodes
    docker_registry = var.docker_registry
    docker_id       = var.docker_id
    docker_password = var.docker_password
  }
}

data "openstack_networking_network_v2" "ext_network" {
  name = var.public_network
  external = true
}

data "openstack_networking_network_v2" "int_network" {
  name = var.cc_private_network
}

# Define a router, only if not using Compute Canada
resource "openstack_networking_router_v2" "router_1" {
  count = var.is_computecanada ? 0 : 1

  name                = "${var.project_name}-router"
  external_network_id = data.openstack_networking_network_v2.ext_network.id
}

# Attach the subnet to the router, only if not using Compute Canada
resource "openstack_networking_router_interface_v2" "router_interface_1" {
  count = var.is_computecanada ? 0 : 1
  router_id = openstack_networking_router_v2.router_1[0].id
  subnet_id = openstack_networking_subnet_v2.subnet[0].id
}

data "template_file" "kubeadm_node" {
  template = file("${path.module}/../../../cloud-init/kubeadm/node.yaml")
  vars = {
    master_ip       = openstack_compute_instance_v2.master.network[0].fixed_ip_v4
    admin_user      = var.admin_user
    docker_registry = var.docker_registry
    docker_id       = var.docker_id
    docker_password = var.docker_password
  }
}

data "template_file" "kubeadm_common" {
  template = file("${path.module}/../../../cloud-init/kubeadm/common.yaml")

  vars = {
    ssh_authorized_keys = indent(2, join("\n", formatlist("- %s", var.ssh_authorized_keys)))
  }
}

data "template_cloudinit_config" "node_config" {
  count = var.nb_nodes

  part {
    filename     = "common.yaml"
    merge_type   = "list(append)+dict(recurse_array)+str()"
    content_type = "text/cloud-config"
    content      = data.template_file.kubeadm_common.rendered
  }

  part {
    filename     = "node.yaml"
    merge_type   = "list(append)+dict(recurse_array)+str()"
    content_type = "text/cloud-config"
    content      = data.template_file.kubeadm_node.rendered
  }
}

data "template_cloudinit_config" "master_config" {
  part {
    filename     = "common.yaml"
    merge_type   = "list(append)+dict(recurse_array)+str()"
    content_type = "text/cloud-config"
    content      = data.template_file.kubeadm_common.rendered
  }

  part {
    filename     = "master.yaml"
    merge_type   = "list(append)+dict(recurse_array)+str()"
    content_type = "text/cloud-config"
    content      = data.template_file.kubeadm_master.rendered
  }
}

resource "openstack_compute_keypair_v2" "keypair" {
  name       = "${var.project_name}-keypair"
  public_key = element(var.ssh_authorized_keys, 0)
}

resource "openstack_blockstorage_volume_v3" "mastervolume" {
  name        = "master-volume"
  size        = var.instance_volume_size
  image_id    = data.openstack_images_image_v2.ubuntu.id
}


resource "openstack_networking_port_v2" "master" {
  name               = "${var.project_name}-master"
  admin_state_up     = "true"
  network_id         = data.openstack_networking_network_v2.int_network.id
  security_group_ids = [
    openstack_networking_secgroup_v2.common.id,
    "neurolibre-test-secgroup"
  ]
}

resource "openstack_compute_instance_v2" "master" {
  name            = "${var.project_name}-master"
  flavor_name     = var.os_flavor_master
  key_pair        = openstack_compute_keypair_v2.keypair.name
  security_groups = [openstack_networking_secgroup_v2.common.id,"neurolibre-test-secgroup"]
  user_data       = data.template_cloudinit_config.master_config.rendered

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.mastervolume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.master.id
  }
}

resource "openstack_blockstorage_volume_v3" "nodevolume" {
  count = var.nb_nodes
  name        = format("node-%02d-volume", count.index + 1)
  size        = var.instance_volume_size
  image_id    = data.openstack_images_image_v2.ubuntu.id
}

resource "openstack_compute_instance_v2" "node" {
  count = var.nb_nodes
  name  = "${var.project_name}-node${count.index + 1}"

  flavor_name     = var.os_flavor_node
  key_pair        = openstack_compute_keypair_v2.keypair.name
  security_groups = [openstack_networking_secgroup_v2.common.id,"neurolibre-test-secgroup"]
  user_data =element(
              data.template_cloudinit_config.node_config.*.rendered,
              count.index,)



  block_device {
    uuid                  = openstack_blockstorage_volume_v3.nodevolume[count.index].id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    name = var.is_computecanada ? data.openstack_networking_network_v2.int_network.name : "${var.project_name}-network"
  }
}

resource "openstack_networking_floatingip_v2" "fip_1" {
  pool = data.openstack_networking_network_v2.ext_network.name
}

resource "openstack_networking_floatingip_associate_v2" "fip_1" {
  floating_ip = openstack_networking_floatingip_v2.fip_1.address
  port_id     = openstack_networking_port_v2.master.id
}