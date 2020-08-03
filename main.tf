variable libvirt_uri {}

provider libvirt {
  uri = var.libvirt_uri
}

locals {
  servers = {
    sv01 = {
      address = "192.168.99.101"
    }
    sv02 = {
      address = "192.168.99.102"
    }
  }
}

resource libvirt_pool dir {
  name = "hoge-dir"
  type = "dir"
  path = "/var/lib/libvirt/images/hoge"
}

resource libvirt_network private {
  name      = "hoge-private"
  mode      = "nat"
  addresses = ["192.168.99.0/24"]
  domain    = "hoge.test"

  dhcp { enabled = true }

  dns {
    enabled = true
    dynamic hosts {
      for_each = local.servers
      content {
        hostname = hosts.key
        ip       = hosts.value.address
      }
    }
  }
}

resource libvirt_cloudinit_disk cloudinit {
  name = "cloudinit.iso"
  pool = libvirt_pool.dir.name

  user_data = <<-EOS
    #cloud-config
    timezone: Asia/Tokyo
    ssh_pwauth: true
    chpasswd:
      list: root:password
      expire: false
    users:
      - name: ore
        groups: wheel
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ${file("${path.module}/ssh_authorized_keys")}
  EOS

  network_config = <<-EOS
    version: 2
    ethernets:
      eth0:
        match:
          name: eth0
        dhcp4: true
      eth1:
        match:
          name: eth1
        dhcp4: true
  EOS
}

resource libvirt_volume servers {
  for_each = local.servers

  name = "${each.key}.qcow2"
  pool = libvirt_pool.dir.name

  base_volume_name = "CentOS-7-x86_64-GenericCloud-2003.qcow2c"
  base_volume_pool = "default"
}

resource libvirt_domain servers {
  for_each = local.servers

  name       = each.key
  memory     = "1024"
  vcpu       = 1
  qemu_agent = true

  network_interface {
    macvtap        = "enp3s0"
    wait_for_lease = true
  }

  network_interface {
    network_id     = libvirt_network.private.id
    addresses      = [each.value.address]
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.servers[each.key].id
  }

  cloudinit = libvirt_cloudinit_disk.cloudinit.id

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

output servers {
  value = {
    for name, server in libvirt_domain.servers : name => [
      for interface in server.network_interface :
      coalesce(interface.addresses...) if length(interface.addresses) > 0
    ]
  }
}
