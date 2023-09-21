#!/bin/bash
#
# update-rarities.sh
#
# Copyright (c) 2023 Sören Gade

set -eu

MOUNTS_FILE="Data.lua"

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

echo "-- AUTOMATICALLY GENERATED. MODIFICATION WILL BE OVERWRITTEN" > $MOUNTS_FILE
{
    echo "-- Source: https://www.dataforazeroth.com/collections/mounts"
    echo ""
    echo "local _, namespace = ..."
    echo ""
    echo "namespace.data = {"
    echo "$MOUNTSRARITY" | jq -r '.[] | "  [" + .key + "] = " + ( .value | tostring ) + ","'
    echo "}"
} >> $MOUNTS_FILE

echo "$MOUNTS_FILE written."
