#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
firmware="${AVM_BADGE_PATH:-$(dirname -- "$root")/avm_badge}"
source="${ATOMVM_SOURCE:?Set ATOMVM_SOURCE to the badge-v1 AtomVM checkout}"
build="${ATOMVM_BUILD:-$source/build}"
boot="${ATOMVM_BOOT_PACK:?Set ATOMVM_BOOT_PACK to the verified badge-v1 boot.avm}"
out="${GOATWARS_RESULTS:-$(mktemp -d "${TMPDIR:-/tmp}/goatwars-native.XXXXXX")}"
expected=a08e9fc1e20131e0d2b1432691ea198020bce0ff
[[ "$(git -C "$source" rev-parse HEAD)" == "$expected" ]] || { echo "Wrong AtomVM revision" >&2; exit 1; }
[[ -x "$build/src/AtomVM" && -f "$boot" && -f "$firmware/lib/badge/page.ex" ]] || { echo "Missing VM, boot pack or firmware" >&2; exit 1; }
elixir -e 'expected = "652d98edf174ea7ec650b9e573a4cb479fbf99fc7d017cddfdebe4fd97f2adbf"; actual = :crypto.hash(:sha256, File.read!(hd(System.argv()))) |> Base.encode16(case: :lower); if actual != expected, do: raise("Wrong boot.avm checksum")' "$boot"
mkdir -p "$out/beams" "$out/loader"
game_sources=()
while IFS= read -r file; do game_sources+=("$file"); done < <(find "$root/apps/goatwars/lib" -name "*.ex" -type f)
elixirc -o "$out/beams" "$firmware/lib/badge/page.ex" "${game_sources[@]}" "$root/scripts/goatwars_atomvm.ex" "$root/scripts/goatwars_resources.ex"
elixir "$root/scripts/goatwars_build_native.exs" "$out" "$firmware" "$source" "$build" "$boot" | tee "$out/build.log"
GOATWARS_PACK="$out/goatwars.avm" GOATWARS_IMPORTS="$out/imports.term" elixirc --ignore-module-conflict -pa "$out/beams" -o "$out/loader" "$firmware/lib/badge/page.ex" "$root/scripts/goatwars_loader.ex"
elixir -e 'Code.require_file(Path.join(Enum.at(System.argv(), 0), "deps/exatomvm/lib/packbeam.ex")); [_, out, boot] = System.argv(); paths = Path.wildcard(Path.join(out, "loader/*.beam")); entry = Path.join(out, "loader/Elixir.GoatwarsLoader.beam"); others = Enum.reject(paths, &(&1 == entry)); :ok = ExAtomVM.PackBEAM.make_avm([{entry, :beam_start}] ++ Enum.map(others, &{&1, :beam}) ++ [{boot, :avm}], Path.join(out, "loader.avm"))' "$firmware" "$out" "$boot"
for entry in loader GoatwarsReadiness GoatwarsResources; do
  "$build/src/AtomVM" "$out/$entry.avm" > "$out/$entry.log" 2>&1 || { cat "$out/$entry.log"; exit 1; }
  tail -n 2 "$out/$entry.log"
done
printf 'Results: %s\n' "$out"
