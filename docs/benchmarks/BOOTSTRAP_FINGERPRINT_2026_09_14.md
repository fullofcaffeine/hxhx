# Bootstrap input hashing: September 14, 2026

Bootstrap regeneration reads its selected source files before it decides whether
to skip compilation. Batching checksum calls removes most of that preparation
cost without caching file contents or changing the input list.

The workload contains 663 files and 9,551,998 bytes on the candidate tree.
The old implementation starts 663 checksum processes and 663 `awk` processes.
The candidate starts six checksum processes. Both retain one final checksum
process and one `awk` process to hash the complete manifest.

## Measured work

The comparison uses base commit `ccc52737c51a470c98a4b0e7eaa6d4d07089e2f1`
(PR #55) and the batching change owned by `haxe_ocaml-850ii.35`.
Both implementations read the same candidate tree, including the changed
regeneration script. Comparing different source trees would change the digest
because that script is itself an input.

The host is an M2 Pro with 12 CPU cores and 32 GiB of memory, running macOS
Darwin 24.4, Bash 3.2.57, and Node 23.9.0. The selected checksum tool is
the installed Apple `sha256sum`; the fallback checks also exercise `shasum`.
Measurements use normal scheduling priority on a shared interactive host.
Filesystem caches were not purged. First-process and repeat samples do not
establish cold-disk performance.

| Work | Original | Batched |
| --- | ---: | ---: |
| Ordered input manifest, first sample | 1.879 s | 0.128 s |
| Ordered input manifest, repeat | 1.696 s | 0.123 s |
| Complete fingerprint, first sample | 1.714 s | 0.176 s |
| Complete fingerprint, repeat | 1.809 s | 0.112 s |
| Complete server lifecycle fixture | 22.201 s | 13.603 s |

The manifest comparison runs the original and candidate `compute_fingerprint`
functions with identical input files and configuration values. It captures the
manifest before the final SHA-256 operation and compares every byte. All 24
configuration variables use the same synthetic `baseline` value to isolate
hashing from toolchain selection and compiler work.

All four manifests contain 86,888 bytes and produce this digest:

```text
a1cc642d3a1e13750ccc8b9b6883b348fc26f10658b36540101d4a9a93d8d9fe
```

The complete lifecycle comparison uses the same fixture and fake compiler on
both paths. It includes server startup, worker observation, failure reports,
timeout handling, and cleanup. It is one comparison pair on a shared host,
not a compiler throughput result or a statistically stable performance budget.
Independent verification ran concurrently during the lifecycle samples.
The final hashing samples ran after that local verification session exited.

An earlier busy-host checkpoint observed about 20 seconds in hashing.
The isolated measurements did not reproduce that cost. The original main-branch
lifecycle fixture also failed its busy-worker assertion in a separate run.
PR #55 owns that fixture correction; both reported lifecycle samples use it.

The unrelated server-identity fixture failed once after a simulated launcher
crash, then passed a diagnostic repeat. A retry does not explain that failure.
The hashing change leaves both the server helper and that fixture unchanged.
The failed result remains recorded for separate process-ownership investigation.

The five-second investigation target remains report-only. These samples meet
it, but they do not establish a portable CI timeout.

## Correctness evidence

Run the focused contract:

```bash
npm run test:hxhx:bootstrap-fingerprint
```

The fixture assembles its expected manifest independently. It verifies every
configuration field, ordered file entries, edits, additions, moves, and deletions.
It also verifies batch count and argument limits, unusual filenames against
each installed checksum tool, empty input, and checksum errors.

An isolated fake compiler exercises the actual skip and force branches.
The saved fingerprint simulates an earlier successful build. The fixture proves
the branching contract and preserves the saved digest after compilation fails.
It does not prove that a real compiler can build this source tree.

Batching retains the existing newline-delimited inventory contract and Bash
relative-path labels. Each batch contains at most 128 paths and about 16 KiB
of path arguments. Failed, malformed, incomplete, or extra checksum output
stops regeneration before it can accept a reusable result.

README Goals status and progress bars remain unchanged. This tooling change
does not establish compiler independence, upstream compatibility, or release readiness.
