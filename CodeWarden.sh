#!/bin/bash

VERSION="v1.07.00"

# Record start time for performance tracking
START_TIME=$(date +%s)

# Default values
DO_RESTART=false
DO_OWNER=false
DO_PERMISSION=false
DO_UNUSED=false
DO_FILE=false
DO_CLEANUP=false
DO_HOSTNAME=false
DRY_RUN=false
AUTO_CONFIRM=false
HOSTNAME_VALUE=""

# Helper function to escape regex metacharacters for sed
escape_regex() {
    printf '%s' "$1" | sed 's/[.[\*^$()+?{|\\]/\\&/g'
}

# Extract translation keys from a language file; one key per line.
extract_keys() {
    local mode="$1" file="$2"
    [[ ! -f "$file" ]] && return
    if [[ "$mode" == "php" ]]; then
        grep -oP "^\s*'\K[A-Z0-9_]+(?='\s*=>)" "$file"
    else
        grep '^msgid "' "$file" | cut -d'"' -f2 | grep -v '^$'
    fi
}

# Return the line number of a translation key in a language file.
key_line() {
    local mode="$1" file="$2" key="$3"
    local esc; esc=$(escape_regex "$key")
    [[ ! -f "$file" ]] && echo "N/A" && return
    local line
    if [[ "$mode" == "php" ]]; then
        line=$(grep -nP "^\s*'${esc}'\s*=>" "$file" | cut -d: -f1)
    else
        line=$(grep -n "^msgid \"${esc}\"" "$file" | cut -d: -f1)
    fi
    [[ -n "$line" ]] && echo "$line" || echo "N/A"
}

# Spinner state for animated progress feedback
SPINNER_PID=""
SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# Start an animated spinner on stderr with a label.
# Degrades to a plain label line when stderr is not a TTY.
start_spinner() {
    local label="${1:-Working…}"
    if [[ -t 2 ]]; then
        printf '\033[?25l' >&2
        (
            local i=0
            while true; do
                printf '\r%s %s ' "${SPINNER_FRAMES[i++ % ${#SPINNER_FRAMES[@]}]}" "$label" >&2
                sleep 0.1
            done
        ) &
        SPINNER_PID=$!
    else
        printf '%s\n' "$label" >&2
        SPINNER_PID=""
    fi
}

# Stop the spinner, clear its line, and optionally print a completion note to stderr.
stop_spinner() {
    local final="${1:-}"
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=""
    fi
    if [[ -t 2 ]]; then
        printf '\r\033[K' >&2
        printf '\033[?25h' >&2
    fi
    [[ -n "$final" ]] && printf '%s\n' "$final" >&2
}

# Ensure spinner is cleaned up on exit, interrupt, or termination.
trap 'stop_spinner' EXIT INT TERM

# Sub-section toggles
RUN_SYNC=false
RUN_MISSING=false
RUN_UNUSED=false
RUN_DUPLICATES=false
RUN_DYNAMIC=false
RUN_DOCONLY=false

BASE_PATH=$(pwd)
PO_RELATIVE_PATH="locale/{LANG}/LC_MESSAGES/messages.po"
PO_PATH_OVERRIDE=false
OWNER_CONFIG=""
OUTPUT_FILE="po_intelligence_report_$(date +%Y-%m-%d).txt"

# Filters for analysis
DOC_EXTENSIONS=" md txt log sql bak json local "
EXCLUDE_DIRS=(vendor .claude database locale .idea .git)
EXCLUDE_FILES=("composer.*" ".git*")

# Translation file path templates (probed in order; first match per language wins)
PHP_PATH_TEMPLATES=( "locale/{LANG}/messages.php" "webroot/locale/{LANG}/messages.php" )
PO_PATH_TEMPLATES=( "locale/{LANG}/LC_MESSAGES/messages.po" "webroot/locale/{LANG}/LC_MESSAGES/messages.po" )
LANG_CODES=("en_US" "hu_HU")

# Display complete usage instructions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "General Options:"
    echo "  -d, --dir <path>         Project base path (default: current directory)"
    echo "  -y, --yes                Auto-confirm sensitive operations"
    echo "  --dry-run                Show what would happen without making changes"
    echo "  -v, --version            Display version information"
    echo ""
    echo "Translation Intelligence & Localization:"
    echo "  -r, --restart            Compile PO files and restart PHP-FPM (auto-detects running version)"
    echo "  -p, --po-path <path>     Override translation file path template (auto-detected by default)"
    echo "                           Default probes: locale/{LANG}/messages.php, webroot/locale/{LANG}/messages.php,"
    echo "                           then locale/{LANG}/LC_MESSAGES/messages.po (PHP preferred over Gettext)"
    echo "  -u, --unused [sub...]    Analyze translations: sync, missing, unused, duplicates, dynamic, doconly"
    echo "  -c, --cleanup            Comment out strictly unused keys (Gettext only; PHP-array is report-only)"
    echo "  -f, --file               Save analysis report to file"
    echo ""
    echo "System Operations:"
    echo "  -o, --owner <u:g>        Set file ownership (user:group)"
    echo "  -m, --permissions        Fix file permissions (664/775)"
    echo "  -n, --hostname <name>    Set local mDNS hostname via avahi"
    echo "  -h, --help               Display this help message"
    exit 1
}

# Check if argument exists for options requiring a value
require_arg() {
    if [[ -z "$2" || "$2" =~ ^- ]]; then
        echo "Error: Option $1 requires an argument."
        exit 1
    fi
}

# Detect the active PHP-FPM systemd service name (e.g. php8.4-fpm).
# Prefers the highest-versioned running service; falls back to active, then any installed unit.
detect_fpm_service() {
    local svc
    for state in running active; do
        svc=$(systemctl list-units --type=service --state="$state" --no-legend 2>/dev/null \
            | grep -oP 'php[0-9.]*-fpm' | sort -V | tail -1)
        [[ -n "$svc" ]] && echo "$svc" && return 0
    done
    svc=$(systemctl list-unit-files --type=service --no-legend 2>/dev/null \
        | grep -oP 'php[0-9.]*-fpm' | sort -V | tail -1)
    [[ -n "$svc" ]] && echo "$svc" && return 0
    return 1
}

# Check if no arguments provided
if [ $# -eq 0 ]; then usage; fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)           require_arg "$1" "$2"; BASE_PATH="${2%/}"; shift 2 ;;
        -r|--restart)       DO_RESTART=true; shift ;;
        -p|--po-path)       require_arg "$1" "$2"; PO_RELATIVE_PATH="$2"; PO_PATH_OVERRIDE=true; shift 2 ;;
        -o|--owner)
            require_arg "$1" "$2"
            if [[ ! "$2" =~ ^[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+$ ]]; then
                echo "Error: Invalid owner format. Use user:group (e.g., www-data:www-data)"
                exit 1
            fi
            DO_OWNER=true; OWNER_CONFIG="$2"; shift 2 ;;
        -m|--permissions)   DO_PERMISSION=true; shift ;;
        -n|--hostname)
            require_arg "$1" "$2"
            if [[ ! "$2" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
                echo "Error: Invalid hostname '$2'. Use RFC 1123 format: alphanumeric and hyphens, no leading/trailing hyphens, max 63 chars per label."
                exit 1
            fi
            DO_HOSTNAME=true; HOSTNAME_VALUE="$2"; shift 2 ;;
        -y|--yes)           AUTO_CONFIRM=true; shift ;;
        -c|--cleanup)       DO_CLEANUP=true; shift ;;
        -f|--file)          DO_FILE=true; shift ;;
        --dry-run)          DRY_RUN=true; shift ;;
        -v|--version)       echo "CodeWarden $VERSION"; exit 0 ;;
        -u|--unused)
            DO_UNUSED=true
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                case "$1" in
                    sync)       RUN_SYNC=true ;;
                    missing)    RUN_MISSING=true ;;
                    unused)     RUN_UNUSED=true ;;
                    duplicates) RUN_DUPLICATES=true ;;
                    dynamic)    RUN_DYNAMIC=true ;;
                    doconly)    RUN_DOCONLY=true ;;
                    *) echo "Warning: Unknown sub-option '$1' for -u/--unused (valid: sync, missing, unused, duplicates, dynamic, doconly)" ;;
                esac
                shift
            done
            if [[ "$RUN_SYNC" = false && "$RUN_MISSING" = false && "$RUN_UNUSED" = false && "$RUN_DUPLICATES" = false && "$RUN_DYNAMIC" = false && "$RUN_DOCONLY" = false ]]; then
                RUN_SYNC=true; RUN_MISSING=true; RUN_UNUSED=true; RUN_DUPLICATES=true; RUN_DYNAMIC=true
            fi
            ;;
        -h|--help)          usage ;;
        *) echo "Warning: Unknown option '$1'"; shift ;;
    esac
done

echo "--- SECTION: INITIALIZATION ---"
echo "Base Path: $BASE_PATH"

# 1. PO Compilation & FPM Restart
if [ "$DO_RESTART" = true ]; then
    echo "--- SECTION: PO COMPILATION & FPM RESTART ---"
    start_spinner "Compiling translations…"
    COMPILE_SUCCESS=true
    for LANG_CODE in "${LANG_CODES[@]}"; do
        FINAL_PO_PATH=$(echo "$PO_RELATIVE_PATH" | sed "s/{LANG}/$LANG_CODE/g")
        FULL_PO_PATH="$BASE_PATH/$FINAL_PO_PATH"
        FULL_MO_PATH="${FULL_PO_PATH%.po}.mo"
        if [ -f "$FULL_PO_PATH" ]; then
            echo "Step: Validating and Compiling $LANG_CODE"
            if [ "$DRY_RUN" = false ]; then
                if ! msgfmt --check "$FULL_PO_PATH" -o "$FULL_MO_PATH"; then
                    echo "Error: Compilation failed for $LANG_CODE. Duplicates found:"
                    grep '^msgid "' "$FULL_PO_PATH" | sort | uniq -d
                    COMPILE_SUCCESS=false
                fi
            else
                echo "[DRY-RUN] Would compile $FULL_PO_PATH to $FULL_MO_PATH"
            fi
        fi
    done

    # FPM Restart
    FPM_SUCCESS=true
    FPM_SERVICE=$(detect_fpm_service)
    if [[ -z "$FPM_SERVICE" ]]; then
        echo "Error: No PHP-FPM service found via systemctl."
        FPM_SUCCESS=false
    else
        echo "Step: Restarting $FPM_SERVICE..."
        if [ "$DRY_RUN" = false ]; then
            if ! sudo systemctl restart "$FPM_SERVICE"; then
                echo "Details: Last few lines of the error log:"
                sudo journalctl -u "$FPM_SERVICE" -n 5 --no-pager
                FPM_SUCCESS=false
            fi
        else
            echo "[DRY-RUN] Would restart $FPM_SERVICE"
        fi
    fi

    # Section status
    stop_spinner
    if [ "$COMPILE_SUCCESS" = true ] && [ "$FPM_SUCCESS" = true ]; then
        echo "Status: [SUCCESS] PO compilation & FPM restart completed."
    else
        echo "Status: [FAILED] PO compilation & FPM restart encountered errors."
    fi
fi

# 2. Translation Intelligence
if [ "$DO_UNUSED" = true ]; then
    echo "--- SECTION: TRANSLATION INTELLIGENCE ANALYSIS ---"

    # Auto-detect translation system and resolve per-language file paths.
    # PHP-array (messages.php) takes priority over Gettext (.po) unless -p overrides.
    TRANS_MODE=""
    FULL_HU=""; FULL_EN=""; FOUND_HU=false; FOUND_EN=false
    declare -A LANG_FILES

    if [[ "$PO_PATH_OVERRIDE" == true ]]; then
        # User passed -p: use that template; derive mode from file extension
        for lang in "${LANG_CODES[@]}"; do
            resolved="$BASE_PATH/$(echo "$PO_RELATIVE_PATH" | sed "s/{LANG}/$lang/g")"
            if [[ -f "$resolved" ]]; then
                LANG_FILES["$lang"]="$resolved"
                if [[ "${resolved##*.}" == "php" ]]; then TRANS_MODE="php"; else TRANS_MODE="po"; fi
            fi
        done
    else
        # Auto-probe: PHP templates first, then PO templates
        for lang in "${LANG_CODES[@]}"; do
            found_for_lang=""
            for tmpl in "${PHP_PATH_TEMPLATES[@]}"; do
                candidate="$BASE_PATH/$(echo "$tmpl" | sed "s/{LANG}/$lang/g")"
                if [[ -f "$candidate" ]]; then
                    found_for_lang="$candidate"
                    TRANS_MODE="php"
                    break
                fi
            done
            if [[ -z "$found_for_lang" && "$TRANS_MODE" != "php" ]]; then
                for tmpl in "${PO_PATH_TEMPLATES[@]}"; do
                    candidate="$BASE_PATH/$(echo "$tmpl" | sed "s/{LANG}/$lang/g")"
                    if [[ -f "$candidate" ]]; then
                        found_for_lang="$candidate"
                        [[ -z "$TRANS_MODE" ]] && TRANS_MODE="po"
                        break
                    fi
                done
            fi
            [[ -n "$found_for_lang" ]] && LANG_FILES["$lang"]="$found_for_lang"
        done
    fi

    FULL_HU="${LANG_FILES[hu_HU]:-}"
    FULL_EN="${LANG_FILES[en_US]:-}"
    [[ -n "$FULL_HU" ]] && FOUND_HU=true
    [[ -n "$FULL_EN" ]] && FOUND_EN=true

    if [[ -z "$TRANS_MODE" ]]; then
        echo "Warning: No translation files found. Skipping analysis."
    else
        hu_label=$([[ "$FOUND_HU" == true ]] && echo "$FULL_HU" || echo "not found")
        en_label=$([[ "$FOUND_EN" == true ]] && echo "$FULL_EN" || echo "not found")
        mode_label=$([[ "$TRANS_MODE" == "php" ]] && echo "PHP-array" || echo "Gettext")
        echo "Mode: $mode_label | hu_HU: $hu_label | en_US: $en_label"

        declare -A PO_HU; declare -A PO_EN; declare -A PO_ALL
        if [[ "$FOUND_HU" == true ]]; then
            while read -r k; do [ -n "$k" ] && PO_HU["$k"]=1 && PO_ALL["$k"]=1; done <<< "$(extract_keys "$TRANS_MODE" "$FULL_HU")"
        fi
        if [[ "$FOUND_EN" == true ]]; then
            while read -r k; do [ -n "$k" ] && PO_EN["$k"]=1 && PO_ALL["$k"]=1; done <<< "$(extract_keys "$TRANS_MODE" "$FULL_EN")"
        fi

        PREFIXES=$(for k in "${!PO_ALL[@]}"; do echo "$k"; done | grep -o '^[^_]\+_' | sort -u)
        JOINED_PREFIXES=$(echo "$PREFIXES" | tr '\n' '|' | sed 's/|$//')

        declare -A KEY_IN_CODE; declare -A DYNAMIC_IN_CODE; declare -A KEY_IN_DOCS; declare -A DYNAMICALLY_USED_KEYS
        GREP_EXCLUDES=(); for d in "${EXCLUDE_DIRS[@]}"; do GREP_EXCLUDES+=(--exclude-dir="$d"); done; for f in "${EXCLUDE_FILES[@]}"; do GREP_EXCLUDES+=(--exclude="$f"); done

        # Only run grep if we have prefixes to search for
        if [[ -n "$JOINED_PREFIXES" ]]; then
            start_spinner "Scanning codebase for translation keys…"
            REGEX="(?<![A-Z0-9_])($JOINED_PREFIXES)[A-Z0-9_]*(?![A-Z0-9_])"
            while IFS=: read -r file match; do
                [ -z "$match" ] && continue
                # Skip files in root-level /storage directory (but not **/storage)
                [[ "$file" == "$BASE_PATH/storage/"* ]] && continue
                ext="${file##*.}"
                is_code=$( [[ "$ext" == "php" || "$ext" == "js" || "$ext" == "twig" || "$ext" == "sql" ]] && echo "true" || echo "false" )
                is_dynamic=$( [[ "$match" =~ _$ ]] && echo "true" || echo "false" )

                if [[ "$is_code" == "true" ]]; then
                    if [[ "$is_dynamic" == "true" ]]; then
                        DYNAMIC_IN_CODE["$match"]="$ext"
                    else
                        KEY_IN_CODE["$match"]="$ext"
                    fi
                else
                    # Only track in docs if it's a full key AND not already found in code
                    if [[ "$is_dynamic" == "false" && -z "${KEY_IN_CODE[$match]}" ]]; then
                        [[ -z "${KEY_IN_DOCS[$match]}" ]] && KEY_IN_DOCS["$match"]="$ext"
                    fi
                fi
            done <<< "$(grep -rPo "${GREP_EXCLUDES[@]}" "$REGEX" "$BASE_PATH" 2>/dev/null)"

            # Post-process: Remove keys from KEY_IN_DOCS if they're also in KEY_IN_CODE
            # (handles case where doc file was processed before code file)
            for k in "${!KEY_IN_DOCS[@]}"; do
                [[ -n "${KEY_IN_CODE[$k]}" ]] && unset "KEY_IN_DOCS[$k]"
            done

            # Link dynamic prefixes to translation keys - marks keys as "dynamically used"
            # Skip prefixes that match ALL keys (naming convention, not dynamic usage)
            TOTAL_PO_KEYS=${#PO_ALL[@]}
            for prefix in "${!DYNAMIC_IN_CODE[@]}"; do
                # Count how many keys match this prefix
                match_count=0
                for po_key in "${!PO_ALL[@]}"; do
                    [[ "$po_key" == "$prefix"* ]] && ((match_count++))
                done
                # Only link if prefix matches a subset of keys (not all)
                if (( match_count < TOTAL_PO_KEYS )); then
                    for po_key in "${!PO_ALL[@]}"; do
                        if [[ "$po_key" == "$prefix"* ]]; then
                            DYNAMICALLY_USED_KEYS["$po_key"]="$prefix"
                        fi
                    done
                else
                    # Remove from DYNAMIC_IN_CODE - it's a naming convention, not dynamic usage
                    unset "DYNAMIC_IN_CODE[$prefix]"
                fi
            done
            stop_spinner
        else
            echo "Warning: No translation keys found in language files."
        fi

        MAX_LEN=40
        for k in "${!PO_ALL[@]}"; do (( ${#k} > MAX_LEN )) && MAX_LEN=${#k}; done
        for k in "${!KEY_IN_CODE[@]}"; do (( ${#k} > MAX_LEN )) && MAX_LEN=${#k}; done
        for k in "${!DYNAMIC_IN_CODE[@]}"; do (( ${#k} > MAX_LEN )) && MAX_LEN=${#k}; done
        for k in "${!KEY_IN_DOCS[@]}"; do (( ${#k} > MAX_LEN )) && MAX_LEN=${#k}; done

        REPORT_CONTENT=""
        DYN_COUNT=0; U_COUNT=0; DUP_COUNT=0; M_COUNT=0; DOC_COUNT=0

        if [ "$RUN_DUPLICATES" = true ]; then
            REPORT_CONTENT+="\nSub-Section: Duplicate Definitions\n"
            for f in "$FULL_HU" "$FULL_EN"; do
                [[ -z "$f" || ! -f "$f" ]] && continue
                fname=$(basename "$f")
                if [[ "$TRANS_MODE" == "php" ]]; then
                    DUPS=""
                    dup_keys=$(grep -oP "^\s*'\K[A-Z0-9_]+(?='\s*=>)" "$f" | sort | uniq -d)
                    while IFS= read -r dup_key; do
                        [ -z "$dup_key" ] && continue
                        line_nums=$(grep -nP "^\s*'${dup_key}'\s*=>" "$f" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
                        DUPS+="  Duplicate | '${dup_key}' | Lines: ${line_nums}"$'\n'
                    done <<< "$dup_keys"
                else
                    DUPS=$(awk '/^msgid "/ { count[$0]++; lines[$0]=lines[$0] (lines[$0]?" , ": "") NR } END { for (m in count) if (count[m]>1) print "  Duplicate | " m " | Lines: " lines[m] }' "$f")
                fi
                if [ -n "$DUPS" ]; then REPORT_CONTENT+="  File: $fname\n$DUPS\n"; ((DUP_COUNT += $(echo "$DUPS" | wc -l))); fi
            done
            REPORT_CONTENT+="\n"
        fi

        if [ "$RUN_SYNC" = true ]; then
            REPORT_CONTENT+="\nSub-Section: Sync Check (HU vs EN)\n"
            if [[ "$FOUND_HU" == false ]]; then
                REPORT_CONTENT+="  Sync skipped: hu_HU translation file not found\n"
            elif [[ "$FOUND_EN" == false ]]; then
                REPORT_CONTENT+="  Sync skipped: en_US translation file not found\n"
            else
                for k in "${!PO_HU[@]}"; do [[ -z "${PO_EN[$k]}" ]] && REPORT_CONTENT+="  Sync    | Missing  | EN | $k\n"; done
                for k in "${!PO_EN[@]}"; do [[ -z "${PO_HU[$k]}" ]] && REPORT_CONTENT+="  Sync    | Missing  | HU | $k\n"; done
            fi
            REPORT_CONTENT+="\n"
        fi

        if [ "$RUN_DYNAMIC" = true ]; then
            REPORT_CONTENT+="\nSub-Section: Dynamic Matches (Prefixes used for concatenation in code)\n"
            mapfile -t sorted_keys < <(printf "%s\n" "${!DYNAMIC_IN_CODE[@]}" | sort)
            for k in "${sorted_keys[@]}"; do
                [ -z "$k" ] && continue
                ((DYN_COUNT++))
                # Count how many translation keys match this prefix
                match_count=0
                for po_key in "${!PO_ALL[@]}"; do
                    [[ "$po_key" == "$k"* ]] && ((match_count++))
                done
                REPORT_CONTENT+=$(printf "  Dynamic | %-12s | %-${MAX_LEN}s | %d keys protected\n" "(${DYNAMIC_IN_CODE[$k]})" "$k" "$match_count")
                REPORT_CONTENT+="\n"
            done
            REPORT_CONTENT+="\n"
        fi

        if [ "$RUN_MISSING" = true ]; then
            REPORT_CONTENT+="\nSub-Section: Missing from translations (Full keys in code but not defined)\n"
            mapfile -t sorted_keys < <(printf "%s\n" "${!KEY_IN_CODE[@]}" | sort)
            for k in "${sorted_keys[@]}"; do
                [ -z "$k" ] && continue
                # Only list if NOT in translations
                if [[ -z "${PO_ALL[$k]}" ]]; then
                    ((M_COUNT++))
                    REPORT_CONTENT+=$(printf "  Missing | %-12s | %-${MAX_LEN}s |\n" "(${KEY_IN_CODE[$k]})" "$k")
                    REPORT_CONTENT+="\n"
                fi
            done
            REPORT_CONTENT+="\n"
        fi

        if [ "$RUN_UNUSED" = true ]; then
            UNUSED_LINES=""; UNUSED_LIST=()
            for k in "${!PO_ALL[@]}"; do
                # A key is unused if it's NOT in KEY_IN_CODE and NOT dynamically used via prefix
                if [[ -z "${KEY_IN_CODE[$k]}" && -z "${DYNAMICALLY_USED_KEYS[$k]}" ]]; then
                    langs=""; line_num="N/A"
                    if [[ -n "${PO_HU[$k]}" ]]; then
                        langs="HU"
                        line_num=$(key_line "$TRANS_MODE" "$FULL_HU" "$k")
                    fi
                    if [[ -n "${PO_EN[$k]}" ]]; then
                        langs=$( [[ -z "$langs" ]] && echo "EN" || echo "HU,EN" )
                        [[ "$line_num" == "N/A" ]] && line_num=$(key_line "$TRANS_MODE" "$FULL_EN" "$k")
                    fi
                    # Show note if key is also found in docs
                    doc_info=$( [[ -n "${KEY_IN_DOCS[$k]}" ]] && echo "[Also in: ${KEY_IN_DOCS[$k]}]" || echo "" )
                    UNUSED_LINES+="$(printf "%-8s | %-8s | %-${MAX_LEN}s | %s\n" "$line_num" "$langs" "$k" "$doc_info")\n"
                    UNUSED_LIST+=("$k"); ((U_COUNT++))
                fi
            done
            REPORT_CONTENT+="\nSub-Section: Unused in Code (Keys defined but not used in PHP/JS/Twig/SQL)\n"
            REPORT_CONTENT+="$(echo -e "$UNUSED_LINES" | sort -n)\n"
        fi

        if [ "$RUN_DOCONLY" = true ]; then
            REPORT_CONTENT+="\nSub-Section: Used Only in Documentation (Keys in docs but not in translations or code)\n"
            mapfile -t sorted_keys < <(printf "%s\n" "${!KEY_IN_DOCS[@]}" | sort)
            for k in "${sorted_keys[@]}"; do
                [ -z "$k" ] && continue
                # Only list if NOT in translations and NOT in code
                if [[ -z "${PO_ALL[$k]}" && -z "${KEY_IN_CODE[$k]}" ]]; then
                    ((DOC_COUNT++))
                    REPORT_CONTENT+=$(printf "  DocOnly | %-12s | %-${MAX_LEN}s |\n" "(${KEY_IN_DOCS[$k]})" "$k")
                    REPORT_CONTENT+="\n"
                fi
            done
            REPORT_CONTENT+="\n"
        fi

        DYN_USED_COUNT=${#DYNAMICALLY_USED_KEYS[@]}
        SUMMARY_LINE="Summary: Found $U_COUNT unused (strict), $DYN_USED_COUNT dynamically protected, $M_COUNT missing from translations, $DYN_COUNT dynamic prefixes, $DOC_COUNT doc-only, $DUP_COUNT duplicates."
        REPORT_CONTENT+="$SUMMARY_LINE\n"
        if [ "$DO_FILE" = true ]; then echo -e "$REPORT_CONTENT" > "$OUTPUT_FILE"; echo "Result saved to $OUTPUT_FILE"; fi
        echo -e "$REPORT_CONTENT"

        if [ "$DO_CLEANUP" = true ] && [ "$DRY_RUN" = false ]; then
            if [[ "$TRANS_MODE" == "php" ]]; then
                echo "Cleanup not supported for PHP-array translations (report-only); skipping."
            else
                if [ "$AUTO_CONFIRM" = false ]; then
                    echo "Warning: About to comment out ${#UNUSED_LIST[@]} unused keys. Continue? (y/N)"
                    read -r confirm
                    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "Cleanup cancelled." && exit 0
                fi
                for k in "${UNUSED_LIST[@]}"; do
                    escaped_k=$(escape_regex "$k")
                    for lang_file in "$FULL_HU" "$FULL_EN"; do
                        [[ -z "$lang_file" ]] && continue
                        sed -i "s/^msgid \"$escaped_k\"/#~ msgid \"$k\"/" "$lang_file"
                        sed -i "/#~ msgid \"$escaped_k\"/,/msgstr/ s/^msgstr/#~ msgstr/" "$lang_file"
                    done
                done
                echo "Cleanup complete: ${#UNUSED_LIST[@]} keys commented out."
            fi
        fi
        echo "Status: [SUCCESS] Translation intelligence analysis completed."
    fi
fi

# 3. Ownership & 4. Permissions
if [ "$DO_OWNER" = true ]; then
    echo "--- SECTION: OWNERSHIP ---"
    if [ "$DRY_RUN" = false ]; then
        start_spinner "Setting ownership to $OWNER_CONFIG…"
        if sudo chown -R "$OWNER_CONFIG" "$BASE_PATH"; then
            stop_spinner
            echo "Status: [SUCCESS] Ownership set to $OWNER_CONFIG."
        else
            stop_spinner
            echo "Status: [FAILED] Could not set ownership."
        fi
    else
        echo "[DRY-RUN] Would set ownership to $OWNER_CONFIG"
    fi
fi
if [ "$DO_PERMISSION" = true ]; then
    echo "--- SECTION: PERMISSIONS ---"
    PERM_SUCCESS=true
    if [ "$DRY_RUN" = false ]; then
        start_spinner "Applying permissions…"
        sudo find "$BASE_PATH" -type d -exec chmod 775 {} \; || PERM_SUCCESS=false
        sudo find "$BASE_PATH" -type f ! -name "*.sh" -exec chmod 664 {} \; || PERM_SUCCESS=false
        sudo find "$BASE_PATH" -type f -name "*.sh" -exec chmod 775 {} \; || PERM_SUCCESS=false
        stop_spinner
        if [ "$PERM_SUCCESS" = true ]; then
            echo "Status: [SUCCESS] Permissions applied (dirs: 775, files: 664, scripts: 775)."
        else
            echo "Status: [FAILED] Some permissions could not be applied."
        fi
    else
        echo "[DRY-RUN] Would set directories to 775, files to 664, .sh files to 775"
    fi
fi

# 5. Hostname
if [ "$DO_HOSTNAME" = true ]; then
    echo "--- SECTION: HOSTNAME ---"
    if [ "$AUTO_CONFIRM" = false ] && [ "$DRY_RUN" = false ]; then
        echo "Warning: About to change hostname to '$HOSTNAME_VALUE' and restart avahi-daemon. Continue? (y/N)"
        read -r confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "Hostname change cancelled." && exit 0
    fi
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would run: sudo hostnamectl set-hostname \"$HOSTNAME_VALUE\""
        echo "[DRY-RUN] Would run: sudo systemctl restart avahi-daemon"
    else
        start_spinner "Setting hostname to '$HOSTNAME_VALUE'…"
        if sudo hostnamectl set-hostname "$HOSTNAME_VALUE" && sudo systemctl restart avahi-daemon; then
            stop_spinner
            echo "Status: [SUCCESS] Hostname set to '$HOSTNAME_VALUE' and avahi-daemon restarted."
        else
            stop_spinner
            echo "Status: [FAILED] Could not set hostname or restart avahi-daemon."
        fi
    fi
fi

echo -e "\n--- SECTION: STATUS ---"
echo "Execution time: $(( $(date +%s) - START_TIME )) seconds. finished."
