#!/usr/bin/env bash
# Flag-Empires Book Generation Pipeline
# Uses OpenRouter API with free/cheap models
# Generates chapter-by-chapter with validation

set -euo pipefail

BOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTLINE="$BOOK_DIR/master-outline.org"
CANON="$BOOK_DIR/canon-schema.org"
STYLE="$BOOK_DIR/style-bible.org"
API_KEY="${OPENROUTER_API_KEY}"
API_URL="https://openrouter.ai/api/v1/chat/completions"

# Models
PROSE_MODEL="arcee-ai/trinity-large-preview:free"    # Best free prose (95/97 prose/verse)
STRUCTURE_MODEL="z-ai/glm-5"                          # Complex reasoning ($0.95/M)
VERIFY_MODEL="openai/gpt-oss-120b:free"               # Verification

# Read reference files
OUTLINE_TEXT="$(cat "$OUTLINE")"
CANON_TEXT="$(cat "$CANON")"
STYLE_TEXT="$(cat "$STYLE")"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

call_api() {
    local model="$1"
    local system_prompt="$2"
    local user_prompt="$3"
    local max_tokens="${4:-4096}"
    local temp="${5:-0.85}"
    
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
    
    local response
    response=$(curl -s -X POST "$API_URL" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    echo "$response" | python3 -c "
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
    local text="$1"
    local chapter_name="$2"
    
    # Check 1: minimum length (at least 500 words)
    local wc
    wc=$(echo "$text" | wc -w)
    if [ "$wc" -lt 500 ]; then
        log "FAIL: $chapter_name has only $wc words (min 500)"
        return 1
    fi
    
    # Check 2: no lorem ipsum
    if echo "$text" | grep -qi "lorem ipsum\|lorem lorem\|dolor sit amet"; then
        log "FAIL: $chapter_name contains Lorem ipsum filler"
        return 1
    fi
    
    # Check 3: unique word ratio (at least 15% unique words)
    local unique_ratio
    unique_ratio=$(echo "$text" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' '\n' | sort -u | wc -l)
    local total_words
    total_words=$(echo "$text" | wc -w)
    local ratio
    ratio=$(python3 -c "print(round($unique_ratio/$total_words*100, 1))")
    if python3 -c "exit(0 if $unique_ratio/$total_words > 0.15 else 1)"; then
        log "OK: $chapter_name — $wc words, $ratio% unique vocabulary"
        return 0
    else
        log "FAIL: $chapter_name — only $ratio% unique words (repetition detected)"
        return 1
    fi
}

SYSTEM_PROMPT="You are a master chronicler writing a Silmarillion-style epic history of flag empires. Write in the high chronicle register described in the style bible below. Every passage must include Canon IDs from the schema. Write rich, original prose — never filler or placeholder text.

=== STYLE BIBLE ===
$STYLE_TEXT

=== CANON SCHEMA ===
$CANON_TEXT"

generate_chapter() {
    local book_num="$1"
    local arc_num="$2"
    local arc_title="$3"
    local arc_outline="$4"
    local output_file="$5"
    
    log "Generating Book $book_num, Arc $arc_num: $arc_title"
    
    local prompt="Write Arc $arc_num of Book $book_num: '$arc_title'

Here is the outline for this arc:
$arc_outline

Write 2500-3500 words of rich narrative prose for this arc. Include:
- Canon ID references in the format [Canon: FE-XX-BN-XXX-NNN | Year: XX NNN]
- At least 3 witness fragments or annal snippets in quoted blocks
- Names and places consistent with the canon schema
- The three registers: annal, witness, and lament
- Org-mode formatting with proper headings

Begin the arc now. Write the COMPLETE arc — do not abbreviate or summarize."

    local attempts=0
    local max_attempts=3
    local chapter_text=""
    
    while [ $attempts -lt $max_attempts ]; do
        attempts=$((attempts + 1))
        log "  Attempt $attempts/$max_attempts..."
        
        chapter_text=$(call_api "$PROSE_MODEL" "$SYSTEM_PROMPT" "$prompt" 6000 0.88) || {
            log "  API call failed, retrying..."
            sleep 5
            continue
        }
        
        if validate_chapter "$chapter_text" "Book${book_num}-Arc${arc_num}"; then
            echo "$chapter_text" >> "$output_file"
            echo "" >> "$output_file"
            log "  ✓ Arc $arc_num written successfully"
            return 0
        fi
        
        sleep 3
    done
    
    log "  ✗ FAILED after $max_attempts attempts for Arc $arc_num"
    return 1
}

# ============================================================
# MAIN GENERATION PIPELINE
# ============================================================

log "=== Flag-Empires Book Generation Pipeline ==="
log "Prose model: $PROSE_MODEL"
log "Structure model: $STRUCTURE_MODEL"
log "Working directory: $BOOK_DIR"

# --- BOOK 1: FLAGARTHA ---
BOOK1_FILE="$BOOK_DIR/book1-flagartha.org"
echo "#+TITLE: The Standard of Flagartha
#+SUBTITLE: Book I of the Flag-Empires Chronicle
" > "$BOOK1_FILE"

generate_chapter 1 1 "The Wind Before Names" \
"- DA memory cycles and proto-banners.
- Hill clans and salt-gift compacts.
- Canon set: FE-DA-B1-ANN-001..020" \
"$BOOK1_FILE"

generate_chapter 1 2 "Raising the First Mast-City" \
"- Founding of Kher Valaan.
- House Talar binds river and ridge.
- Canon set: FE-FA-B1-ANN-021..090" \
"$BOOK1_FILE"

generate_chapter 1 3 "Consolidation and Covenant Wars" \
"- Banner fealties standardized.
- East March uprisings.
- Lantern Peace and hidden reprisals.
- Canon set: FE-FA-B1-ANN-091..170; FE-FA-B1-EDI-001..030" \
"$BOOK1_FILE"

generate_chapter 1 4 "Crown of Seven Cloths" \
"- Peak of Flagarthan integration.
- Ritualization of succession.
- Seeds of maritime dependency.
- Canon set: FE-FA-B1-RIT-001..022" \
"$BOOK1_FILE"

log "=== Book 1 complete ==="

# --- BOOK 2: FLAGISTAN ---
BOOK2_FILE="$BOOK_DIR/book2-flagistan.org"
echo "#+TITLE: The Crescent of Flagistan
#+SUBTITLE: Book II of the Flag-Empires Chronicle
" > "$BOOK2_FILE"

generate_chapter 2 1 "Crossing to the Crescent Coasts" \
"- Admirals granted semi-hereditary charter.
- Founding of salt courts.
- Canon set: FE-SA-B2-ANN-001..070" \
"$BOOK2_FILE"

generate_chapter 2 2 "Coin, Grain, and Fracture" \
"- Trade boom and inequality.
- Provincial military autonomy.
- Canon set: FE-SA-B2-ANN-071..150; FE-SA-B2-EDI-031..080" \
"$BOOK2_FILE"

generate_chapter 2 3 "The Hundred Harbors Crisis" \
"- Pirate leagues, embargo spirals.
- Coup of the Fifth Ledger.
- Canon set: FE-SA-B2-WIT-001..120" \
"$BOOK2_FILE"

generate_chapter 2 4 "The Quiet Partition" \
"- Administrative split masked as reform.
- Child hostage treaties.
- Canon set: FE-SA-B2-ANN-151..220" \
"$BOOK2_FILE"

log "=== Book 2 complete ==="

# --- BOOK 3: SURFACE AND LAST YEAR ---
BOOK3_FILE="$BOOK_DIR/book3-surface-and-last-year.org"
echo "#+TITLE: Surface and Last Year
#+SUBTITLE: Book III of the Flag-Empires Chronicle
" > "$BOOK3_FILE"

generate_chapter 3 1 "Iron Roads and Surface Doctrine" \
"- TA expansion inland and upward.
- Bureaucratic faith in metrics.
- Canon set: FE-TA-B3-ANN-001..100" \
"$BOOK3_FILE"

generate_chapter 3 2 "The Two Famines" \
"- Logistics success without food justice.
- Mutiny of Road-Wardens.
- Canon set: FE-TA-B3-WIT-121..220" \
"$BOOK3_FILE"

generate_chapter 3 3 "Lantern Riots to Border Fires" \
"- Legitimacy collapse.
- Provisional councils.
- Canon set: FE-LA-B3-ANN-001..130" \
"$BOOK3_FILE"

generate_chapter 3 4 "The Last Year" \
"- Month-by-month unraveling.
- Dissolution decrees.
- Memory politics after the fall.
- Canon set: FE-LA-B3-EDI-131..200; FE-LA-B3-WIT-221..320" \
"$BOOK3_FILE"

log "=== Book 3 complete ==="

# --- ASSEMBLE COMPLETE VOLUME ---
COMPLETE="$BOOK_DIR/flag-empires-complete.org"
log "Assembling complete volume..."
cat "$BOOK_DIR/style-bible.org" > "$COMPLETE"
echo "" >> "$COMPLETE"
cat "$BOOK_DIR/canon-schema.org" >> "$COMPLETE"
echo "" >> "$COMPLETE"
cat "$BOOK_DIR/master-outline.org" >> "$COMPLETE"
echo "" >> "$COMPLETE"
cat "$BOOK1_FILE" >> "$COMPLETE"
echo "" >> "$COMPLETE"
cat "$BOOK2_FILE" >> "$COMPLETE"
echo "" >> "$COMPLETE"
cat "$BOOK3_FILE" >> "$COMPLETE"

# Final stats
log "=== FINAL STATISTICS ==="
for f in "$BOOK1_FILE" "$BOOK2_FILE" "$BOOK3_FILE" "$COMPLETE"; do
    wc_count=$(wc -w < "$f")
    log "  $(basename "$f"): $wc_count words"
done

# Commit
cd "$BOOK_DIR"
git add -A
git commit -m "Regenerated all three books with real prose content (v2 pipeline)

- Used Arcee Trinity Large for prose generation
- Chapter-by-chapter with validation gates
- Verified: no Lorem filler, minimum vocabulary diversity
- See RETRO-2026-02-26.md for failure analysis of v1"

log "=== DONE ==="
