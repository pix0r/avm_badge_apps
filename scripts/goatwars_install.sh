#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
firmware="${AVM_BADGE_PATH:-$(dirname -- "$root")/avm_badge}"
out="${GOATWARS_USB_OUTPUT:-$root/_build/goatwars-usb}"
build_only=false
case "${1:-}" in
  '') [[ $# == 0 ]] || exit 2 ;;
  --build-only) [[ $# == 1 ]] || exit 2; build_only=true ;;
  --help|-h) echo "Usage: $0 [--build-only]"; echo "AVM_BADGE_PATH selects Store firmware; GOATWARS_USB_OUTPUT selects output."; exit 0 ;;
  *) echo "Usage: $0 [--build-only]; serial port is automatic" >&2; exit 2 ;;
esac
[[ -f "$firmware/lib/badge/store.ex" ]] || { echo "AVM_BADGE_PATH must point to Store firmware" >&2; exit 1; }
if command -v mise >/dev/null 2>&1; then
  mix_cmd=(mise exec elixir@1.18.3-otp-27 erlang@27.1.2 -- mix)
else
  mix_cmd=(mix)
fi
out="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$out")"
firmware="$(cd -- "$firmware" && pwd)"
run_mix() { local dir="$1"; shift; (cd -- "$dir" && "${mix_cmd[@]}" "$@"); }
echo "Building offline GoatWars USB image from $root"
MIX_TARGET=badge run_mix "$firmware" run --no-start -e 'for path <- Mix.Tasks.Atomvm.Packbeam.runtime_deps(Mix.Dep.cached()), do: File.mkdir_p!(path)'
run_mix "$firmware" atomvm.packbeam
run_mix "$firmware" badge.assets
run_mix "$root" run --no-start scripts/goatwars_usb.exs "$firmware" "$out"
python3 - "$out" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
for name, limit in [('firmware.avm', 671744), ('assets.avm', 262144)]:
    data = (root/name).read_bytes()
    if not data.startswith(b'#!/usr/bin/env AtomVM\n\0\0') or len(data) > limit or len(data) <= 24:
        sys.exit(f'{name}: invalid pack or partition overflow')
    print(f'{name}: {len(data):,} / {limit:,} bytes')
PY
if "$build_only"; then echo "Build ready: $out; hardware untouched"; exit 0; fi
if command -v esptool >/dev/null 2>&1; then tool=(esptool)
elif command -v esptool.py >/dev/null 2>&1; then tool=(esptool.py)
elif python3 -c 'import esptool' >/dev/null 2>&1; then tool=(python3 -m esptool)
else echo "Install esptool before flashing" >&2; exit 1; fi
echo "Close serial monitors. Writing assets and main firmware; NVS and base image are preserved."
"${tool[@]}" --chip esp32s3 --baud 921600 --before default_reset --after hard_reset write_flash \
  0x278000 "$out/assets.avm" 0x2B8000 "$out/firmware.avm"
echo "Installed."
cat "$out/navigation.txt"
