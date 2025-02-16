# Usage (Ubuntu 22.04 host)

Create and install the [base Windows 2022 vagrant box](https://github.com/rgl/windows-vagrant).

Install the dependencies:

* [Docker](https://docs.docker.com/engine/install/).
* [Visual Studio Code](https://code.visualstudio.com).
* [Dev Container plugin](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers).

Open this directory with the Dev Container plugin.

Open `bash` inside the Visual Studio Code Terminal.

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
ansible-galaxy collection install -r requirements.yml

#ansible-doc -l # list all the available modules
ansible-inventory --list --yaml
ansible-lint --offline --parseable playbook.yml
ansible-playbook playbook.yml --syntax-check
ansible-playbook playbook.yml --list-hosts

# execute ad-hoc commands.
ansible -vvv -m gather_facts all
ansible -vvv -m win_ping all
ansible -vvv -m win_command -a 'whoami /all' all
ansible -vvv -m win_shell -a '$FormatEnumerationLimit = -1; dir env: | Sort-Object Name | Format-Table -AutoSize | Out-String -Stream -Width ([int]::MaxValue) | ForEach-Object {$_.TrimEnd()}' all

# execute the playbook.
# see https://docs.ansible.com/ansible-core/2.18/os_guide/windows_winrm.html#winrm-limitations
# see https://docs.ansible.com/ansible-core/2.18/os_guide/windows_usage.html
# see https://docs.ansible.com/ansible-core/2.18/os_guide/windows_faq.html#can-i-run-python-modules-on-windows-hosts
time ansible-playbook playbook.yml #-vvv
```

Destroy the infrastructure:

```bash
time terraform destroy -auto-approve
```

## Windows Management

Ansible can use one of the native Windows management protocols: [psrp](https://docs.ansible.com/ansible-core/2.18/collections/ansible/builtin/psrp_connection.html) (recommended) or [winrm](https://docs.ansible.com/ansible-core/2.18/collections/ansible/builtin/winrm_connection.html).

Its also advisable to use the `credssp` transport, as its the most flexible transport:

| transport   | local accounts | active directory accounts | credentials delegation | encryption |
|-------------|----------------|---------------------------|------------------------|------------|
| basic       | yes            | no                        | no                     | no         |
| certificate | yes            | no                        | no                     | no         |
| kerberos    | no             | yes                       | yes                    | yes        |
| ntlm        | yes            | yes                       | no                     | yes        |
| credssp     | yes            | yes                       | yes                    | yes        |

For more information see the [Ansible CredSSP documentation](https://docs.ansible.com/ansible-core/2.18/os_guide/windows_winrm.html#credssp).
