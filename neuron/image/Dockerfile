# neuron (cuda-lite) builds on your stem "dev OS"
FROM suhailphotos/stem:latest

ARG DEBIAN_FRONTEND=noninteractive

# Match your chosen CUDA line (12.6)
ARG CUDA_MAJOR_MINOR=12-6

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# -----------------------------
# CUDA repo keyring + CUDA toolkit
# (host NVIDIA driver still required; this installs userland tooling like nvcc)
# -----------------------------
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends wget ca-certificates gnupg; \
  rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  rm -f /etc/apt/sources.list.d/cuda.list || true; \
  wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb; \
  dpkg -i cuda-keyring_1.1-1_all.deb; \
  rm -f cuda-keyring_1.1-1_all.deb; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    cuda-toolkit-${CUDA_MAJOR_MINOR} \
  ; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/*

# Optional but nice: make sure nvcc is on PATH for interactive shells
RUN set -eux; \
  cat >/etc/profile.d/50-cuda-path.sh <<'EOF'
# CUDA PATH (neuron)
if [ -d /usr/local/cuda/bin ]; then
  case ":$PATH:" in
    *":/usr/local/cuda/bin:"*) ;;
    *) PATH="/usr/local/cuda/bin:$PATH" ;;
  esac
fi
export PATH
EOF
RUN chmod 644 /etc/profile.d/50-cuda-path.sh

# -----------------------------
# Create a shared ML venv under /opt/neuron/venv
# - This is the "base stack" for neuron.
# - Keep it root-owned (stable); projects can make their own envs if needed.
# -----------------------------
RUN set -eux; \
  mkdir -p /opt/neuron; \
  python3 -m venv /opt/neuron/venv

ENV PATH="/opt/neuron/venv/bin:$PATH" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Put neuron venv on PATH for all interactive shells
RUN set -eux; \
  cat >/etc/profile.d/45-neuron-venv.sh <<'EOF'
# neuron base venv (cuda)
if [ -d /opt/neuron/venv/bin ]; then
  case ":$PATH:" in
    *":/opt/neuron/venv/bin:"*) ;;
    *) PATH="/opt/neuron/venv/bin:$PATH" ;;
  esac
fi
export PATH
EOF
RUN chmod 644 /etc/profile.d/45-neuron-venv.sh

# Copy requirements early for caching
COPY image/requirements-cuda-lite.txt /tmp/requirements-cuda-lite.txt

# Install python deps (no Jupyter)
RUN set -eux; \
  uv pip install --upgrade pip setuptools wheel; \
  uv pip install --no-cache-dir -r /tmp/requirements-cuda-lite.txt; \
  rm -f /tmp/requirements-cuda-lite.txt

# Install PyTorch CUDA 12.6 wheels explicitly (cu126)
RUN set -eux; \
  uv pip install --no-cache-dir torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu126

# Quick sanity check (won't fail build if no GPU present at build time)
RUN set -eux; \
  python -c "import torch; print('torch', torch.__version__); print('cuda_available', torch.cuda.is_available())" || true; \
  nvcc --version | head -n 1 || true

# keep stem behavior: ssh + my_init
EXPOSE 22
CMD ["/sbin/my_init"]
