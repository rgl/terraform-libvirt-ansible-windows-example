# Usage (Ubuntu 20.04 host)

Install Terraform:

```bash
wget https://releases.hashicorp.com/terraform/0.15.0/terraform_0.15.0_linux_amd64.zip
unzip terraform_0.15.0_linux_amd64.zip
sudo install terraform /usr/local/bin
rm terraform terraform_*_linux_amd64.zip
```

Install the [terraform libvirt provider](https://github.com/dmacvicar/terraform-provider-libvirt):

```bash
wget https://github.com/dmacvicar/terraform-provider-libvirt/releases/download/v0.6.3/terraform-provider-libvirt-0.6.3+git.1604843676.67f4f2aa.Ubuntu_20.04.amd64.tar.gz
tar xf terraform-provider-libvirt-0.6.3+git.1604843676.67f4f2aa.Ubuntu_20.04.amd64.tar.gz
install -d ~/.local/share/terraform/plugins/registry.terraform.io/dmacvicar/libvirt/0.6.3/linux_amd64
install terraform-provider-libvirt ~/.local/share/terraform/plugins/registry.terraform.io/dmacvicar/libvirt/0.6.3/linux_amd64/
rm terraform-provider-libvirt terraform-provider-libvirt-*.amd64.tar.gz
```

Or install it from source:

```bash
sudo apt-get install -y libvirt-dev
git clone https://github.com/dmacvicar/terraform-provider-libvirt.git
cd terraform-provider-libvirt
make
install -d ~/.local/share/terraform/plugins/registry.terraform.io/dmacvicar/libvirt/0.6.3/linux_amd64
install terraform-provider-libvirt ~/.local/share/terraform/plugins/registry.terraform.io/dmacvicar/libvirt/0.6.3/linux_amd64/
cd ..
```

Install Ansible:

```bash
# install ansible dependencies from system packages.
# see https://docs.ansible.com/ansible-core/latest/installation_guide/intro_installation.html#installing-ansible-with-pip
sudo apt-get install -y --no-install-recommends \
    python3-pip \
    python3-venv \
    python3-cryptography \
    python3-yaml
# (re)create the venv.
rm -rf .ansible-venv
python3 -m venv --system-site-packages .ansible-venv
source .ansible-venv/bin/activate
# install ansible and dependencies.
# NB this pip install will display several "error: invalid command 'bdist_wheel'"
#    messages, those can be ignored.
python3 -m pip install -r requirements.txt
```

Install the ansible terraform dynamic inventory provider:

```bash
ansible_terraform_inventory_version='2.2.0' # see https://github.com/nbering/terraform-inventory/releases
wget -q https://github.com/nbering/terraform-inventory/releases/download/v$ansible_terraform_inventory_version/terraform.py
# make it use the python3 binary instead of just python.
sed -i -E 's,#!.+,#!/usr/bin/python3,' terraform.py
# fix the following error/warning:
#   /etc/ansible/terraform.py:390: DeprecationWarning: 'encoding' is ignored and deprecated. It will be removed in Python 3.9   return json.loads(out_cmd, encoding=encoding)
sed -i -E 's/return json.loads\(out_cmd, encoding=encoding\)/return json.loads(out_cmd)/g' terraform.py
install -m 755 terraform.py .ansible-venv/terraform.py
rm terraform.py
```

Create the infrastructure:

```bash
terraform init
terraform plan -out=tfplan
time terraform apply tfplan
```

**NB** if you have errors alike `Could not open '/var/lib/libvirt/images/terraform_example_root.img': Permission denied'` you need to reconfigure libvirt by setting `security_driver = "none"` in `/etc/libvirt/qemu.conf` and restart libvirt with `sudo systemctl restart libvirtd`.

Show information about the libvirt/qemu guest:

```bash
virsh dumpxml terraform_example
virsh qemu-agent-command terraform_example '{"execute":"guest-info"}' --pretty
virsh qemu-agent-command terraform_example '{"execute":"guest-network-get-interfaces"}' --pretty
./qemu-agent-guest-exec terraform_example winrm enumerate winrm/config/listener
./qemu-agent-guest-exec terraform_example winrm get winrm/config
```

Configure the infrastructure:

```bash
# install the required collections.
ansible-galaxy collection install -r ansible-collection-requirements.yml

#ansible-doc -l # list all the available modules
ansible-inventory --list --yaml
ansible-lint playbook.yml
ansible-playbook playbook.yml --syntax-check
ansible-playbook playbook.yml --list-hosts

# execute ad-hoc commands.
ansible -vvv -m gather_facts all
ansible -vvv -m win_ping all
ansible -vvv -m win_command -a 'whoami /all' all
ansible -vvv -m win_shell -a '$FormatEnumerationLimit = -1; dir env: | Sort-Object Name | Format-Table -AutoSize | Out-String -Stream -Width ([int]::MaxValue) | ForEach-Object {$_.TrimEnd()}' all

# execute the playbook.
# see https://docs.ansible.com/ansible-core/2.11/user_guide/windows_winrm.html#limitations
# see https://docs.ansible.com/ansible-core/2.11/user_guide/windows_usage.html
# see https://docs.ansible.com/ansible-core/2.11/user_guide/windows_faq.html#can-i-run-python-modules-on-windows-hosts
time ansible-playbook playbook.yml #-vvv
```

Destroy the infrastructure:

```bash
time terraform destroy -auto-approve
```

## Windows Management

Ansible can use one of the native Windows management protocols: [psrp](https://docs.ansible.com/ansible-core/2.11/collections/ansible/builtin/psrp_connection.html) (recommended) or [winrm](https://docs.ansible.com/ansible-core/2.11/collections/ansible/builtin/winrm_connection.html).

Its also advisable to use the `credssp` transport, as its the most flexible transport:

| transport   | local accounts | active directory accounts | credentials delegation | encryption |
|-------------|----------------|---------------------------|------------------------|------------|
| basic       | yes            | no                        | no                     | no         |
| certificate | yes            | no                        | no                     | no         |
| kerberos    | no             | yes                       | yes                    | yes        |
| ntlm        | yes            | yes                       | no                     | yes        |
| credssp     | yes            | yes                       | yes                    | yes        |

For more information see the [Ansible CredSSP documentation](https://docs.ansible.com/ansible-core/2.11/user_guide/windows_winrm.html#credssp).
