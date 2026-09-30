#!/usr/bin/env bash
set -euo pipefail
GOATWARS_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GOATWARS_BADGE="${AVM_BADGE_PATH:-$(dirname -- "$GOATWARS_ROOT")/avm_badge}"
if [[ ! -f "$GOATWARS_BADGE/mix.exs" ]]; then
  echo "Set AVM_BADGE_PATH to the firmware checkout." >&2
  exit 1
fi
cd -- "$GOATWARS_BADGE"
export MIX_TARGET=host
exec mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- iex -S mix run "$GOATWARS_ROOT/scripts/goatwars_sim.exs"
