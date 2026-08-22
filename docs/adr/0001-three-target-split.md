# ADR-0001: Three-target split with a pure core

Status: accepted
Date: 2026-08-22

## Context

PushText touches an unusual number of system surfaces for an app this small: a CGEvent tap, the
audio engine, the Speech framework, the Foundation Models framework, the pasteboard, synthetic
keyboard events, and three separate TCC permissions. Most of that cannot be exercised in a unit
test, and — for the two macOS 26 frameworks — cannot even be compiled on the development machine
until Xcode 26 is installed.

If the interesting logic lives next to those surfaces, none of it is testable.

## Decision

Three targets:

- **`PushTextCore`** — pure logic. The dictation state machine, the cleanup drift guard, the
  dictionary matcher, the history model. It imports Foundation and nothing else. This is enforced
  fail-closed by `.engine/checks/core-purity.sh`, which greps for forbidden imports and is wired
  into CI. The check tolerates attribute-prefixed and submodule import forms
  (`@preconcurrency import ApplicationServices`, `import AVFoundation.AVAudioEngine`) because
  anchoring on `^import` fails open for exactly those.
- **`PushTextKit`** — one adapter per system capability, each behind a protocol declared in
  `Ports.swift`. UI-free, so it unit-tests.
- **`PushText`** — SwiftUI shell and composition root. All wiring happens in one place.

## Consequences

Good:

- The logic most likely to be wrong — when does the microphone close, is this cleanup safe to use —
  is testable with no OS involved. The state machine has 11 tests and needs no permissions.
- Phase 0 development proceeds on macOS 15.1 against `MockTranscriptionEngine`, with the real
  engine swapped in behind the same protocol once Xcode 26 exists.
- If FB22149971 forces a pivot from streaming to chunked file-based transcription, that is a new
  conformer to `TranscriptionEngine`, not surgery across the app.

Costs:

- A protocol boundary for capabilities that currently have exactly one real implementation each.
  Accepted deliberately: the second implementation is not speculative here — the mock is in use
  today, and a Parakeet engine is a live option.
- Three targets and three test targets is more ceremony than a single-module app.

## Alternatives rejected

**One module.** Simpler, and untestable in exactly the places that matter.

**Two modules (core + app).** The adapters would land in the shell alongside the SwiftUI views,
which is where UI-free system code goes to become untestable.

## Prior art

This mirrors `TermTile`'s `Core` / `Kit` / shell split, including the purity-check script, which
has been running in that project's CI. See `research/05-termtile-blueprint.md`.
