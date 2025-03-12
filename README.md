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
# NB the first command after a (re)boot will take some minutes until
#    qemu-agent and winrm are available. the commands that follow it
#    should execute quickly.
# NB these command are executed as the local system user.
./qemu-agent-guest-exec terraform_example winrm enumerate winrm/config/listener
./qemu-agent-guest-exec terraform_example winrm get winrm/config
```

Get the guest ssh host public keys, convert them to the knowns hosts format,
and show their fingerprints:

```bash
./qemu-agent-guest-exec-get-sshd-public-keys.sh \
  terraform_example \
  | tail -1 \
  | jq -r .sshd_public_keys \
  | sed "s/^/$(terraform output --raw example_ip_address) /" \
  > example-ssh-known-hosts.txt
ssh-keygen -l -f example-ssh-known-hosts.txt
```

Using your ssh client, open a shell inside the VM and execute some commands:

```bash
ssh \
  -o UserKnownHostsFile=example-ssh-known-hosts.txt \
  "vagrant@$(terraform output --raw example_ip_address)"
whoami /all
exit
```

Configure the infrastructure:

```bash
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

Using your ssh client, open a shell inside the VM and execute some commands:

```bash
ssh \
  -o UserKnownHostsFile=example-ssh-known-hosts.txt \
  "vagrant@$(terraform output --raw example_ip_address)"
whoami /all
ver
exit
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
