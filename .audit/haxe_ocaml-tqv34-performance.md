# Runtime-use authority guard performance

## Outcome

The complete runtime-use authority gate now finishes in about three seconds on
the measured machine. Before this change, the unchanged gate remained at full
CPU for more than 12 minutes and had to be stopped before it reached the actual
behavior fixture.

The test still runs Haxe 4.3.7 null-safety over the complete `reflaxe.ocaml`
package. The improvement comes from expressing a closed set of 42 private
runtime names as a string switch instead of one long Boolean `or` condition.

## Diagnosis

Three exact-type checks separated package cost from source-shape cost:

| Null-safety owner | Before change |
| --- | ---: |
| `OcamlRuntimeUseModel` | 0.37 seconds |
| `OcamlRuntimeUseAuthority` | exceeded 10-second timeout |
| `OcamlFinalRuntimeUseAuthority` | 0.29 seconds |

A three-second sample of the slow Haxe process placed nearly all observed work
inside Haxe's null-safety condition traversal. The authority class contained a
42-branch equality condition. After replacing that condition with an equivalent
switch, the exact authority check completed in 0.39 seconds.

## Complete gate measurements

The first complete run through the new owned runner reported:

| Phase | Cold elapsed |
| --- | ---: |
| Runtime-use authority | 1,077 ms |
| Checked generated text | 237 ms |
| Type-registry generated text | 912 ms |
| Complete npm command | 2.81 seconds |

Maximum resident memory was 117,489,664 bytes. Two immediate warm runs reported
phase times of `866/224/891 ms` and `870/229/889 ms`. All runs were green.

Each phase has a 30-second default limit. That is more than 27 times the slowest
measured normal phase, but it turns the former multi-minute regression into a
clear, bounded failure. The environment variable
`REFLAXE_OCAML_RUNTIME_USE_TIMEOUT_SECONDS` may set an integer from 1 through
600 when a deliberately slower machine needs an explicit budget.

## Claim boundary

This fixes developer and CI latency; it does not advance `reflaxe.ocaml`
readiness. The reserved-name fixture independently checks all 42 accepted names
and three similar rejected-by-the-set names. The timeout fixture proves that a
stuck parent and grandchild are both removed without signaling unrelated jobs.
