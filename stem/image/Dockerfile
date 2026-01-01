FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=America/Los_Angeles

# Optional: install your Rust app at build time
ARG APOGEE_VERSION=

# -----------------------------
# Base packages
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
    eza \
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
    nodejs \
    npm \
  ; \
  rm -rf /var/lib/apt/lists/*

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
# Compatibility symlinks
# -----------------------------
RUN set -eux; \
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then \
    ln -s "$(command -v fdfind)" /usr/local/bin/fd; \
  fi; \
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then \
    ln -s "$(command -v batcat)" /usr/local/bin/bat; \
  fi

# -----------------------------
# Create a stable default user (dev)
# Runtime user remap is handled by entrypoint.
# -----------------------------
RUN set -eux; \
  if ! id -u dev >/dev/null 2>&1; then \
    useradd -m -s /bin/bash dev; \
  fi; \
  usermod -aG sudo dev; \
  echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev; \
  chmod 0440 /etc/sudoers.d/dev

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
  rm -rf /var/lib/apt/lists/*

# -----------------------------
# Rust toolchain (system-wide) + optional Apogee install
# -----------------------------
ENV RUSTUP_HOME=/opt/rust/rustup \
    CARGO_HOME=/opt/rust/cargo
ENV PATH=/opt/rust/cargo/bin:${PATH}

RUN set -eux; \
  cat >/etc/profile.d/10-stem-rust.sh <<'EOF'
export RUSTUP_HOME=/opt/rust/rustup
export CARGO_HOME=/opt/rust/cargo
export PATH="$CARGO_HOME/bin:$PATH"
EOF

RUN set -eux; \
  mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}"; \
  curl -fsSL --retry 10 --retry-delay 2 --retry-connrefused https://sh.rustup.rs -o /tmp/rustup.sh; \
  sh /tmp/rustup.sh -y --profile minimal; \
  rm -f /tmp/rustup.sh; \
  cargo --version; \
  if [ -n "${APOGEE_VERSION}" ]; then \
    for i in 1 2 3 4 5; do cargo install apogee --version "${APOGEE_VERSION}" && break || sleep 3; done; \
  else \
    for i in 1 2 3 4 5; do cargo install apogee && break || sleep 3; done; \
  fi

# -----------------------------
# Starship
# -----------------------------
RUN set -eux; \
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y; \
  starship --version

# -----------------------------
# SSH base
# -----------------------------
RUN set -eux; \
  mkdir -p /var/run/sshd /etc/ssh/sshd_config.d /opt/ssh

COPY image/entrypoint.sh /usr/local/bin/stem-entrypoint
RUN chmod +x /usr/local/bin/stem-entrypoint

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/stem-entrypoint"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
