# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.16.1"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    # see https://github.com/hashicorp/terraform-provider-random
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
    # see https://registry.terraform.io/providers/northwood-labs/corefunc
    # see https://github.com/northwood-labs/terraform-provider-corefunc
    corefunc = {
      source  = "northwood-labs/corefunc"
      version = "2.3.0"
    }
    # see https://registry.terraform.io/providers/hashicorp/cloudinit
    # see https://github.com/hashicorp/terraform-provider-cloudinit
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.4.0"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.9"
    }
    # see https://registry.terraform.io/providers/ansible/ansible
    # see https://github.com/ansible/terraform-provider-ansible
    ansible = {
      source  = "ansible/ansible"
      version = "1.5.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "prefix" {
  type    = string
  default = "terraform-libvirt-ansible-windows-example"
}

variable "workspace_path" {
  type = string
}

variable "winrm_username" {
  type    = string
  default = "vagrant"
}

variable "winrm_password" {
  type      = string
  sensitive = true
  # set the administrator password.
  # NB the administrator password will be reset to this value by the cloudbase-init SetUserPasswordPlugin plugin.
  # NB this value must meet the Windows password policy requirements.
  #    see https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/password-must-meet-complexity-requirements
  default = "HeyH0Password"
}

# NB this uses the vagrant windows image imported from https://github.com/rgl/windows-vagrant.
variable "base_volume_name" {
  type    = string
  default = "windows-2022-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
  # default = "windows-2025-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
  # default = "windows-11-24h2-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
}

output "example_ip_address" {
  value = local.example_ip_address
}

locals {
  cpu_sockets = 1
  cpu_cores   = 4
  cpu_threads = 1
  memory_mb   = 4 * 1024
}

locals {
  example_ip_cidr = "10.17.3.0/24"
  example_ip_address = one(flatten([
    for interface in data.libvirt_domain_interface_addresses.example.interfaces : [
      for addr in interface.addrs : addr.addr
      if addr.type == "ipv4" && provider::corefunc::net_cidr_contains(local.example_ip_cidr, addr.addr)
    ]
  ]))
}

# see https://gitlab.com/libosinfo/osinfo-db/-/blob/main/data/os/microsoft.com/win-2k22.xml.in
# see https://gitlab.com/libosinfo/osinfo-db/-/blob/main/data/os/microsoft.com/win-2k25.xml.in
# see https://gitlab.com/libosinfo/osinfo-db/-/blob/main/data/os/microsoft.com/win-11.xml.in
locals {
  windows_version = regex("windows-([^-]+)", var.base_volume_name)[0]
  windows_version_to_os_map = {
    "2022" = "2k22"
    "2025" = "2k25"
    "11"   = "11"
  }
  os_id = "http://microsoft.com/win/${lookup(local.windows_version_to_os_map, local.windows_version, "2k22")}"
}

resource "ansible_host" "example" {
  name = "example"
  groups = [
    ansible_group.windows.name,
  ]
  variables = {
    ansible_host = local.example_ip_address
  }
}

resource "ansible_host" "example-wsl-ubuntu" {
  name = "example-wsl-ubuntu"
  groups = [
    ansible_group.wsl.name,
  ]
  variables = {
    ansible_host     = local.example_ip_address
    wsl_distribution = "Ubuntu-26.04"
    wsl_user         = "ubuntu"
  }
}

resource "ansible_group" "windows" {
  name = "windows"
  variables = {
    # connection configuration.
    # see https://docs.ansible.com/ansible-core/2.20/collections/ansible/builtin/psrp_connection.html
    ansible_user                    = var.winrm_username
    ansible_password                = var.winrm_password
    ansible_connection              = "psrp"
    ansible_psrp_protocol           = "http"
    ansible_psrp_message_encryption = "never"
    ansible_psrp_auth               = "credssp"
  }
}

resource "ansible_group" "wsl" {
  name = "wsl"
  variables = {
    ansible_user               = var.winrm_username
    ansible_password           = var.winrm_password
    ansible_connection         = "community.general.wsl"
    ansible_python_interpreter = "/usr/bin/python3"
  }
}

# NB this generates a single random number for the cloud-init instance-id.
resource "random_id" "example" {
  byte_length = 10
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/network
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/network.md
resource "libvirt_network" "example" {
  name = var.prefix
  forward = {
    nat = {
      ports = [
        {
          start = 1024
          end   = 65535
        }
      ]
    }
  }
  domain = {
    name = "example.test"
  }
  ips = [
    {
      address = cidrhost(local.example_ip_cidr, 1)
      netmask = cidrnetmask(local.example_ip_cidr)
      dhcp = {
        ranges = [
          {
            start = cidrhost(local.example_ip_cidr, 2)
            end   = cidrhost(local.example_ip_cidr, -2)
          }
        ]
      }
    }
  ]
}

# a multipart cloudbase-init cloud-config.
# NB the parts are executed by their declared order.
# see https://github.com/cloudbase/cloudbase-init
# see https://cloudbase-init.readthedocs.io/en/1.1.8/userdata.html#cloud-config
# see https://cloudbase-init.readthedocs.io/en/1.1.8/userdata.html#userdata
# see https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/config
# see https://www.terraform.io/docs/configuration/expressions.html#string-literals
data "cloudinit_config" "example" {
  gzip          = false
  base64_encode = false
  part {
    filename     = "enable-winrm-service-auth-credssp.ps1"
    content_type = "text/x-shellscript"
    content      = <<-EOF
      #ps1_sysnative
      Set-StrictMode -Version Latest
      $ErrorActionPreference = 'Stop'
      $ProgressPreference = 'SilentlyContinue'
      # wait for the winrm service to be ready.
      while (!(Test-WSMan -ErrorAction SilentlyContinue)) {
        Start-Sleep -Seconds 1
      }
      # enable credssp.
      Enable-WSManCredSSP -Role Server -Force
      EOF
  }
  part {
    content_type = "text/cloud-config"
    content      = <<-EOF
      #cloud-config
      users:
        - name: ${jsonencode(var.winrm_username)}
          passwd: ${jsonencode(var.winrm_password)}
          primary_group: Administrators
          ssh_authorized_keys:
            - ${jsonencode(trimspace(file("~/.ssh/id_rsa.pub")))}
      EOF
  }
}

# a cloudbase-init cloud-config disk.
# NB this creates an iso image that will be used by the NoCloud cloudbase-init datasource.
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/cloudinit_disk
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/cloudinit_disk.md
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/internal/provider/cloudinit_disk_resource.go#L291-L341
resource "libvirt_cloudinit_disk" "example_cloudinit" {
  name = "${var.prefix}_example_cloudinit.iso"
  meta_data = jsonencode({
    "instance-id" : random_id.example.hex,
  })
  user_data = data.cloudinit_config.example.rendered
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/volume.md
resource "libvirt_volume" "example_cloudinit" {
  pool = "default"
  name = "${var.prefix}_example_cloudinit.iso"
  create = {
    content = {
      url = libvirt_cloudinit_disk.example_cloudinit.path
    }
  }
}

# this uses the vagrant windows image imported from https://github.com/rgl/windows-vagrant.
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/volume.md
resource "libvirt_volume" "example_root" {
  pool     = "default"
  name     = "${var.prefix}_root.img"
  capacity = 66 * 1024 * 1024 * 1024 # 66GiB. this root FS is automatically resized by cloudbase-init (by its cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin plugin which is included in the rgl/windows-vagrant image).
  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    format = {
      type = "qcow2"
    }
    path = "/var/lib/libvirt/images/${var.base_volume_name}"
  }
}

# a data disk.
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/volume.md
resource "libvirt_volume" "example_data" {
  pool     = "default"
  name     = "${var.prefix}_data.img"
  capacity = 6 * 1024 * 1024 * 1024 # 6GiB.
  target = {
    format = {
      type = "qcow2"
    }
  }
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/domain
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/domain.md
resource "libvirt_domain" "example" {
  name        = var.prefix
  description = "see ${var.workspace_path}"
  running     = true
  type        = "kvm"
  vcpu        = local.cpu_sockets * local.cpu_cores * local.cpu_threads
  memory      = local.memory_mb
  memory_unit = "MiB"
  features = {
    acpi = true
    apic = {}
    hyper_v = {
      mode = "passthrough"
    }
    vm_port = {
      state = "off"
    }
  }
  metadata = {
    xml = <<-EOF
      <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
        <libosinfo:os id="${local.os_id}"/>
      </libosinfo:libosinfo>
      EOF
  }
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
  }
  cpu = {
    mode = "host-passthrough"
    topology = {
      sockets = local.cpu_sockets
      cores   = local.cpu_cores
      threads = local.cpu_threads
    }
  }
  clock = {
    offset = "localtime"
    timer = [
      {
        name        = "rtc"
        tick_policy = "catchup"
      },
      {
        name        = "pit"
        tick_policy = "delay"
      },
      {
        name    = "hpet"
        present = "no"
      },
      {
        name    = "hypervclock"
        present = "yes"
      },
    ]
  }
  devices = {
    graphics = [
      {
        spice = {
          auto_port = true
          listeners = [
            {
              address = {}
            }
          ]
        }
      }
    ]
    videos = [
      {
        model = {
          type    = "qxl"
          primary = "yes"
          vram    = 65536
          ram     = 65536
          vga_mem = 16384
          heads   = 1
        }
      }
    ]
    controllers = [
      {
        type  = "scsi"
        model = "virtio-scsi"
      },
      {
        type = "virtio-serial"
      }
    ]
    channels = [
      {
        source = {
          unix = {
            mode = "bind"
          }
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      },
      {
        source = {
          spice_vmc = true
        }
        target = {
          virt_io = {
            name = "com.redhat.spice.0"
          }
        }
      }
    ]
    rngs = [
      {
        model = "virtio"
        backend = {
          random = "/dev/urandom"
        }
      }
    ]
    disks = [
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = libvirt_volume.example_root.pool
            volume = libvirt_volume.example_root.name
          }
        }
        block_io = {
          # set the discard_granularity to make windows happy.
          # NB when using a qemu/kvm based hypervisor, ssd trim is only available when
          #    discard_granularity is set to 8K (or higher), otherwise,
          #    defrag.exe C: /H /L fails as: Incorrect function. (0x80070001) error.
          #    NB when using proxmox, there is no explicit way to set discard_granularity.
          #       it could be set using qemu_additional_args argument, but when using
          #       non-root user token, that fails as: only root can set 'args' config, so
          #       we do not do it.
          #    see lsblk -o NAME,PHY-SEC,LOG-SEC,DISC-GRAN,DISC-ALN
          #    see fsutil.exe behavior query DisableDeleteNotify
          #    see /etc/libvirt/qemu/{vm_name}.xml (when using libvirt).
          #    see /etc/pve/qemu-server/{vm_id}.conf (when using proxmox).
          # see https://libvirt.org/formatdomain.html
          # see https://github.com/virtio-win/kvm-guest-drivers-windows/issues/1574
          discard_granularity = 8 * 1024
        }
        target = {
          bus = "scsi"
          dev = "sda"
        }
        wwn = format("000000000000aa%02x", 0)
      },
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = libvirt_volume.example_data.pool
            volume = libvirt_volume.example_data.name
          }
        }
        block_io = {
          # set the discard_granularity to make windows happy.
          # NB when using a qemu/kvm based hypervisor, ssd trim is only available when
          #    discard_granularity is set to 8K (or higher), otherwise,
          #    defrag.exe C: /H /L fails as: Incorrect function. (0x80070001) error.
          #    NB when using proxmox, there is no explicit way to set discard_granularity.
          #       it could be set using qemu_additional_args argument, but when using
          #       non-root user token, that fails as: only root can set 'args' config, so
          #       we do not do it.
          #    see lsblk -o NAME,PHY-SEC,LOG-SEC,DISC-GRAN,DISC-ALN
          #    see fsutil.exe behavior query DisableDeleteNotify
          #    see /etc/libvirt/qemu/{vm_name}.xml (when using libvirt).
          #    see /etc/pve/qemu-server/{vm_id}.conf (when using proxmox).
          # see https://libvirt.org/formatdomain.html
          # see https://github.com/virtio-win/kvm-guest-drivers-windows/issues/1574
          discard_granularity = 8 * 1024
        }
        target = {
          bus = "scsi"
          dev = "sdb"
        }
        wwn = format("000000000000ab%02x", 0)
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.example_cloudinit.pool
            volume = libvirt_volume.example_cloudinit.name
          }
        }
        target = {
          bus = "scsi"
          dev = "hdd"
        }
        serial = "cloudinit"
      }
    ]
    interfaces = [
      {
        type = "network"
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.example.name
          }
        }
        wait_for_ip = {
          network = local.example_ip_cidr
          source  = "agent"
          timeout = 300 # 300s (5m).
        }
      }
    ]
  }
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/data-sources/domain_interface_addresses
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/data-sources/domain_interface_addresses.md
data "libvirt_domain_interface_addresses" "example" {
  domain = libvirt_domain.example.name
  source = "agent"
}
