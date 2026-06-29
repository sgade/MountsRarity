#!/bin/bash
#
#  MountsRarity/scripts/update-interface-version.sh
#
#  Copyright (c) 2026 Sören Gade
#  For the full license, see the LICENSE file.
#

set -euo pipefail

TOC_FILE="${TOC_FILE:-MountsRarity.toc}"
PATCH_ENDPOINT_BASE_URL="${PATCH_ENDPOINT_BASE_URL:-http://us.patch.battle.net:1119}"
MAINLINE_PRODUCT="${MAINLINE_PRODUCT:-wow}"
MAINLINE_TEST_PRODUCT="${MAINLINE_TEST_PRODUCT:-wowt}"
REGION="${REGION:-us}"
CHECK_ONLY=false

function usage() {
    cat <<EOF
Usage: $0 [--check]

Updates the WoW Interface metadata in ${TOC_FILE}.

Environment overrides:
  TOC_FILE                    TOC file to update. Default: MountsRarity.toc
  PATCH_ENDPOINT_BASE_URL     Blizzard CDN base URL. Default: http://us.patch.battle.net:1119
  MAINLINE_PRODUCT            Retail mainline product slug. Default: wow
  MAINLINE_TEST_PRODUCT       Retail PTR/beta product slug. Default: wowt
  REGION                      Region row to read from versions files. Default: us

Options:
  --check                     Verify the TOC is already current without writing it.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

function get_product_version() {
    local product="$1"
    local endpoint="${PATCH_ENDPOINT_BASE_URL}/${product}/versions"

    curl --fail --silent --show-error --location "$endpoint" \
        | awk -F'|' -v region="$REGION" '$1 == region { print $6; exit }'
}

function interface_version_from_product_version() {
    local product_version="$1"
    local semantic_version="${product_version%.*}"
    local major minor patch

    IFS='.' read -r major minor patch <<< "$semantic_version"

    if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ || ! "$patch" =~ ^[0-9]+$ ]]; then
        echo "Could not parse WoW product version: $product_version" >&2
        exit 1
    fi

    printf "%d%02d%02d" "$major" "$minor" "$patch"
}

function require_version() {
    local product="$1"
    local version

    version="$(get_product_version "$product")"

    if [[ -z "$version" ]]; then
        echo "Could not find region '${REGION}' in Blizzard versions for product '${product}'." >&2
        exit 1
    fi

    echo "$version"
}

function add_unique_interface_version() {
    local interface_version="$1"
    local existing_interface_version

    if [[ ${#INTERFACE_VERSIONS[@]} -gt 0 ]]; then
        for existing_interface_version in "${INTERFACE_VERSIONS[@]}"; do
            if [[ "$existing_interface_version" == "$interface_version" ]]; then
                return
            fi
        done
    fi

    INTERFACE_VERSIONS+=("$interface_version")
}

function current_interface_line() {
    awk '/^## Interface:/ { print; exit }' "$TOC_FILE"
}

function join_interface_versions() {
    local joined=""
    local interface_version

    for interface_version in "$@"; do
        if [[ -n "$joined" ]]; then
            joined+=", "
        fi

        joined+="$interface_version"
    done

    echo "$joined"
}

if [[ ! -f "$TOC_FILE" ]]; then
    echo "TOC file not found: $TOC_FILE" >&2
    exit 1
fi

echo "Downloading Blizzard versions for ${MAINLINE_PRODUCT} and ${MAINLINE_TEST_PRODUCT}..."

MAINLINE_VERSION="$(require_version "$MAINLINE_PRODUCT")"
MAINLINE_INTERFACE_VERSION="$(interface_version_from_product_version "$MAINLINE_VERSION")"

MAINLINE_TEST_VERSION="$(require_version "$MAINLINE_TEST_PRODUCT")"
MAINLINE_TEST_INTERFACE_VERSION="$(interface_version_from_product_version "$MAINLINE_TEST_VERSION")"

INTERFACE_VERSIONS=()
add_unique_interface_version "$MAINLINE_INTERFACE_VERSION"
add_unique_interface_version "$MAINLINE_TEST_INTERFACE_VERSION"

INTERFACE_LINE="## Interface: $(join_interface_versions "${INTERFACE_VERSIONS[@]}")"

echo "${MAINLINE_PRODUCT}: ${MAINLINE_VERSION} -> ${MAINLINE_INTERFACE_VERSION}"
echo "${MAINLINE_TEST_PRODUCT}: ${MAINLINE_TEST_VERSION} -> ${MAINLINE_TEST_INTERFACE_VERSION}"
echo "Expected ${TOC_FILE}: ${INTERFACE_LINE}"

if [[ "$(current_interface_line)" == "$INTERFACE_LINE" ]]; then
    echo "${TOC_FILE} is already current."
    exit 0
fi

if [[ "$CHECK_ONLY" == true ]]; then
    echo "${TOC_FILE} is not current." >&2
    exit 1
fi

TEMPORARY_TOC_FILE="$(mktemp)"
awk -v interface_line="$INTERFACE_LINE" '
    BEGIN { wrote_interface = 0 }

    /^## Interface:/ {
        if (wrote_interface == 0) {
            print interface_line
            wrote_interface = 1
        }
        next
    }

    {
        print
    }
' "$TOC_FILE" > "$TEMPORARY_TOC_FILE"

mv "$TEMPORARY_TOC_FILE" "$TOC_FILE"

echo "${TOC_FILE} written."
