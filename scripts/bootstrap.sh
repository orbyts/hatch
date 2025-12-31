#!/usr/bin/env bash
set -euo pipefail

: "${BINDU_REPO:=}"
: "${BINDU_REF:=main}"

if [[ -z "${BINDU_REPO}" ]]; then
  echo "BINDU_REPO not set; skipping."
  exit 0
fi

dest="${HOME}/.local/share/bindu"
mkdir -p "${HOME}/.local/share"

if [[ ! -d "${dest}/.git" ]]; then
  git clone --depth=1 --branch "${BINDU_REF}" "${BINDU_REPO}" "${dest}"
else
  git -C "${dest}" fetch --depth=1 origin "${BINDU_REF}"
  git -C "${dest}" checkout "${BINDU_REF}"
  git -C "${dest}" pull --ff-only
fi

echo "Bindu cloned to: ${dest}"
