# neuron/Dockerfile
# base: microsoft devcontainers python image (works great with vscode devcontainers)
FROM mcr.microsoft.com/devcontainers/python:1-3.12-bookworm

# system deps
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      curl \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# uv (fast python packaging)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
 && ln -sf /root/.local/bin/uv /usr/local/bin/uv

# optional: a sane default workdir
WORKDIR /workspaces
