#!/usr/bin/env bash
# ADR-0001 fail-closed guard: PushTextCore is the PURE functional core. It may import Foundation
# domain types only — never AppKit, ApplicationServices, AVFoundation, Speech, FoundationModels or
# CoreGraphics. Those are the side-effect surfaces that belong in PushTextKit, behind a port.
#
# The match must catch attribute-prefixed and submodule import forms, e.g.
# `@preconcurrency import ApplicationServices` and `import AVFoundation.AVAudioEngine`.
# Anchoring on `^import` fails OPEN for exactly those. Match `import` anywhere on the line,
# tolerant of leading attributes and a trailing `.Submodule`.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
core_dir="$root/Sources/PushTextCore"

# No core dir yet = nothing to violate.
[ -d "$core_dir" ] || exit 0

FORBIDDEN='AppKit|ApplicationServices|AVFoundation|Speech|FoundationModels|CoreGraphics|SwiftUI|Cocoa'

if grep -REn "(^|[[:space:]])import[[:space:]]+($FORBIDDEN)([.[:space:]]|$)" "$core_dir"; then
    echo "core-purity: FORBIDDEN import in Sources/PushTextCore/ — system frameworks belong in PushTextKit, behind a port (ADR-0001)" >&2
    exit 1
fi
exit 0
