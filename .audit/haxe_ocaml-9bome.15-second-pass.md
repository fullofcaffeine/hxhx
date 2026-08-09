# Second-pass review: nested local-plan ownership

## Outcome

The change is narrow and the evidence supports closing this task. Nested
functions now consume local storage and carrier conversions with the root
function binding that sealed the complete closure tree. Their separate nested
binding still owns calls, control flow, array-literal production, and IMap
behavior.

## Challenges and dispositions

### Could this hide a missing nested local plan?

No second plan was introduced. `OcamlLocalStoragePlanner` and
`OcamlLocalRepresentationPlanner` already traverse the complete root body,
including nested functions, and seal nested locals and captures under the root
binding. The builder now names that existing owner explicitly instead of
reusing the unrelated active behavior binding.

### Could root ownership leak into nested control or IMap decisions?

The new binding is used only by local representation resolution and
initializer/assignment/read conversion lookup. `currentFunctionPlanBinding`
still changes when a nested function is entered, so nested call, control, and
IMap checks keep their existing identity. The full IMap positive and corruption
fixtures passed.

### Did the fix weaken stale or wrong-occurrence detection?

No. Conversion IDs still include the function, program, body, pipeline, local,
role, and source span. The change selects the correct already-sealed binding;
it does not ignore or rewrite any identity component. A missing conversion
still fails before output is accepted.

### Is the plan revision honest and fully propagated?

The ordinary-function plan revision moved from v80 to v81. Tooling validators,
focused report checks, and reviewed lowering goldens were regenerated through
the deterministic two-run workflow. All six golden inventories retained the
same claim counts; only revision-derived identities, hashes, and ordering
changed. The complete 106-fixture portfolio passed.

### Did testing accidentally depend on revision-derived ordering?

One IMap negative fixture assumed that the first sorted alias was a string map.
The v81 identities exposed that brittle assumption. The fixture now selects the
root string-map alias by semantic fields, then corrupts it. Both positive and
negative IMap checks passed afterward.

### Did this edit handwritten or generated OCaml?

No. Compiler semantics remain in Haxe. Generated output was only produced by
the normal target/build tests, and the handwritten-OCaml ownership guard passed.

### Does the compiler-scale result prove the original failure is fixed?

Yes. The current-source build passed EmitterStage.hx:7778 and stopped 288 lines
later at EmitterStage.hx:8066. The new diagnostic concerns a place/update plan
for `seenStamp[i] = 0`, not a local nullable conversion. It is preserved for a
follow-up rather than folded into this task.

## Oracle disposition

An additional Oracle review was deliberately skipped. The repository already
had a bounded, executable ownership invariant, the smallest reproducer was
clear, no competing semantic designs remained, and focused plus full
conformance evidence passed. The next place-plan failure receives its own task
and can escalate separately if its owner is not equally bounded.

## Review conclusion

The initial `thinking:xhigh` level was sufficient. It was warranted because the
wrong binding could make a cache/plan lookup silently authorize incorrect
syntax, but `max` or an Oracle round trip was not needed after the exact owner
was proven.
