#!/usr/bin/env bash
# Fail-closed guard: every CLASS a SwiftUI view file holds must be `@Observable`.
#
# WHY. `AppActions` owned `updateAvailability` and fed all three update marks, and it was a plain
# `@MainActor final class`. That value is written when Sparkle's passive check comes BACK, seconds
# after the menu has rendered - so SwiftUI was never told, every surface kept drawing `.unknown`,
# and the update indicator could not appear in real use on any of them (#170).
#
# It shipped in #138 and survived that issue's RENDER check, because the probe forced the value
# before the view was built: the screenshot showed a dot and could only ever show a dot. Two
# releases went out with a feature that had never worked once.
#
# Nothing here can catch "the value arrives late". This catches the PRECONDITION - a class feeding a
# view that has no way to notify it - which is the mechanically checkable part.
#
# THIS SCRIPT'S FIRST DRAFT WAS ITSELF FAIL-OPEN, and is why the extraction is checked below: it used
# gawk's `match(s, re, arr)`, which macOS awk does not have. awk errored, printed nothing, the loop
# never iterated, and the gate reported OK with `@Observable` deleted from AppActions. A gate that
# cannot go red is worth less than no gate, because it is trusted.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

views="Sources/PushText"

# Files that declare a SwiftUI view, and the types their stored properties name.
view_files="$(grep -rl ": View {" "$views"/*.swift 2>/dev/null || true)"
if [ -z "$view_files" ]; then
	echo "view-models-are-observable: FAIL - found no SwiftUI view files at all" >&2
	echo "  The extractor is broken, or the views moved. Not reporting OK on an empty search." >&2
	exit 1
fi

types="$(
	# The FULL dotted type, reduced to its last component. Truncating at the FIRST component made
	# this gate report `DictationHUDController` for a property whose type is
	# `DictationHUDController.HUDModel` - and HUDModel is @Observable, so the very first real run
	# was a false positive on correct code. A gate that cries wolf gets switched off.
	# shellcheck disable=SC2086
	grep -hoE '^[[:space:]]+(let|var|@Bindable var) [a-zA-Z_]+: [A-Z][A-Za-z0-9_.]*' $view_files 2>/dev/null \
		| sed -E 's/.*: //' | sed -E 's/.*\.//' | sort -u
)"
if [ -z "$types" ]; then
	echo "view-models-are-observable: FAIL - no stored-property types extracted from the views" >&2
	echo "  Agreement about absence is not success: this reads identically to a broken extractor." >&2
	exit 1
fi

checked=0
bad=""
for type in $types; do
	decl="$(grep -rl "class $type\b" "$views"/*.swift 2>/dev/null | head -1)"
	[ -z "$decl" ] && continue          # a struct, an enum, or a type from another module
	checked=$((checked + 1))
	if ! grep -B6 "class $type\b" "$decl" | grep -q "@Observable"; then
		bad="$bad $type($(basename "$decl"))"
	fi
done

if [ "$checked" -eq 0 ]; then
	echo "view-models-are-observable: FAIL - matched no locally-declared classes to check" >&2
	echo "  Every view holding only structs is possible but unlikely; treat it as a broken match." >&2
	exit 1
fi

if [ -n "$bad" ]; then
	echo "view-models-are-observable: FAIL - a view holds a class that cannot notify it:$bad" >&2
	echo "  Add @Observable, or the view keeps drawing whatever it read at render time." >&2
	echo "  That is #170: the update dot could never appear, and a render check still passed." >&2
	exit 1
fi
echo "view-models-are-observable: OK ($checked view-held classes, all @Observable)"
exit 0
