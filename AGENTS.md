# Agent Instructions

This is the short core of the repository rules. Read all of it before you act. The detailed
policies are in [`docs/00-project/AGENT_POLICIES.md`](docs/00-project/AGENT_POLICIES.md). They
still apply: read the sections that match the files and the task you touch.

When rules differ, this order decides: first the owner decisions (section 9) and the stop list
(section 6) of
[`docs/00-project/ARCHITECTURE_REVIEW_2026_11_16.md`](docs/00-project/ARCHITECTURE_REVIEW_2026_11_16.md),
then this file, then the detailed policies.

This project uses **bd** (Beads) for issue tracking. Run `bd prime` for current workflow context.

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd export -o .beads/issues.jsonl  # Refresh tracked bead data before committing
```

## What we build, in order

The owner accepted these priorities on 2026-11-16 (review decisions D1, D2 and D4).

1. **`reflaxe.ocaml` 1.0 on upstream Haxe 4.3.7, for a declared scope, is the first product.**
   `reflaxe.ocaml` is the Haxe-to-OCaml target.
2. **`hxhx` milestones, in order:**
   - **F1, frontend parity:** the `hxhx` parser and typer match upstream Haxe 4.3.7, measured by
     the parse and typed oracles in `scripts/oracle/` (beads `haxe_ocaml-7cxgt` and
     `haxe_ocaml-rten2`).
   - **F2, the upstream unit suite on JavaScript:** `hxhx` compiles and passes the upstream
     unit suite for the JavaScript target.
   - **F3, self-hosting:** two native `hxhx` generations build each other, with stage0
     (the installed upstream `haxe`) forbidden.
3. **Full1** (a complete Haxe 4.3.7-equivalent compiler) stays the long-term contract. Do not
   claim it before its evidence exists.

## Stop list

These rules from the review are in force now. Do not start:

1. New semantics in the Stage3 OCaml emitter (`packages/hxhx-core/src/EmitterStage.hx` and
   `packages/hxhx-core/src/backend/ocaml/Stage3Ocaml*.hx`), except what keeps the existing
   macro-plugin path and the bootstrap working. The emitter is deleted after the move to one
   OCaml lowering.
2. New node kinds under `packages/reflaxe.ocaml/src/reflaxe/ocaml/target/`.
3. New feature work on non-JavaScript `hxhx` backends (C++, Cppia, HashLink, Neko, PHP, Lua,
   Python, Java, C#). Fix regressions only.
4. The M22 native-compiler pilot, the broad plugin SDK, compiler customization, Haxe-family
   compiler variations, and the Bend2-inspired dialect (P3 research).
5. New evidence machinery: receipts, collectors, ledgers, policy guards, and proof or digest
   records on individual lowering decisions.
6. Claiming a bead when it is created, or leaving landed work "in progress".
7. Large consolidation merges, unless the owner asks for one.
8. Closing a bead whose title promises more than its closing note delivers. Rename it to the
   delivered scope first.
9. Further whole-project reviews before the parse and typed oracle numbers exist.

Items 3 and 4 hold until F2. No more than three implementation fronts are active at once
(`docs/00-project/NORTH_STAR_GOALS.md`).

## Hard rules

- **Provenance.** Use upstream Haxe only as a behavior oracle. You may read its source to
  understand behavior, but record only behavior-level notes. Never copy, translate, or retype
  upstream compiler source or upstream tests into this repository, its docs, Beads, or commit
  messages. Only upstream standard-library code under `vendor/haxe/std/**` may be reused, under
  `docs/00-project/STD_LIB_POLICY.md`, with notices and the provenance ledger kept current.
  Never commit the upstream checkout. Run `npm run ci:guards` after such changes. Details:
  "Licensing", "Strict provenance rules", "Upstream OCaml Reference".
- **Upstream Haxe 4.3.7 decides behavior.** For a behavior change, write the failing test
  first; if that is not feasible, say why in the bead. When the expected behavior is not
  already certain, check it with upstream `haxe` (for example `--interp`). For a claim of Haxe
  4.3.7 equivalence, upstream suite results are the proof; repo-local tests only support it.
  Details: "Upstream Haxe Source", "Test-First Workflow", "Compatibility Policy".
- **Compiler semantics are written in Haxe.** Handwritten OCaml may own only narrow primitives,
  such as I/O, processes, sockets, native loading, hashing, runtime representation support, and
  toolchain integration. Generated OCaml is an artifact: never edit it by hand. Fix the Haxe
  owner, or the smallest justified handwritten adapter, then regenerate. Keep
  `npm run guard:handwritten-ocaml-ownership` passing. Details: "Keep compiler semantics
  Haxe-authored" under "Thinking Levels".
- **No backward compatibility layers.** Use hard cutovers. Details: "Compatibility Policy".
- **Typed code.** `Any` and `Dynamic` are forbidden except at unavoidable runtime boundaries.
  Details: "Type Safety Rule".

## Beads, tasks, and other agents

- At the start of a task, set or infer its `thinking:*` label and calibrate reasoning effort.
  Details: "Thinking Levels".
- Claim a bead when you start work on it, not when you create it. Close it only when its own
  acceptance criteria and integration evidence are met.
- Write pull-request and bead prose to a file and pass it with `--body-file`, `--file`, or
  stdin, not inside a shell string. Details: "Shell-Safe Issue and Pull-Request Text".
- Never terminate another agent's process without its owner's or the user's authority.
- Change a sibling repository only in a dedicated worktree and pull request. Never push its
  default branch. Details: "Cross-Repository Changes".

## Pull requests

- One independently mergeable Beads task per pull request. Before you start, record its merge
  contract in the bead: outcome, evidence, required checks, and exclusions. Keep the pull
  request description aligned with it. Review the scope when a change passes 500 authored
  lines or 20 authored files. Details: "Bounded Pull Requests".
- Merge on the day the required checks pass. An agent may merge its own pull request, except
  one that changes `AGENTS.md`, the agent policies, or an owner decision; removes, loosens, or
  re-routes a CI check (including its time limits); touches provenance or licensing files; or
  makes a release or version change. Those need the owner's approval on the pull request. The
  owner can delegate that approval for a named pull request or decision. Then quote the owner's
  words and the reviewer's verdict on the pull request before the merge. If unsure, ask.
- "Checks pass" means every required job is green on the head commit. A `Tests` summary job
  that is still queued counts as passed once every other job in its run has succeeded or was
  skipped by the route. Before a self-merge, comment with the head commit, the run link, and
  the bead.
- No required workflow stays red for more than 14 days. Fix it, or the owner disables it with
  a named owner and a re-enable condition recorded in a bead. Apart from that recorded
  decision, never weaken an assertion, disable a check, or hide a regression to make a change
  smaller or green.

## Finishing work

A pull-request task is done when the pull request is merged and you have checked the result on
`main`, or when it is withdrawn or superseded with a recorded reason. A push only preserves the
work. Before you stop:

1. Run the checks for what you changed.
2. Run `bd export -o .beads/issues.jsonl` and commit the result.
3. Push, then follow the pull request through review, checks, and merge.
4. Update or close the bead, and file Beads for remaining work.

Details: "Landing the Plane" and "Artifact Hygiene".

## Where the detailed policies are

`docs/00-project/AGENT_POLICIES.md` has these sections. Some names below are shortened.

| Topic | Sections |
| --- | --- |
| Writing | Documentation Must Teach the Reader; Beginner-Friendly Communication; Documentation (hxdoc); Documentation Quality; README Maintenance; Docs Must Stay Current (README); Repository Docs (README) |
| Tools and shell | Shell-Safe Issue and Pull-Request Text; Verification Efficiency; Tooling And Performance Are Product Features; Artifact Hygiene |
| Reasoning and review | Thinking Levels (Bead Labels). It also holds the Oracle escalation rules, the Haxe-authored semantics rules, and the rules for long-running sessions, shell scripts, target extern stubs, and large files. |
| Scope | Example Coverage Policy; Compatibility Policy; Autonomy Policy; Cross-Repository Changes; Reflaxe Integration Fork; Long-Term Acceptance Example: Haxe-in-Haxe |
| Change flow | Commit Messages; Commit Cadence; Bounded Pull Requests (MANDATORY); Landing the Plane (Session Completion) |
| References | Local Reference Repos; Haxe Library Research First; Haxe-First API Design For Target Layers; Upstream OCaml Reference; Upstream Haxe Source; Sibling Reflaxe Repos Are Pressure Tests |
| Licensing | Licensing (MIT Goal, Keep Private for Now), with its subsections: Permissive-license success criteria; Strict provenance rules; Bootstrap artifacts; "Not a translation" rule |
| Quality | "Spec First"; Test-First Workflow (TDD by default); Bugs (Regression Tests); Type Safety Rule |
| Terms | Beginner-Friendly Terms (Read This First): stage0 to stage3, compiler lanes, library resolution |

Some detailed policies still describe the plan before 2026-11-16, such as compilation-server
work, later product goals, and old model names. Where they conflict with the order above,
follow the order above. `haxe_ocaml-zikyf` tracks their cleanup.
