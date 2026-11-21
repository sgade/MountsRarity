#!/usr/bin/env bash
#
#  MountsRarity/scripts/update-interface-version.sh
#
#  Copyright (c) 2026 Sören Gade
#  For the full license, see the LICENSE file.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/output.sh
source "$SCRIPT_DIR/lib/output.sh"

TOC_FILE="${TOC_FILE:-MountsRarity.toc}"
PATCH_ENDPOINT_BASE_URL="${PATCH_ENDPOINT_BASE_URL:-http://us.patch.battle.net:1119}"
LIVE_PRODUCT="${LIVE_PRODUCT:-wow}"
TEST_PRODUCTS="${TEST_PRODUCTS:-wowt wowxptr wow_beta}"
FOREVER_LIVE_PRODUCT="${FOREVER_LIVE_PRODUCT:-wowf}"
FOREVER_TEST_PRODUCTS="${FOREVER_TEST_PRODUCTS:-}"
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
  FOREVER_LIVE_PRODUCT        Forever live product slug, used as the version floor. Default: wowf
  FOREVER_TEST_PRODUCTS       Space-separated public Forever test product slugs to poll.
                               Default: none
  NO_PROGRESS                 If set, do not show progress in an interactive terminal.

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

if [[ ! -f "$TOC_FILE" ]]; then
    echo "TOC file not found: $TOC_FILE" >&2
    exit 1
fi

VERSIONS_DIR="$(mktemp -d)"
on_exit "rm -rf '$VERSIONS_DIR'"

function download_product_versions() {
    curl --fail --silent --show-error --location --max-time 60 "${PATCH_ENDPOINT_BASE_URL}/$1/versions"
}

# Writes the versions of a product from its downloaded file.
# Returns 1 if the download failed.
function get_product_versions() {
    local product="$1"

    [[ "$(bg_status_of "$product")" == "0" ]] || return 1

    awk -F'|' 'NF >= 6 && $1 !~ /^Region/ && $1 !~ /^##/ { print $6 }' "$VERSIONS_DIR/$product" | sort -u
}

function interface_version_from_product_version() {
    local product_version="$1"
    local semantic_version="${product_version%.*}"
    local major minor patch

    IFS='.' read -r major minor patch <<< "$semantic_version"

    if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ || ! "$patch" =~ ^[0-9]+$ ]]; then
        log_error "Could not parse WoW product version: $product_version"
        exit 1
    fi

    printf "%d%02d%02d" "$major" "$minor" "$patch"
}

function require_versions() {
    local product="$1"
    local versions

    if ! versions="$(get_product_versions "$product")" || [[ -z "$versions" ]]; then
        log_error "Could not find any versions in Blizzard versions for product '${product}'."
        print_file "$VERSIONS_DIR/$product.err" >&2
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

# Each game has its own version numbers, so each one needs its own floor.
function collect_interface_versions() {
    local live_product="$1"
    local test_products="$2"
    local live_versions live_floor version interface_version product versions

    log "Determining live interface version floor from '${live_product}'..."

    live_versions="$(require_versions "$live_product")"
    live_floor=0
    while IFS= read -r version; do
        [[ -z "$version" ]] && continue
        interface_version="$(interface_version_from_product_version "$version")"
        if (( 10#$interface_version > 10#$live_floor )); then
            live_floor="$interface_version"
        fi
    done <<< "$live_versions"

    log "Live interface version floor: ${live_floor}"

    for product in "$live_product" $test_products; do
        if ! versions="$(get_product_versions "$product")" || [[ -z "$versions" ]]; then
            log_error "Skipping product '${product}': no versions reported."
            continue
        fi

        while IFS= read -r version; do
            [[ -z "$version" ]] && continue
            interface_version="$(interface_version_from_product_version "$version")"

            if (( 10#$interface_version < 10#$live_floor )); then
                log "${product}: ${version} -> ${interface_version} (below live ${live_floor}, discarded)"
                continue
            fi

            log "${product}: ${version} -> ${interface_version}"
            add_unique_interface_version "$interface_version"
        done <<< "$versions"
    done
}

progress_indeterminate

# The products do not depend on each other, so download all of them at the same time.
# Each product is downloaded one time, also if it is in more than one list.
PRODUCTS=" "
for product in $LIVE_PRODUCT $TEST_PRODUCTS $FOREVER_LIVE_PRODUCT $FOREVER_TEST_PRODUCTS; do
    case "$PRODUCTS" in
        *" $product "*) ;;
        *) PRODUCTS+="$product " ;;
    esac
done

# shellcheck disable=SC2086 # One product for each word.
step "Downloading versions for products:" $PRODUCTS
for product in $PRODUCTS; do
    bg_start "$product" "Downloading versions..." "$VERSIONS_DIR/$product" download_product_versions "$product"
done
bg_wait 0 90

INTERFACE_VERSIONS=()

group_start "Retail"
collect_interface_versions "$LIVE_PRODUCT" "$TEST_PRODUCTS"
group_end

group_start "Forever"
collect_interface_versions "$FOREVER_LIVE_PRODUCT" "$FOREVER_TEST_PRODUCTS"
group_end

INTERFACE_LINE="## Interface: $(join_interface_versions "${INTERFACE_VERSIONS[@]}")"

log "Expected ${TOC_FILE}: ${INTERFACE_LINE}"

if [[ "$(current_interface_line)" == "$INTERFACE_LINE" ]]; then
    log "${TOC_FILE} is already current."
    exit 0
fi

if [[ "$CHECK_ONLY" == true ]]; then
    log_error "${TOC_FILE} is not current."
    exit 1
fi

TEMPORARY_TOC_FILE="$VERSIONS_DIR/toc"
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

# Use cat, not mv: the TOC file keeps its permissions.
cat "$TEMPORARY_TOC_FILE" > "$TOC_FILE"

log "${TOC_FILE} written."
