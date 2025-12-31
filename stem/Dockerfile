FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG STEM_USER=dev
ARG STEM_UID=1000
ARG STEM_GID=1000
ARG TZ=UTC
ARG APOGEE_VERSION=""

ENV TZ=${TZ}
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Base tools (approx parity with your host tooling list)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip locales tzdata \
    build-essential cmake ninja-build pkg-config \
    autoconf automake libtool meson \
    python3 python3-venv python3-pip python3-setuptools python3-wheel \
    jq ripgrep fd-find fzf bat tree file \
    gawk xclip xsel wl-clipboard \
    ffmpeg poppler-utils p7zip-full imagemagick \
    tmux \
    openssh-server \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# fd-find provides fdfind; add fd alias
RUN if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then \
      ln -s "$(command -v fdfind)" /usr/local/bin/fd; \
    fi

# Create user from args (generic, driven by compose env)
RUN groupadd --gid ${STEM_GID} ${STEM_USER} \
 && useradd  --uid ${STEM_UID} --gid ${STEM_GID} -m -s /bin/bash ${STEM_USER} \
 && echo "${STEM_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${STEM_USER} \
 && chmod 0440 /etc/sudoers.d/${STEM_USER}

# SSHD minimal sane config
RUN mkdir -p /var/run/sshd \
 && sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
 && sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config \
 && echo "AllowUsers ${STEM_USER}" >> /etc/ssh/sshd_config

USER ${STEM_USER}
WORKDIR /home/${STEM_USER}

# Rust toolchain (so we can install apogee + other crates)
RUN curl -fsSL https://sh.rustup.rs | bash -s -- -y
ENV PATH=/home/${STEM_USER}/.cargo/bin:/home/${STEM_USER}/.local/bin:${PATH}

# Apogee
RUN if [ -n "${APOGEE_VERSION}" ]; then \
      cargo install apogee --version "${APOGEE_VERSION}"; \
    else \
      cargo install apogee; \
    fi

# Starship prompt (bash)
RUN curl -fsSL https://starship.rs/install.sh | bash -s -- -y \
 && echo 'eval "$(starship init bash)"' >> /home/${STEM_USER}/.bashrc

# Neovim (use Ubuntu package for now; swap to upstream later if you want)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends neovim \
 && rm -rf /var/lib/apt/lists/*

# Ensure authorized_keys exists (we'll mount it via compose)
RUN mkdir -p /home/${STEM_USER}/.ssh \
 && chown -R ${STEM_UID}:${STEM_GID} /home/${STEM_USER}/.ssh \
 && chmod 700 /home/${STEM_USER}/.ssh

# Entrypoint: run sshd in foreground
EXPOSE 22
CMD ["/usr/sbin/sshd","-D","-e"]
