#!/usr/bin/env bash
# notary-auth.sh - shared Notary credential preparation for PushText scripts.
# shellcheck shell=bash

pushtext_notary_prepare_auth() {
	local work_dir="${1:?work directory required}"

	test -n "${PUSHTEXT_NOTARY_KEY_ID:-}" || {
		echo "notary-auth.sh: PUSHTEXT_NOTARY_KEY_ID is required" >&2
		return 1
	}
	test -n "${PUSHTEXT_NOTARY_ISSUER_ID:-}" || {
		echo "notary-auth.sh: PUSHTEXT_NOTARY_ISSUER_ID is required" >&2
		return 1
	}

	PUSHTEXT_NOTARY_AUTH_KEY_PATH="${PUSHTEXT_NOTARY_KEY_PATH:-}"
	if [ -z "$PUSHTEXT_NOTARY_AUTH_KEY_PATH" ]; then
		test -n "${PUSHTEXT_NOTARY_KEY_P8_BASE64:-}" || {
			echo "notary-auth.sh: PUSHTEXT_NOTARY_KEY_PATH or PUSHTEXT_NOTARY_KEY_P8_BASE64 is required" >&2
			return 1
		}
		mkdir -p "$work_dir"
		PUSHTEXT_NOTARY_AUTH_KEY_PATH="$work_dir/AuthKey.p8"
		printf '%s' "$PUSHTEXT_NOTARY_KEY_P8_BASE64" | base64 --decode > "$PUSHTEXT_NOTARY_AUTH_KEY_PATH"
		chmod 600 "$PUSHTEXT_NOTARY_AUTH_KEY_PATH"
	fi

	test -f "$PUSHTEXT_NOTARY_AUTH_KEY_PATH" || {
		echo "notary-auth.sh: notary key not found: $PUSHTEXT_NOTARY_AUTH_KEY_PATH" >&2
		return 1
	}

	PUSHTEXT_NOTARY_ARGS=(
		--key "$PUSHTEXT_NOTARY_AUTH_KEY_PATH"
		--key-id "$PUSHTEXT_NOTARY_KEY_ID"
		--issuer "$PUSHTEXT_NOTARY_ISSUER_ID"
	)
}
