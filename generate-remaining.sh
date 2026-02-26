#!/usr/bin/env bash
# Continue generation from Book 2 onwards
set -euo pipefail

BOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTLINE="$BOOK_DIR/master-outline.org"
CANON="$BOOK_DIR/canon-schema.org"
STYLE="$BOOK_DIR/style-bible.org"
API_KEY="${OPENROUTER_API_KEY}"
API_URL="https://openrouter.ai/api/v1/chat/completions"

PROSE_MODEL="arcee-ai/trinity-large-preview:free"
OUTLINE_TEXT="$(cat "$OUTLINE")"
CANON_TEXT="$(cat "$CANON")"
STYLE_TEXT="$(cat "$STYLE")"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

call_api() {
    local model="$1" system_prompt="$2" user_prompt="$3" max_tokens="${4:-4096}" temp="${5:-0.85}"
    local payload
    payload=$(python3 -c "
import json,sys
print(json.dumps({
    'model': sys.argv[1],
    'messages': [
        {'role': 'system', 'content': sys.argv[2]},
        {'role': 'user', 'content': sys.argv[3]}
    ],
    'max_tokens': int(sys.argv[4]),
    'temperature': float(sys.argv[5])
}))
" "$model" "$system_prompt" "$user_prompt" "$max_tokens" "$temp")
    
    curl -s --max-time 300 -X POST "$API_URL" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" | python3 -c "
import json,sys
try:
    data=json.load(sys.stdin)
    if 'choices' in data and len(data['choices'])>0:
        print(data['choices'][0]['message']['content'])
    else:
        print('ERROR: ' + json.dumps(data), file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
"
}

validate_chapter() {
    local text="$1" chapter_name="$2"
    local wc=$(echo "$text" | wc -w)
    if [ "$wc" -lt 500 ]; then log "FAIL: $chapter_name only $wc words"; return 1; fi
    if echo "$text" | grep -qi "lorem ipsum\|lorem lorem"; then log "FAIL: $chapter_name Lorem filler"; return 1; fi
    local unique=$(echo "$text" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' '\n' | sort -u | wc -l)
    local ratio=$(python3 -c "print(round($unique/$wc*100, 1))")
    if python3 -c "exit(0 if $unique/$wc > 0.15 else 1)"; then
        log "OK: $chapter_name — $wc words, $ratio% unique"; return 0
    else
        log "FAIL: $chapter_name — $ratio% unique (repetition)"; return 1
    fi
}

SYSTEM_PROMPT="You are a master chronicler writing a Silmarillion-style epic history of flag empires. Write in the high chronicle register described in the style bible below. Every passage must include Canon IDs from the schema. Write rich, original prose — never filler or placeholder text.

=== STYLE BIBLE ===
$STYLE_TEXT

=== CANON SCHEMA ===
$CANON_TEXT"

generate_chapter() {
    local book_num="$1" arc_num="$2" arc_title="$3" arc_outline="$4" output_file="$5"
    log "Generating Book $book_num, Arc $arc_num: $arc_title"
    local prompt="Write Arc $arc_num of Book $book_num: '$arc_title'

Outline:
$arc_outline

Write 2500-3500 words of rich narrative prose. Include:
- Canon ID references [Canon: FE-XX-BN-XXX-NNN | Year: XX NNN]
- At least 3 witness fragments or annal snippets in quoted blocks
- Three registers: annal, witness, and lament
- Org-mode formatting

Write the COMPLETE arc now."

    for attempt in 1 2 3; do
        log "  Attempt $attempt/3..."
        local text
        text=$(call_api "$PROSE_MODEL" "$SYSTEM_PROMPT" "$prompt" 6000 0.88) || { sleep 10; continue; }
        if validate_chapter "$text" "Book${book_num}-Arc${arc_num}"; then
            echo "$text" >> "$output_file"
            echo "" >> "$output_file"
            log "  ✓ Arc $arc_num written"
            return 0
        fi
        sleep 5
    done
    log "  ✗ FAILED Arc $arc_num"; return 1
}

# --- BOOK 2 ---
BOOK2_FILE="$BOOK_DIR/book2-flagistan.org"
echo "#+TITLE: The Crescent of Flagistan
#+SUBTITLE: Book II of the Flag-Empires Chronicle
" > "$BOOK2_FILE"

generate_chapter 2 1 "Crossing to the Crescent Coasts" \
"- Admirals granted semi-hereditary charter. Founding of salt courts.
- Canon set: FE-SA-B2-ANN-001..070" "$BOOK2_FILE"

generate_chapter 2 2 "Coin, Grain, and Fracture" \
"- Trade boom and inequality. Provincial military autonomy.
- Canon set: FE-SA-B2-ANN-071..150; FE-SA-B2-EDI-031..080" "$BOOK2_FILE"

generate_chapter 2 3 "The Hundred Harbors Crisis" \
"- Pirate leagues, embargo spirals. Coup of the Fifth Ledger.
- Canon set: FE-SA-B2-WIT-001..120" "$BOOK2_FILE"

generate_chapter 2 4 "The Quiet Partition" \
"- Administrative split masked as reform. Child hostage treaties.
- Canon set: FE-SA-B2-ANN-151..220" "$BOOK2_FILE"

log "=== Book 2 complete ==="

# --- BOOK 3 ---
BOOK3_FILE="$BOOK_DIR/book3-surface-and-last-year.org"
echo "#+TITLE: Surface and Last Year
#+SUBTITLE: Book III of the Flag-Empires Chronicle
" > "$BOOK3_FILE"

generate_chapter 3 1 "Iron Roads and Surface Doctrine" \
"- TA expansion inland and upward. Bureaucratic faith in metrics.
- Canon set: FE-TA-B3-ANN-001..100" "$BOOK3_FILE"

generate_chapter 3 2 "The Two Famines" \
"- Logistics success without food justice. Mutiny of Road-Wardens.
- Canon set: FE-TA-B3-WIT-121..220" "$BOOK3_FILE"

generate_chapter 3 3 "Lantern Riots to Border Fires" \
"- Legitimacy collapse. Provisional councils.
- Canon set: FE-LA-B3-ANN-001..130" "$BOOK3_FILE"

generate_chapter 3 4 "The Last Year" \
"- Month-by-month unraveling. Dissolution decrees. Memory politics after the fall.
- Canon set: FE-LA-B3-EDI-131..200; FE-LA-B3-WIT-221..320" "$BOOK3_FILE"

log "=== Book 3 complete ==="

# --- ASSEMBLE ---
COMPLETE="$BOOK_DIR/flag-empires-complete.org"
cat "$BOOK_DIR/style-bible.org" > "$COMPLETE"
echo "" >> "$COMPLETE"
cat "$BOOK_DIR/canon-schema.org" >> "$COMPLETE"
echo "" >> "$COMPLETE"
cat "$BOOK_DIR/master-outline.org" >> "$COMPLETE"
echo "" >> "$COMPLETE"
cat "$BOOK_DIR/book1-flagartha.org" >> "$COMPLETE"
echo "" >> "$COMPLETE"
cat "$BOOK2_FILE" >> "$COMPLETE"
echo "" >> "$COMPLETE"
cat "$BOOK3_FILE" >> "$COMPLETE"

log "=== FINAL STATISTICS ==="
for f in "$BOOK_DIR/book1-flagartha.org" "$BOOK2_FILE" "$BOOK3_FILE" "$COMPLETE"; do
    log "  $(basename "$f"): $(wc -w < "$f") words"
done

cd "$BOOK_DIR"
git add -A
git commit -m "Regenerated books 2-3 with real prose (v2 pipeline)

- Arcee Trinity Large for prose, validated chapter-by-chapter
- No Lorem filler, all content verified
- See RETRO-2026-02-26.md for v1 failure analysis"

log "=== DONE ==="
