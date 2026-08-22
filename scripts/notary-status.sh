#!/usr/bin/env bash
# notary-status.sh - read existing Apple Notary submissions without uploading new artifacts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/notary-auth.sh
source "$ROOT/scripts/lib/notary-auth.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

OUTPUT_FORMAT="${PUSHTEXT_NOTARY_OUTPUT_FORMAT:-json}"
pushtext_notary_prepare_auth "$WORK"

if [ "$#" -eq 0 ]; then
	xcrun notarytool history \
		"${PUSHTEXT_NOTARY_ARGS[@]}" \
		--output-format "$OUTPUT_FORMAT"
	exit 0
fi

for submission_id in "$@"; do
	xcrun notarytool info "$submission_id" \
		"${PUSHTEXT_NOTARY_ARGS[@]}" \
		--output-format "$OUTPUT_FORMAT"
	if [ "${PUSHTEXT_NOTARY_FETCH_LOGS:-0}" = "1" ]; then
		xcrun notarytool log "$submission_id" \
			"${PUSHTEXT_NOTARY_ARGS[@]}" || true
	fi
done
