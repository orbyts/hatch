FROM phusion/baseimage:noble-1.0.2

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=America/Los_Angeles
ARG APOGEE_VERSION=

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# -----------------------------
# Base packages (full list you posted)
# -----------------------------
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    sudo \
    openssh-server \
    ca-certificates \
    curl \
    git \
    tzdata \
    locales \
    gnupg \
    gpg \
    debsig-verify \
    ncurses-term \
    ncurses-bin \
    \
    stow \
    unzip \
    gh \
    tree \
    gawk \
    bat \
    zoxide \
    wl-clipboard \
    xsel \
    file \
    fd-find \
    ripgrep \
    fzf \
    jq \
    xclip \
    \
    build-essential \
    tree-sitter-cli \
    cmake \
    ninja-build \
    pkg-config \
    autoconf \
    automake \
    libtool \
    meson \
    \
    python3 \
    python3-venv \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    \
    # nodejs \
    # npm \
  ; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# -----------------------------
# Terminfo (Ghostty)
# -----------------------------
COPY image/terminfo/xterm-ghostty.terminfo /tmp/xterm-ghostty.terminfo
RUN set -eux; \
  tic -x /tmp/xterm-ghostty.terminfo; \
  rm -f /tmp/xterm-ghostty.terminfo

# -----------------------------
# Locale + TZ
# -----------------------------
RUN set -eux; \
  ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime; \
  echo "${TZ}" > /etc/timezone; \
  locale-gen en_US.UTF-8; \
  update-locale LANG=en_US.UTF-8

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# -----------------------------
# Compatibility symlinks (fd, bat)
# -----------------------------
RUN set -eux; \
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then \
    ln -sf "$(command -v fdfind)" /usr/local/bin/fd; \
  fi; \
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then \
    ln -sf "$(command -v batcat)" /usr/local/bin/bat; \
  fi

# Enable sshd (baseimage ships sshd as a runit service, disabled by default)
RUN rm -f /etc/service/sshd/down

# -----------------------------
# SSH host keys live in /etc/ssh/keys (backed by a volume)
# -----------------------------
RUN set -eux; \
  install -d -m 700 /etc/ssh/keys; \
  sed -i \
    -e 's|^HostKey /etc/ssh/ssh_host_ed25519_key|HostKey /etc/ssh/keys/ssh_host_ed25519_key|g' \
    -e 's|^HostKey /etc/ssh/ssh_host_rsa_key|HostKey /etc/ssh/keys/ssh_host_rsa_key|g' \
    -e 's|^HostKey /etc/ssh/ssh_host_ecdsa_key|HostKey /etc/ssh/keys/ssh_host_ecdsa_key|g' \
    /etc/ssh/sshd_config

# -----------------------------
# 1Password CLI (APT)
# -----------------------------
RUN set -eux; \
  install -m 0755 -d /usr/share/keyrings /etc/apt/sources.list.d; \
  install -m 0755 -d /etc/debsig/policies/AC2D62742012EA22 /usr/share/debsig/keyrings/AC2D62742012EA22; \
  \
  curl -fsSL --retry 5 --retry-delay 2 https://downloads.1password.com/linux/keys/1password.asc -o /tmp/1password.asc; \
  gpg --batch --yes --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg /tmp/1password.asc; \
  gpg --batch --yes --dearmor -o /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg /tmp/1password.asc; \
  rm -f /tmp/1password.asc; \
  \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
    > /etc/apt/sources.list.d/1password.list; \
  \
  curl -fsSL --retry 5 --retry-delay 2 https://downloads.1password.com/linux/debian/debsig/1password.pol \
    -o /etc/debsig/policies/AC2D62742012EA22/1password.pol; \
  \
  apt-get update; \
  apt-get install -y --no-install-recommends 1password-cli; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/*

# -----------------------------
# eza (deb.gierens.de) -> apt-managed newer builds
# -----------------------------
RUN set -eux; \
  mkdir -p /etc/apt/keyrings; \
  curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
    | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg; \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/gierens.gpg] https://deb.gierens.de stable main" \
    > /etc/apt/sources.list.d/gierens.list; \
  chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list; \
  apt-get update; \
  apt-get install -y --no-install-recommends eza; \
  eza --version; \
  rm -rf /var/lib/apt/lists/*

# -----------------------------
# Node.js (modern LTS via NodeSource)
# -----------------------------
ARG NODE_MAJOR=22

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends ca-certificates curl; \
  mkdir -p /etc/apt/keyrings; \
  curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list; \
  apt-get update; \
  apt-get install -y --no-install-recommends nodejs; \
  node --version; \
  npm --version; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/*

# -----------------------------
# uv (system-wide) -> /usr/local/bin/uv
# -----------------------------
ARG UV_VERSION=

RUN set -eux; \
  if [[ -n "${UV_VERSION}" ]]; then \
    curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | env UV_NO_MODIFY_PATH=1 UV_UNMANAGED_INSTALL="/usr/local/bin" sh; \
  else \
    curl -LsSf "https://astral.sh/uv/install.sh" | env UV_NO_MODIFY_PATH=1 UV_UNMANAGED_INSTALL="/usr/local/bin" sh; \
  fi; \
  command -v uv; \
  uv --version

# -----------------------------
# Rust toolchain (baseline) -> /opt/rust/*
# - baseline binaries are exposed via /usr/local/bin symlinks
# - NO global ENV for CARGO_HOME/RUSTUP_HOME at runtime
# -----------------------------
RUN set -eux; \
  export RUSTUP_HOME=/opt/rust/rustup; \
  export CARGO_HOME=/opt/rust/cargo; \
  export RUSTUP_USE_CURL=1; \
  export RUSTUP_MAX_RETRIES=10; \
  rm -rf /opt/rust; \
  mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"; \
  curl -fsSL --retry 10 --retry-delay 2 --retry-connrefused https://sh.rustup.rs -o /tmp/rustup.sh; \
  sh /tmp/rustup.sh -y --profile minimal --no-modify-path; \
  rm -f /tmp/rustup.sh; \
  "$CARGO_HOME/bin/rustup" toolchain install stable; \
  "$CARGO_HOME/bin/rustup" default stable; \
  TOOLCHAIN="$("$CARGO_HOME/bin/rustup" show active-toolchain | awk '{print $1}')"; \
  BIN="/opt/rust/rustup/toolchains/${TOOLCHAIN}/bin"; \
  ln -sf "${BIN}/cargo"   /usr/local/bin/cargo; \
  ln -sf "${BIN}/rustc"   /usr/local/bin/rustc; \
  ln -sf "${BIN}/rustdoc" /usr/local/bin/rustdoc; \
  /usr/local/bin/cargo --version; \
  /usr/local/bin/rustc --version

# -----------------------------
# Apogee baseline (system-wide) -> /usr/local/bin
# - uses baseline cargo, installs apogee into /usr/local
# - IMPORTANT: don't execute apogee during build
# -----------------------------
RUN set -eux; \
  export RUSTUP_HOME=/opt/rust/rustup; \
  export CARGO_HOME=/opt/rust/cargo; \
  if [[ -n "${APOGEE_VERSION}" ]]; then \
    /opt/rust/cargo/bin/cargo install apogee --version "${APOGEE_VERSION}" --locked --root /usr/local; \
  else \
    /opt/rust/cargo/bin/cargo install apogee --locked --root /usr/local; \
  fi; \
  rm -rf /opt/rust/cargo/registry /opt/rust/cargo/git || true; \
  test -x /usr/local/bin/apogee

# -----------------------------
# Starship (opt-in via config or STEM_STARSHIP_FORCE)
# -----------------------------
RUN set -eux; \
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y; \
  starship --version

RUN set -eux; \
  cat >/etc/profile.d/30-stem-starship.sh <<'EOF'
if [[ $- == *i* ]] && command -v starship >/dev/null 2>&1; then
  if [[ -f "$HOME/.config/starship.toml" || -n "${STEM_STARSHIP_FORCE:-}" ]]; then
    eval "$(starship init bash)"
  fi
fi
EOF
RUN chmod 644 /etc/profile.d/30-stem-starship.sh


# -----------------------------
# Neovim (latest stable release) -> /opt/nvim + /usr/local/bin/nvim
# -----------------------------
ARG NVIM_VERSION=

RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    amd64) asset="nvim-linux-x86_64.tar.gz" ;; \
    arm64) asset="nvim-linux-arm64.tar.gz" ;; \
    *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
  esac; \
  if [[ -n "${NVIM_VERSION}" ]]; then \
    base="https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}"; \
  else \
    base="https://github.com/neovim/neovim/releases/latest/download"; \
  fi; \
  tmp="$(mktemp -d)"; \
  curl -fsSL "${base}/${asset}" -o "${tmp}/nvim.tgz"; \
  tar -xzf "${tmp}/nvim.tgz" -C "${tmp}"; \
  nvimdir="$(find "${tmp}" -maxdepth 1 -type d -name 'nvim-linux-*' -print -quit)"; \
  test -n "${nvimdir}"; \
  rm -rf /opt/nvim; \
  mv "${nvimdir}" /opt/nvim; \
  ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim; \
  rm -rf "${tmp}"; \
  nvim --version | head -n 1




# -----------------------------
# Your existing PATH policy script (unchanged)
# -----------------------------
RUN set -eux; \
  cat >/etc/profile.d/99-user-bins-first.sh <<'EOF'
path_prepend_unique() {
  local d="$1"
  [ -d "$d" ] || return 0

  local new=""
  local IFS=':'
  for p in $PATH; do
    [ -z "$p" ] && continue
    [ "$p" = "$d" ] && continue
    new="${new:+$new:}$p"
  done
  PATH="$d${new:+:$new}"
}

if [ -n "${HOME:-}" ]; then
  for d in \
    "$HOME/.local/bin" \
    "$HOME/.cargo/bin" \
    "$HOME/.npm-global/bin" \
    "$HOME/.bun/bin" \
    "$HOME/.deno/bin" \
    "$HOME/go/bin" \
    "$HOME/.local/share/pnpm" \
    "$HOME/.yarn/bin" \
    "$HOME/.config/yarn/global/node_modules/.bin" \
  ; do
    path_prepend_unique "$d"
  done
fi

export PATH
EOF
RUN chmod 644 /etc/profile.d/99-user-bins-first.sh

# Startup scripts (run by /sbin/my_init)
COPY my_init.d/ /etc/my_init.d/
RUN chmod +x /etc/my_init.d/*.sh

EXPOSE 22
CMD ["/sbin/my_init"]
