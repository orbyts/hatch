#!/usr/bin/env bash
# If invoked under /bin/sh (dash), re-exec under bash before parsing bash syntax.
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

log() { echo "[stem:init] $*" >&2; }

: "${STEM_USER:=suhail}"
: "${STEM_UID:=1000}"
: "${STEM_GID:=1000}"
: "${STEM_SUPP_GIDS:=}"

HOME_DIR="/home/${STEM_USER}"
SSH_DIR="${HOME_DIR}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

ensure_group_user() {
  mkdir -p /home

  # Track the group name that corresponds to STEM_GID
  local PRIMARY_GROUP_NAME=""

  # If a group with STEM_GID exists already, capture its name
  PRIMARY_GROUP_NAME="$(getent group "${STEM_GID}" | cut -d: -f1 || true)"

  # Otherwise, create a group with STEM_GID
  if [[ -z "${PRIMARY_GROUP_NAME}" ]]; then
    if getent group "${STEM_USER}" >/dev/null 2>&1; then
      # Group name exists with a different GID; create a safe name
      PRIMARY_GROUP_NAME="${STEM_USER}-grp"
    else
      PRIMARY_GROUP_NAME="${STEM_USER}"
    fi

    groupadd --gid "${STEM_GID}" "${PRIMARY_GROUP_NAME}"
  fi

  # If UID already exists under a different username, rename that user to STEM_USER
  local existing_u
  existing_u="$(getent passwd "${STEM_UID}" | cut -d: -f1 || true)"
  if [[ -n "${existing_u}" && "${existing_u}" != "${STEM_USER}" ]]; then
    log "Adopting uid=${STEM_UID}: renaming ${existing_u} -> ${STEM_USER}"
    usermod -l "${STEM_USER}" "${existing_u}" || true
    rm -f "/etc/sudoers.d/${existing_u}" 2>/dev/null || true
  fi

  # Ensure user exists (use the actual group name for the gid we prepared)
  if ! id -u "${STEM_USER}" >/dev/null 2>&1; then
    useradd --uid "${STEM_UID}" --gid "${PRIMARY_GROUP_NAME}" -m -d "${HOME_DIR}" -s /bin/bash "${STEM_USER}"
  fi

  # Ensure primary group is STEM_GID (in case user existed already)
  usermod -g "${STEM_GID}" "${STEM_USER}" || true

  # Ensure home dir exists (volume-safe)
  mkdir -p "${HOME_DIR}"

  # Fix passwd home path (avoid moves when a volume mount is present)
  local current_home
  current_home="$(getent passwd "${STEM_USER}" | cut -d: -f6 || true)"

  if [[ -n "${current_home}" && "${current_home}" != "${HOME_DIR}" ]]; then
    if [[ -d "${current_home}" && ! -e "${HOME_DIR}" ]]; then
      log "Moving home ${current_home} -> ${HOME_DIR}"
      usermod -d "${HOME_DIR}" -m "${STEM_USER}" || usermod -d "${HOME_DIR}" "${STEM_USER}"
    else
      log "Setting home to ${HOME_DIR} (no move; current_home=${current_home:-<empty>})"
      usermod -d "${HOME_DIR}" "${STEM_USER}" || true
    fi
  fi

  # Ensure sudo rights
  usermod -aG sudo "${STEM_USER}" || true
  install -m 0440 /dev/null "/etc/sudoers.d/${STEM_USER}"
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${STEM_USER}" > "/etc/sudoers.d/${STEM_USER}"
}

add_user_to_gid() {
  local user="$1"
  local gid="$2"

  # Find group name for this gid (if any)
  local grp
  grp="$(getent group "${gid}" | cut -d: -f1 || true)"

  # If no group exists with this gid, create a stable one
  if [[ -z "${grp}" ]]; then
    grp="hostgid${gid}"
    groupadd -g "${gid}" "${grp}" || true
  fi

  # Add user to that group (idempotent)
  usermod -aG "${grp}" "${user}" || true
}

ensure_supplemental_groups() {
  local user="${STEM_USER}"

  [[ -n "${STEM_SUPP_GIDS}" ]] || return 0

  log "Applying supplemental gids for ${user}: ${STEM_SUPP_GIDS}"

  local gid
  for gid in ${STEM_SUPP_GIDS}; do
    [[ "${gid}" =~ ^[0-9]+$ ]] || { log "Skipping non-numeric gid: ${gid}"; continue; }
    add_user_to_gid "${user}" "${gid}"
  done

  log "Groups for ${user}:"
  id "${user}" || true
}

ensure_account_unlocked() {
  # With UsePAM=yes, a locked account blocks *all* auth methods (including pubkey)
  local status
  status="$(passwd -S "${STEM_USER}" 2>/dev/null | awk '{print $2}' || true)"

  if [[ "${status}" == "L" ]]; then
    log "Account ${STEM_USER} is locked; unlocking (required for pubkey login)"

    if [[ -n "${STEM_PASSWORD:-}" ]]; then
      echo "${STEM_USER}:${STEM_PASSWORD}" | chpasswd
    else
      local pw
      pw="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
      echo "${STEM_USER}:${pw}" | chpasswd
    fi

    passwd -u "${STEM_USER}" >/dev/null 2>&1 || usermod -U "${STEM_USER}" || true
  fi
}

# Recursive chown that:
# - NEVER descends into $HOME_DIR/Dropbox (bind mount)
# - Uses -xdev elsewhere to avoid crossing mount points
safe_chown_tree() {
  local root="$1"

  # If root doesn't exist, nothing to do
  [[ -e "${root}" ]] || return 0

  # Always fix the root node itself
  chown "${STEM_UID}:${STEM_GID}" "${root}" 2>/dev/null || true

  # If root is the home dir, prune Dropbox explicitly
  if [[ "${root}" == "${HOME_DIR}" ]]; then
    find "${root}" \
      -path "${HOME_DIR}/Dropbox" -prune -o \
      -exec chown -h "${STEM_UID}:${STEM_GID}" {} + \
      2>/dev/null || true
  else
    # Normal recursive chown but don't cross mountpoints
    find "${root}" -xdev \
      -exec chown -h "${STEM_UID}:${STEM_GID}" {} + \
      2>/dev/null || true
  fi
}

# Create/repair dirs that matter for user-installed tools + XDG paths
ensure_user_dirs() {
  # 1) Fix ONLY the home dir inode (do NOT recurse)
  chown "${STEM_UID}:${STEM_GID}" "${HOME_DIR}" 2>/dev/null || true

  # 2) Create + fix only safe subdirs (never chown -R $HOME)
  local dirs=(
    "${HOME_DIR}/.ssh"
    "${HOME_DIR}/.cargo"
    "${HOME_DIR}/.cargo/bin"
    "${HOME_DIR}/.config"
    "${HOME_DIR}/.local"
    "${HOME_DIR}/.local/bin"
    "${HOME_DIR}/.local/share"
    "${HOME_DIR}/.local/state"
    "${HOME_DIR}/.cache"
    "${HOME_DIR}/.pixi"
    "${HOME_DIR}/.pixi/bin"
    "${HOME_DIR}/.pixi/manifests"
    "${HOME_DIR}/.pixi/envs"
    "${HOME_DIR}/.pixi/completions"
    "${APOGEE_UV_VENV_ROOT:-${HOME_DIR}/.venvs}"
    "${HOME_DIR}/.bashrc.d"
  )

  local d
  for d in "${dirs[@]}"; do
    if [[ -e "${d}" && ! -d "${d}" ]]; then
      log "WARNING: ${d} exists but is not a directory; skipping."
      continue
    fi

    if [[ -d "${d}" ]]; then
      # If top dir owner differs, repair subtree safely
      local uid_now
      uid_now="$(stat -c '%u' "${d}" 2>/dev/null || echo "")"
      if [[ -n "${uid_now}" && "${uid_now}" != "${STEM_UID}" ]]; then
        safe_chown_tree "${d}"
      fi

      # Fix common permission gotchas for key dirs (without being heavy-handed)
      case "${d}" in
        */.ssh)      chmod 700 "${d}" 2>/dev/null || true ;;
        */.bashrc.d) chmod 700 "${d}" 2>/dev/null || true ;;
        *)           : ;;
      esac
    else
      case "${d}" in
        */.ssh)        install -d -m 700 -o "${STEM_UID}" -g "${STEM_GID}" "${d}" ;;
        */.bashrc.d)   install -d -m 700 -o "${STEM_UID}" -g "${STEM_GID}" "${d}" ;;
        *)             install -d -m 755 -o "${STEM_UID}" -g "${STEM_GID}" "${d}" ;;
      esac
    fi
  done

  # Neovim expects these; ensure they exist + are owned (safe)
  install -d -m 755 -o "${STEM_UID}" -g "${STEM_GID}" "${HOME_DIR}/.local/state/nvim" || true
  install -d -m 755 -o "${STEM_UID}" -g "${STEM_GID}" "${HOME_DIR}/.local/share/nvim" || true
  install -d -m 755 -o "${STEM_UID}" -g "${STEM_GID}" "${HOME_DIR}/.cache/nvim" || true
}

install_uv_pythons_if_requested() {
  : "${STEM_UV_PYTHONS:=}"
  : "${STEM_UV_PYTHON_DIR:=}"

  [[ -z "${STEM_UV_PYTHONS}" ]] && return 0

  if ! command -v uv >/dev/null 2>&1; then
    log "ERROR: uv not found. Did you install uv in the Dockerfile?"
    return 1
  fi

  log "Installing uv-managed Python versions for ${STEM_USER}: ${STEM_UV_PYTHONS}"

  sudo -u "${STEM_USER}" -H bash -lc "
    set -euo pipefail

    if [[ -n \"${STEM_UV_PYTHON_DIR}\" ]]; then
      export UV_PYTHON_INSTALL_DIR=\"${STEM_UV_PYTHON_DIR}\"
      mkdir -p \"\${UV_PYTHON_INSTALL_DIR}\"
    fi

    for v in ${STEM_UV_PYTHONS}; do
      uv python install \"\$v\"
    done

    uv python dir
    uv python list
  "
}

ensure_uv_managed_python() {
  command -v uv >/dev/null 2>&1 || return 0

  local want="${APOGEE_UV_DEFAULT_PY:-}"
  [[ -z "$want" ]] && return 0
  [[ "$want" == "auto-houdini" ]] && return 0

  if ! [[ "$want" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    return 0
  fi

  local marker_dir="${HOME_DIR}/.local/state/stem"
  local marker="${marker_dir}/uv_python_${want}_installed"
  install -d -m 755 -o "${STEM_UID}" -g "${STEM_GID}" "${marker_dir}"

  [[ -f "$marker" ]] && return 0

  log "Installing uv-managed Python ${want} (persisted in home volume)..."

  sudo -u "${STEM_USER}" -H bash -lc "
    set -euo pipefail
    uv python install '${want}' --default
    uv python dir >/dev/null
    uv python dir --bin >/dev/null
  "

  date -Iseconds > "$marker"
  chown "${STEM_UID}:${STEM_GID}" "$marker"
}

ensure_user_cargo_env() {
  local cargo_env="${HOME_DIR}/.cargo/env"

  if [[ ! -f "${cargo_env}" ]]; then
    cat > "${cargo_env}" <<'EOF'
# ~/.cargo/env (stem)
case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac
EOF
  fi

  chown "${STEM_UID}:${STEM_GID}" "${cargo_env}"
  chmod 644 "${cargo_env}"
}

write_shell_files() {
  local tmp

  tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
# ~/.profile (stem)
# Make interactive bash login shells source ~/.bashrc
if [ -n "$BASH_VERSION" ]; then
  case $- in
    *i*) [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc" ;;
  esac
fi
EOF
  install -m 0644 -o "${STEM_UID}" -g "${STEM_GID}" "${tmp}" "${HOME_DIR}/.profile"
  rm -f "${tmp}"

  tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
# ~/.bash_profile (stem)
# Ensure system profile scripts run for SSH logins
if [ -f /etc/profile ]; then
  . /etc/profile
fi

# Keep user profile behavior consistent
if [ -f "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi
EOF
  install -m 0644 -o "${STEM_UID}" -g "${STEM_GID}" "${tmp}" "${HOME_DIR}/.bash_profile"
  rm -f "${tmp}"

  tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
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

if [ -f /etc/profile.d/99-user-bins-first.sh ]; then
  . /etc/profile.d/99-user-bins-first.sh
fi

if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi

if command -v apogee >/dev/null 2>&1; then
  eval "$(apogee)"
fi
EOF
  install -m 0644 -o "${STEM_UID}" -g "${STEM_GID}" "${tmp}" "${HOME_DIR}/.bashrc"
  rm -f "${tmp}"
}

install_bindu_if_requested() {
  : "${BINDU_REPO:=}"
  : "${BINDU_REF:=main}"
  : "${BINDU_FORCE:=0}"

  if [[ -z "${BINDU_REPO}" ]]; then
    log "BINDU_REPO not set; skipping bindu."
    return 0
  fi

  local cfg="${HOME_DIR}/.config"
  local marker="${cfg}/.bindu_installed"

  install -d -m 755 -o "${STEM_UID}" -g "${STEM_GID}" "${cfg}"

  if [[ -f "${marker}" && "${BINDU_FORCE}" != "1" ]]; then
    log "Bindu already installed (${marker}); skipping."
    return 0
  fi

  if [[ "${BINDU_FORCE}" != "1" ]]; then
    local non_marker
    non_marker="$(find "${cfg}" -mindepth 1 -maxdepth 1 ! -name '.bindu_installed' -print -quit 2>/dev/null || true)"
    if [[ -n "${non_marker}" ]]; then
      log "~/.config not empty; skipping bindu (set BINDU_FORCE=1 to overwrite)."
      return 0
    fi
  fi

  log "Installing bindu into ${cfg} (repo=${BINDU_REPO}, ref=${BINDU_REF})"

  su - "${STEM_USER}" -c "
    set -euo pipefail
    tmp=\$(mktemp -d)
    git clone --depth=1 --branch \"${BINDU_REF}\" \"${BINDU_REPO}\" \"\$tmp\"
    cp -a \"\$tmp/.\" \"${cfg}/\"
    rm -rf \"\$tmp\"
    date -Iseconds > \"${marker}\"
  "

  safe_chown_tree "${cfg}"
}

install_apogee_secrets_if_injected() {
  local injected="/opt/secrets/apogee-secrets.env"
  local target_dir="${HOME_DIR}/.config/apogee"
  local target="${target_dir}/secrets.env"

  [[ -f "${injected}" && -s "${injected}" ]] || return 0

  install -d -m 700 -o "${STEM_UID}" -g "${STEM_GID}" "${target_dir}"

  # Only write if missing (don’t overwrite silently)
  if [[ ! -f "${target}" ]]; then
    log "Installing apogee secrets.env (one-time) -> ${target}"
    install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" "${injected}" "${target}"
  else
    log "apogee secrets.env already exists; leaving as-is."
  fi
}

install_pixi_if_missing() {
  : "${STEM_PIXI_ENABLE:=1}"
  [[ "${STEM_PIXI_ENABLE}" == "1" ]] || { log "STEM_PIXI_ENABLE!=1; skipping pixi install."; return 0; }

  # Already installed for this user?
  if sudo -u "${STEM_USER}" -H bash -lc 'test -x "$HOME/.pixi/bin/pixi"'; then
    return 0
  fi

  log "Installing pixi for ${STEM_USER} (user-local ~/.pixi)..."

  sudo -u "${STEM_USER}" -H bash -lc '
    set -euo pipefail
    curl -fsSL https://pixi.sh/install.sh | env PIXI_NO_PATH_UPDATE=1 sh
    test -x "$HOME/.pixi/bin/pixi"
  '
}

configure_pixi_host_if_present() {
  : "${STEM_PIXI_ENABLE:=1}"
  [[ "${STEM_PIXI_ENABLE}" == "1" ]] || return 0

  # Control whether we attempt stow at all
  : "${STEM_PIXI_STOW:=auto}"   # auto|0|1
  [[ "${STEM_PIXI_STOW}" == "0" ]] && { log "STEM_PIXI_STOW=0; skipping stow."; return 0; }

  # Pick host folder name:
  # - If you want "container name", the reliable path is: set this env var, OR set container hostname.
  # - Default: hostname -s (works if you set `hostname:` in compose or `--hostname` in docker run)
  local host
  host="${STEM_PIXI_HOST:-}"
  if [[ -z "${host}" ]]; then
    host="${STEM_HOSTNAME:-}"
  fi
  if [[ -z "${host}" ]]; then
    host="$(hostname -s 2>/dev/null || true)"
  fi
  host="${host:-stem}"

  local hosts_root="${HOME_DIR}/.config/pixi/hosts"
  local host_dir="${hosts_root}/${host}"

  if [[ ! -d "${host_dir}" ]]; then
    log "No pixi host config found at ${host_dir}; leaving pixi defaults."
    return 0
  fi

  log "Found pixi host config: ${host_dir} -> stowing into ${HOME_DIR}"

  sudo -u "${STEM_USER}" -H bash -lc "
    set -euo pipefail
    command -v stow >/dev/null 2>&1 || exit 0
    mkdir -p \"\$HOME/.pixi/manifests\"
    stow -d \"${hosts_root}\" -t \"\$HOME\" -R \"${host}\" || true
  "

  # Optional: run global sync (OFF by default)
  : "${STEM_PIXI_GLOBAL_SYNC:=0}"
  if [[ "${STEM_PIXI_GLOBAL_SYNC}" == "1" ]]; then
    log "Running: pixi global sync"
    sudo -u "${STEM_USER}" -H bash -lc '
      set -euo pipefail
      pixi global sync
    ' || log "pixi global sync failed (non-fatal)."
  else
    log "pixi host stow complete. Run: pixi global sync"
  fi
}


bootstrap_neovim_if_configured() {
  local marker_dir="${HOME_DIR}/.local/state/stem"
  local marker="${marker_dir}/nvim_bootstrapped"

  install -d -m 755 -o "${STEM_UID}" -g "${STEM_GID}" "${marker_dir}"

  command -v nvim >/dev/null 2>&1 || return 0
  [[ -d "${HOME_DIR}/.config/nvim" ]] || return 0
  [[ -f "${marker}" ]] && return 0

  log "Bootstrapping Neovim plugins (lazy/mason/treesitter) for ${STEM_USER}..."

  sudo -u "${STEM_USER}" -H bash -lc '
    set -euo pipefail

    nvim --headless \
      "+lua if vim.fn.exists(\":Lazy\")==2 then vim.cmd(\"Lazy! sync\") end" \
      "+lua if vim.fn.exists(\":MasonUpdate\")==2 then vim.cmd(\"MasonUpdate\") end" \
      "+lua if vim.fn.exists(\":MasonToolsInstall\")==2 then vim.cmd(\"MasonToolsInstall\") end" \
      "+lua if vim.fn.exists(\":TSUpdateSync\")==2 then vim.cmd(\"TSUpdateSync\") end" \
      "+qa"
  ' || log "Neovim bootstrap had errors (non-fatal). You can re-run inside nvim."

  date -Iseconds > "${marker}"
  chown "${STEM_UID}:${STEM_GID}" "${marker}"
}


configure_ssh_agent_env() {
  # If compose didn't set SSH_AUTH_SOCK, nothing to do.
  [[ -n "${SSH_AUTH_SOCK:-}" ]] || return 0

  # If it's not a socket, unset it to avoid confusing ssh/git.
  if [[ ! -S "${SSH_AUTH_SOCK}" ]]; then
    log "SSH_AUTH_SOCK is set but is not a socket; unsetting."
    unset SSH_AUTH_SOCK
    return 0
  fi

  log "SSH agent socket detected at ${SSH_AUTH_SOCK}"
}

install_ssh_agent_snippet() {
  local f="${HOME_DIR}/.bashrc.d/20-ssh-agent.sh"
  local tmp
  tmp="$(mktemp)"

  cat > "${tmp}" <<'EOF'
# ssh-agent plumbing (stem)
# Prefer SSH-forwarded agent (set by sshd) if present.
# Otherwise fall back to a host-mounted agent at /ssh-agent if it exists.
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  if [[ -S /ssh-agent ]]; then
    export SSH_AUTH_SOCK=/ssh-agent
  fi
fi
EOF

  install -m 0644 -o "${STEM_UID}" -g "${STEM_GID}" "${tmp}" "${f}"
  rm -f "${tmp}"
}


install_authorized_keys() {
  local persist_dir="/opt/stem/ssh"
  local persist_keys="${persist_dir}/authorized_keys"
  local injected="/opt/ssh/authorized_keys"

  install -d -m 700 -o "${STEM_UID}" -g "${STEM_GID}" "${SSH_DIR}"
  install -d -m 700 "${persist_dir}"

  if [[ -f "${injected}" && -s "${injected}" ]]; then
    log "Persisting provided authorized_keys from ${injected} -> ${persist_keys}"
    cp -f "${injected}" "${persist_keys}"
    chmod 600 "${persist_keys}"
  fi

  if [[ -f "${persist_keys}" && -s "${persist_keys}" ]]; then
    log "Installing authorized_keys from persisted store"
    install -m 600 -o "${STEM_UID}" -g "${STEM_GID}" "${persist_keys}" "${AUTH_KEYS}"
    chmod 700 "${SSH_DIR}"
    chmod 600 "${AUTH_KEYS}"
  else
    log "No authorized_keys found (neither injected nor persisted); SSH key login will fail."
  fi
}

ensure_group_user
ensure_supplemental_groups
ensure_account_unlocked
ensure_user_dirs
install_ssh_agent_snippet
ensure_uv_managed_python
ensure_user_cargo_env
write_shell_files

install_bindu_if_requested
install_apogee_secrets_if_injected

install_pixi_if_missing
configure_pixi_host_if_present

install_uv_pythons_if_requested
bootstrap_neovim_if_configured
install_authorized_keys
configure_ssh_agent_env

exit 0
