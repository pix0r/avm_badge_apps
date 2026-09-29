#!/usr/bin/env bash
set -euo pipefail
GOATRON_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GOATRON_BADGE="${AVM_BADGE_PATH:-$(dirname -- "$GOATRON_ROOT")/avm_badge}"
if [[ ! -f "$GOATRON_BADGE/mix.exs" ]]; then
  echo "Set AVM_BADGE_PATH to the firmware checkout." >&2
  exit 1
fi
cd -- "$GOATRON_BADGE"
export MIX_TARGET=host
exec mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- iex -S mix run "$GOATRON_ROOT/scripts/goatron_sim.exs"
