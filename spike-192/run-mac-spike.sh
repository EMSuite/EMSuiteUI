#!/bin/zsh
# MU0 spike (EMSuiteUI #192): RealityKit crystal view, parallel projection, frame times on the reference Mac.
# One script. Works only in $TMPDIR/crystal-spike (a copy of this folder); touches no repository and no suite folder.
# Opens a window per run (about 12 s each, 5 runs) and sends no mouse or keyboard events: a timer turns the crystal as a
# drag would. Each run records the load before and after and is flagged BUSY when other processes used the CPU.
# Results: $TMPDIR/crystal-spike/out/result.txt and PNG pictures beside it.
set -u
here="${0:A:h}"
work="${TMPDIR:-/tmp}/crystal-spike"
out="$work/out"
if pgrep -x swift-build >/dev/null || pgrep -x xcodebuild >/dev/null || pgrep -x swift-frontend >/dev/null; then
  echo "BUSY: a swift build or xcodebuild is already running; not starting the spike."; exit 3
fi
if [[ "$here" != "$work" ]]; then rm -rf "$work"; mkdir -p "$work"; cp -R "$here/Package.swift" "$here/Sources" "$work/"; fi
mkdir -p "$out"
{
  date -u
  sysctl -n machdep.cpu.brand_string
  sysctl -n hw.model
  echo "memory $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
  sw_vers -productVersion
  swift --version 2>&1 | head -1
  system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset|Resolution|Refresh|Main Display' | sed 's/^ *//'
} > "$out/meta.txt"

( cd "$work" && swift build -c release -j 8 ) > "$out/build.txt" 2>&1 || { echo "BUILD FAILED"; tail -40 "$out/build.txt"; exit 1; }
bin="$work/.build/release/CrystalSpike"

# CPU used by everything except the spike, in percent of one core (sum of ps %CPU), plus memory pressure.
load() {
  local others=$(ps -Ao pcpu=,comm= | grep -v CrystalSpike | awk '{s+=$1} END {printf "%.0f", s}')
  local top=$(ps -Ao pcpu=,comm= -r | grep -v CrystalSpike | head -3 | awk '{printf "%s:%s ", $1, $2}')
  local mp=$(memory_pressure 2>/dev/null | tail -1 | sed 's/.*: //')
  echo "others_cpu=$others|top=${top% }|mem_free=$mp|loadavg=$(sysctl -n vm.loadavg | tr -d '{}' | xargs)"
}

run() {   # tag, then app arguments
  local tag=$1; shift
  local before=$(load)
  "$bin" --out "$out" --tag "$tag" "$@" > "$out/$tag-stdout.txt" 2>&1
  local code=$?
  local after=$(load)
  local b=${${before#others_cpu=}%%|*} a=${${after#others_cpu=}%%|*}
  local flag=quiet
  (( b > 150 || a > 150 )) && flag=BUSY
  echo "RUN|tag=$tag|exit=$code|machine=$flag|before:$before|after:$after" >> "$out/runs.txt"
}

run si500-instanced-dark  --cells 4  --mode instanced --lighting studio --appearance dark  --bench 10
run si500-instanced-light --cells 4  --mode instanced --lighting studio --appearance light --bench 10
run si500-entities-dark   --cells 4  --mode entities  --lighting studio --appearance dark  --bench 10
run si500-plainlight-dark --cells 4  --mode instanced --lighting plain  --appearance dark  --bench 5
run si20k-instanced-dark  --cells 14 --mode instanced --lighting studio --appearance dark  --bench 10

cat "$out/meta.txt" "$out/runs.txt" "$out/results.txt" > "$out/result.txt" 2>/dev/null
echo "RESULT $out/result.txt"
cat "$out/result.txt"
ls -la "$out"/*.png
