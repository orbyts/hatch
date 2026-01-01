#!/usr/bin/env bash
set -euo pipefail

log() { echo "[stem] $*" >&2; }

# -----------------------------
# Runtime config
# -----------------------------
: "${STEM_USER:=dev}"
: "${STEM_UID:=1000}"
: "${STEM_GID:=1000}"

: "${STEM_SSH_PASSWORD_AUTH:=0}"   # 0 = keys only, 1 = allow password
: "${STEM_SSH_PASSWORD:=}"
: "${STEM_ALLOW_ROOT_LOGIN:=0}"    # 0 = default, 1 = allow root login

: "${BINDU_REPO:=}"
: "${BINDU_REF:=main}"

HOME_DIR="/home/${STEM_USER}"
CONFIG_DIR="${HOME_DIR}/.config"
SSH_DIR="${HOME_DIR}/.ssh"
AUTH_OUT="${SSH_DIR}/authorized_keys"

PROFILE_FILE="${HOME_DIR}/.profile"
BASHRC_FILE="${HOME_DIR}/.bashrc"
BASHRC_D="${HOME_DIR}/.bashrc.d"

CACHE_DIR="${HOME_DIR}/.cache"
STATE_DIR="${HOME_DIR}/.local/state"
DATA_DIR="${HOME_DIR}/.local/share"

# -----------------------------
# Helpers
# -----------------------------
ensure_group_user() {
  local gid="$1" uid="$2" user="$3"

  mkdir -p /home

  # --- group by GID (adopt/rename if needed) ---
  local gname
  gname="$(getent group "${gid}" | cut -d: -f1 || true)"
  if [[ -z "${gname}" ]]; then
    groupadd --gid "${gid}" "${user}"
  elif [[ "${gname}" != "${user}" ]]; then
    # single-user container: safe to rename
    log "Adopting gid=${gid}: renaming group ${gname} -> ${user}"
    groupmod -n "${user}" "${gname}" || true
  fi

  # --- user by UID (adopt/rename if needed) ---
  local existing_u
  existing_u="$(getent passwd "${uid}" | cut -d: -f1 || true)"
  if [[ -n "${existing_u}" && "${existing_u}" != "${user}" ]]; then
    log "Adopting uid=${uid}: renaming user ${existing_u} -> ${user}"
    usermod -l "${user}" "${existing_u}"
    rm -f "/etc/sudoers.d/${existing_u}" 2>/dev/null || true
  fi

  # Ensure user exists (by name)
  if ! id -u "${user}" >/dev/null 2>&1; then
    useradd --uid "${uid}" --gid "${gid}" -m -s /bin/bash "${user}"
  fi

  # Ensure primary group is the target gid
  usermod -g "${gid}" "${user}" || true

  # Ensure home path correct (volume-safe)
  local current_home
  current_home="$(getent passwd "${user}" | cut -d: -f6)"
  if [[ "${current_home}" != "${HOME_DIR}" ]]; then
    mkdir -p "${HOME_DIR}"
    usermod -d "${HOME_DIR}" "${user}" || true
  fi

  # Sudo rights
  usermod -aG sudo "${user}" || true
  if [[ ! -f "/etc/sudoers.d/${user}" ]]; then
    echo "${user} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${user}"
    chmod 0440 "/etc/sudoers.d/${user}"
  fi
}

ensure_dirs() {
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${CONFIG_DIR}"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${SSH_DIR}"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${CACHE_DIR}"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${STATE_DIR}"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${DATA_DIR}"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${BASHRC_D}"

  # VM-like cargo behavior: user installs go here
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${HOME_DIR}/.cargo"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${HOME_DIR}/.cargo/bin"

  # starship cache dir
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${CACHE_DIR}/starship"
}

repair_ownership_if_needed() {
  local home_uid
  home_uid="$(stat -c '%u' "${HOME_DIR}" 2>/dev/null || echo "")"
  if [[ -n "${home_uid}" && "${home_uid}" != "${STEM_UID}" ]]; then
    log "Repairing ownership under ${HOME_DIR} (was uid=${home_uid}, want uid=${STEM_UID})"
    chown -R "${STEM_UID}:${STEM_GID}" "${HOME_DIR}" 2>/dev/null || true
  fi
}

write_managed_profile() {
  # Ensures login shells (SSH) pull in ~/.bashrc
  cat > "${PROFILE_FILE}" <<'EOF'
# ~/.profile
# Managed by stem entrypoint

if [ -n "$BASH_VERSION" ]; then
  case $- in
    *i*) [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc" ;;
  esac
fi
EOF
  chown "${STEM_UID}:${STEM_GID}" "${PROFILE_FILE}"
  chmod 644 "${PROFILE_FILE}"
}

write_managed_bashrc() {
  cat > "${BASHRC_FILE}" <<'EOF'
# ~/.bashrc - Managed by stem

# 1. Standard Interactive Guard
case $- in
    *i*) ;;
    *) return ;;
esac

# 2. Load System Tool Paths First (Rust system-wide, etc.)
if [ -f "/etc/profile.d/10-stem-rust.sh" ]; then
    . "/etc/profile.d/10-stem-rust.sh"
fi

# 3. User-Specific PATH overrides (THE PRIORITY ZONE)
# This ensures $HOME binaries always come BEFORE /usr or /opt
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

# Cargo/Rust user-space
if [ -d "$HOME/.cargo/bin" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# NPM/Node user-space (if using prefix or default global)
if [ -d "$HOME/.npm-global/bin" ]; then
    export PATH="$HOME/.npm-global/bin:$PATH"
fi

# 4. Load Apogee (Now it will find the $HOME version first)
if command -v apogee >/dev/null 2>&1; then
    eval "$(apogee)"
fi

# 5. Generic Includes
[ -f "$HOME/.bash_aliases" ] && . "$HOME/.bash_aliases"
if [ -d "$HOME/.bashrc.d" ]; then
    for f in "$HOME/.bashrc.d/"*.sh; do [ -r "$f" ] && . "$f"; done
fi
EOF
  chown "${STEM_UID}:${STEM_GID}" "${BASHRC_FILE}"
  chmod 644 "${BASHRC_FILE}"
}

install_bindu_once() {
  local marker="${CONFIG_DIR}/.stem.bindu_installed"
  [[ -z "${BINDU_REPO}" ]] && return 0
  [[ -f "${marker}" ]] && return 0

  log "Installing Bindu into ${CONFIG_DIR} from ${BINDU_REPO}@${BINDU_REF}"
  local tmp
  tmp="$(mktemp -d)"
  chown "${STEM_UID}:${STEM_GID}" "${tmp}"
  chmod 755 "${tmp}"

  sudo -u "${STEM_USER}" git clone --depth 1 --branch "${BINDU_REF}" "${BINDU_REPO}" "${tmp}/bindu"
  tar -C "${tmp}/bindu" --exclude=.git -cf - . | tar -C "${CONFIG_DIR}" -xf -
  rm -rf "${tmp}"
  sudo -u "${STEM_USER}" bash -lc "touch '${marker}'"
}

install_authorized_keys() {
  install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" /dev/null "${AUTH_OUT}" || true

  if [[ -f /opt/ssh/authorized_keys ]]; then
    log "Installing authorized_keys from /opt/ssh/authorized_keys"
    install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" /opt/ssh/authorized_keys "${AUTH_OUT}"
  else
    log "No /opt/ssh/authorized_keys mount found; no keys installed."
  fi

  chmod 700 "${SSH_DIR}" || true
  chmod 600 "${AUTH_OUT}" || true
  chown -R "${STEM_UID}:${STEM_GID}" "${SSH_DIR}" || true
}

configure_sshd() {
  mkdir -p /var/run/sshd
  ssh-keygen -A >/dev/null 2>&1 || true

  if [[ ! -f /etc/ssh/sshd_config ]]; then
    log "ERROR: /etc/ssh/sshd_config missing (did you mount a blank /etc/ssh volume?)"
    exit 1
  fi

  sed -i 's/^\s*#\?\s*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

  if [[ "${STEM_SSH_PASSWORD_AUTH}" == "1" ]]; then
    sed -i 's/^\s*#\?\s*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    if [[ -n "${STEM_SSH_PASSWORD}" ]]; then
      echo "${STEM_USER}:${STEM_SSH_PASSWORD}" | chpasswd
      if [[ "${STEM_ALLOW_ROOT_LOGIN}" == "1" ]]; then
        sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
        echo "root:${STEM_SSH_PASSWORD}" | chpasswd
      fi
    else
      log "Password auth enabled but STEM_SSH_PASSWORD is empty."
    fi
  else
    sed -i 's/^\s*#\?\s*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    if [[ "${STEM_ALLOW_ROOT_LOGIN}" == "1" ]]; then
      sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    fi
  fi

  # AllowUsers
  if [[ "${STEM_ALLOW_ROOT_LOGIN}" == "1" ]]; then
    grep -q "^AllowUsers" /etc/ssh/sshd_config || echo "AllowUsers ${STEM_USER} root" >> /etc/ssh/sshd_config
  else
    grep -q "^AllowUsers" /etc/ssh/sshd_config || echo "AllowUsers ${STEM_USER}" >> /etc/ssh/sshd_config
  fi
}

# -----------------------------
# Main
# -----------------------------
ensure_group_user "${STEM_GID}" "${STEM_UID}" "${STEM_USER}"
ensure_dirs
repair_ownership_if_needed

# Always enforce your desired shell init files
write_managed_profile
write_managed_bashrc

install_bindu_once
install_authorized_keys
configure_sshd

exec "$@"
