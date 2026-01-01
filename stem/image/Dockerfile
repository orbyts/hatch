FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

ARG STEM_USER=dev
ARG STEM_UID=1000
ARG STEM_GID=1000
ARG TZ=America/Los_Angeles

RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    openssh-server \
    gnupg \
    gpg \
    curl \
    ca-certificates \
    git \
    tzdata \
    locales \
    debsig-verify \
    ncurses-term \
    \
    stow \
    nodejs \
    npm \
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
    python3 \
    python3-venv \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    pkg-config \
    autoconf \
    automake \
    libtool \
    meson \
  && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends ncurses-bin \
  && rm -rf /var/lib/apt/lists/*

COPY image/terminfo/xterm-ghostty.terminfo /tmp/xterm-ghostty.terminfo
RUN tic -x /tmp/xterm-ghostty.terminfo && rm -f /tmp/xterm-ghostty.terminfo

RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone \
  && locale-gen en_US.UTF-8 \
  && update-locale LANG=en_US.UTF-8

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then \
      ln -s "$(command -v fdfind)" /usr/local/bin/fd; \
    fi

RUN set -eux; \
    EXISTING_G="$(getent group "${STEM_GID}" | cut -d: -f1 || true)"; \
    if [ -z "${EXISTING_G}" ]; then groupadd --gid "${STEM_GID}" "${STEM_USER}"; fi; \
    EXISTING_U="$(getent passwd "${STEM_UID}" | cut -d: -f1 || true)"; \
    if [ -n "${EXISTING_U}" ] && [ "${EXISTING_U}" != "${STEM_USER}" ]; then usermod -l "${STEM_USER}" "${EXISTING_U}"; fi; \
    if ! id -u "${STEM_USER}" >/dev/null 2>&1; then useradd --uid "${STEM_UID}" --gid "${STEM_GID}" -m -s /bin/bash "${STEM_USER}"; fi; \
    usermod -aG sudo "${STEM_USER}"; \
    echo "${STEM_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${STEM_USER}; \
    chmod 0440 /etc/sudoers.d/${STEM_USER}

# 1Password CLI (APT)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates gnupg; \
    rm -rf /var/lib/apt/lists/*; \
    \
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

# Rust + Apogee
ENV RUSTUP_HOME=/opt/rust/rustup \
    CARGO_HOME=/opt/rust/cargo
ENV PATH=${CARGO_HOME}/bin:${PATH}

RUN set -eux; \
    mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}"; \
    curl -fsSL --retry 10 --retry-delay 2 --retry-connrefused https://sh.rustup.rs -o /tmp/rustup.sh; \
    sh /tmp/rustup.sh -y --profile minimal; \
    rm -f /tmp/rustup.sh; \
    "${CARGO_HOME}/bin/cargo" --version; \
    for i in 1 2 3 4 5; do "${CARGO_HOME}/bin/cargo" install apogee && break || sleep 3; done

# SSH base + /opt/ssh mountpoint directory
RUN set -eux; \
    mkdir -p /var/run/sshd; \
    mkdir -p /etc/ssh/sshd_config.d; \
    mkdir -p /opt/ssh

COPY image/entrypoint.sh /usr/local/bin/stem-entrypoint
RUN chmod +x /usr/local/bin/stem-entrypoint

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/stem-entrypoint"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
