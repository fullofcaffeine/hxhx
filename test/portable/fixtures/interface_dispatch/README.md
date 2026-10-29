# Interface dispatch

Run `PORTABLE_FIXTURE_ALLOWLIST=interface_dispatch bash scripts/test-portable.sh`
from the repository root.

The native program calls a derived override through an interface. Silent
assertions also check parent interfaces, shared object state, captured methods,
nested functions, static initialization, and calls during construction.
Empty instances receive method entries before their first call. Their value
field is explicitly initialized; this test makes no claim about default fields.

The test compares the same program with upstream Haxe. Its original stdout
remains unchanged. Structural anonymous views have a separate fixture.

Compile-time contract checks distinguish source types and native carriers.
They reject changed method signatures and unsupported optional or generic
methods before those methods can authorize a native lookup.
