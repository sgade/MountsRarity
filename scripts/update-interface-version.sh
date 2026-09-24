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
LIVE_PRODUCT="${LIVE_PRODUCT:-wow}"
TEST_PRODUCTS="${TEST_PRODUCTS:-wowt wowxptr wow_beta}"
CHECK_ONLY=false

function usage() {
    cat <<EOF
Usage: $0 [--check]

Updates the WoW Interface metadata in ${TOC_FILE}.

Environment overrides:
  TOC_FILE                    TOC file to update. Default: MountsRarity.toc
  PATCH_ENDPOINT_BASE_URL     Blizzard CDN base URL. Default: http://us.patch.battle.net:1119
  LIVE_PRODUCT                Retail live product slug, used as the version floor. Default: wow
  TEST_PRODUCTS               Space-separated public test/beta product slugs to poll.
                               Default: "wowt wowxptr wow_beta"

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

function get_product_versions() {
    local product="$1"
    local endpoint="${PATCH_ENDPOINT_BASE_URL}/${product}/versions"
    local response

    if ! response="$(curl --fail --silent --show-error --location "$endpoint" 2>/dev/null)"; then
        return 1
    fi

    echo "$response" | awk -F'|' 'NF >= 6 && $1 !~ /^Region/ && $1 !~ /^##/ { print $6 }' | sort -u
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

function require_versions() {
    local product="$1"
    local versions

    if ! versions="$(get_product_versions "$product")" || [[ -z "$versions" ]]; then
        echo "Could not find any versions in Blizzard versions for product '${product}'." >&2
        exit 1
    fi

    echo "$versions"
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

echo "Determining live interface version floor from '${LIVE_PRODUCT}'..."

LIVE_VERSIONS="$(require_versions "$LIVE_PRODUCT")"
LIVE_FLOOR=0
while IFS= read -r version; do
    [[ -z "$version" ]] && continue
    interface_version="$(interface_version_from_product_version "$version")"
    if (( 10#$interface_version > 10#$LIVE_FLOOR )); then
        LIVE_FLOOR="$interface_version"
    fi
done <<< "$LIVE_VERSIONS"

echo "Live interface version floor: ${LIVE_FLOOR}"

INTERFACE_VERSIONS=()

for product in "$LIVE_PRODUCT" $TEST_PRODUCTS; do
    if ! versions="$(get_product_versions "$product")" || [[ -z "$versions" ]]; then
        echo "Skipping product '${product}': no versions reported." >&2
        continue
    fi

    while IFS= read -r version; do
        [[ -z "$version" ]] && continue
        interface_version="$(interface_version_from_product_version "$version")"

        if (( 10#$interface_version < 10#$LIVE_FLOOR )); then
            echo "${product}: ${version} -> ${interface_version} (below live ${LIVE_FLOOR}, discarded)"
            continue
        fi

        echo "${product}: ${version} -> ${interface_version}"
        add_unique_interface_version "$interface_version"
    done <<< "$versions"
done

INTERFACE_LINE="## Interface: $(join_interface_versions "${INTERFACE_VERSIONS[@]}")"

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
