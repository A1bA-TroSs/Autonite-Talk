# Autunite (working name)

An iPhone in-person conversation coach. The product docs at the repo root are the source of truth. Read them before changing code:

- `INTENTIONAL.md`: behavior rules (requirements)
- `IMPLEMENTATION_BLUEPRINT.md`: screens, records and acceptance checks
- `DESIGN.md`: visual rules and tokens
- `CLAUDE_CODE_HANDOFF.md`: the pass plan

Current pass: **Pass 0, feasibility**. See `docs/PASS0_FEASIBILITY.md`. Don't start Pass 1 until its decision gate has device evidence.

## Layout

- `Sources/AutoniteCore`: Foundation-only logic (attribution, gate, latency, report). Test with `swift test` on a Mac.
- `Sources/Autonite`: the SwiftUI app (Speech, AVFoundation, Core Haptics). Build with xtool (`xtool dev build`, `xtool dev`), never an `.xcodeproj`. On a Mac, xtool needs Xcode installed for the SDK only. Validate with the `ios-xtool` skill's `xtkit.py check` and `simtest` first.

## Rules

- Never fire a live cue on speech that isn't confidently attributed to the user (`CueGate`).
- Never store raw audio by accident, and never write to Calendar without an explicit user save.
- Don't claim something works unless it ran on a device. State what is unverified.
- Danny's ontology vault (`~/projects/ontology-vault`) applies to all work here. Consult it before substantive work and record his decisions with `domain: autunite`, as the `operating-ontology-vault` skill describes.

## Vault connection (required, every session)

Connecting to the vault is the first step of every session, before research, code or a report. It is not optional and must not be skipped silently.

1. Load the `operating-ontology-vault` skill.
2. Reach the vault on Danny's Mac (`/Users/younseopark/projects/ontology-vault`):
   - **Cloud or thread session:** use folder access to `/Users/younseopark/projects` (`list_devices`, then `device_request_folder_access`). If there are no folder tools, call `connect_device` and wait for Danny's answer. Git in the vault also needs delete permission on that folder.
   - **On the Mac:** `cd ~/projects/ontology-vault`.
3. Run `./vault status`, then read `07 Self/07.00 Profile.md` and `~/projects/AGENTS.md`.
4. Log decisions, corrections and principles to `05 Log/05.03 Verdict/` with `domain: autunite`. Get ids from `./vault next-id`, and commit with an `Actor: claude` trailer.
5. If the vault still can't be reached, tell Danny in your first reply, before doing the work. Use the skill's capture-block fallback, and log the capture once the vault is reachable.
