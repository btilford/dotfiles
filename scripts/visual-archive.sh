#!/usr/bin/env bash
# Archive fresh captures into the long-term visual history.
#
# Usage:
#   scripts/visual-archive.sh [--dest DIR] [--ref REF] [--epic EPIC] [--milestone]
#                             [--title TITLE] [--note NOTE] [file ...]
#
#   --dest       archive root. Defaults to $DOTFILES_SCREENSHOT_ARCHIVE. The history
#                lives in the notes vault, not in this repo, so the path comes from
#                the environment and is never hardcoded here.
#   --ref        story / MR reference (e.g. mr-12). Default: the open MR for this
#                branch, else the branch name.
#   --epic       epic this batch belongs to. Groups the timeline.
#   --milestone  mark this batch as the END of that epic — milestones are the only
#                images shown on the top-level index page.
#   --title      short human label for the batch. Default: subject of HEAD.
#   --note       one line on what changed visually.
#   file...      explicit captures. Default: newest capture per surface in
#                build/visuals/ (.png stills and .gif clips).
#
# Layout, under the archive root:
#   history/<YYYY-MM>/<YYYYmmdd-HHMMSS>-<surface>-<ref>.<png|gif>
#   history/<YYYY-MM>.md   month page — every batch, images inline
#   SCREENSHOTS.md         top index — epic milestones + text-only tables
#   history/log.tsv        append-only ledger; the pages are built from it
#
# Filenames sort chronologically, so the directory listing is itself the timeline.
# Never hand-edit the .md files — they are regenerated here from the ledger.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

SRC="$ROOT/build/visuals"
HEADER=$'timestamp\tsurface\tref\tfile\tepic\tmilestone\ttitle\tnote'

log() { printf '\033[1;36m[archive]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[archive]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31m[archive]\033[0m %s\n' "$*" >&2
  exit 1
}

DEST="${DOTFILES_SCREENSHOT_ARCHIVE:-}"
REF=""
EPIC=""
MILESTONE="0"
TITLE=""
NOTE=""
files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dest)
      DEST="${2:-}"
      shift 2
      ;;
    --ref)
      REF="${2:-}"
      shift 2
      ;;
    --epic)
      EPIC="${2:-}"
      shift 2
      ;;
    --milestone)
      MILESTONE="1"
      shift
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --note)
      NOTE="${2:-}"
      shift 2
      ;;
    -h | --help)
      sed -n '2,29p' "$0"
      exit 0
      ;;
    *)
      files+=("$1")
      shift
      ;;
  esac
done

[ -n "$DEST" ] || die "no archive root — set \$DOTFILES_SCREENSHOT_ARCHIVE or pass --dest DIR"
[ -d "$DEST" ] || die "archive root does not exist: $DEST"
case "$DEST" in "$ROOT" | "$ROOT"/*) die "archive root must be outside this repo: $DEST" ;; esac

[ "$MILESTONE" = "1" ] && [ -z "$EPIC" ] && die "--milestone requires --epic"

HIST="$DEST/history"
LEDGER="$HIST/log.tsv"

branch="$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"

# Ref: prefer the open MR for this branch so history rows link straight to it.
if [ -z "$REF" ]; then
  if command -v glab > /dev/null 2>&1; then
    mrnum="$(glab api "projects/:id/merge_requests?source_branch=$branch&state=opened" 2> /dev/null |
      sed -n 's/.*"iid":\([0-9]*\).*/\1/p' | head -1)"
    [ -n "${mrnum:-}" ] && REF="mr-$mrnum"
  fi
fi
[ -z "$REF" ] && REF="$branch"
REF="$(printf '%s' "$REF" | tr -c 'A-Za-z0-9._-' '-')"

[ -z "$TITLE" ] && TITLE="$(git log -1 --pretty=%s 2> /dev/null)"

# Tabs would corrupt the TSV; newlines would corrupt the row.
sanitize() { printf '%s' "$1" | tr '\t\n' '  '; }
EPIC="$(sanitize "$EPIC")"
TITLE="$(sanitize "$TITLE")"
NOTE="$(sanitize "$NOTE")"

# Default set: the newest capture per surface. visual-capture.sh writes
# <surface>-<YYYYmmdd-HHMMSS>.<ext>, so strip the timestamp to get the surface.
#
# The timestamp glob is not decoration. A prefix match on "$stem-" makes the
# surface `drawer` also match `drawer-motion-<ts>.gif` — the clip is newer than
# the still, so it wins twice and the still is never archived at all. Anchor on
# the timestamp so a stem only ever matches its own files.
TS_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]'
if [ ${#files[@]} -eq 0 ]; then
  [ -d "$SRC" ] || die "no $SRC — run 'mise run screenshots' first"
  while IFS= read -r stem; do
    newest="$(find "$SRC" -maxdepth 1 \
      \( -name "$stem-$TS_GLOB.png" -o -name "$stem-$TS_GLOB.gif" \) \
      -printf '%T@ %p\n' 2> /dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
    [ -n "$newest" ] && files+=("$newest")
  done < <(find "$SRC" -maxdepth 1 \( -name '*.png' -o -name '*.gif' \) -printf '%f\n' 2> /dev/null |
    sed -E 's/-[0-9]{8}-[0-9]{6}\.(png|gif)$//' | sort -u)
fi

[ ${#files[@]} -eq 0 ] && die "no captures found in $SRC — run 'mise run screenshots' first"

TS="$(date +%Y%m%d-%H%M%S)"
MONTH="${TS:0:4}-${TS:4:2}"

mkdir -p "$HIST/$MONTH" || die "cannot write to $HIST"
[ -f "$LEDGER" ] || printf '%s\n' "$HEADER" > "$LEDGER"

n=0
for f in "${files[@]}"; do
  [ -f "$f" ] || {
    warn "missing: $f; skip"
    continue
  }
  base="$(basename "$f")"
  ext="${base##*.}"
  surface="$(printf '%s' "${base%.*}" | sed -E 's/-[0-9]{8}-[0-9]{6}$//')"
  dest="$HIST/$MONTH/$TS-$surface-$REF.$ext"
  cp -- "$f" "$dest" || {
    warn "copy failed: $f"
    continue
  }
  # Lossless shrink when available — the archive keeps these forever.
  [ "$ext" = "png" ] && command -v oxipng > /dev/null 2>&1 &&
    oxipng -q -o2 --strip safe "$dest" > /dev/null 2>&1
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$TS" "$surface" "$REF" "$MONTH/$(basename "$dest")" "$EPIC" "$MILESTONE" "$TITLE" "$NOTE" >> "$LEDGER"
  log "archived $surface -> $dest"
  n=$((n + 1))
done

[ "$n" -eq 0 ] && die "nothing archived"

python3 "$ROOT/scripts/render-visual-history.py" --dest "$DEST" || die "render failed"

summary="$n capture(s) under ref '$REF'"
[ -n "$EPIC" ] && summary="$summary, epic '$EPIC'"
[ "$MILESTONE" = "1" ] && summary="$summary (epic milestone)"
log "$summary"
log "index: $DEST/SCREENSHOTS.md · month page: $HIST/$MONTH.md"
