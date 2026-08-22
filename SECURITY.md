# Security Policy

## Supported versions

The **latest [release](https://github.com/EvanCNavarro/PushText/releases/latest)** is the supported
line. Fixes ship in a new release; there are no back-ported patch branches.

## Reporting a vulnerability

Please report privately via a
[GitHub security advisory](https://github.com/EvanCNavarro/PushText/security/advisories/new) rather
than a public issue. Include affected version, reproduction steps, and the impact (what an attacker
gains). You'll get an acknowledgement and, once fixed, a released version.

## What PushText can and can't touch

PushText is a dictation tool, so its permission set is broad by nature and worth stating plainly.

It records **microphone audio** while the dictation key is held, and only while it is held. It uses
the macOS **Accessibility** and **PostEvent** services to read which application has focus and to
send a synthetic paste keystroke into it. It writes the transcribed text to the **pasteboard** for
the duration of that paste, then restores the previous contents.

It does **not** log keystrokes, read the contents of other applications' windows, or read files.

**It deliberately does not request Input Monitoring.** `CGRequestListenEventAccess` is a permission
request rather than a detection mechanism, and the OS's own `TCCServiceList.plist` marks that service
`requiresAdmin`, while Accessibility carries no such flag.

Transcription and text cleanup both run on-device. **The app makes no network request except the
signed update check** against this repo's Sparkle appcast. There is no telemetry, and no audio or
transcript ever leaves the machine.

## The pasteboard, specifically

Insertion uses the pasteboard rather than an Accessibility text write, because AX writes report
success while silently doing nothing in Electron apps, browsers and several native apps. The
consequence is that the user's clipboard is briefly replaced. PushText captures
`NSPasteboard.changeCount` before writing and restores the prior contents only if nothing else
claimed the pasteboard in between — a concurrent writer wins rather than being clobbered.

## Supply-chain integrity

- **Releases are built by this repo's GitHub Actions**, not a personal machine.
- **Build provenance attestation** — verify a download came from this repo's CI untampered:
  `gh attestation verify PushText-<version>.zip --repo EvanCNavarro/PushText`.
- **SHA-256** checksum published beside each release zip.
- **Developer ID signed** public releases keep a stable Apple code identity, so macOS TCC grants
  survive updates. Ad-hoc signing rebinds every grant to a per-build cdhash and silently resets them.
- **Notarized and stapled** before the release zip is created.
- **EdDSA-signed auto-updates** — Sparkle refuses an update whose signature doesn't verify against
  the public key baked into the app.
- **Dependabot** keeps CI action versions current; **Semgrep** (`p/security-audit`, `p/secrets`) and
  **SwiftLint** run on every push.

## Known limitations

Apple Silicon only. Speech recognition requires macOS 26; the on-device cleanup model additionally
requires Apple Intelligence to be enabled, and the app runs with cleanup disabled when it is not.
