#!/bin/bash
#
#  MountsRarity/scripts/update-rarities.sh
#
#  Copyright (c) 2023 Sören Gade
#  For the full license, see the LICENSE file.
#

set -euo pipefail

DATA_BASE_URL="${DATA_BASE_URL:-https://www.dataforazeroth.com}"
# Refuse the update if the new mount count drops below this percentage of the previous count.
# Guards against partial/broken upstream responses silently wiping out most of the data.
MIN_COUNT_RATIO=95

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
    echo "$1" >&2
    exit 1
}

MOUNTS_FILE="MountsRarity.lua"

CLIENT="${1:-all}"
case "$CLIENT" in
    all)
        # Each client runs in its own process and changes only its own data block,
        # so a Forever problem cannot stop or change the Retail update.
        # The clients run one after the other because they write to the same file.
        "$0" retail
        "$0" forever || echo "::warning::Forever rarity data was not updated. Examine the log for the reason."
        exit 0
        ;;
    # A client without the constants must not match: there, both sides of the comparison are nil.
    retail)
        CLIENT_CONDITION="WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE"
        ;;
    forever)
        CLIENT_CONDITION="WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT"
        ;;
    *)
        fail "Unknown client: $CLIENT (expected retail or forever)."
        ;;
esac

# The data of this client is the block from BEGIN_MARKER to END_MARKER in MOUNTS_FILE.
BEGIN_MARKER="-- BEGIN DATA $CLIENT"
END_MARKER="-- END DATA $CLIENT"

function data_block() {
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '$0 == begin { found = 1 } found { print } $0 == end { found = 0 }' "$1"
}

[[ "$(grep -cxF -- "$BEGIN_MARKER" "$MOUNTS_FILE")" -eq 1 && "$(grep -cxF -- "$END_MARKER" "$MOUNTS_FILE")" -eq 1 ]] \
    || fail "$MOUNTS_FILE must contain the lines '$BEGIN_MARKER' and '$END_MARKER' one time each."
[[ "$(grep -cE '^local MINOR = [0-9]+$' "$MOUNTS_FILE")" -eq 1 ]] \
    || fail "$MOUNTS_FILE must contain the line 'local MINOR = <number>' one time."

echo "[$CLIENT] Downloading version information..."
VERSION_RESPONSE=$(get "$DATA_BASE_URL/$CLIENT/dynamic/index.json")

echo "$VERSION_RESPONSE" | jq -e '(.mountsrarity | type) == "string" and (.mountsrarity | length) > 0' > /dev/null \
    || fail "Unexpected version response: 'mountsrarity' is missing or not a non-empty string."

echo "[$CLIENT] Downloading mountsrarity information..."
MOUNTSRARITY_SOURCE="$DATA_BASE_URL$(echo "$VERSION_RESPONSE" | jq -r '.mountsrarity')"
MOUNTSRARITY_RESPONSE=$(get "$MOUNTSRARITY_SOURCE")

echo "$MOUNTSRARITY_RESPONSE" | jq -e '(.mounts | type) == "object"' > /dev/null \
    || fail "Unexpected mountsrarity response: 'mounts' is missing or not an object."

MOUNTSRARITY=$(echo "$MOUNTSRARITY_RESPONSE" | jq '.mounts | to_entries')

echo "Validating downloaded data..."
INVALID_ENTRIES=$(echo "$MOUNTSRARITY" | jq -c '
    [.[] | select(
        (.key | test("^[0-9]+$") | not)
        or (.value | type != "number")
        or (.value < 0)
        or (.value > 100)
    )]
')
INVALID_COUNT=$(echo "$INVALID_ENTRIES" | jq 'length')
if [[ "$INVALID_COUNT" -gt 0 ]]; then
    echo "Invalid entries:" >&2
    echo "$INVALID_ENTRIES" | jq -c '.[]' >&2
    fail "Refusing to update: found $INVALID_COUNT invalid mount entries above (mount ID must be an integer, rarity must be a number between 0 and 100)."
fi

# Retail data at the wrong path must not reach this client: its mount IDs are partly the same.
if [[ "$CLIENT" != "retail" ]]; then
    echo "$VERSION_RESPONSE" | jq -e '(.mounts | type) == "string" and (.mounts | length) > 0' > /dev/null \
        || fail "Unexpected version response: 'mounts' is missing or not a non-empty string."

    CATALOG_RESPONSE=$(get "$DATA_BASE_URL$(echo "$VERSION_RESPONSE" | jq -r '.mounts')")
    echo "$CATALOG_RESPONSE" | jq -e '(.mounts | type) == "array" and (.mounts | length) > 0' > /dev/null \
        || fail "Unexpected mounts response: 'mounts' is missing or not a non-empty array."

    UNKNOWN_IDS=$(comm -23 \
        <(echo "$MOUNTSRARITY" | jq -r '.[].key' | LC_ALL=C sort -u) \
        <(echo "$CATALOG_RESPONSE" | jq -r '.mounts[].id' | LC_ALL=C sort -u))
    if [[ -n "$UNKNOWN_IDS" ]]; then
        fail "Refusing to update: these mount IDs are not in the $CLIENT mount catalog: $(echo "$UNKNOWN_IDS" | tr '\n' ' ')"
    fi
fi

NEW_COUNT=$(echo "$MOUNTSRARITY" | jq 'length')
PREVIOUS_COUNT=$(data_block "$MOUNTS_FILE" | grep -cE '^[[:space:]]*\[[0-9]+\] = ' || true)
echo "Downloaded $NEW_COUNT mounts (previously $PREVIOUS_COUNT)."

if [[ "$PREVIOUS_COUNT" -gt 0 ]]; then
    MIN_ALLOWED_COUNT=$((PREVIOUS_COUNT * MIN_COUNT_RATIO / 100))
    if ((NEW_COUNT < MIN_ALLOWED_COUNT)); then
        fail "Refusing to update: new mount count ($NEW_COUNT) is more than $((100 - MIN_COUNT_RATIO))% lower than the previous count ($PREVIOUS_COUNT). This likely indicates a broken or partial upstream response."
    fi
fi

# Write to a temporary file first so $MOUNTS_FILE is only touched once the result is known-good.
TMP_MOUNTS_FILE=$(mktemp)
TMP_DATA_BLOCK=$(mktemp)
trap 'rm -f "$TMP_MOUNTS_FILE" "$TMP_DATA_BLOCK"' EXIT

# The version and the data time come from the same moment. MINOR is the UTC date and time (YYYYMMDDHHMM).
read -r NOW_EPOCH NEXT_MINOR < <(date -u +'%s %Y%m%d%H%M')
{
    echo "$BEGIN_MARKER"
    echo "if $CLIENT_CONDITION then"
    echo "  lastUpdated = $NOW_EPOCH"
    echo "  data = {"
    echo "$MOUNTSRARITY" | jq -r '.[] | "    [" + .key + "] = " + ( .value | tostring ) + ","'
    echo "  }"
    echo "end"
    echo "$END_MARKER"
} > "$TMP_DATA_BLOCK"

# Replace only the data block of this client and the version. All other lines stay the same.
awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v block="$TMP_DATA_BLOCK" -v minor="$NEXT_MINOR" '
    /^local MINOR = [0-9]+$/ { print "local MINOR = " minor; next }
    $0 == begin { while ((getline line < block) > 0) print line; skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
' "$MOUNTS_FILE" > "$TMP_MOUNTS_FILE"

echo "Validating generated Lua syntax..."
LUAC_BIN=""
for candidate in luac5.1 luac5.3 luac5.4 luac; do
    if command -v "$candidate" > /dev/null 2>&1; then
        LUAC_BIN="$candidate"
        break
    fi
done
LUA_BIN=""
for candidate in lua5.1 lua5.3 lua5.4 lua; do
    if command -v "$candidate" > /dev/null 2>&1; then
        LUA_BIN="$candidate"
        break
    fi
done

if [[ -n "$LUAC_BIN" ]]; then
    "$LUAC_BIN" -p "$TMP_MOUNTS_FILE" || fail "Refusing to update: $MOUNTS_FILE failed Lua syntax validation."
elif [[ -n "$LUA_BIN" ]]; then
    "$LUA_BIN" -e "assert(loadfile('$TMP_MOUNTS_FILE'))" || fail "Refusing to update: $MOUNTS_FILE failed Lua syntax validation."
else
    fail "Refusing to update: no Lua interpreter (luac/lua, any version) available to validate the generated $MOUNTS_FILE."
fi

# Only the data decides if the file changes. A new timestamp alone must not create a release.
if cmp -s <(data_block "$MOUNTS_FILE" | grep -v '^  lastUpdated = ') <(data_block "$TMP_MOUNTS_FILE" | grep -v '^  lastUpdated = '); then
    echo "[$CLIENT] The data in $MOUNTS_FILE is already current."
    exit 0
fi

cat "$TMP_MOUNTS_FILE" > "$MOUNTS_FILE"

echo "[$CLIENT] $MOUNTS_FILE written and validated (MINOR $NEXT_MINOR)."
