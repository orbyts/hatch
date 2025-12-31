#!/usr/bin/env bash
set -euo pipefail

# bootstrap.sh: create a new devcontainer folder from a template
# usage:
#   ./scripts/bootstrap.sh <name>
#
# example:
#   ./scripts/bootstrap.sh rustbox

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "usage: $0 <name>"
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/neuron"
DST="$ROOT/$NAME"

if [[ -e "$DST" ]]; then
  echo "error: destination already exists: $DST"
  exit 1
fi

mkdir -p "$DST"
cp -R "$SRC/.devcontainer" "$DST/"
cp "$SRC/Dockerfile" "$DST/"
cp "$SRC/README.md" "$DST/README.md"

# patch names inside devcontainer.json + README
python3 - <<'PY'
import json, pathlib, sys
name = sys.argv[1]
dst = pathlib.Path(sys.argv[2])
p = dst/".devcontainer"/"devcontainer.json"
data = json.loads(p.read_text())
data["name"] = name
p.write_text(json.dumps(data, indent=2) + "\n")

r = dst/"README.md"
txt = r.read_text()
txt = txt.replace("# neuron", f"# {name}")
txt = txt.replace("neuron", name)
r.write_text(txt)
PY "$NAME" "$DST"

echo "created: $DST"
