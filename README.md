# stem (ssh dev container)

`stem` is a portable Ubuntu-based dev container you can SSH into. It bootstraps a normal user, supports persistent home volumes, and can optionally:
- install **pixi** and apply a host-specific pixi global manifest via stow
- bootstrap **bindu** (dotfiles) into `~/.config`
- inject SSH `authorized_keys` at first boot
- optionally mount an SSH agent socket from the Docker host
- optionally mount **apogee** `secrets.env` into the container (your secrets stay off the image)

This repo ships a **public template**: `stem/docker-compose.yml` + `stem/.env.example`.
You copy `.env.example` → `.env`, adjust paths, and run `docker compose up -d`.

> Notes:
> - Your `.env` is intentionally not tracked.
> - This README assumes you run Docker on Linux, but macOS works too if paths are updated.

---

## What you get

- Ubuntu (phusion baseimage) with SSH enabled (port exposed via compose)
- A user created/normalized at boot (`STEM_USER`, `STEM_UID`, `STEM_GID`)
- Persistent `/home/<user>` volume (survives rebuilds)
- Persistent SSH host keys (so clients don’t see “host key changed”)
- Optional Dropbox bind mount into `/home/<user>/Dropbox`
- Optional `bindu` install into `~/.config`
- Optional `pixi` install + host config stow + optional `pixi global sync`

---

## Repo layout

Relevant paths:

- `stem/image/Dockerfile` — base image build
- `stem/my_init.d/00-user-bootstrap.sh` — main bootstrap logic (user creation, optional hooks)
- `stem/my_init.d/01-ssh-hostkeys.sh` — persistent SSH host keys generation
- `stem/docker-compose.yml` — public compose template
- `stem/.env.example` — public env template

---

## Quick start (template)

### 1) Copy `.env.example` → `.env`

From the repo root:

```bash
cd stem
cp .env.example .env
```

Edit `.env` to match your machine (paths + UID/GID).

### 2) Create volumes (first time only)

If your compose uses named volumes, Docker will create them automatically.
If you’re using external volumes in your local deployment, create them once:

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

If you mounted `authorized_keys`, you should be able to login immediately.

---

## Configuration

All configuration is driven by `.env` + `docker-compose.yml`.

### Core identity

- `STEM_CONTAINER_NAME` — Docker container name (optional)
- `STEM_HOSTNAME` — container hostname (used for pixi host selection)
- `STEM_SSH_PORT` — host port mapped to container `22`

### User mapping

- `STEM_USER` — username inside container (default `dev`)
- `STEM_UID`, `STEM_GID` — numeric IDs (recommended: match your host user)

Why it matters: if you mount host folders into `/home/<user>`, matching UID/GID prevents permission pain.

### SSH authorized keys injection (recommended)

Set `STEM_AUTH_KEYS_PATH` to a file on the Docker host, mounted read-only into the container at boot:

- a public key file (e.g. `~/.ssh/id_ed25519.pub`)
- or an `authorized_keys` file

The bootstrap persists it into the `sshstate` volume so it survives rebuilds.

### Dropbox bind mount (optional)

Set `DROPBOX_PATH_ON_HOST` if you want host Dropbox mounted into the container:

- Linux example: `/home/<you>/Dropbox`
- macOS example: `/Users/<you>/Library/CloudStorage/Dropbox`

If unset, the mount will resolve to `/dev/null` in the public template and be effectively disabled.

### Bindu (dotfiles) bootstrap (optional)

If you want the container to clone/copy your dotfiles repo into `~/.config` on first boot:

- `BINDU_REPO` — https repo url (recommended for public usage)
- `BINDU_REF` — branch/tag (default `main`)
- `BINDU_FORCE` — set `1` to overwrite an existing non-empty `~/.config`

If `BINDU_REPO` is empty, bindu bootstrap is skipped.

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

Tip: set `hostname: stem` in compose and keep a `hosts/stem/` folder for pixi.

### Apogee secrets (optional)

If you use Apogee and want `~/.config/apogee/secrets.env` available inside the container without baking it into the image:

- Set `APOGEE_SECRETS_PATH` in `.env` to a file on the Docker host
- It will be mounted read-only at `/opt/secrets/apogee-secrets.env`

Your bootstrap can copy it into `~/.config/apogee/secrets.env` **only when present**.

This keeps secrets off the image and out of the repo.

---

## SSH agent forwarding (optional)

There are two different “agent” concepts people mix up:

1) **Your laptop/client SSH agent** (the machine you type `ssh ...` from)
2) **The Docker host’s SSH agent** (the machine actually running Docker)

A Docker container can only mount sockets from the **Docker host**, not from your remote client.
So agent forwarding into the container works like this:

- You run Docker on host `vortex`
- You mount `vortex`’s `SSH_AUTH_SOCK` into the container (a socket file)
- Inside the container, `SSH_AUTH_SOCK=/ssh-agent` points at that mounted socket

This enables GitHub pushes/pulls from inside the container *using keys loaded on the Docker host agent*.

### Requirements

On the Docker host (the machine running Docker):

```bash
echo "$SSH_AUTH_SOCK"
test -S "$SSH_AUTH_SOCK" && echo ok
```

If you see `ok`, you can mount it into the container.

### How to enable

In your `.env` on the Docker host:

```dotenv
STEM_SSH_AUTH_SOCK_HOST=/path/to/host/agent.sock
```

And in compose the mount is:

```yaml
- "${STEM_SSH_AUTH_SOCK_HOST:-/dev/null}:/ssh-agent"
```

Inside the container, set:

```yaml
environment:
  SSH_AUTH_SOCK: /ssh-agent
```

> If you SSH into the Docker host from your laptop and use SSH agent forwarding (`ssh -A`),
> the Docker host may have an agent socket available that represents your laptop keys.
> That can indirectly make your laptop keys usable *on the Docker host* and therefore usable by the container.
> This part depends on your host SSH configuration and is outside the container’s control.

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

### Rebuild image locally (dev)

From `stem/`:

```bash
docker compose build --no-cache
docker compose up -d
```

### Verify pixi config

Inside the container:

```bash
ls -la ~/.pixi/manifests
pixi global sync
```

---

## Security notes

- Do not commit `.env` or any secrets file.
- Prefer `authorized_keys` injection or host-agent forwarding over copying private keys into the container.
- If you mount an SSH agent socket into a container, processes in the container may be able to use that agent.
  Treat this as equivalent to granting access to the keys loaded in that agent.

---

## license

MIT
