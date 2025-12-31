# hatch

A curated set of reusable development containers you can mix and match across projects.

## layout

- `neuron/` — ml-focused devcontainer (python)
- `scripts/` — small helpers for bootstrapping new container folders

## usage

1. clone the repo
2. open in vscode
3. pick a dev container (example: `neuron`)
4. **Dev Containers: Open Folder in Container**

## adding a new container

- copy an existing container folder (like `neuron/`)
- rename it
- update its `.devcontainer/devcontainer.json` + `Dockerfile`
- commit

## license

MIT
