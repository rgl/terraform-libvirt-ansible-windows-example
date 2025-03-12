#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

domain_name="$1"

sshd_public_keys="$(./qemu-agent-guest-exec \
    "$domain_name" \
    PowerShell \
    Get-Content \
    'C:/ProgramData/ssh/ssh_host_*_key.pub' \
    | perl -ne 's/\r?\n/\n/; print unless /^\s*$/')"

jq -n --compact-output --arg keys "$sshd_public_keys" '{"sshd_public_keys":$keys}'
