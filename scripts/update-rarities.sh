#!/bin/bash
#
#  MountsRarity/scripts/update-rarities.sh
#
#  Copyright (c) 2023 Sören Gade
#  For the full license, see the LICENSE file.
#

set -euo pipefail

MOUNTS_FILE="MountsRarity.lua"
# Refuse the update if the new mount count drops below this percentage of the previous count.
# Guards against partial/broken upstream responses silently wiping out most of the data.
MIN_COUNT_RATIO=95

function get() {
    curl "$1" \
        -X 'GET' \
        -H 'Accept: text/json; charset=iso-8859-1' \
        -H 'Origin: https://www.dataforazeroth.com' \
        -H 'User-Agent: MountsRarity'
}

function fail() {
    echo "$1" >&2
    exit 1
}

echo "Downloading version information..."
VERSION_RESPONSE=$(get 'https://dataforazeroth.com/dynamic/index.json')

echo "$VERSION_RESPONSE" | jq -e '(.mountsrarity | type) == "string" and (.mountsrarity | length) > 0' > /dev/null \
    || fail "Unexpected version response: 'mountsrarity' is missing or not a non-empty string."

echo "Downloading mountsrarity information..."
MOUNTSRARITY_SOURCE="https://www.dataforazeroth.com$(echo "$VERSION_RESPONSE" | jq -r '.mountsrarity')"
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

NEW_COUNT=$(echo "$MOUNTSRARITY" | jq 'length')
PREVIOUS_COUNT=$(grep -cE '^[[:space:]]*\[[0-9]+\] = ' "$MOUNTS_FILE" || true)
echo "Downloaded $NEW_COUNT mounts (previously $PREVIOUS_COUNT)."

if [[ "$PREVIOUS_COUNT" -gt 0 ]]; then
    MIN_ALLOWED_COUNT=$((PREVIOUS_COUNT * MIN_COUNT_RATIO / 100))
    if ((NEW_COUNT < MIN_ALLOWED_COUNT)); then
        fail "Refusing to update: new mount count ($NEW_COUNT) is more than $((100 - MIN_COUNT_RATIO))% lower than the previous count ($PREVIOUS_COUNT). This likely indicates a broken or partial upstream response."
    fi
fi

# Write to a temporary file first so $MOUNTS_FILE is only touched once the result is known-good.
TMP_MOUNTS_FILE=$(mktemp)
trap 'rm -f "$TMP_MOUNTS_FILE"' EXIT

sed '/Everything after this line/q' "$MOUNTS_FILE" > "$TMP_MOUNTS_FILE"
{
    echo "lazyLoadData = function() return {"
    echo "$MOUNTSRARITY" | jq -r '.[] | "  [" + .key + "] = " + ( .value | tostring ) + ","'
    echo "} end"
} >> "$TMP_MOUNTS_FILE"

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

cat "$TMP_MOUNTS_FILE" > "$MOUNTS_FILE"

echo "$MOUNTS_FILE written and validated."
