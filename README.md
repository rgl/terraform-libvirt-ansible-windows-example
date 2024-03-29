# Usage (Ubuntu 22.04 host)

Create and install the [base Windows 2022 vagrant box](https://github.com/rgl/windows-vagrant).

Install Terraform:

```bash
wget https://releases.hashicorp.com/terraform/1.3.7/terraform_1.3.7_linux_amd64.zip
unzip terraform_1.3.7_linux_amd64.zip
sudo install terraform /usr/local/bin
rm terraform terraform_*_linux_amd64.zip
```

Install Ansible:

```bash
# install ansible dependencies from system packages.
# see https://docs.ansible.com/ansible-core/latest/installation_guide/intro_installation.html#installing-ansible-with-pip
sudo apt-get install -y --no-install-recommends \
    python3-pip \
    python3-venv \
    python3-cryptography \
    python3-openssl \
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
# NB it will take some minutes until qemu-agent and winrm are available. so retry until it works.
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
# see https://docs.ansible.com/ansible-core/2.14/os_guide/windows_winrm.html#winrm-limitations
# see https://docs.ansible.com/ansible-core/2.14/os_guide/windows_usage.html
# see https://docs.ansible.com/ansible-core/2.14/os_guide/windows_faq.html#can-i-run-python-modules-on-windows-hosts
time ansible-playbook playbook.yml #-vvv
```

Destroy the infrastructure:

```bash
time terraform destroy -auto-approve
```

## Windows Management

Ansible can use one of the native Windows management protocols: [psrp](https://docs.ansible.com/ansible-core/2.14/collections/ansible/builtin/psrp_connection.html) (recommended) or [winrm](https://docs.ansible.com/ansible-core/2.14/collections/ansible/builtin/winrm_connection.html).

Its also advisable to use the `credssp` transport, as its the most flexible transport:

| transport   | local accounts | active directory accounts | credentials delegation | encryption |
|-------------|----------------|---------------------------|------------------------|------------|
| basic       | yes            | no                        | no                     | no         |
| certificate | yes            | no                        | no                     | no         |
| kerberos    | no             | yes                       | yes                    | yes        |
| ntlm        | yes            | yes                       | no                     | yes        |
| credssp     | yes            | yes                       | yes                    | yes        |

For more information see the [Ansible CredSSP documentation](https://docs.ansible.com/ansible-core/2.14/os_guide/windows_winrm.html#credssp).
