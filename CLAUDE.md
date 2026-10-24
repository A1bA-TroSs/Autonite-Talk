# Autunite (working name)

An iPhone in-person conversation coach. The product docs at the repo root are the source of truth. Read them before changing code:

- `INTENTIONAL.md`: behavior rules (requirements)
- `IMPLEMENTATION_BLUEPRINT.md`: screens, records and acceptance checks
- `DESIGN.md`: visual rules and tokens
- `CLAUDE_CODE_HANDOFF.md`: the pass plan

Current pass: **Pass 0, feasibility**. See `docs/PASS0_FEASIBILITY.md`. Don't start Pass 1 until its decision gate has device evidence.

## Layout

- `Sources/AutoniteCore`: Foundation-only logic (attribution, gate, latency, report). Test with `swift test` on a Mac.
- `Sources/Autonite`: the SwiftUI app (Speech, AVFoundation, Core Haptics). Build with `xtool dev` on a Mac with Xcode 26+ and a USB-connected iPhone.

## Rules

- Never fire a live cue on speech that isn't confidently attributed to the user (`CueGate`).
- Never store raw audio by accident, and never write to Calendar without an explicit user save.
- Don't claim something works unless it ran on a device. State what is unverified.
- Danny's ontology vault (`~/projects/ontology-vault`) applies to all work here. Consult it before substantive work and record his decisions with `domain: autunite`, as the `operating-ontology-vault` skill describes.
