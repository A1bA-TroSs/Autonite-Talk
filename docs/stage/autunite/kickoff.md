You are building Autunite Pass 1: Korea-first register reading in this repository, one phase at a time. This session is phase {{PHASE}}.

Read `{{PKG}}/SPEC.md`, `{{PKG}}/PLAN.md`, `{{PKG}}/phases.json` (your phase's goal, constraints, check and handoff) and `{{PKG}}/progress.md`. Product rules live at the repo root: `INTENTIONAL.md`, `IMPLEMENTATION_BLUEPRINT.md` and `DESIGN.md` (the design scheme is settled; do not redesign it). Then inspect the repository's existing conventions before changing code.

Your phase is finished when its `check` command passes; the runner executes it after you stop and sends you its output if it fails. When the phase's work is in place, mark its features in `{{PKG}}/features.json` (`passes` only), add one line to `{{PKG}}/progress.md` saying what you did and what the next phase should know, and stop.

Scope: do only this phase. Do not start later phases, add features or refactors that SPEC.md does not ask for, or edit SPEC.md, PLAN.md, phases.json or the check. If the phase cannot be done within its constraints, write why in progress.md and stop; do not work around a constraint.

Subagents: use at most two, only for independent searches or reads.

When you stop, end with three short lines: what changed, what ran, what is not verified.
