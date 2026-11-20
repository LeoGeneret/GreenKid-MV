#!/bin/bash
# SPDX-License-Identifier: MIT
# GreenKid-MV: the resolution test. Plays Ocarina of Time's field-run route (dm/games/0400486024DEC000/bench.tsv: Hyrule Field, standing 20 s,
# then camera turns and walking) from the player's own save, once per step of the Render scale slider, twice each in turn, and writes one table to
# compare them: GreenKid-MV-local/bench/<date-time>/results.md (and latest-results.md beside it). scripts/bench.py does the measuring.
# Usage: greenkid_bench.sh <game-folder> [<save folder>] [--open]   (the folder greenkid_build.sh built; the game app closed; the Mac left alone for about 35 minutes)
#   <save folder>: the save to start from (default the game app's, ~/Library/Application Support/nxnative/<title ID>/save). --open: the table opened when it ends
#   (the game app's Test Resolutions button, dm/mac/Launcher.swift, runs it so, its output in GreenKid-MV-local/bench/test.log)
# Builds only from the player's files. No game data belongs in this repository.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT_DIR="${GREENKID_SUPPORT_DIR:-$HOME/Library/Application Support/GreenKid-MV}"
GAME_ID=0400486024DEC000
ROUTE=field-run
RUNS="${GREENKID_BENCH_RUNS:-2}"
# The slider's seven steps (twelfths of 1920x1080 handheld): label (also the run folders' name) and scale
STEPS=("50pct-960x540-Potato:0.5" "58pct-1120x630:0.5833" "67pct-1280x720-Normal:0.6667" "75pct-1440x810:0.75"
       "83pct-1600x900:0.8333" "92pct-1760x990:0.9167" "100pct-1920x1080-Native:1.0")

GAME_DIR="${1:?Choose the game folder you built}"
SAVE_ARG=""; OPEN=0
for x in "${@:2}"; do if [[ "$x" == --open ]]; then OPEN=1; else SAVE_ARG="$x"; fi; done
[[ -d "$GAME_DIR" ]] || { echo 'The game folder does not exist.'; exit 2; }
GAME_DIR="$(cd "$GAME_DIR" && pwd -P)"
PRIVATE_DIR="$GAME_DIR/GreenKid-MV-local"
WORK_DIR="$PRIVATE_DIR/build"
ENV_FILE="$PRIVATE_DIR/runtime.env"
[[ -x "$WORK_DIR/tools/dmhost" ]] || { echo 'No finished build in this folder: click Build My Local Game first.'; exit 2; }
grep -q "game profile: $GAME_ID" "$PRIVATE_DIR/build.log" 2>/dev/null || { echo 'The resolution test is for The Legend of Zelda: Ocarina of Time (v131072) builds.'; exit 2; }
REVISION="$(tr -d '\r\n' < "$SOURCE_ROOT/UPSTREAM-REVISION")"
ENGINE_DIR="$SUPPORT_DIR/engine/$REVISION"
PYTHON="$SUPPORT_DIR/venv/bin/python3"
[[ -f "$ENGINE_DIR/.copy-complete" && -x "$PYTHON" ]] || { echo 'The engine of this builder version is not prepared: build the game again with this builder first.'; exit 2; }

# The game app's save (dm/mac/launcher.c: ~/Library/Application Support/nxnative/<title ID>/save); each run plays a copy of it
SAVE_DIR="$SAVE_ARG"
[[ -n "$SAVE_DIR" ]] || for d in "$HOME/Library/Application Support/nxnative/"*; do
  [[ "$(basename "$d" | tr '[:lower:]' '[:upper:]')" == "$GAME_ID" && -d "$d/save" ]] && SAVE_DIR="$d/save"
done
if [[ -z "$SAVE_DIR" ]] || [[ -z "$(find "$SAVE_DIR" -type f -print -quit)" ]]; then
  echo 'No save yet. Open Game.app, play until Link stands in Hyrule Field, save there (the last save is the one loaded), then quit and test again.'
  exit 2
fi
if pgrep -x dmhost >/dev/null; then echo 'Quit the game first: the test runs the game itself, and two at once would share the GPU.'; exit 2; fi

# The game app's settings (runtime.env, as greenkid_build.sh wrote them), but in a window and with the resolution each run sets
ARGS=(--game "$GAME_ID" --route "$ROUTE" --save "$SAVE_DIR" --runs "$RUNS" --fps 60 --no-hud)
if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
    case "${line%%=*}" in DM_FULLSCREEN|DM_RES_PRESET|DM_RENDER_SCALE|DM_FPS_TARGET) continue ;; esac
    ARGS+=(--env "$line")
  done < "$ENV_FILE"
fi
for step in "${STEPS[@]}"; do ARGS+=(--variant "${step%%:*}:DM_RES_PRESET=2,DM_RENDER_SCALE=${step##*:}"); done
OUT="$PRIVATE_DIR/bench/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
rm -f "$PRIVATE_DIR/bench/latest-results.md"   # the builder opens it when the test ends: never an older test's
printf 'Resolution test: route %s from your save, %d steps x %s runs (about %d minutes). Leave the Mac alone until it ends.\nResults: %s\n\n' \
  "$ROUTE" "${#STEPS[@]}" "$RUNS" "$(( ${#STEPS[@]} * RUNS * 25 / 10 ))" "$OUT"
cd "$ENGINE_DIR"
set +e
"$PYTHON" scripts/bench.py "$WORK_DIR" "${ARGS[@]}" --out "$OUT"
rc=$?
set -e
if [[ -f "$OUT/results.md" ]]; then
  {
    printf '# GreenKid-MV resolution test, %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
    mem="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    printf 'Mac: %s, %s GB, macOS %s. Each run plays %s from %s.\n' "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)" "$(( ${mem:-0} / 1073741824 ))" "$(sw_vers -productVersion 2>/dev/null || echo unknown)" "$ROUTE" "$SAVE_DIR"
    printf 'Read gpu_p50 and frame_p99 first: at a 60 fps cap two steps can both show 60 fps; the GPU time says how much room each leaves.\n'
    printf 'Check one screenshot (shot_*.png in a run folder): Link should stand in Hyrule Field. If he does not, the route\x27s timings do not match your save.\n\n'
    cat "$OUT/results.md"
  } > "$OUT/report.md"
  cp "$OUT/report.md" "$PRIVATE_DIR/bench/latest-results.md"
  printf '\nRESULTS: %s\n' "$PRIVATE_DIR/bench/latest-results.md"
  [[ $OPEN == 1 ]] && open "$PRIVATE_DIR/bench/latest-results.md"
elif [[ $OPEN == 1 ]]; then
  osascript -e 'display alert "Resolution test stopped" message "GreenKid-MV-local/bench/test.log says why."' >/dev/null 2>&1 || true
fi
exit $rc
