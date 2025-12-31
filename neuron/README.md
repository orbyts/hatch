# neuron

ml-focused devcontainer (python). good starting point for cv/vfx, notebooks, and model training.

## what's inside

- python 3.12 base
- `uv` for dependency management
- common build deps (git, curl, build-essential)

## notes

- if you want gpu support, extend the Dockerfile with a cuda base image and add the nvidia container runtime on the host.
