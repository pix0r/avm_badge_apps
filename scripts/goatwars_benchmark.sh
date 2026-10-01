#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
firmware="${AVM_BADGE_PATH:-$(dirname -- "$root")/avm_badge}"
source="${ATOMVM_SOURCE:?Set ATOMVM_SOURCE to the pinned AtomVM checkout}"
build="${ATOMVM_BUILD:-$source/build}"
boot="${ATOMVM_BOOT_PACK:?Set ATOMVM_BOOT_PACK to the verified badge-v1 boot.avm}"
out="${GOATWARS_RESULTS:-$(mktemp -d "${TMPDIR:-/tmp}/goatwars-benchmark.XXXXXX")}"
baseline="${GOATWARS_BASELINE_REF:-a1e6f4b}"
[[ "$(git -C "$source" rev-parse HEAD)" == a08e9fc1e20131e0d2b1432691ea198020bce0ff ]] || { echo "Wrong VM" >&2; exit 1; }
mkdir -p "$out/baseline/source" "$out/baseline/beams" "$out/current/beams"
git -C "$root" archive "$baseline" apps/goatwars/lib | tar -x -C "$out/baseline/source"
elixir -e 'expected="652d98edf174ea7ec650b9e573a4cb479fbf99fc7d017cddfdebe4fd97f2adbf"; actual=:crypto.hash(:sha256, File.read!(hd(System.argv()))) |> Base.encode16(case: :lower); if actual != expected, do: raise("Wrong boot pack")' "$boot"
for variant in baseline current; do
  if [[ "$variant" == baseline ]]; then code="$out/baseline/source"; else code="$root"; fi
  files=()
  while IFS= read -r file; do files+=("$file"); done < <(find "$code/apps/goatwars/lib" -name '*.ex' -type f)
  elixirc -o "$out/$variant/beams" "$firmware/lib/badge/page.ex" "${files[@]}" "$root/scripts/goatwars_benchmark.ex"
  elixir -e 'Code.require_file(Path.join(Enum.at(System.argv(),0),"deps/exatomvm/lib/packbeam.ex")); [_,dir,boot]=System.argv(); start=Path.join(dir,"beams/Elixir.GoatwarsBenchmark.beam"); rest=Path.wildcard(Path.join(dir,"beams/Elixir.Badge*.beam")); :ok=ExAtomVM.PackBEAM.make_avm([{start,:beam_start}] ++ Enum.map(rest,&{&1,:beam}) ++ [{boot,:avm}],Path.join(dir,"benchmark.avm"))' "$firmware" "$out/$variant" "$boot"
  "$build/src/AtomVM" "$out/$variant/benchmark.avm" > "$out/$variant/results.log" 2>&1
  tail -n 2 "$out/$variant/results.log"
done
python3 "$root/scripts/goatwars_compare.py" "$out/baseline/results.log" "$out/current/results.log"
echo "Results: $out"
