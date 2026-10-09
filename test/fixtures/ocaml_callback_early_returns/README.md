# Early callback returns

A callback can leave a function through an early return or its final return.
Both paths must preserve the original function identity and Boolean conversions.
An ordinary Haxe catch clause must not intercept the compiler's private return signal.

The authored source covers a conditional parameter return, a return inside `try/catch`,
a returned local alias, and a callback supplied by another method.
The expected output specifies the selected branch, false callback results, and identity comparisons.
Upstream Haxe eval supplies the independent behavior reference.

Run `haxe test/m14_dynamic_callable_conversion_test.hxml` for source generation,
native compilation, execution, and the report checks.

`CheckOcamlCallableEarlyReturnReports` checks the generated control records against their prepared callback returns.
Its corruptions include missing links, stale revisions, foreign bodies, different source occurrences,
another return from the same function, and an ordinary function payload.
Each corruption recomputes the report checksum so a stale digest cannot hide a missing ownership check.

A captured closure also escapes through an early return.
The native test forces a major collection through a precise test-only GC extern before invoking that closure.
The closure must retain its captured value, and a second factory call must create a distinct identity.

A factory that always throws also declares a callback result. Its completed return inventory
has zero entries. The recorded count must distinguish this valid body from missing return evidence.
The test catches its String error and requires `unavailable` as the final output line.
