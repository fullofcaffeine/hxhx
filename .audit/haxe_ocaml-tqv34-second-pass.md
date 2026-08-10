# Runtime-use authority guard second pass

## Outcome

The runtime-use guard keeps its original behavior and full package null-safety
coverage while changing a multi-minute compiler stall into a roughly
three-second check. The review found no weakened semantic assertion, broadened
product claim, or unowned process signal.

## Test sensitivity and independent expectation

The source change is deliberately mechanical: a 42-way Boolean equality chain
became a string switch. The fixture does not derive its expected names from the
production switch. It contains an independently authored list of all 42 names
that must reject unchecked use, including the four names missing from its older
partial list. It also proves that three similar but unmigrated names remain
allowed. Removing, adding, or misspelling a switch case therefore makes a
focused test fail.

## Null-safety boundary

The runner invokes the same real Haxe compiler and the same package-wide
`nullSafety("reflaxe.ocaml")` macro for the runtime authority, checked generated
text, and type-registry generated text fixtures. It does not replace the
compiler with a mock, disable null-safety, or reduce the checked path to the
single class used during diagnosis.

Sampling and exact-type measurements justified keeping this broader boundary:
only `OcamlRuntimeUseAuthority` was pathological, and changing its source shape
made the complete package check fast. There is no classpath or repeated-process
workaround hidden in the runner.

## Timeout ownership and cleanup

Every Haxe phase receives its own 30-second deadline and its own process tree.
On POSIX systems the child is a new process-group leader; the runner signals
that negative process-group ID rather than searching for Haxe processes by
name. Windows uses `taskkill /T` for the exact spawned PID. The normal path does
not signal anything.

The cleanup fixture starts a parent and grandchild that both stay alive and
resist the polite termination request. It then verifies that the forced cleanup
removes both PIDs. The timeout helper waits for cleanup before reporting the
phase result, so a timeout cannot be presented as complete while its owned
compiler tree is still running.

## Failure reporting and limits

The runner prints the exact phase, elapsed time, and budget for passes and
timeouts. A timeout exits with status 124; spawn and compiler failures retain
separate output. The optional environment override accepts only whole seconds
from 1 through 600, preventing zero, negative, fractional, or unbounded values.

The measured slowest normal phase was 1.077 seconds, so the default budget has
more than 27 times local headroom. This is a tooling reliability fix only;
README goals and release readiness remain unchanged.
