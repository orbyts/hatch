#!/usr/bin/env bash
set -euo pipefail

: "${BINDU_REPO:=}"
: "${BINDU_REF:=main}"

if [[ -z "${BINDU_REPO}" ]]; then
  echo "BINDU_REPO not set; skipping."
  exit 0
fi

cfg="${HOME}/.config"
mkdir -p "${cfg}"

tmp="$(mktemp -d)"
git clone --depth=1 --branch "${BINDU_REF}" "${BINDU_REPO}" "${tmp}"
cp -a "${tmp}/." "${cfg}/"
rm -rf "${tmp}"

echo "Bindu installed into: ${cfg}"
