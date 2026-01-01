#!/usr/bin/env bash
set -euo pipefail

log() { echo "[stem] $*" >&2; }

: "${STEM_USER:=dev}"
: "${STEM_UID:=1000}"
: "${STEM_GID:=1000}"

: "${STEM_SSH_PASSWORD_AUTH:=0}"   # 0 = keys only, 1 = allow password
: "${STEM_SSH_PASSWORD:=}"

: "${BINDU_REPO:=}"
: "${BINDU_REF:=main}"

HOME_DIR="/home/${STEM_USER}"
CONFIG_DIR="${HOME_DIR}/.config"
SSH_DIR="${HOME_DIR}/.ssh"
PROFILE_FILE="${HOME_DIR}/.profile"
BASHRC_FILE="${HOME_DIR}/.bashrc"
CACHE_DIR="${HOME_DIR}/.cache"
STATE_DIR="${HOME_DIR}/.local/state"
DATA_DIR="${HOME_DIR}/.local/share"



# --- ensure group exists (by GID) ---
EXISTING_G="$(getent group "${STEM_GID}" | cut -d: -f1 || true)"
if [[ -z "${EXISTING_G}" ]]; then
  groupadd --gid "${STEM_GID}" "${STEM_USER}"
fi

# --- if UID is already taken, rename that user to STEM_USER (keeps UID stable) ---
EXISTING_U="$(getent passwd "${STEM_UID}" | cut -d: -f1 || true)"
if [[ -n "${EXISTING_U}" && "${EXISTING_U}" != "${STEM_USER}" ]]; then
  usermod -l "${STEM_USER}" "${EXISTING_U}"
fi

# --- ensure user exists ---
if ! id -u "${STEM_USER}" >/dev/null 2>&1; then
  useradd --uid "${STEM_UID}" --gid "${STEM_GID}" -m -s /bin/bash "${STEM_USER}"
fi

# --- ensure home path points to /home/STEM_USER (don’t try to move if volume exists) ---
CURRENT_HOME="$(getent passwd "${STEM_USER}" | cut -d: -f6)"
if [[ "${CURRENT_HOME}" != "${HOME_DIR}" ]]; then
  if [[ ! -e "${HOME_DIR}" ]]; then
    log "Moving home ${CURRENT_HOME} -> ${HOME_DIR}"
    usermod -d "${HOME_DIR}" -m "${STEM_USER}"
  else
    log "Home dir ${HOME_DIR} already exists (volume). Setting home path without move."
    usermod -d "${HOME_DIR}" "${STEM_USER}"
  fi
fi

# --- create dirs / perms in home ---
install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${CONFIG_DIR}"
install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${SSH_DIR}"
install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${CACHE_DIR}"
install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${STATE_DIR}"
install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${DATA_DIR}"

# --- shell init bootstrap (because home is a volume and starts empty) ---

PROFILE_FILE="${HOME_DIR}/.profile"
BASHRC_FILE="${HOME_DIR}/.bashrc"

# 1) Ensure ~/.profile exists and sources ~/.bashrc for interactive shells
if [[ ! -f "${PROFILE_FILE}" ]]; then
  cat > "${PROFILE_FILE}" <<'EOF'
# ~/.profile (stem bootstrap)

# If running bash, and interactive, source ~/.bashrc
if [ -n "$BASH_VERSION" ]; then
  case $- in
    *i*) [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc" ;;
  esac
fi
EOF
  chown "${STEM_UID}:${STEM_GID}" "${PROFILE_FILE}"
  chmod 644 "${PROFILE_FILE}"
fi

# 2) Ensure ~/.bashrc exists (your host-parity template)
if [[ ! -f "${BASHRC_FILE}" ]]; then
  cat > "${BASHRC_FILE}" <<'EOF'
# ~/.bashrc
# stem default (volume-safe)

# Only run for interactive shells
case $- in
  *i*) ;;
  *) return ;;
esac

# -------------------------------------------------------------
# Basics
# -------------------------------------------------------------
export HISTCONTROL=ignoreboth
shopt -s histappend
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s checkwinsize

# Optional: your personal aliases live here (not managed)
if [ -f "$HOME/.bash_aliases" ]; then
  . "$HOME/.bash_aliases"
fi

# Optional: drop-in directory (not managed)
if [ -d "$HOME/.bashrc.d" ]; then
  for f in "$HOME/.bashrc.d/"*.sh; do
    [ -r "$f" ] && . "$f"
  done
fi

# -------------------------------------------------------------
# Rust/cargo env (container installs rust under /opt/rust)
# -------------------------------------------------------------
if [ -f "/etc/profile.d/10-stem-rust.sh" ]; then
  . "/etc/profile.d/10-stem-rust.sh"
fi

# -------------------------------------------------------------
# Apogee
# -------------------------------------------------------------
if command -v apogee >/dev/null 2>&1; then
  eval "$(apogee)"
fi
EOF

  chown "${STEM_UID}:${STEM_GID}" "${BASHRC_FILE}"
  chmod 644 "${BASHRC_FILE}"
fi

# 3) Ensure ~/.bashrc.d exists
install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 755 "${HOME_DIR}/.bashrc.d"

# --- Bindu “install into” ~/.config (copy contents) ---
MARKER="${CONFIG_DIR}/.stem.bindu_installed"
if [[ -n "${BINDU_REPO}" && ! -f "${MARKER}" ]]; then
  log "Installing Bindu into ${CONFIG_DIR} from ${BINDU_REPO}@${BINDU_REF}"
  tmp="$(mktemp -d)"

  # IMPORTANT: mktemp dir is root:root 0700 by default; make it writable by the user
  chown "${STEM_UID}:${STEM_GID}" "${tmp}"
  chmod 755 "${tmp}"

  # clone as the user (so resulting files are owned correctly)
  sudo -u "${STEM_USER}" git clone --depth 1 --branch "${BINDU_REF}" "${BINDU_REPO}" "${tmp}/bindu"

  # copy repo contents into ~/.config, excluding .git
  tar -C "${tmp}/bindu" --exclude=.git -cf - . \
    | tar -C "${CONFIG_DIR}" -xf -

  rm -rf "${tmp}"
  sudo -u "${STEM_USER}" bash -lc "touch '${MARKER}'"
fi

# --- SSH server setup ---
mkdir -p /var/run/sshd
ssh-keygen -A >/dev/null 2>&1 || true

# --- Install authorized_keys from /opt/ssh mount ---
# We mount host path -> /opt/ssh (dir). That host path can be:
# - a file (authorized_keys)
# - a directory (bundle of .pub files / authorized_keys files)
AUTH_OUT="${SSH_DIR}/authorized_keys"

# Always ensure output exists & has correct perms
install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" /dev/null "${AUTH_OUT}" || true

if [[ -f /opt/ssh ]]; then
  # /opt/ssh is a file (host mounted a file onto /opt/ssh)
  log "Installing authorized_keys from file /opt/ssh"
  install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" /opt/ssh "${AUTH_OUT}"

elif [[ -d /opt/ssh ]]; then
  # /opt/ssh is a directory (normal case with our compose mount)
  # Prefer /opt/ssh/authorized_keys if present, else concat all regular files
  if [[ -f /opt/ssh/authorized_keys ]]; then
    log "Installing authorized_keys from /opt/ssh/authorized_keys"
    install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" /opt/ssh/authorized_keys "${AUTH_OUT}"
  else
    # Concatenate all files (e.g. *.pub) into authorized_keys
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
  fi
else
  log "No /opt/ssh mount found; no keys installed."
fi

chmod 700 "${SSH_DIR}" || true
chmod 600 "${AUTH_OUT}" || true
chown -R "${STEM_UID}:${STEM_GID}" "${SSH_DIR}" || true

# starship expects to be able to create its log dir
install -d -o "${STEM_UID}" -g "${STEM_GID}" -m 700 "${CACHE_DIR}/starship"

# If the volume ever came in with root ownership, repair just the common dirs
chown -R "${STEM_UID}:${STEM_GID}" \
  "${CONFIG_DIR}" \
  "${SSH_DIR}" \
  "${CACHE_DIR}" \
  "${HOME_DIR}/.local" \
  2>/dev/null || true


# sshd config
sed -i 's/^\s*#\?\s*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

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

grep -q "^AllowUsers" /etc/ssh/sshd_config || echo "AllowUsers ${STEM_USER}" >> /etc/ssh/sshd_config

exec "$@"
