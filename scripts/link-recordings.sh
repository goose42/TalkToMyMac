#!/bin/bash
#
# Renames recordings saved before they were named after their transcripts, so the
# Transcriptions detail screen can play them.
#
# Older builds saved each recording under a random recording-<UUID> name. The app now saves
# it as recording-<transcript ID>.m4a. This script matches each old file to the transcript
# it produced and renames it to that ID. A match needs:
#   - the transcript saved within 2 minutes after the file was last written (the time the
#     pipeline took), and
#   - the file's duration within 0.3 s of the audio length the transcript recorded.
# When several files and transcripts could pair up, the closest in time pair first, and
# each file and transcript is used at most once. Files that match nothing (dictations that
# produced no transcript, or ones from before metrics were kept) are left alone.
#
# Run scripts/compress-recordings.sh first if there are still WAVs; it keeps their
# modification dates, which this relies on. Safe to re-run: linked files are skipped.
#
# Usage: scripts/link-recordings.sh [--dry-run] [data directory]
#   --dry-run       show the renames, change nothing
#   data directory  defaults to ~/Library/Caches/TalkToMyMac

set -euo pipefail

dry_run=false
data="$HOME/Library/Caches/TalkToMyMac"

for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=true ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        echo "Unknown option: $arg" >&2; exit 2 ;;
        *)         data="$arg" ;;
    esac
done

dir="$data/Recordings"
db="$data/transcription_history.sqlite"
for path in "$dir" "$db"; do
    if [[ ! -e "$path" ]]; then
        echo "Not found: $path" >&2
        exit 1
    fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Transcripts with an audio length: "T <id> <timestamp> <audio seconds>".
sqlite3 -readonly -separator ' ' "$db" \
    "SELECT 'T', id, timestamp, audio_seconds FROM transcription_metrics;" > "$work/transcripts"
cut -d' ' -f2 "$work/transcripts" > "$work/ids"

# Recordings not yet named after a transcript: "F <file> <mtime> <duration>".
linked=0
shopt -s nullglob nocaseglob
for file in "$dir"/recording-*.m4a "$dir"/recording-*.wav; do
    name=$(basename "$file")
    id=${name#recording-}
    id=${id%.*}
    if grep -qxF "$id" "$work/ids"; then
        echo "$id" >> "$work/linked"
        linked=$((linked + 1))
        continue
    fi
    duration=$(afinfo "$file" 2>/dev/null | awk '/estimated duration:/ {print $3; exit}')
    [[ -n "$duration" ]] && echo "F $name $(stat -f %m "$file") $duration"
done > "$work/files"

# Transcripts that already have their recording are out of the running.
touch "$work/linked"
awk -v linked="$work/linked" 'FILENAME == linked { has[$1]; next } !($2 in has)' "$work/linked" "$work/transcripts" > "$work/unlinked"

# Every plausible pair as "<seconds apart> <file> <transcript id>", closest first, then
# taken greedily so each file and transcript is used once.
awk '
    $1 == "T" { n++; tid[n] = $2; ts[n] = $3; secs[n] = $4; next }
    $1 == "F" {
        for (i = 1; i <= n; i++) {
            dt = ts[i] - $3; dd = secs[i] - $4
            if (dt >= -5 && dt <= 120 && dd > -0.3 && dd < 0.3) print (dt < 0 ? -dt : dt), $2, tid[i]
        }
    }
' "$work/unlinked" "$work/files" | sort -n -k1,1 | awk '
    !($2 in usedFile) && !($3 in usedID) { usedFile[$2]; usedID[$3]; print $2, $3 }
' > "$work/pairs"

renamed=0 failed=0
while read -r name id; do
    ext=${name##*.}
    target="recording-$id.$(echo "$ext" | tr 'A-Z' 'a-z')"
    if $dry_run; then
        echo "would rename $name → $target"
    elif [[ -e "$dir/$target" ]]; then
        echo "FAILED  $name ($target already exists)" >&2
        failed=$((failed + 1))
        continue
    else
        mv "$dir/$name" "$dir/$target"
        # Kept beside the recordings (hidden, so the app ignores it) in case a rename needs undoing.
        echo "$name $target" >> "$dir/.link-recordings.log"
    fi
    renamed=$((renamed + 1))
done < "$work/pairs"

unmatched=$(( $(wc -l < "$work/files") - renamed - failed ))
echo
if $dry_run; then
    echo "$renamed to link, $unmatched unmatched, $linked already linked (dry run, nothing changed)"
else
    echo "$renamed linked, $unmatched unmatched, $linked already linked, $failed failed"
    ((renamed > 0)) && echo "Renames logged to $dir/.link-recordings.log"
fi
((failed == 0))
