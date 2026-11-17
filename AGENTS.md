# Agent Instructions

This is the short core of the repository rules. Read all of it before you act. The detailed
policies are in [`docs/00-project/AGENT_POLICIES.md`](docs/00-project/AGENT_POLICIES.md). They
still apply: read the sections that match the files and the task you touch. When a detailed
policy and this core differ, this core and the decisions in
[`docs/00-project/ARCHITECTURE_REVIEW_2026_11_16.md`](docs/00-project/ARCHITECTURE_REVIEW_2026_11_16.md)
apply.

This project uses **bd** (Beads) for issue tracking. Run `bd prime` for current workflow context.

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd export -o .beads/issues.jsonl  # Refresh tracked bead data before committing
```

## What we build, in order

The owner accepted these priorities on 2026-11-16 (architecture review, decisions D1, D2, D4).

1. **`reflaxe.ocaml` 1.0 is the first product.** It is the Haxe 4.3.7 to OCaml target, hosted
   by upstream Haxe and by `hxhx`.
2. **`hxhx` milestones, in order:**
   - **F1, frontend parity:** the `hxhx` parser and typer match upstream Haxe 4.3.7, measured by
     the parse and typed oracles under `scripts/oracle/`.
   - **F2, the upstream unit suite on JavaScript:** `hxhx` compiles and passes the upstream
     unit suite for the JavaScript target.
   - **F3, self-hosting:** two native `hxhx` generations build each other, with stage0
     (the installed upstream `haxe`) forbidden.
3. **Full1** (a complete Haxe 4.3.7-equivalent compiler) stays the long-term contract. Do not
   claim it before its evidence exists.

## Freeze

Until F2, unless the owner approves an exception:

- Add no new semantics to the Stage3 emitter, and no new node kinds in `target/`.
- Non-JavaScript `hxhx` backends (C++, Cppia, HashLink, Neko, PHP, Lua, Python, Java, C#)
  get regression fixes only.
- M22, the SDK, compiler customization, compiler variations, and the hxb dialect are
  deferred.

## Hard rules

- **Provenance.** Never copy, translate, or retype upstream Haxe compiler source or upstream
  tests into this repository, its docs, Beads, or commit messages. Upstream is a black-box
  behavior oracle. Upstream standard-library code under `vendor/haxe/std/**` is permissive
  and can be reused with its notices. Details: "Licensing" and "Strict provenance rules" in
  the policies.
- **Upstream Haxe 4.3.7 decides behavior.** Write the failing test first (TDD), check the
  expected result with upstream `haxe` (for example `--interp`), then fix. A repo-local test
  supports a claim; it does not replace upstream evidence. Details: "Upstream Haxe Source"
  and "Test-First Workflow".
- **Compiler semantics are written in Haxe.** Handwritten OCaml may own only narrow
  primitives (I/O, processes, hashing, runtime representation support). Generated OCaml is
  an artifact: never edit it by hand; fix the Haxe owner and regenerate. Details: "Keep
  compiler semantics Haxe-authored" under "Thinking Levels".
- **No backward compatibility layers.** Use hard cutovers. Details: "Compatibility Policy".
- **Typed code.** `Any` and `Dynamic` are forbidden except at unavoidable runtime
  boundaries. Details: "Type Safety Rule".

## Pull requests

- One independently mergeable Beads task per pull request. Keep it small and merge it the
  same day its checks pass. A consolidation pull request is an exception that needs a
  recorded reason. Details: "Bounded Pull Requests".
- Each pull request states why, what, and the evidence, names its bead, and names the agent
  that prepared it.
- A required workflow that is red for 14 days must be fixed, or disabled with a named owner
  and a re-enable condition.
- Never weaken an assertion, disable a required check, or hide a regression to get a smaller
  or greener change.

## Finishing work

Work is not done until it is pushed. Before you stop, file Beads for remaining work, run the
quality gates for what you changed, and update bead status. Then run:

```bash
git pull --rebase
bd export -o .beads/issues.jsonl
git push
git status  # must show "up to date with origin"
```

Details: "Landing the Plane" and "Artifact Hygiene".

## Where the detailed policies are

`docs/00-project/AGENT_POLICIES.md` has these sections:

| Topic | Sections |
| --- | --- |
| Writing | Documentation Must Teach the Reader; Beginner-Friendly Communication; Documentation (hxdoc); Documentation Quality; README Maintenance; Docs Must Stay Current; Repository Docs |
| Tools and shell | Shell-Safe Issue and Pull-Request Text; Verification Efficiency; Tooling And Performance Are Product Features; Artifact Hygiene |
| Reasoning and review | Thinking Levels (Bead Labels), which also holds the Oracle escalation rules and the Haxe-authored semantics rules |
| Scope | Example Coverage Policy; Compatibility Policy; Autonomy Policy; Cross-Repository Changes; Reflaxe Integration Fork; Long-Term Acceptance Example |
| Change flow | Commit Messages; Commit Cadence; Bounded Pull Requests; Landing the Plane |
| References | Local Reference Repos; Haxe Library Research First; Haxe-First API Design For Target Layers; Upstream OCaml Reference; Upstream Haxe Source; Sibling Reflaxe Repos |
| Licensing | Licensing (MIT Goal); Permissive-license success criteria; Strict provenance rules; Bootstrap artifacts; "Not a translation" rule |
| Quality | Spec First; Test-First Workflow; Bugs (Regression Tests); Type Safety Rule |
| Terms | Beginner-Friendly Terms (stage0 to stage3, compiler lanes, library resolution) |
