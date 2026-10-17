#!/bin/bash
#
# Converts the WAV recordings older builds saved into the format the app now writes:
# 16 kHz mono AAC at ~32 kbps in an .m4a (see Sources/TalkToMyMac/RecordingArchiver.swift).
#
# Each recording-<UUID>.wav becomes recording-<UUID>.m4a with the same modification date.
# The WAV is deleted only after the .m4a has been checked to have the same duration, so an
# interrupted or failed run never loses a recording. Re-running is safe: a WAV that already
# has an .m4a next to it isn't converted again, and is deleted (unless --keep) once the
# .m4a has passed the same check.
#
# Usage: scripts/compress-recordings.sh [--dry-run] [--keep] [directory]
#   --dry-run  list what would be converted, change nothing
#   --keep     keep the WAVs after converting
#   directory  defaults to ~/Library/Caches/TalkToMyMac/Recordings

set -euo pipefail

dry_run=false
keep=false
dir="$HOME/Library/Caches/TalkToMyMac/Recordings"

for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=true ;;
        --keep)    keep=true ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        echo "Unknown option: $arg" >&2; exit 2 ;;
        *)         dir="$arg" ;;
    esac
done

if [[ ! -d "$dir" ]]; then
    echo "No recordings directory at $dir" >&2
    exit 1
fi

# Duration in seconds as afinfo reports it, or empty if the file can't be read.
duration() {
    afinfo "$1" 2>/dev/null | awk '/estimated duration:/ {print $3; exit}'
}

# Whether two files' durations match. AAC pads to whole 1024-frame packets, so allow a
# little drift.
same_duration() {
    local a b
    a=$(duration "$1") b=$(duration "$2")
    [[ -n "$a" && -n "$b" ]] && awk -v a="$a" -v b="$b" 'BEGIN { d = a - b; exit !(d < 0.2 && d > -0.2) }'
}

file_size() {
    stat -f %z "$1"
}

converted=0 skipped=0 cleaned=0 failed=0
bytes_before=0 bytes_after=0

shopt -s nullglob nocaseglob
for wav in "$dir"/*.wav; do
    m4a="${wav%.*}.m4a"
    name=$(basename "$wav")

    if [[ -e "$m4a" ]]; then
        # Converted by an earlier run, e.g. one with --keep.
        if ! $keep && ! $dry_run && same_duration "$wav" "$m4a"; then
            rm "$wav"
            cleaned=$((cleaned + 1))
        else
            skipped=$((skipped + 1))
        fi
        continue
    fi
    if $dry_run; then
        echo "would convert $name"
        converted=$((converted + 1))
        continue
    fi

    # Hidden temp name, so the app's Storage pane never counts a half-written file.
    partial="$dir/.$(basename "$m4a")"
    rm -f "$partial"
    if ! afconvert -f m4af -d aac@16000 -c 1 --mix -b 32000 "$wav" "$partial" 2>/dev/null; then
        echo "FAILED  $name (afconvert error)" >&2
        rm -f "$partial"
        failed=$((failed + 1))
        continue
    fi

    if ! same_duration "$wav" "$partial"; then
        echo "FAILED  $name (duration $(duration "$wav")s → $(duration "$partial")s)" >&2
        rm -f "$partial"
        failed=$((failed + 1))
        continue
    fi

    touch -r "$wav" "$partial"
    mv "$partial" "$m4a"
    before=$(file_size "$wav") after=$(file_size "$m4a")
    bytes_before=$((bytes_before + before))
    bytes_after=$((bytes_after + after))
    $keep || rm "$wav"
    converted=$((converted + 1))
    echo "ok      $name  $((before / 1024)) KB → $((after / 1024)) KB"
done

echo
if $dry_run; then
    echo "$converted to convert, $skipped already converted (dry run, nothing changed)"
else
    echo "$converted converted, $skipped skipped, $failed failed"
    ((cleaned > 0)) && echo "$cleaned WAVs deleted that were already converted"
    if ((converted > 0)); then
        awk -v a="$bytes_before" -v b="$bytes_after" 'BEGIN { printf "%.1f MB → %.1f MB\n", a / 1048576, b / 1048576 }'
        $keep && echo "WAVs kept; run again without --keep to delete them"
    fi
fi
((failed == 0))
