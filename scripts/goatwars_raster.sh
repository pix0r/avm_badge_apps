#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
vm="${ATOMVM_SOURCE:?Set ATOMVM_SOURCE}"
renderer="${ATOMGL_SOURCE:?Set ATOMGL_SOURCE to the pinned display driver checkout}"
[[ $# == 1 ]] || { echo "Usage: $0 benchmark-results-directory" >&2; exit 2; }
out="$1"
[[ "$(git -C "$renderer" rev-parse HEAD)" == 11be5f9a85a6eabb3ffcd331ed8678101224b237 ]] || { echo "Wrong AtomGL revision" >&2; exit 1; }
mkdir -p "$out/raster/driver"
printf '#define SPI_SWAP_DATA_TX(v,n) __builtin_bswap16(v)\n' > "$out/raster/driver/spi_master.h"
clang -O3 -DHAVE_ATOMIC=1 -I "$out/raster" -I "$renderer" -I "$vm/src/libAtomVM" \
  "$root/scripts/goatwars_raster.c" "$renderer/dcs_lcd_draw.c" "$renderer/font_data.c" -o "$out/raster/bench"
GOATWARS_RASTER_EXE="$out/raster/bench" python3 -m unittest discover -s "$root/test/scripts" -p test_goatwars_raster.py -v
for variant in baseline current; do
  elixir "$root/scripts/goatwars_raster_export.exs" "$out/$variant/beams" "$out/$variant/scenes"
  : > "$out/$variant/raster.log"
  for tick in {1..207}; do
    "$out/raster/bench" "$out/$variant/scenes/$tick.scene" >> "$out/$variant/raster.log"
  done
done
python3 "$root/scripts/goatwars_compare.py" "$out/baseline/results.log" "$out/current/results.log" "$out/baseline/raster.log" "$out/current/raster.log"
