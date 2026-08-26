#!/usr/bin/env bash
# The shipped icon PNG must be what the SVG source renders to.
#
# WHY: the PNG is what becomes the .icns, and nothing else connects it to the SVG. Editing the source
# and forgetting to re-render ships the OLD icon while the repo shows the new one - a divergence with
# no symptom until somebody looks at the Dock, which is the shape of defect this project keeps
# finding the hard way.
#
# Delegates to the render script rather than repeating the command, so there is one definition of
# "current" (#210).
set -euo pipefail
cd "$(dirname "$0")/../.."
exec scripts/render-icon.sh --check
