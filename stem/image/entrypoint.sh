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

: "${STEM_ALLOW_ROOT_LOGIN:=0}"   # 0 = default, 1 = allow root login (keys or password depending on auth mode)

: "${BINDU_REPO:=}"
: "${BINDU_REF:=main}"

HOME_DIR="/home/${STEM_USER}"
CONFIG_DIR="${HOME_DIR}/.config"
SSH_DIR="${HOME_DIR}/.ssh"
AUTH_OUT="${SSH_DIR}/authorized_keys"

PROFILE_FILE="${HOME_DIR}/.profile"
BASHRC_FILE="${HOME_DIR}/.bashrc"

CACHE_DIR="${HOME_DIR}/.cache"
STATE_DIR="${HOME_DIR}/.local/state"
DATA_DIR="${HOME_DIR}/.local/share"
BASHRC_D="${HOME_DIR}/.bashrc.d"

# -----------------------------
# Helpers
# -----------------------------
ensure_group_user() {
  local gid="$1" uid="$2" user="$3"

  # group by GID
  if ! getent group "${gid}" >/dev/null 2>&1; then
    groupadd --gid "${gid}" "${user}"
  fi

  # If UID is taken by a different name, rename that user to $user (keeps UID stable)
  local existing_u
  existing_u="$(getent passwd "${uid}" | cut -d: -f1 || true)"
  if [[ -n "${existing_u}" && "${existing_u}" != "${user}" ]]; then
    usermod -l "${user}" "${existing_u}"
  fi

  # Ensure user exists
  if ! id -u "${user}" >/dev/null 2>&1; then
    useradd --uid "${uid}" --gid "${gid}" -m -s /bin/bash "${user}"
  fi

  # Ensure home path is correct (don’t move if volume already exists)
  local current_home
  current_home="$(getent passwd "${user}" | cut -d: -f6)"
  if [[ "${current_home}" != "${HOME_DIR}" ]]; then
    if [[ ! -e "${HOME_DIR}" ]]; then
      log "Moving home ${current_home} -> ${HOME_DIR}"
      usermod -d "${HOME_DIR}" -m "${user}"
    else
      log "Home dir ${HOME_DIR} exists (volume). Setting home path without move."
      usermod -d "${HOME_DIR}" "${user}"
    fi
  fi
}

ensure_dirs() {
  # Core dirs (volume-safe)
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${CONFIG_DIR}"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${SSH_DIR}"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${CACHE_DIR}"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${STATE_DIR}"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${DATA_DIR}"
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${BASHRC_D}"

  # starship cache dir
  install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${CACHE_DIR}/starship"
}

repair_ownership_if_needed() {
  # If the volume came in root-owned, fix just what we need, only when wrong.
  local home_uid
  home_uid="$(stat -c '%u' "${HOME_DIR}" 2>/dev/null || echo "")"
  if [[ -n "${home_uid}" && "${home_uid}" != "${STEM_UID}" ]]; then
    log "Repairing ownership under ${HOME_DIR} (was uid=${home_uid}, want uid=${STEM_UID})"
    chown -R "${STEM_UID}:${STEM_GID}" \
      "${HOME_DIR}" \
      2>/dev/null || true
  fi
}

bootstrap_shell_init() {
  if [[ ! -f "${PROFILE_FILE}" ]]; then
    cat > "${PROFILE_FILE}" <<'EOF'
# ~/.profile (stem bootstrap)
# Source ~/.bashrc for interactive bash shells.

if [ -n "$BASH_VERSION" ]; then
  case $- in
    *i*) [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc" ;;
  esac
fi
EOF
    chown "${STEM_UID}:${STEM_GID}" "${PROFILE_FILE}"
    chmod 644 "${PROFILE_FILE}"
  fi

  if [[ ! -f "${BASHRC_FILE}" ]]; then
    cat > "${BASHRC_FILE}" <<'EOF'
# ~/.bashrc (stem bootstrap)

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

# Rust/cargo env (system install under /opt/rust)
if [ -f "/etc/profile.d/10-stem-rust.sh" ]; then
  . "/etc/profile.d/10-stem-rust.sh"
fi

# Apogee
if command -v apogee >/dev/null 2>&1; then
  eval "$(apogee)"
fi
EOF
    chown "${STEM_UID}:${STEM_GID}" "${BASHRC_FILE}"
    chmod 644 "${BASHRC_FILE}"
  fi
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

  tar -C "${tmp}/bindu" --exclude=.git -cf - . \
    | tar -C "${CONFIG_DIR}" -xf -

  rm -rf "${tmp}"
  sudo -u "${STEM_USER}" bash -lc "touch '${marker}'"
}

install_authorized_keys() {
  install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" /dev/null "${AUTH_OUT}" || true

  # Your compose mounts: hostfile -> /opt/ssh/authorized_keys
  if [[ -f /opt/ssh/authorized_keys ]]; then
    log "Installing authorized_keys from /opt/ssh/authorized_keys"
    install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" /opt/ssh/authorized_keys "${AUTH_OUT}"
    return 0
  fi

  # If someone mounts a dir to /opt/ssh, use /opt/ssh/authorized_keys or concat all files
  if [[ -d /opt/ssh ]]; then
    if [[ -f /opt/ssh/authorized_keys ]]; then
      log "Installing authorized_keys from /opt/ssh/authorized_keys"
      install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" /opt/ssh/authorized_keys "${AUTH_OUT}"
      return 0
    fi

    local tmpk
    tmpk="$(mktemp)"
    find /opt/ssh -maxdepth 1 -type f -print0 2>/dev/null \
      | sort -z \
      | xargs -0 cat > "${tmpk}" 2>/dev/null || true

    if [[ -s "${tmpk}" ]]; then
      log "Installing authorized_keys by concatenating files from /opt/ssh"
      install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" "${tmpk}" "${AUTH_OUT}"
    else
      log "No key material found in /opt/ssh"
    fi
    rm -f "${tmpk}"
    return 0
  fi

  log "No /opt/ssh mount found; no keys installed."
}

configure_sshd() {
  mkdir -p /var/run/sshd
  ssh-keygen -A >/dev/null 2>&1 || true

  # Base hardening
  sed -i 's/^\s*#\?\s*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

  # Password auth
  if [[ "${STEM_SSH_PASSWORD_AUTH}" == "1" ]]; then
    sed -i 's/^\s*#\?\s*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    if [[ -n "${STEM_SSH_PASSWORD}" ]]; then
      echo "${STEM_USER}:${STEM_SSH_PASSWORD}" | chpasswd
    else
      log "Password auth enabled but STEM_SSH_PASSWORD is empty."
    fi
  else
    sed -i 's/^\s*#\?\s*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  fi

  # AllowUsers
  # If root login is explicitly enabled, allow both; otherwise only STEM_USER
  if [[ "${STEM_ALLOW_ROOT_LOGIN}" == "1" ]]; then
    sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
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
bootstrap_shell_init
install_bindu_once
install_authorized_keys

chmod 700 "${SSH_DIR}" || true
chmod 600 "${AUTH_OUT}" || true
chown -R "${STEM_UID}:${STEM_GID}" "${SSH_DIR}" || true

configure_sshd

exec "$@"
