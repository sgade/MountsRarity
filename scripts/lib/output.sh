# shellcheck shell=bash
#
#  MountsRarity/scripts/lib/output.sh
#
#  Copyright (c) 2026 Sören Gade
#  For the full license, see the LICENSE file.
#
#  Output and background job helpers for the scripts. Source this file, do not run it.
#
#  In an interactive terminal, the helpers show the progress with OSC 9;4 codes, with
#  one status line that updates, and with one line for each background job. In CI (or
#  without a terminal), all output is plain, linear text. Set NO_PROGRESS to always
#  use the plain output.
#
#  The code must work with Bash 3.2, because macOS has this version in /bin/bash.
#

OUTPUT_INTERACTIVE=false
if [[ -t 2 && -z "${CI:-}" && -z "${NO_PROGRESS:-}" && "${TERM:-dumb}" != "dumb" ]]; then
    OUTPUT_INTERACTIVE=true
fi

# Only the top-level script sets the OSC progress. A script that it starts (for example
# update-rarities.sh for one client) must not change or clear the progress of its parent.
OUTPUT_OWNS_PROGRESS=false
if [[ "$OUTPUT_INTERACTIVE" == true && -z "${OUTPUT_PROGRESS_OWNER:-}" ]]; then
    OUTPUT_OWNS_PROGRESS=true
    export OUTPUT_PROGRESS_OWNER="$$"
fi

OUTPUT_STATUS_SHOWN=false
OUTPUT_CURSOR_HIDDEN=false
OUTPUT_EXIT_COMMANDS=""

BG_PIDS=()
BG_NAMES=()
BG_STATUS=()
BG_STEP_FILES=()
BG_STARTED=()
BG_ENDED=()

# --- Progress (OSC 9;4) -------------------------------------------------------

function progress_osc() {
    [[ "$OUTPUT_OWNS_PROGRESS" == true ]] || return 0
    printf '\033]9;4;%s;%s\a' "$1" "$2" >&2
}

# Sets the progress to a percentage (0-100).
function progress_set() {
    progress_osc 1 "$1"
}

# Shows that work occurs, but without a known percentage.
function progress_indeterminate() {
    progress_osc 3 0
}

function progress_clear() {
    progress_osc 0 0
}

# --- Text output --------------------------------------------------------------

# Shows a temporary status line. The next output replaces it.
# Without an interactive terminal, this does nothing.
function status() {
    [[ "$OUTPUT_INTERACTIVE" == true ]] || return 0
    printf '\r\033[K%s' "$*" >&2
    OUTPUT_STATUS_SHOWN=true
}

function status_clear() {
    [[ "$OUTPUT_STATUS_SHOWN" == true ]] || return 0
    printf '\r\033[K' >&2
    OUTPUT_STATUS_SHOWN=false
}

# Writes a line that stays in the output.
function log() {
    status_clear
    echo "$*"
}

# Writes an error line to stderr.
function log_error() {
    status_clear
    echo "$*" >&2
}

# Writes a step of the work. In an interactive terminal, the step is a status line
# that the next output replaces. In CI, the step is a line that stays in the log.
# In a background job, the step also goes to the line of the job in the job display.
function step() {
    if [[ -n "${OUTPUT_STEP_FILE:-}" ]]; then
        printf '%s\n' "$*" > "$OUTPUT_STEP_FILE" 2> /dev/null || true
    fi

    if [[ "$OUTPUT_INTERACTIVE" == true ]]; then
        status "$*"
    else
        log "$*"
    fi
}

# Writes a warning. GitHub Actions shows it as an annotation.
function warn() {
    status_clear
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo "::warning::$*"
    else
        echo "Warning: $*" >&2
    fi
}

# Starts a group of lines. GitHub Actions can collapse the group.
function group_start() {
    status_clear
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo "::group::$*"
    else
        echo "== $* =="
    fi
}

function group_end() {
    status_clear
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo "::endgroup::"
    fi
}

# Prints the contents of a file, if the file exists and is not empty.
function print_file() {
    [[ -s "$1" ]] || return 0
    status_clear
    cat "$1"
}

function cursor_hide() {
    printf '\033[?25l' >&2
    OUTPUT_CURSOR_HIDDEN=true
}

function cursor_show() {
    [[ "$OUTPUT_CURSOR_HIDDEN" == true ]] || return 0
    printf '\033[?25h' >&2
    OUTPUT_CURSOR_HIDDEN=false
}

# --- Background jobs ----------------------------------------------------------
#
# Use background jobs for independent work, for example downloads. A job does not
# write to the terminal: its stdout goes to a file and its stderr to "<file>.err".
# Thus, the output stays in a known order, also when the jobs run at the same time.
# A job can call "step" to show what it does at the moment.

function bg_reset() {
    BG_PIDS=()
    BG_NAMES=()
    BG_STATUS=()
    BG_STEP_FILES=()
    BG_STARTED=()
    BG_ENDED=()
}

# Runs in the background process. The job has no terminal, so it uses the plain output.
function bg_job() {
    OUTPUT_INTERACTIVE=false
    OUTPUT_OWNS_PROGRESS=false
    OUTPUT_STATUS_SHOWN=false
    OUTPUT_CURSOR_HIDDEN=false
    export OUTPUT_STEP_FILE="$1"
    shift
    trap - EXIT INT TERM

    "$@"
}

# Usage: bg_start <name> <description> <output file> <command> [<argument>...]
# The description is the first text on the line of the job, until the job calls "step".
function bg_start() {
    local name="$1"
    local description="$2"
    local output_file="$3"
    shift 3

    printf '%s\n' "$description" > "$output_file.step"
    bg_job "$output_file.step" "$@" < /dev/null > "$output_file" 2> "$output_file.err" &

    BG_PIDS+=("$!")
    BG_NAMES+=("$name")
    BG_STATUS+=("")
    BG_STEP_FILES+=("$output_file.step")
    BG_STARTED+=("$SECONDS")
    BG_ENDED+=("")
}

# Records the exit code of job $1, if the job has stopped.
function bg_poll() {
    local i="$1"

    [[ -z "${BG_STATUS[i]}" ]] || return 0
    kill -0 "${BG_PIDS[i]}" 2> /dev/null && return 0

    if wait "${BG_PIDS[i]}"; then
        BG_STATUS[i]=0
    else
        BG_STATUS[i]=$?
    fi
    BG_ENDED[i]="$SECONDS"
}

# Waits for all started jobs and records their exit codes.
# Usage: bg_wait [<progress at start> <progress at end>]
function bg_wait() {
    local progress_from="${1:-0}"
    local progress_to="${2:-100}"
    local total="${#BG_PIDS[@]}"
    local i

    if [[ "$OUTPUT_INTERACTIVE" == true ]]; then
        bg_wait_live "$progress_from" "$progress_to"
        return
    fi

    for ((i = 0; i < total; i++)); do
        [[ -n "${BG_STATUS[i]}" ]] && continue

        if wait "${BG_PIDS[i]}"; then
            BG_STATUS[i]=0
        else
            BG_STATUS[i]=$?
        fi
        BG_ENDED[i]="$SECONDS"
    done
}

# Shows one line for each job, with the current step of the job, until all jobs stop.
# Then it removes the lines, so the next output is the same as in CI.
function bg_wait_live() {
    local progress_from="$1"
    local progress_to="$2"
    local total="${#BG_PIDS[@]}"
    local name_width=0 columns=80 frame=0 done_count=0 drawn=false
    local i symbol text elapsed line size
    local frames symbol_done symbol_failed

    [[ "$total" -gt 0 ]] || return 0

    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*)
            frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
            symbol_done="✓"
            symbol_failed="✗"
            ;;
        *)
            frames=("-" "\\" "|" "/")
            symbol_done="+"
            symbol_failed="x"
            ;;
    esac

    for ((i = 0; i < total; i++)); do
        if [[ ${#BG_NAMES[i]} -gt $name_width ]]; then
            name_width=${#BG_NAMES[i]}
        fi
    done

    # A line that is wider than the terminal wraps, and then the lines cannot be redrawn.
    size="$(stty size < /dev/tty 2> /dev/null || true)"
    if [[ "${size##* }" =~ ^[0-9]+$ && "${size##* }" -gt 10 ]]; then
        columns="${size##* }"
    fi

    status_clear
    cursor_hide

    while true; do
        done_count=0
        for ((i = 0; i < total; i++)); do
            bg_poll "$i"
            [[ -n "${BG_STATUS[i]}" ]] && done_count=$((done_count + 1))
        done

        if [[ "$drawn" == true ]]; then
            printf '\033[%dA' "$total" >&2
        fi

        for ((i = 0; i < total; i++)); do
            if [[ -z "${BG_STATUS[i]}" ]]; then
                symbol="${frames[frame % ${#frames[@]}]}"
                text=""
                read -r text < "${BG_STEP_FILES[i]}" 2> /dev/null || true
                # The name is already at the start of the line.
                text="${text#"[${BG_NAMES[i]}] "}"
                elapsed=$((SECONDS - BG_STARTED[i]))
                text="$text (${elapsed}s)"
            elif [[ "${BG_STATUS[i]}" -eq 0 ]]; then
                symbol="$symbol_done"
                text="Done ($((BG_ENDED[i] - BG_STARTED[i]))s)"
            else
                symbol="$symbol_failed"
                text="Failed with exit code ${BG_STATUS[i]}"
            fi

            printf -v line '  %s %-*s  %s' "$symbol" "$name_width" "${BG_NAMES[i]}" "$text"
            printf '\r\033[K%s\n' "${line:0:columns-1}" >&2
        done
        drawn=true

        progress_set $((progress_from + (progress_to - progress_from) * done_count / total))

        [[ "$done_count" -lt "$total" ]] || break

        sleep 0.1
        frame=$((frame + 1))
    done

    # Show the final state for a moment, then remove the lines.
    sleep 0.3
    printf '\033[%dA\r\033[J' "$total" >&2
    cursor_show
}

# Writes the exit code of the job with the given name.
function bg_status_of() {
    local i

    for ((i = 0; i < ${#BG_NAMES[@]}; i++)); do
        if [[ "${BG_NAMES[i]}" == "$1" ]]; then
            echo "${BG_STATUS[i]}"
            return 0
        fi
    done

    return 1
}

# --- Cleanup ------------------------------------------------------------------

# Adds a command that runs when the script stops, also after an error.
function on_exit() {
    OUTPUT_EXIT_COMMANDS+="$1"$'\n'
}

function output_on_exit() {
    local pids

    pids="$(jobs -p)"
    if [[ -n "$pids" ]]; then
        # shellcheck disable=SC2086 # One PID for each word.
        kill $pids 2> /dev/null || true
    fi

    eval "$OUTPUT_EXIT_COMMANDS" || true
    status_clear
    cursor_show
    progress_clear
}

trap output_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
