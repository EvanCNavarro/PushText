# Releasing PushText

A release is cut by pushing a `v*` tag. `.github/workflows/release.yml` does everything else:
test, lint, import the signing identity, build, smoke, notarize, staple, package, sign the appcast,
verify that signature, attest provenance, and create the GitHub release.

    git tag v0.1.0 && git push origin v0.1.0

The tag name is the source of the marketing version: `CFBundleShortVersionString` is the tag minus
its leading `v`. `CFBundleVersion` - the number Sparkle actually compares - stays the monotonic
`git rev-list --count`, which is why the workflow checks out with `fetch-depth: 0`.

## What belongs in release notes

They are read by USERS, in two places: the GitHub release body and Sparkle's "What's new" pane, which
appears in the update dialog before anyone has agreed to install. So they answer "what changed for
me?" and nothing else.

**Do NOT include a "Not in this release" section.** 0.2.0 shipped one, listing withdrawn features and
an untested internal code path, and it read to the person being asked to install it as a list of
things that do not work. Bobby: *"what's not in the release is a bad thing to include in the release,
makes no sense."* Unfinished work belongs in `.engine/BACKLOG.md` and the issue tracker, which is
where it already is.

Measurements are worth keeping when they inform a CHOICE the user makes - the cleanup latency numbers
explain why that setting defaults to off. They are not worth keeping as a record of engineering
diligence.

Write `release-notes/<version>.md` **before** tagging. That one file is both the GitHub release body
and the "What's new" pane Sparkle shows. Without it the release still ships, with auto-generated
notes and no Sparkle notes, and the workflow logs a warning.

## Credentials

| name | kind | purpose |
| --- | --- | --- |
| `PUSHTEXT_SIGN_IDENTITY` | variable | exact Keychain identity name; must be a `Developer ID Application` |
| `PUSHTEXT_RELEASE_SIGNING_CERT_P12_BASE64` | secret | the identity, exported (see below) |
| `PUSHTEXT_RELEASE_SIGNING_CERT_PASSWORD` | secret | that `.p12`'s password |
| `PUSHTEXT_NOTARY_KEY_P8_BASE64` | secret | App Store Connect API key |
| `PUSHTEXT_NOTARY_KEY_ID` | secret | its key id |
| `PUSHTEXT_NOTARY_ISSUER_ID` | secret | its issuer id |
| `SPARKLE_ED_PRIVATE_KEY` | secret | signs the appcast |
| `VIRUSTOTAL_API_KEY` | secret | optional; the scan step skips cleanly without it |

## Exporting the signing certificate

Run `scripts/export-signing-cert.sh`. It exports the Developer ID identity, checks the `.p12`
actually contains both the certificate and its private key, sets both GitHub secrets, and deletes
the `.p12` and its password. The password is generated at random inside the script and never
printed.

**A human has to run this, not an agent.** `security export` raises a Keychain dialog, and the
password it wants is the **Mac login password** - the one that unlocks this Mac. It is *not* the
Apple ID password, and Keychain will never accept the Apple ID one. If the Mac login password is
also refused, the login keychain has come unsynced from the account password (this happens after a
password reset done through Apple ID); the keychain still wants the *old* password, and Keychain
Access > Edit > Change Password for Keychain "login" is where that gets repaired.

This procedure is written down because the equivalent secrets were set on a sibling project on
2026-07-15 and only their *names* were recorded. The knowledge left with the session, and the next
release had to rediscover it.

## Why ad-hoc signing is not acceptable for a release

macOS TCC grants bind to the app's designated code requirement. For an ad-hoc build that
requirement is the per-build cdhash, so an update can leave System Settings showing PushText as
enabled for Accessibility or Input Monitoring while the new binary is silently denied. `build-app.sh`
keeps an ad-hoc fallback so a fresh clone can build; release CI refuses it.

## The appcast signature is verified, not assumed

The release signs the archive with `SPARKLE_ED_PRIVATE_KEY`; clients verify with the `SUPublicEDKey`
compiled into `Info.plist`. Those are set in different places and nothing inherently connects them,
so `scripts/verify-appcast-signature.sh` checks the generated appcast the way a client will, before
the release is created.

`sign_update --verify` cannot do this job: it derives the public key from the private key it is
handed, so it agrees with itself no matter which key that is. The check has to come from the built
app's own plist.

Verified 2026-08-23: the Sparkle private key in the login Keychain signs a payload that validates
against the `SUPublicEDKey` currently baked in by `build-app.sh`, and the verifier rejects a
tampered archive, a mismatched public key, a missing public key, and a signature belonging to a
different appcast item.
