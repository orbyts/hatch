FROM phusion/baseimage:noble-1.0.2

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Minimal useful tooling (add more later)
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    sudo ca-certificates curl git \
    openssh-server \
  ; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Enable sshd (baseimage ships sshd as a runit service, disabled by default)
RUN rm -f /etc/service/sshd/down
# Optionally regenerate host keys at build time (safe); baseimage also provides scripts for this.
RUN /etc/my_init.d/00_regen_ssh_host_keys.sh || true

RUN set -eux; \
  cat >/etc/profile.d/99-user-bins-first.sh <<'EOF'
# Put per-user bins first (cargo, pip/uv, npm-prefix, bun, deno, go, pnpm, yarn).
# Runs late (99-*) so it wins over other PATH edits.

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
  # Order here matters: earlier items end up *more* preferred.
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

# Startup scripts (run by /sbin/my_init in lexicographic order)
COPY my_init.d/ /etc/my_init.d/
RUN chmod +x /etc/my_init.d/*.sh

EXPOSE 22

# baseimage expects this
CMD ["/sbin/my_init"]
