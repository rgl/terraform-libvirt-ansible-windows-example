# syntax=docker.io/docker/dockerfile:1.20
# shellcheck shell=bash

# see https://github.com/hashicorp/terraform/releases
# renovate: datasource=github-releases depName=hashicorp/terraform
ARG TERRAFORM_VERSION='1.14.0'

# see https://github.com/devcontainers/images/tree/main/src/base-debian/history
FROM mcr.microsoft.com/devcontainers/base:2.1.2-trixie

RUN <<'EOF'
#!/usr/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install --no-install-recommends \
    bash-completion \
    curl \
    git \
    libvirt-clients \
    mkisofs \
    openssh-client \
    pylint \
    python3-argcomplete \
    python3-cryptography \
    python3-libvirt \
    python3-openssl \
    python3-paramiko \
    python3-pip \
    python3-venv \
    python3-yaml \
    sshpass \
    sudo \
    unzip \
    wget \
    xorriso \
    xsltproc
apt-get clean
rm -rf /var/lib/apt/lists/*
activate-global-python-argcomplete
python3 -m venv --system-site-packages /opt/venv
EOF
ENV PATH="/opt/venv/bin:$PATH"

ARG TERRAFORM_VERSION
ENV CHECKPOINT_DISABLE=1
RUN <<'EOF'
#!/usr/bin/bash
set -euxo pipefail
terraform_url="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
t="$(mktemp -q -d --suffix=.terraform)"
wget -qO "$t/terraform.zip" "$terraform_url"
unzip "$t/terraform.zip" -d "$t"
install "$t/terraform" /usr/local/bin
rm -rf "$t"
terraform -install-autocomplete
EOF

RUN <<'EOF'
#!/usr/bin/bash
set -euxo pipefail
# ensure /etc/profile is called at the top of the file, when running in a
# login shell.
sed -i '0,/esac/s/esac/&\n\nsource \/etc\/profile/' /home/vscode/.bashrc
EOF
COPY .devcontainer/inputrc /etc/inputrc
COPY .devcontainer/login.sh /etc/profile.d/login.sh

COPY requirements.txt /tmp/pip-tmp/requirements.txt
RUN <<'EOF'
#!/usr/bin/bash
set -euxo pipefail
python -m pip \
    --disable-pip-version-check \
    --no-cache-dir \
    install \
    -r /tmp/pip-tmp/requirements.txt
rm -rf /tmp/pip-tmp
EOF

# install ansible collections and roles.
COPY requirements.yml /tmp/ansible-tmp/requirements.yml
RUN <<EOF
#!/bin/bash
set -euxo pipefail
ansible-galaxy collection install \
    -r /tmp/ansible-tmp/requirements.yml \
    -p /usr/share/ansible/collections
ansible-galaxy role install \
    -r /tmp/ansible-tmp/requirements.yml \
    -p /usr/share/ansible/roles
rm -rf /tmp/ansible-tmp
EOF

ENV LIBVIRT_DEFAULT_URI='qemu:///system'
