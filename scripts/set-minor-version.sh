#!/bin/bash
#
# set-minor-version.sh
#
# Copyright (c) 2023 Sören Gade

set -eu

VERSION_FILE="Version.lua"

if [ -z ${1+x} ]; then
    >&2 echo "Usage: $0 <minor>"
    exit 1
fi

VERSION_MINOR=$1

echo "Setting minor version to $VERSION_MINOR."

{
    echo "-- AUTOMATICALLY GENERATED. MODIFICATION WILL BE OVERWRITTEN"
    echo ""
    echo "local _, namespace = ..."
    echo ""
    echo "namespace.VERSION_MINOR = ${VERSION_MINOR}"
} > $VERSION_FILE

echo "$VERSION_FILE written."
