#!/usr/bin/env bash
set -euo pipefail
log() { echo "[stem:ssh] $*" >&2; }

KEYDIR="/etc/ssh/keys"
install -d -m 700 "$KEYDIR"

gen_if_missing() {
  local type="$1"
  local file="$2"
  if [[ ! -s "$file" ]]; then
    log "Generating host key: $type -> $file"
    ssh-keygen -q -t "$type" -N "" -f "$file"
    chmod 600 "$file"
    chmod 644 "${file}.pub"
  fi
}

gen_if_missing ed25519 "$KEYDIR/ssh_host_ed25519_key"
gen_if_missing rsa     "$KEYDIR/ssh_host_rsa_key"
gen_if_missing ecdsa   "$KEYDIR/ssh_host_ecdsa_key"
