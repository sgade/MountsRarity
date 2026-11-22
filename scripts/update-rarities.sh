#!/usr/bin/env bash
#
#  MountsRarity/scripts/update-rarities.sh
#
#  Copyright (c) 2023 Sören Gade
#  For the full license, see the LICENSE file.
#
#  Usage: update-rarities.sh [all|retail|forever]
#
#  The update of a client has two phases:
#  1. Fetch: download and validate the data. This phase does not change files in the repository.
#  2. Apply: write the data to MOUNTS_FILE.
#  For "all", the fetch phases of all clients run at the same time. The apply phases
#  run one after the other, because they write to the same file.
#

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/output.sh
source "$SCRIPT_DIR/lib/output.sh"

DATA_BASE_URL="${DATA_BASE_URL:-https://www.dataforazeroth.com}"
# Refuse the update if the new mount count drops below this percentage of the previous count.
# Guards against partial/broken upstream responses silently wiping out most of the data.
MIN_COUNT_RATIO=95

MOUNTS_FILE="MountsRarity.lua"

function get() {
    curl "$1" \
        -sS \
        --fail-with-body \
        --compressed \
        --max-time 60 \
        -H 'Accept: application/json' \
        -H 'Origin: https://www.dataforazeroth.com' \
        -H 'User-Agent: MountsRarity (+https://github.com/sgade/MountsRarity)'
}

function fail() {
    log_error "$1"
    exit 1
}

# Runs this script again in a new process, with the same Bash.
function run_self() {
    "$BASH" "$SCRIPT_PATH" "$@"
}

function usage() {
    cat <<EOF
Usage: $0 [all|retail|forever]

Updates the rarity data in ${MOUNTS_FILE}. Without an argument, updates all clients.

Environment overrides:
  DATA_BASE_URL               Data for Azeroth base URL. Default: https://www.dataforazeroth.com
  NO_PROGRESS                 If set, do not show progress in an interactive terminal.
EOF
}

function client_display_name() {
    case "$1" in
        retail) echo "Retail" ;;
        forever) echo "Forever" ;;
        *) echo "$1" ;;
    esac
}

# --- All clients --------------------------------------------------------------

# Each client runs in its own process and changes only its own data block,
# so a Forever problem cannot stop or change the Retail update.
function update_all_clients() {
    local clients=(retail forever)
    local count="${#clients[@]}"
    local work_dir client fetch_status apply_status
    local index=0

    work_dir="$(mktemp -d)"
    on_exit "rm -rf '$work_dir'"

    progress_indeterminate
    step "Downloading data for all clients..."

    bg_reset
    for client in "${clients[@]}"; do
        mkdir "$work_dir/$client"
        bg_start "$client" "Starting..." "$work_dir/$client.log" run_self --fetch "$client" "$work_dir/$client"
    done
    bg_wait 0 50

    # Show the result of each client in a fixed order, so the log is easy to read.
    for client in "${clients[@]}"; do
        group_start "$(client_display_name "$client")"
        print_file "$work_dir/$client.log"
        print_file "$work_dir/$client.log.err" >&2

        fetch_status="$(bg_status_of "$client")"
        apply_status=0
        if [[ "$fetch_status" -ne 0 ]]; then
            apply_status="$fetch_status"
        else
            run_self "$client" "$work_dir/$client" || apply_status=$?
        fi
        group_end

        index=$((index + 1))
        progress_set $((50 + 50 * index / count))

        if [[ "$apply_status" -ne 0 ]]; then
            if [[ "$client" == "retail" ]]; then
                exit "$apply_status"
            fi
            warn "$(client_display_name "$client") rarity data was not updated. Examine the log for the reason."
        fi
    done
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

if [[ "${1:-all}" == "all" ]]; then
    update_all_clients
    exit 0
fi

# --- One client ---------------------------------------------------------------

FETCH_ONLY=false
if [[ "$1" == "--fetch" ]]; then
    FETCH_ONLY=true
    shift
fi

CLIENT="$1"
DATA_DIR="${2:-}"

case "$CLIENT" in
    # A client without the constants must not match: there, both sides of the comparison are nil.
    retail)
        CLIENT_CONDITION="WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE"
        ;;
    forever)
        CLIENT_CONDITION="WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT"
        ;;
    *)
        fail "Unknown client: $CLIENT (expected all, retail or forever)."
        ;;
esac

# The data of this client is the block from BEGIN_MARKER to END_MARKER in MOUNTS_FILE.
BEGIN_MARKER="-- BEGIN DATA $CLIENT"
END_MARKER="-- END DATA $CLIENT"

function data_block() {
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '$0 == begin { found = 1 } found { print } $0 == end { found = 0 }' "$1"
}

# Downloads and validates the data of CLIENT into the directory $1.
# The directory then contains mountsrarity.json, which has the validated entries.
function fetch_client() {
    local dir="$1"
    local version_file="$dir/index.json"
    local response_file="$dir/mountsrarity-response.json"
    local catalog_file="$dir/catalog.json"
    local mountsrarity_file="$dir/mountsrarity.json"
    local invalid_entries invalid_count unknown_ids

    step "[$CLIENT] Downloading version information..."
    get "$DATA_BASE_URL/$CLIENT/dynamic/index.json" > "$version_file"

    jq -e '(.mountsrarity | type) == "string" and (.mountsrarity | length) > 0' "$version_file" > /dev/null \
        || fail "[$CLIENT] Unexpected version response: 'mountsrarity' is missing or not a non-empty string."

    # Retail data at the wrong path must not reach this client: its mount IDs are partly the same.
    # Thus, the other clients also download their mount catalog to compare the IDs.
    if [[ "$CLIENT" != "retail" ]]; then
        jq -e '(.mounts | type) == "string" and (.mounts | length) > 0' "$version_file" > /dev/null \
            || fail "[$CLIENT] Unexpected version response: 'mounts' is missing or not a non-empty string."
    fi

    # The two downloads do not depend on each other, so they run at the same time.
    step "[$CLIENT] Downloading mountsrarity information..."
    bg_reset
    bg_start "mountsrarity" "Downloading mountsrarity information..." "$response_file" get "$DATA_BASE_URL$(jq -r '.mountsrarity' "$version_file")"
    if [[ "$CLIENT" != "retail" ]]; then
        bg_start "catalog" "Downloading the mount catalog..." "$catalog_file" get "$DATA_BASE_URL$(jq -r '.mounts' "$version_file")"
    fi
    bg_wait 10 40

    if [[ "$(bg_status_of mountsrarity)" -ne 0 ]]; then
        print_file "$response_file.err" >&2
        fail "[$CLIENT] Could not download mountsrarity information."
    fi
    if [[ "$CLIENT" != "retail" && "$(bg_status_of catalog)" -ne 0 ]]; then
        print_file "$catalog_file.err" >&2
        fail "[$CLIENT] Could not download the mount catalog."
    fi

    jq -e '(.mounts | type) == "object"' "$response_file" > /dev/null \
        || fail "[$CLIENT] Unexpected mountsrarity response: 'mounts' is missing or not an object."

    jq '.mounts | to_entries' "$response_file" > "$mountsrarity_file"

    step "[$CLIENT] Validating downloaded data..."
    invalid_entries=$(jq -c '
        [.[] | select(
            (.key | test("^[0-9]+$") | not)
            or (.value | type != "number")
            or (.value < 0)
            or (.value > 100)
        )]
    ' "$mountsrarity_file")
    invalid_count=$(echo "$invalid_entries" | jq 'length')
    if [[ "$invalid_count" -gt 0 ]]; then
        log_error "[$CLIENT] Invalid entries:"
        echo "$invalid_entries" | jq -c '.[]' >&2
        fail "[$CLIENT] Refusing to update: found $invalid_count invalid mount entries above (mount ID must be an integer, rarity must be a number between 0 and 100)."
    fi

    if [[ "$CLIENT" != "retail" ]]; then
        jq -e '(.mounts | type) == "array" and (.mounts | length) > 0' "$catalog_file" > /dev/null \
            || fail "[$CLIENT] Unexpected mounts response: 'mounts' is missing or not a non-empty array."

        unknown_ids=$(comm -23 \
            <(jq -r '.[].key' "$mountsrarity_file" | LC_ALL=C sort -u) \
            <(jq -r '.mounts[].id' "$catalog_file" | LC_ALL=C sort -u))
        if [[ -n "$unknown_ids" ]]; then
            fail "[$CLIENT] Refusing to update: these mount IDs are not in the $CLIENT mount catalog: $(echo "$unknown_ids" | tr '\n' ' ')"
        fi
    fi

    log "[$CLIENT] The downloaded data is valid."
}

# Writes the validated data in the directory $1 to MOUNTS_FILE.
function apply_client() {
    local dir="$1"
    local mountsrarity_file="$dir/mountsrarity.json"
    local tmp_mounts_file="$dir/MountsRarity.lua"
    local tmp_data_block="$dir/data-block.lua"
    local new_count previous_count min_allowed_count now_epoch next_minor
    local luac_bin lua_bin candidate

    [[ -s "$mountsrarity_file" ]] || fail "[$CLIENT] No downloaded data found in $dir."

    new_count=$(jq 'length' "$mountsrarity_file")
    previous_count=$(data_block "$MOUNTS_FILE" | grep -cE '^[[:space:]]*\[[0-9]+\] = ' || true)
    log "[$CLIENT] Downloaded $new_count mounts (previously $previous_count)."

    if [[ "$previous_count" -gt 0 ]]; then
        min_allowed_count=$((previous_count * MIN_COUNT_RATIO / 100))
        if ((new_count < min_allowed_count)); then
            fail "[$CLIENT] Refusing to update: new mount count ($new_count) is more than $((100 - MIN_COUNT_RATIO))% lower than the previous count ($previous_count). This likely indicates a broken or partial upstream response."
        fi
    fi

    # Write to a temporary file first so $MOUNTS_FILE is only touched once the result is known-good.
    # The version and the data time come from the same moment. MINOR is the UTC date and time (YYYYMMDDHHMM).
    read -r now_epoch next_minor < <(date -u +'%s %Y%m%d%H%M')
    {
        echo "$BEGIN_MARKER"
        echo "if $CLIENT_CONDITION then"
        echo "  lastUpdated = $now_epoch"
        echo "  data = {"
        jq -r '.[] | "    [" + .key + "] = " + ( .value | tostring ) + ","' "$mountsrarity_file"
        echo "  }"
        echo "end"
        echo "$END_MARKER"
    } > "$tmp_data_block"

    # Replace only the data block of this client and the version. All other lines stay the same.
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v block="$tmp_data_block" -v minor="$next_minor" '
        /^local MINOR = [0-9]+$/ { print "local MINOR = " minor; next }
        $0 == begin { while ((getline line < block) > 0) print line; skip = 1; next }
        $0 == end { skip = 0; next }
        !skip { print }
    ' "$MOUNTS_FILE" > "$tmp_mounts_file"

    step "[$CLIENT] Validating generated Lua syntax..."
    luac_bin=""
    for candidate in luac5.1 luac5.3 luac5.4 luac; do
        if command -v "$candidate" > /dev/null 2>&1; then
            luac_bin="$candidate"
            break
        fi
    done
    lua_bin=""
    for candidate in lua5.1 lua5.3 lua5.4 lua; do
        if command -v "$candidate" > /dev/null 2>&1; then
            lua_bin="$candidate"
            break
        fi
    done

    if [[ -n "$luac_bin" ]]; then
        "$luac_bin" -p "$tmp_mounts_file" || fail "[$CLIENT] Refusing to update: $MOUNTS_FILE failed Lua syntax validation."
    elif [[ -n "$lua_bin" ]]; then
        "$lua_bin" -e "assert(loadfile('$tmp_mounts_file'))" || fail "[$CLIENT] Refusing to update: $MOUNTS_FILE failed Lua syntax validation."
    else
        fail "[$CLIENT] Refusing to update: no Lua interpreter (luac/lua, any version) available to validate the generated $MOUNTS_FILE."
    fi

    # Only the data decides if the file changes. A new timestamp alone must not create a release.
    if cmp -s <(data_block "$MOUNTS_FILE" | grep -v '^  lastUpdated = ') <(data_block "$tmp_mounts_file" | grep -v '^  lastUpdated = '); then
        log "[$CLIENT] The data in $MOUNTS_FILE is already current."
        return 0
    fi

    cat "$tmp_mounts_file" > "$MOUNTS_FILE"

    log "[$CLIENT] $MOUNTS_FILE written and validated (MINOR $next_minor)."
}

if [[ "$FETCH_ONLY" == true ]]; then
    [[ -d "$DATA_DIR" ]] || fail "--fetch requires an existing directory for the downloaded data."
    fetch_client "$DATA_DIR"
    exit 0
fi

[[ "$(grep -cxF -- "$BEGIN_MARKER" "$MOUNTS_FILE")" -eq 1 && "$(grep -cxF -- "$END_MARKER" "$MOUNTS_FILE")" -eq 1 ]] \
    || fail "$MOUNTS_FILE must contain the lines '$BEGIN_MARKER' and '$END_MARKER' one time each."
[[ "$(grep -cE '^local MINOR = [0-9]+$' "$MOUNTS_FILE")" -eq 1 ]] \
    || fail "$MOUNTS_FILE must contain the line 'local MINOR = <number>' one time."

progress_indeterminate

# Without a directory with downloaded data, download the data first.
if [[ -z "$DATA_DIR" ]]; then
    DATA_DIR="$(mktemp -d)"
    on_exit "rm -rf '$DATA_DIR'"
    fetch_client "$DATA_DIR"
fi

progress_set 50
apply_client "$DATA_DIR"
progress_set 100
