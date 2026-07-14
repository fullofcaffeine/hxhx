# Full1 Macro/Eval Evidence Decision

Last reviewed: 2026-07-14

This decision explains how `hxhx` decides whether the Full1 macro and
compile-time execution check passed. It is written for readers who are new to
the compiler.

In plain language, a green GitHub job is not the proof itself. The job must
also upload a small, machine-readable receipt that says what ran, which exact
`hxhx` commit ran it, and which required checks passed. The combined Full1
check must open those receipts before it reports success.

Owning bead: `haxe_ocaml-vhk47.4`.

## The Problem

The macro and native-eval workflows already upload useful files. However,
their summary jobs currently create pass markers from GitHub job-status
strings such as `success`.

That leaves an avoidable trust gap:

- a child job can be green while its expected receipt is absent or malformed;
- a receipt can accidentally belong to another commit or workflow attempt;
- the top-level Full1 workflow can repeat a macro/eval pass marker without
  opening either proof package.

The exact-commit runs below show that the compiler behavior is currently
green, but they do not repair that aggregation gap by themselves:

- Macro Runtime Parity run `29350539265` at commit `b2277951`.
- Full1 / Eval Native run `29350537630` at the same commit.

## Chosen Trust Flow

```text
in-process macro proof ----\
external-host macro proof --+--> verified macro summary --\
project macro proof --------/                              \
                                                            +--> verified macro/eval summary
native eval proof ------------------------------------------/
                                                                    |
                                                                    v
                                                         Gate Full1 may emit
                                                   FULL1_MACRO_EVAL_PARITY:PASS
```

Each arrow means “open and validate the uploaded files.” It does not mean
“trust the previous job's green status.”

The implementation will use four layers:

1. The existing macro jobs upload their mode-specific and project-macro proof
   packages.
2. The macro summary job downloads those packages and builds a new verified
   macro summary.
3. A focused Macro/Eval workflow runs the macro and native-eval workflows,
   downloads both verified summaries, and builds one combined summary.
4. Gate Full1 reuses the focused workflow and opens its combined summary before
   repeating the aggregate marker.

The prepublication RC collector will continue to verify GitHub's outer
artifact ZIP digest. It will also understand the upgraded macro and eval
summary schemas. This keeps archive provenance in the release layer while the
focused workflow validates the meaning of the files inside each archive.

## What the Macro Summary Must Prove

The macro summary may emit `FULL1_MACRO_PARITY:PASS` only when all three proof
packages are present and valid:

- **in-process mode:** compile-time code ran inside the main `hxhx` process;
- **external-host mode:** compile-time code ran in the reusable helper process,
  with its candidate-bound host receipt and protocol handshake;
- **project macro module:** one Haxe-authored project macro was generated,
  authenticated, loaded, and executed through both native modes.

For every package, the validator checks:

- the exact 40-character candidate commit;
- the GitHub run ID and run attempt where available;
- the expected evidence schema;
- the required stage0-forbidden/pass markers;
- the relevant receipt or timing-summary file hash;
- and the absence of synthetic evidence.

GitHub's matrix result remains useful diagnostic information and a fail-safe
control. It cannot create a pass marker by itself.

## What the Native-Eval Summary Must Prove

The native-eval summary will move from schema
`full1-eval-native-summary.v1` to `full1-eval-native-summary.v2`. The upgraded
summary must include:

- `synthetic: false`;
- the exact candidate commit;
- the run ID and run attempt;
- the pinned upstream Haxe oracle ref (`4.3.7`);
- `stage0_forbidden: true`;
- a zero process exit code;
- and `FULL1_EVAL_NATIVE:PASS`.

The runner will still work locally. Local evidence can use a clearly labeled
local run identity, but only a positive GitHub run ID and attempt may satisfy a
Full1 candidate workflow.

## What the Combined Summary Must Prove

The focused workflow will emit a
`full1-macro-eval-summary.v1` receipt. It may contain
`FULL1_MACRO_EVAL_PARITY:PASS` only when:

- the macro summary and eval summary are both authentic, not synthetic;
- both summaries name the same candidate commit, run ID, and attempt as the
  focused workflow;
- the macro summary contains both required macro markers;
- the eval summary contains `FULL1_EVAL_NATIVE:PASS`;
- and the validator records hashes of both input summaries.

Gate Full1 will download this exact combined receipt. Its own macro/eval marker
will come from the validated receipt, not from the reusable workflow's result
string.

## Fail-Closed Cases

Network-free fixture tests must reject at least these cases:

- a missing proof package or summary;
- malformed JSON or the wrong schema;
- a different candidate commit;
- a different run ID or attempt;
- `synthetic: true`;
- a missing required marker;
- a false stage0-forbidden claim;
- a failed child workload;
- a changed file whose recorded SHA-256 no longer matches;
- and a duplicate summary where exactly one is required.

“Fail closed” means the validator writes no pass marker and exits with an
error. It must not guess that a green job probably produced the right files.

## Alternatives Considered

### Keep trusting job-status strings

Rejected. This is simple, but it does not satisfy the parent bead or the Full1
release evidence model. A status says that a command exited successfully; it
does not describe or authenticate the result.

### Fix only the final RC collector

Rejected as incomplete. The RC collector already verifies artifact ZIP
digests, but normal Gate Full1 summaries would still be able to overstate what
they inspected. Every public aggregate marker should be honest at the layer
that emits it.

### Make the focused workflow call the GitHub API directly

Rejected for this layer. `actions/download-artifact` can retrieve artifacts
from the same workflow run without extra token/API code. The final RC collector
already owns the stricter GitHub API identity and ZIP-digest checks.

## XHIGH Second-Pass Review Before Implementation

The trust chain was re-read from the leaf proof files through Gate Full1 and
the prepublication RC collector. The following corrections were made before
implementation:

1. A matrix/job result may block a pass but may never create a pass marker.
2. The macro aggregate must validate all three proof shapes, including the new
   project-macro receipt; validating only the existing macro summary would
   preserve the original gap.
3. The eval summary itself must carry candidate and run identity. Relying only
   on a neighboring timing file would make the pass receipt ambiguous when
   copied out of its artifact bundle.
4. Gate Full1 must open the combined receipt. Merely replacing two reusable
   jobs with one reusable job would still trust a result string.
5. The RC collector remains responsible for GitHub artifact ZIP identity and
   digest. The focused validators record content hashes but do not duplicate
   the network/provenance collector.
6. The focused workflow is the remote proof surface, so this change does not
   require running unrelated targets, suites, plugin, or performance gates.
7. The new workflow nesting must be verified on GitHub because local YAML
   parsing cannot prove that same-run artifacts are visible across reusable
   workflow boundaries.
8. This is evidence plumbing. It does not increase the README readiness bars
   unless the validated compiler capability itself expands.

This review found a bounded implementation seam, so an external architecture
review is not needed for this slice. Upstream Haxe remains the behavior oracle;
no upstream compiler or test code is copied.

## Verification and Closure

Before closing `haxe_ocaml-vhk47.4`:

1. Run the new network-free positive and fail-closed fixtures.
2. Run the macro/eval contract guard and RC collector fixtures.
3. Parse/check every touched workflow and run the repository CI guards that
   cover workflow contracts.
4. Trigger the focused workflow on one exact pushed commit.
5. Download its macro, eval, and combined summaries and inspect the candidate
   commit, run identity, markers, and input hashes.
6. Record a final xhigh review in the bead before closure.
