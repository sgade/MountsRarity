#!/bin/bash
#
#  MountsRarity/scripts/update-rarities.sh
#
#  Copyright (c) 2023 Sören Gade
#  For the full license, see the LICENSE file.
#

set -eu

MOUNTS_FILE="MountsRarity.lua"

function get() {
    curl "$1" \
        -X 'GET' \
        -H 'Accept: text/json; charset=iso-8859-1' \
        -H 'Origin: https://www.dataforazeroth.com' \
        -H 'User-Agent: MountsRarity'
}

echo "Downloading version information..."
VERSION_RESPONSE=$(get 'https://api.dataforazeroth.com/version')

echo "Downloading mountsrarity information..."
MOUNTSRARITY_SOURCE="https://www.dataforazeroth.com$(echo "$VERSION_RESPONSE" | jq .mountsrarity | tr -d '"')"
MOUNTSRARITY_RESPONSE=$(get "$MOUNTSRARITY_SOURCE")

MOUNTSRARITY=$(echo "$MOUNTSRARITY_RESPONSE" | jq '.mounts | to_entries')
echo "Downloaded $(echo "$MOUNTSRARITY" | jq 'length') mounts."

sed -i '/Everything after this line/q' $MOUNTS_FILE
{
    echo "lazyLoadData = function() return {"
    echo "$MOUNTSRARITY" | jq -r '.[] | "  [" + .key + "] = " + ( .value | tostring ) + ","'
    echo "} end"
} >> $MOUNTS_FILE

echo "$MOUNTS_FILE written."
