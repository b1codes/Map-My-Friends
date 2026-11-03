#!/usr/bin/env bash
# Runs the golden tests (the app's and the Widgetbook catalog's) on the
# platform they are recorded on, Linux x64.
#
#   scripts/goldens.sh            # compare against the committed images
#   scripts/goldens.sh --update   # re-record them
#
# Other platforms render text and blur slightly differently, so there the
# golden tests skip themselves (see frontend/golden_harness). This script runs
# them where they count:
#   - On Linux x64, directly, with the Flutter pinned in .fvmrc.
#   - Anywhere else, in the Flutter image pinned below, as linux/amd64.
#     On Apple Silicon that is emulated, so a full run takes a few minutes.
#
# The container gets a copy of frontend/, not the checkout itself: a pub get
# in there would point this machine's .dart_tool at container paths. Only
# images come back: the goldens (with --update) and any failure diffs, in
# the failures/ directory next to each golden.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND="$ROOT/frontend"
UPDATE=""
case "${1:-}" in
  "") ;;
  --update) UPDATE="--update-goldens" ;;
  *) echo "usage: $0 [--update]" >&2; exit 2 ;;
esac

# The image's Flutter must be the one .fvmrc pins: goldens recorded with
# another engine differ. Bump both together; the digest is the multi-arch
# index for the tag.
IMAGE_FLUTTER="3.41.7"
IMAGE="ghcr.io/cirruslabs/flutter@sha256:644e3cea0a8440ce75804b67ceab77b16a87b39d9e9d89b07aceca7a98af1aa3"
PINNED="$(sed -n 's/.*"flutter": *"\([^"]*\)".*/\1/p' "$ROOT/.fvmrc")"
if [[ "$PINNED" != "$IMAGE_FLUTTER" ]]; then
  echo ".fvmrc pins Flutter $PINNED, but $0 runs the $IMAGE_FLUTTER image." >&2
  echo "Update IMAGE_FLUTTER and IMAGE in $0 to match." >&2
  exit 1
fi

# Pinned times render as local times, so record and compare in UTC, as CI
# does. The harness refuses any other zone.
export TZ=UTC

# Losslessly recompresses newly recorded goldens: the comparator decodes
# both images and compares pixels, so only the file gets smaller (by about
# 40%). Pinned by digest, like actionlint.
OXIPNG_IMAGE="ghcr.io/shssoichiro/oxipng:v9.1.5@sha256:e1623b0da9f14b63b242ffb78e4eef4ba0f09c9159880d238665af4654c75b4f"
optimize_changed_goldens() {
  local changed=()
  while IFS= read -r file; do changed+=("/repo/$file"); done < <(
    cd "$ROOT" && git ls-files --modified --others --exclude-standard -- 'frontend/*goldens/*.png'
  )
  if (( ${#changed[@]} )); then
    echo "Optimizing ${#changed[@]} recorded golden(s)"
    docker run --rm -v "$ROOT:/repo" "$OXIPNG_IMAGE" -q -o max --strip safe "${changed[@]}"
  fi
}

# Failure diffs from an earlier run would be mistaken for this one's.
find "$FRONTEND" -type d -name failures -path '*/test/*' -not -path '*/build/*' \
  -prune -exec rm -r {} +

# The packages with golden tests, relative to frontend/.
PACKAGES=(. widgetbook)

# The test files with goldens in the current package. Naming them saves
# compiling every other test file just to find it has no golden tag, which
# under emulation is most of the run.
golden_files() { grep -rl --include='*_test.dart' 'setUpGoldens()' test; }

if [[ "$(uname -s)-$(uname -m)" == "Linux-x86_64" ]]; then
  if command -v fvm >/dev/null 2>&1; then FLUTTER=(fvm flutter); else FLUTTER=(flutter); fi
  status=0
  for package in "${PACKAGES[@]}"; do
    # $UPDATE is empty or one flag, and golden_files one word per file.
    # shellcheck disable=SC2046,SC2086
    (cd "$FRONTEND/$package" && "${FLUTTER[@]}" pub get >/dev/null &&
      "${FLUTTER[@]}" test --tags golden $UPDATE $(golden_files)) || status=1
  done
  if [[ -n "$UPDATE" ]]; then optimize_changed_goldens; fi
  exit $status
fi

# The pub cache persists between runs in a named volume, so only the first
# run downloads packages.
status=0
docker run --rm --platform linux/amd64 \
  -v "$FRONTEND:/src:ro" \
  -v "$FRONTEND:/out" \
  -v map-my-friends-goldens-pub-cache:/root/.pub-cache \
  -e "UPDATE=$UPDATE" \
  -e TZ=UTC \
  -e "PACKAGES=${PACKAGES[*]}" \
  "$IMAGE" bash -euo pipefail -c "$(declare -f golden_files)"'
    mkdir -p /work
    tar -C /src --exclude=.dart_tool --exclude=build --exclude=failures -cf - . |
      tar -C /work -xf -
    status=0
    for package in $PACKAGES; do
      echo "== frontend/$package"
      (cd "/work/$package" && flutter pub get >/dev/null &&
        flutter test --tags golden $UPDATE $(golden_files)) || status=1
    done
    cd /work
    find . -path ./build -prune -o -path "*/build" -prune -o \
      \( -path "*/goldens/*.png" -o -path "*/failures/*.png" \) -print |
      tar -cf - -T - | tar -C /out -xf -
    exit $status
  ' || status=$?
if [[ -n "$UPDATE" ]]; then optimize_changed_goldens; fi
exit $status
