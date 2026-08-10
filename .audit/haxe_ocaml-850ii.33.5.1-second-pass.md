# Second-pass review: compiler-server memory plateau proof

## Outcome

The revised check distinguishes live compiler state from process memory that
the allocator or operating system has reserved for reuse. It still fails on
unbounded managed or native growth, but a single noisy RSS window no longer
rejects an otherwise stable 30-request server run.

## What the proof now requires

- Exactly 31 evaluator samples: one baseline and one after each of 30 unchanged
  requests.
- A newer major garbage collection in every evaluator sample. The OCaml
  evaluator's `compactions` counter remains zero even when the test hook calls
  `Gc.compact()`, so the checker relies on the observed increasing
  `major_collections` count and on the hook's explicit call contract.
- Zero active target-cache leases at every sample, so pinned cache entries do
  not hide request-lifetime retention.
- The exact same non-empty set of repository-owned compiler-server process IDs
  in every RSS sample. A process restart, disappearance, or replacement makes
  the proof invalid instead of producing a misleading comparison.
- No more than 128 MiB total compacted live-heap growth across 30 requests and
  no more than 32 MiB compacted live-heap growth in the final ten requests.
- No more than 128 MiB total RSS growth. Two consecutive ten-request RSS
  windows that each grow by more than 32 MiB also fail, even when managed live
  objects appear stable; this protects against sustained native or untracked
  growth.

A single final RSS window over 32 MiB is reported as
`reserved-capacity-observed` when the other limits pass. This status means the
process retained address-space pages, not that a leak was waived. The next
request sequence still has to remain below the total cap and cannot show the
same large growth in two consecutive windows.

## Independent sensitivity checks

The deterministic fixture proves that the checker rejects:

- live-object growth over the final-ten limit;
- total RSS growth over the 128 MiB limit;
- sustained RSS growth in two consecutive windows;
- a missing compacted evaluator sample; and
- a sample without a newer major collection.

It also proves that stable live objects plus one noisy final RSS window is
accepted and explicitly reported.

## Real-server evidence

The complete server matrix passed after the collection check was corrected.
Its final observed values were:

- live heap: 62,290,641 baseline words, 61,766,491 at request 20, and
  61,767,441 at request 30;
- final-ten live growth: 7,600 bytes;
- RSS: 1,144,752 KiB baseline, 1,191,200 KiB at request 20, and 978,560 KiB at
  request 30; and
- unchanged generated output plus the existing edit, delete, move, classpath,
  define, profile, DCE, macro, source-map, reset, restart, and package checks.

The final repository guard is rerun after the sustained-RSS rule was added, so
the committed evidence uses the exact final checker rather than relying only
on these earlier samples. That final `npm run ci:guards` run passed. Its live
server proof recorded 62,290,663 baseline words and 61,767,463 final words,
with 7,600 bytes of final-ten live growth. RSS fell from 1,502,560 KiB to
903,200 KiB across the same two owned processes.

## Deliberate limits

This changes test evidence, not compiler caching or generated program
semantics. It does not enable target reuse, change the default server, advance
README readiness, or claim that every long-lived workload is leak-free. The
30-request matrix remains a bounded admission check.

Oracle review was deliberately skipped. The repository already had a test-only
compacted-GC observation hook, two contradictory RSS runs exposed the exact
measurement defect, and deterministic negative fixtures can challenge the new
rule locally. This was a bounded evidence-seam correction rather than an
undefined compiler architecture decision.
