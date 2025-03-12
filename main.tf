# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.11.1"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    # see https://github.com/hashicorp/terraform-provider-random
    random = {
      source  = "hashicorp/random"
      version = "3.7.1"
    }
    # see https://registry.terraform.io/providers/hashicorp/cloudinit
    # see https://github.com/hashicorp/terraform-provider-cloudinit
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.6"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.3"
    }
    # see https://registry.terraform.io/providers/ansible/ansible
    # see https://github.com/ansible/terraform-provider-ansible
    ansible = {
      source  = "ansible/ansible"
      version = "1.3.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "prefix" {
  default = "terraform_example"
}

variable "winrm_username" {
  default = "vagrant"
}

variable "winrm_password" {
  sensitive = true
  # set the administrator password.
  # NB the administrator password will be reset to this value by the cloudbase-init SetUserPasswordPlugin plugin.
  # NB this value must meet the Windows password policy requirements.
  #    see https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/password-must-meet-complexity-requirements
  default = "HeyH0Password"
}

# NB this uses the vagrant windows image imported from https://github.com/rgl/windows-vagrant.
variable "base_volume_name" {
  default = "windows-2022-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
  # default = "windows-2025-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
  # default = "windows-11-24h2-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
}

output "example_ip_address" {
  value = local.example_ip_address
}

locals {
  example_ip_cidr    = "10.17.3.0/24"
  example_ip_address = "10.17.3.2"
}

resource "ansible_host" "example" {
  name = "example"
  groups = [
    ansible_group.windows.name
  ]
  variables = {
    ansible_host = length(libvirt_domain.example.network_interface[0].addresses) > 0 ? libvirt_domain.example.network_interface[0].addresses[0] : ""
  }
}

resource "ansible_group" "windows" {
  name = "windows"
  variables = {
    # connection configuration.
    # see https://docs.ansible.com/ansible-core/2.18/collections/ansible/builtin/psrp_connection.html
    ansible_user                    = var.winrm_username
    ansible_password                = var.winrm_password
    ansible_connection              = "psrp"
    ansible_psrp_protocol           = "http"
    ansible_psrp_message_encryption = "never"
    ansible_psrp_auth               = "credssp"
  }
}

# NB this generates a single random number for the cloud-init instance-id.
resource "random_id" "example" {
  byte_length = 10
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/website/docs/r/network.markdown
resource "libvirt_network" "example" {
  name      = var.prefix
  mode      = "nat"
  domain    = "example.test"
  addresses = [local.example_ip_cidr]
  dhcp {
    enabled = true
  }
  dns {
    enabled    = true
    local_only = false
  }
}

# a multipart cloudbase-init cloud-config.
# NB the parts are executed by their declared order.
# see https://github.com/cloudbase/cloudbase-init
# see https://cloudbase-init.readthedocs.io/en/1.1.2/userdata.html#cloud-config
# see https://cloudbase-init.readthedocs.io/en/1.1.2/userdata.html#userdata
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
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/website/docs/r/cloudinit.html.markdown
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/libvirt/cloudinit_def.go#L139-L168
resource "libvirt_cloudinit_disk" "example_cloudinit" {
  name = "${var.prefix}_example_cloudinit.iso"
  meta_data = jsonencode({
    "instance-id" : random_id.example.hex,
  })
  user_data = data.cloudinit_config.example.rendered
}

# this uses the vagrant windows image imported from https://github.com/rgl/windows-vagrant.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/website/docs/r/volume.html.markdown
resource "libvirt_volume" "example_root" {
  name             = "${var.prefix}_root.img"
  base_volume_name = var.base_volume_name
  format           = "qcow2"
  size             = 66 * 1024 * 1024 * 1024 # 66GiB. this root FS is automatically resized by cloudbase-init (by its cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin plugin which is included in the rgl/windows-vagrant image).
}

# a data disk.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/website/docs/r/volume.html.markdown
resource "libvirt_volume" "example_data" {
  name   = "${var.prefix}_data.img"
  format = "qcow2"
  size   = 6 * 1024 * 1024 * 1024 # 6GiB.
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/website/docs/r/domain.html.markdown
resource "libvirt_domain" "example" {
  name = var.prefix
  machine  = "q35"
  firmware = "/usr/share/OVMF/OVMF_CODE.fd"
  cpu {
    mode = "host-passthrough"
  }
  vcpu   = 2
  memory = 1024
  video {
    type = "qxl"
  }
  xml {
    xslt = file("libvirt-domain.xsl")
  }
  qemu_agent = true
  cloudinit  = libvirt_cloudinit_disk.example_cloudinit.id
  disk {
    volume_id = libvirt_volume.example_root.id
    scsi      = true
  }
  disk {
    volume_id = libvirt_volume.example_data.id
    scsi      = true
  }
  network_interface {
    network_id     = libvirt_network.example.id
    wait_for_lease = true
    hostname       = "example"
    addresses      = [local.example_ip_address]
  }
}
