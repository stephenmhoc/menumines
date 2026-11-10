#!/usr/bin/env bash
# Notarizes and staples a .app, .zip or .dmg, giving every network call a time limit and retrying.
#
# Usage: scripts/notarize.sh <path> <keychain-profile> [staple-target]
#   path            The file to submit. A .app is zipped first, since notarytool takes archives.
#   keychain-profile  A profile saved with `notarytool store-credentials`.
#   staple-target   What to staple the ticket to. Defaults to <path>; a .zip can't be stapled,
#                   so pass the .app it was made from.
#
# Why: the 1.0.24 Direct release hung on "initiating connection to the Apple notary service" for
# the DMG, 30 seconds after the same command notarized the app, and sat there until GitHub
# cancelled the job at 45 minutes. notarytool's own --timeout only covers --wait, not the
# connection, so each attempt runs under a hard limit and a stalled one is retried.

set -euo pipefail

SUBMIT_PATH="${1:?usage: notarize.sh <path> <keychain-profile> [staple-target]}"
PROFILE="${2:?usage: notarize.sh <path> <keychain-profile> [staple-target]}"
STAPLE_TARGET="${3:-$SUBMIT_PATH}"

ATTEMPTS="${NOTARIZE_ATTEMPTS:-3}"
# One attempt: upload plus Apple's processing, which is normally a minute or two.
SUBMIT_LIMIT="${NOTARIZE_SUBMIT_LIMIT:-900}"
STAPLE_LIMIT="${NOTARIZE_STAPLE_LIMIT:-120}"

NOTARYTOOL="$(xcrun --find notarytool)"
STAPLER="$(xcrun --find stapler)"

# Runs a command, killing it after a number of seconds. macOS has no `timeout`; perl's alarm
# survives exec, so the command itself gets SIGALRM (exit status 142) when time is up.
with_limit() {
    local seconds="$1"
    shift
    perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\n"' "$seconds" "$@"
}

if [[ "$SUBMIT_PATH" == *.app ]]; then
    ARCHIVE="$(mktemp -d)/$(basename "$SUBMIT_PATH" .app).zip"
    ditto -c -k --keepParent "$SUBMIT_PATH" "$ARCHIVE"
    SUBMIT_PATH="$ARCHIVE"
fi

submitted=false
for attempt in $(seq 1 "$ATTEMPTS"); do
    echo "Notarizing $(basename "$SUBMIT_PATH"), attempt $attempt of $ATTEMPTS"
    # If Apple rejects the file, stapling below fails for want of a ticket, so a rejection
    # can't slip through whatever notarytool's exit status is.
    status=0
    with_limit "$SUBMIT_LIMIT" "$NOTARYTOOL" submit "$SUBMIT_PATH" \
        --keychain-profile "$PROFILE" \
        --wait \
        --timeout "$((SUBMIT_LIMIT - 60))s" || status=$?
    if [[ "$status" -eq 0 ]]; then
        submitted=true
        break
    fi
    echo "Attempt $attempt didn't finish (exit $status)."
    [[ "$attempt" -lt "$ATTEMPTS" ]] && sleep 20
done
if [[ "$submitted" != true ]]; then
    echo "Notarization failed after $ATTEMPTS attempts." >&2
    exit 1
fi

# The ticket can take a moment to reach Apple's CDN after notarization succeeds.
for attempt in $(seq 1 "$ATTEMPTS"); do
    status=0
    with_limit "$STAPLE_LIMIT" "$STAPLER" staple "$STAPLE_TARGET" || status=$?
    [[ "$status" -eq 0 ]] && exit 0
    echo "Stapling attempt $attempt didn't finish (exit $status)."
    [[ "$attempt" -lt "$ATTEMPTS" ]] && sleep 30
done
echo "Stapling failed after $ATTEMPTS attempts." >&2
exit 1
