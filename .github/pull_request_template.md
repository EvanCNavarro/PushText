# Pull Request

## Summary

- 

## Verification

- [ ] `swift build && swift test && swiftlint --strict`
- [ ] `.engine/checks/core-purity.sh` (ADR-0001)
- [ ] `scripts/build-app.sh && scripts/test-packaged-app.sh` when packaging, Info.plist, or signing changed
- [ ] Evidence attached when behaviour changed — a real app receiving real text, not a green suite

## Claims

- [ ] Every macOS 26 claim is marked as documentation-derived, or was actually run on Tahoe
- [ ] No number in the description or commit message that wasn't read off a run in this change

## Security notes

- [ ] No secrets, tokens, `.env`, `.env.*`, `.dev.vars`, or `.dev.vars.*` values were committed
- [ ] Workflow permission or dependency changes are explained
- [ ] Permission surface unchanged, or the change is justified here (never Input Monitoring)
