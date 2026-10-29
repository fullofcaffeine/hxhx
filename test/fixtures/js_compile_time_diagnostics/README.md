# Diagnostic query results in JavaScript

Run `haxe test/m14_js_compile_time_diagnostics_test.hxml` for the focused check.
The existing `npm run test:m14:js-stmt-key-value-for` command also runs it.

The upstream run executes real, independently authored macros that call `Context.typeof`.
The candidate uses the existing diagnostic helper adapter with ordinary shared typing.
Both generated JavaScript programs check the same diagnostic text and Boolean results.
Qualified and statically imported helper calls preserve both original call forms.

The cases preserve the earlier integration assertions: integer and missing-provider iteration fail,
a Dynamic object field accepts a string, and an Int field rejects a Float initializer.
Additional controls check invalid range entries, successful queries, and private declarations.
The enclosing test also verifies that raw source blocks and loops cannot bypass typed lowering.

Saved query results belong to one unchanged source occurrence and one function's inference state.
The companion facts test rejects copied or changed syntax and verifies that speculative results stay private.
Projection reads the saved outcome after inference finishes; it does not type invalid input again.

This verifies the existing adapter's integration. It does not prove general native macro execution
or remove the remaining name-based helper recognition tracked by `haxe_ocaml-pmsr1`.
README Goals and Full1 readiness are unchanged.
