#!/usr/bin/env bash
set -euo pipefail

log() { echo "[stem:init] $*" >&2; }

: "${STEM_USER:=suhail}"
: "${STEM_UID:=1000}"
: "${STEM_GID:=1000}"

HOME_DIR="/home/${STEM_USER}"
SSH_DIR="${HOME_DIR}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

ensure_group_user() {
  mkdir -p /home

  # Ensure group exists by GID
  if ! getent group "${STEM_GID}" >/dev/null 2>&1; then
    groupadd --gid "${STEM_GID}" "${STEM_USER}"
  fi

  # If UID already exists under a different username, rename that user to STEM_USER
  local existing_u
  existing_u="$(getent passwd "${STEM_UID}" | cut -d: -f1 || true)"
  if [[ -n "${existing_u}" && "${existing_u}" != "${STEM_USER}" ]]; then
    log "Adopting uid=${STEM_UID}: renaming ${existing_u} -> ${STEM_USER}"
    usermod -l "${STEM_USER}" "${existing_u}" || true
    # If a sudoers file exists under the old name, remove it
    rm -f "/etc/sudoers.d/${existing_u}" 2>/dev/null || true
  fi

  # Ensure user exists
  if ! id -u "${STEM_USER}" >/dev/null 2>&1; then
    # Create with the correct home path from the start
    useradd --uid "${STEM_UID}" --gid "${STEM_GID}" -m -d "${HOME_DIR}" -s /bin/bash "${STEM_USER}"
  fi

  # Ensure primary group matches STEM_GID
  usermod -g "${STEM_GID}" "${STEM_USER}" || true

  # Ensure home dir exists (volume-safe)
  mkdir -p "${HOME_DIR}"

  # Fix passwd home path (move only if old home exists and target doesn't)
  local current_home
  current_home="$(getent passwd "${STEM_USER}" | cut -d: -f6 || true)"

  if [[ -n "${current_home}" && "${current_home}" != "${HOME_DIR}" ]]; then
    if [[ -d "${current_home}" && ! -e "${HOME_DIR}" ]]; then
      log "Moving home ${current_home} -> ${HOME_DIR}"
      usermod -d "${HOME_DIR}" -m "${STEM_USER}" || usermod -d "${HOME_DIR}" "${STEM_USER}"
    else
      # Old home missing or target already exists (common with /home volume mounts)
      log "Setting home to ${HOME_DIR} (no move; current_home=${current_home:-<empty>})"
      usermod -d "${HOME_DIR}" "${STEM_USER}" || true
    fi
  fi

  # Ensure sudo rights
  usermod -aG sudo "${STEM_USER}" || true
  echo "${STEM_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${STEM_USER}"
  chmod 0440 "/etc/sudoers.d/${STEM_USER}"
}

repair_home_ownership_if_needed() {
  # If the home comes from a volume, it may be root-owned.
  if [[ -d "${HOME_DIR}" ]]; then
    local uid_now
    uid_now="$(stat -c '%u' "${HOME_DIR}" 2>/dev/null || echo "")"
    if [[ -n "${uid_now}" && "${uid_now}" != "${STEM_UID}" ]]; then
      log "Repairing ownership under ${HOME_DIR} (was uid=${uid_now}, want uid=${STEM_UID})"
      chown -R "${STEM_UID}:${STEM_GID}" "${HOME_DIR}" 2>/dev/null || true
    fi
  fi
}

write_shell_files_always() {
  # Make sure the directory exists BEFORE writing files into it
  install -d -m 755 -o "${STEM_UID}" -g "${STEM_GID}" "${HOME_DIR}"

  cat > "${HOME_DIR}/.profile" <<'EOF'
# ~/.profile (stem)
# Make interactive bash login shells source ~/.bashrc
if [ -n "$BASH_VERSION" ]; then
  case $- in
    *i*) [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc" ;;
  esac
fi
EOF

  cat > "${HOME_DIR}/.bashrc" <<'EOF'
# ~/.bashrc
# Managed by stem

case $- in
  *i*) ;;
  *) return ;;
esac

export HISTCONTROL=ignoreboth
shopt -s histappend
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s checkwinsize

if [ -f "$HOME/.bash_aliases" ]; then
  . "$HOME/.bash_aliases"
fi

if [ -d "$HOME/.bashrc.d" ]; then
  for f in "$HOME/.bashrc.d/"*.sh; do
    [ -r "$f" ] && . "$f"
  done
fi

# Ensure PATH policy applies even in shells that don't read /etc/profile
if [ -f /etc/profile.d/99-user-bins-first.sh ]; then
  . /etc/profile.d/99-user-bins-first.sh
fi

if command -v apogee >/dev/null 2>&1; then
  eval "$(apogee)"
fi
EOF

  install -d -m 700 -o "${STEM_UID}" -g "${STEM_GID}" "${HOME_DIR}/.bashrc.d"
  chown "${STEM_UID}:${STEM_GID}" "${HOME_DIR}/.profile" "${HOME_DIR}/.bashrc"
  chmod 644 "${HOME_DIR}/.profile" "${HOME_DIR}/.bashrc"
}

ensure_account_unlocked() {
  # With UsePAM=yes, a locked account blocks *all* auth methods (including pubkey)
  local status
  status="$(passwd -S "${STEM_USER}" 2>/dev/null | awk "{print \$2}" || true)"

  if [[ "${status}" == "L" ]]; then
    log "Account ${STEM_USER} is locked; unlocking (required for pubkey login)"

    # If a password is provided, set it and unlock cleanly
    if [[ -n "${STEM_PASSWORD:-}" ]]; then
      echo "${STEM_USER}:${STEM_PASSWORD}" | chpasswd
      passwd -u "${STEM_USER}" >/dev/null 2>&1 || usermod -U "${STEM_USER}" || true
    else
      # No password provided: set a random one so the account can be unlocked
      # (key auth will work; password fallback just becomes unknown)
      local pw
      pw="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
      echo "${STEM_USER}:${pw}" | chpasswd
      passwd -u "${STEM_USER}" >/dev/null 2>&1 || usermod -U "${STEM_USER}" || true
    fi
  fi
}


install_authorized_keys() {
  local persist_dir="/opt/stem/ssh"
  local persist_keys="${persist_dir}/authorized_keys"
  local injected="/opt/ssh/authorized_keys"

  install -d -m 700 -o "${STEM_UID}" -g "${STEM_GID}" "${SSH_DIR}"
  install -d -m 700 "${persist_dir}"

  # If user provided a key file via bind mount, persist it
  if [[ -f "${injected}" && -s "${injected}" ]]; then
    log "Persisting provided authorized_keys from ${injected} -> ${persist_keys}"
    cp -f "${injected}" "${persist_keys}"
    chmod 600 "${persist_keys}"
  fi

  # Use persisted keys if they exist
  if [[ -f "${persist_keys}" && -s "${persist_keys}" ]]; then
    log "Installing authorized_keys from persisted store"
    install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" "${persist_keys}" "${AUTH_KEYS}"
  else
    log "No authorized_keys found (neither injected nor persisted); SSH key login will fail."
  fi
}

ensure_group_user
ensure_account_unlocked
repair_home_ownership_if_needed
write_shell_files_always
install_authorized_keys

exit 0
