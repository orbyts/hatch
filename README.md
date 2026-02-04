# hatch: stem + neuron (ssh dev containers)

This repo builds two related images:

- **stem**: a portable Ubuntu-based dev container you can SSH into.
- **neuron**: a GPU-capable “workbench” container that builds on the same bootstrap pattern (and often the stem base).

Both containers are designed around a simple idea:

- **the container starts as root** (so init can do privileged setup safely)
- **a normal user is created/normalized on boot** using `STEM_USER`, `STEM_UID`, `STEM_GID`
- **your home lives on a volume** so it survives rebuilds
- you can optionally mount host folders (Dropbox, project dirs, etc.) without fighting permissions

> This README is intentionally **general**.
> Host-specific mounts (like your NFS / VirtIO-FS shares) belong in per-host docs under
> `$DOCKER/services/<host>/{stem,neuron}/README.md`.

---

## What you get

### stem

- Ubuntu (phusion baseimage) with SSH enabled (port exposed via compose)
- Boot-time user creation/normalization (`STEM_USER`, `STEM_UID`, `STEM_GID`)
- Persistent `/home/<user>` volume (survives rebuilds)
- Persistent SSH host keys (so clients don’t see “host key changed”)
- Optional Dropbox bind mount into `/home/<user>/Dropbox`
- Optional dotfiles bootstrap (bindu) into `~/.config`
- Optional Pixi install + host config stow + optional `pixi global sync`
- Optional Apogee secrets injection into `~/.config/apogee/secrets.env`

### neuron

- Everything above (same bootstrap philosophy)
- GPU access via Docker’s `gpus:` stanza (when supported on the Docker host)
- A place to mount your ML workspace paths consistently (projects/datasets/models/etc.)
- Designed to run long-lived and be reachable via SSH like stem

---

## Why UID/GID mapping matters

If you bind-mount host paths into a container (Dropbox, repos, NFS shares, VirtIO-FS mounts, etc.),
Linux permissions are still enforced.

The most reliable pattern is:

- Keep the container’s “real” user **numerically identical** to your host user (UID/GID)
- For shared folders, manage access via groups (GID) and setgid directories where appropriate

That’s why stem/neuron take:

- `STEM_UID` (default `1000`)
- `STEM_GID` (default `1000`)

At boot, the init script will:

1. ensure the group with `STEM_GID` exists
2. ensure the user with `STEM_UID` exists
3. ensure the user’s **primary group** is `STEM_GID`
4. repair ownership for a curated set of safe home subdirectories (without `chown -R $HOME`)

This makes mounts “just work” when you keep your host user at `1000:1000` (typical on Ubuntu),
and avoids permission pain for future mounts.

---

## Repo layout

Relevant paths:

- `stem/image/Dockerfile` — stem image build
- `stem/my_init.d/00-user-bootstrap.sh` — user/bootstrap logic (user creation + optional hooks)
- `stem/my_init.d/01-ssh-hostkeys.sh` — persistent SSH host keys generation
- `stem/docker-compose.yml` — public compose template
- `stem/.env.example` — public env template

Neuron equivalents:

- `neuron/image/Dockerfile`
- `neuron/compose/docker-compose.yml`

---

## Quick start: stem (template)

### 1) Copy `.env.example` → `.env`

From the repo root:

```bash
cd stem
cp .env.example .env
```

Edit `.env` to match your machine (paths + UID/GID).

### 2) Create volumes (first time only)

If your compose uses named volumes, Docker may create them automatically.
If you’re using **external volumes** (recommended for rebuild safety), create them once:

```bash
docker volume create home
docker volume create sshkeys
docker volume create sshstate
```

### 3) Start the container

From `stem/`:

```bash
docker compose up -d
docker compose ps
```

### 4) SSH in

Default SSH port is `22222` (configurable):

```bash
ssh -p 22222 dev@<docker-host-ip>
```

If you injected `authorized_keys`, you should be able to login immediately.

---

## Quick start: neuron (template)

Neuron’s compose lives under `neuron/compose/`. The pattern is the same:

1. copy a `.env`
2. create required external volumes (if used)
3. bring it up with Docker Compose
4. SSH in

GPU hosts typically require:

- NVIDIA drivers installed on the host
- the NVIDIA container runtime configured
- your Docker version supporting the `gpus:` stanza

---

## Configuration surface

Everything is driven by `.env` + `docker-compose.yml`.

### Core identity

- `STEM_CONTAINER_NAME` — Docker container name (optional)
- `STEM_HOSTNAME` — container hostname (used for pixi host selection)
- `STEM_SSH_PORT` — host port mapped to container `22`

### User mapping

- `STEM_USER` — username inside container (default `dev`)
- `STEM_UID`, `STEM_GID` — numeric IDs (recommended: match your host user)

If you mount host folders into `/home/<user>` or elsewhere, matching UID/GID prevents permission pain.

### SSH authorized keys injection (recommended)

Set `STEM_AUTH_KEYS_PATH` to a file on the Docker host, mounted read-only into the container:

- a public key file (e.g. `~/.ssh/id_ed25519.pub`)
- or an `authorized_keys` file

On first boot, the bootstrap persists it into the `sshstate` volume so it survives rebuilds.

### Dropbox bind mount (optional)

Set `DROPBOX_PATH_ON_HOST` if you want host Dropbox mounted into the container:

- Linux example: `/home/<you>/Dropbox`
- macOS example: `/Users/<you>/Library/CloudStorage/Dropbox`

If unset, your compose can map `/dev/null` instead to effectively disable the mount.

### Bindu (dotfiles) bootstrap (optional)

If you want the container to clone/copy your dotfiles repo into `~/.config`:

- `BINDU_REPO` — HTTPS repo URL
- `BINDU_REF` — branch/tag (default `main`)
- `BINDU_FORCE` — set `1` to overwrite an existing non-empty `~/.config`

If `BINDU_REPO` is empty, bindu bootstrap is skipped.

#### Keeping bindu up to date later

The first-boot bootstrap is intentionally conservative (it won’t overwrite a non-empty `~/.config` by default).
If you want to update later, you have two safe patterns:

**A) Re-run bootstrap with force** (simple, but overwrites `~/.config`):

```bash
# On the Docker host, in your .env:
# BINDU_FORCE=1
docker compose restart
```

**B) Update only a specific subtree using rsync** (recommended)

Stem includes `rsync` (v0.1.2+), so you can update just the portion you care about.
Example: update only `~/.config/apogee` from your bindu repo:

```bash
docker exec -it stem bash -lc '
  set -euo pipefail
  u="${STEM_USER:-dev}"
  su - "$u" -c "
    set -euo pipefail
    tmp=\$(mktemp -d)
    git clone --depth=1 --branch "${BINDU_REF:-main}" "${BINDU_REPO}" "\$tmp"
    mkdir -p "\$HOME/.config/apogee"
    rsync -a --delete "\$tmp/apogee/" "\$HOME/.config/apogee/"
    rm -rf "\$tmp"
  "
'
```

> In a future version (planned), we’ll make “update-only” behavior a first-class command/hook.

### Pixi (optional)

Pixi can be installed and configured per “host folder” like:

`~/.config/pixi/hosts/<host>/.pixi/manifests/pixi-global.toml`

The bootstrap can stow that into `~/.pixi/manifests/pixi-global.toml`.

Environment flags:

- `STEM_PIXI_ENABLE` — `1` installs pixi if missing (default `1`)
- `STEM_PIXI_STOW` — `auto|0|1` controls whether bootstrap attempts to stow host config
- `STEM_PIXI_GLOBAL_SYNC` — `1` runs `pixi global sync` during boot (default `0`)

Host selection logic (typical):

- Prefer `STEM_PIXI_HOST` (if set)
- Else use `STEM_HOSTNAME`
- Else `hostname -s`

Tip: set `hostname:` in compose and keep a matching `hosts/<hostname>/` folder for pixi.

### Apogee secrets (optional)

If you use Apogee and want `~/.config/apogee/secrets.env` available inside the container without baking it into the image:

- Set `APOGEE_SECRETS_PATH` in `.env` to a file on the Docker host
- It will be mounted read-only at `/opt/secrets/apogee-secrets.env`

The bootstrap copies it into `~/.config/apogee/secrets.env` only when present (and doesn’t overwrite silently).

This keeps secrets off the image and out of the repo.

---

## SSH agent forwarding (optional)

A Docker container can only mount sockets from the **Docker host**, not from your remote client.

So agent forwarding into the container works like this:

- Docker runs on host `vortex`
- You mount `vortex`’s `SSH_AUTH_SOCK` into the container (a socket file)
- Inside the container, `SSH_AUTH_SOCK=/ssh-agent` points at that mounted socket

This enables GitHub pushes/pulls from inside the container using keys loaded in the Docker host’s agent.

On the Docker host:

```bash
echo "$SSH_AUTH_SOCK"
test -S "$SSH_AUTH_SOCK" && echo ok
```

If you see `ok`, set in `.env`:

```dotenv
STEM_SSH_AUTH_SOCK_HOST=/path/to/host/agent.sock
```

And mount in compose:

```yaml
- "${STEM_SSH_AUTH_SOCK_HOST:-/dev/null}:/ssh-agent"
```

Inside the container, set:

```yaml
environment:
  SSH_AUTH_SOCK: /ssh-agent
```

---

## Common operations

### View logs

```bash
docker logs stem
```

### Restart

```bash
docker compose restart
```

### Rebuild locally (dev)

From `stem/`:

```bash
docker compose build --no-cache
docker compose up -d
```

### Sanity checks inside the container

```bash
id
getent passwd "$STEM_USER"
ls -la "$HOME"
```

---

## Image build + publish workflow (reference)

Example for stem:

```bash
cd "$MATRIX/hatch/stem"

docker build -f image/Dockerfile \
  -t suhailphotos/stem:0.1.2 \
  -t suhailphotos/stem:latest \
  .

docker push suhailphotos/stem:0.1.2
docker push suhailphotos/stem:latest
```

Neuron follows the same idea.

---

## License

MIT

