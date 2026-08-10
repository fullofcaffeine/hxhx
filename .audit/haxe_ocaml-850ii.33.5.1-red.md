# Red evidence: complete-program server memory plateau

## User-visible failure

The broad guard rejected a semantically correct 30-request compiler-server run
because its final process RSS was 89,792 KiB above request 20:

```text
owned server RSS did not approach a plateau in the final ten requests
(after20=871056KB final=960848KB)
```

The immediately preceding full run had passed the same check with RSS falling
from 917,312 KiB at request 20 to 894,880 KiB at request 30. The generated
program, diagnostics, runtime behavior, and request-isolation matrix passed in
both runs. This contradictory result showed that one final RSS window was not a
stable measure of live compiler state.

## Smallest focused red contract

Before the checker existed, the fixture command failed because the required
module was absent:

```text
node scripts/ci/reflaxe-ocaml-memory-plateau-fixture-test.js
Error: Cannot find module './reflaxe-ocaml-memory-plateau'
```

That fixture now independently describes the intended boundary: compacted
live OCaml objects must plateau, total process memory remains capped, sustained
native/RSS growth fails, and incomplete collection or process evidence fails.

## Why this is the intended red state

RSS includes allocator pages that a process keeps for reuse even after their
objects are gone. The server already records `Gc.stat().live_words` after a
test-only full major collection and heap compaction. The correct proof must use
that live-object count for managed retention while keeping RSS as a backstop
for memory outside the OCaml heap.
