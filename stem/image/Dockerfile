FROM phusion/baseimage:noble-1.0.2

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    sudo ca-certificates curl git \
    openssh-server \
    ncurses-bin ncurses-term \
  ; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Enable sshd (baseimage ships sshd as a runit service, disabled by default)
RUN rm -f /etc/service/sshd/down

# -----------------------------
# Terminfo (Ghostty)
# -----------------------------
COPY image/terminfo/xterm-ghostty.terminfo /tmp/xterm-ghostty.terminfo
RUN set -eux; \
  tic -x -o /usr/share/terminfo /tmp/xterm-ghostty.terminfo; \
  rm -f /tmp/xterm-ghostty.terminfo

# Host keys will live in /etc/ssh/keys (backed by a volume)
RUN set -eux; \
  install -d -m 700 /etc/ssh/keys; \
  sed -i \
    -e 's|^HostKey /etc/ssh/ssh_host_ed25519_key|HostKey /etc/ssh/keys/ssh_host_ed25519_key|g' \
    -e 's|^HostKey /etc/ssh/ssh_host_rsa_key|HostKey /etc/ssh/keys/ssh_host_rsa_key|g' \
    -e 's|^HostKey /etc/ssh/ssh_host_ecdsa_key|HostKey /etc/ssh/keys/ssh_host_ecdsa_key|g' \
    /etc/ssh/sshd_config

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

COPY my_init.d/ /etc/my_init.d/
RUN chmod +x /etc/my_init.d/*.sh

EXPOSE 22
CMD ["/sbin/my_init"]
