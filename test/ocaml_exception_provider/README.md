# Native exception providers

This program checks exception messages, previous exceptions, value payloads,
typed catches, and deterministic stack formatting, length, and subtraction.
The expected output is observed with upstream Haxe before native compilation.

Run `haxe test/m14_stage3_exception_providers_test.hxml` from the repository root.
The test uses production classpaths and defines, with no provider copies or emitter overrides.
It checks the selected source bundle and compiles the complete dependency graph.
The existing runtime CallStack test command also runs this observer.

Native stack capture remains a target primitive. Stack contents depend on the
host and build; the test checks deterministic operations on authored StackItem values.
This fixture does not establish full language or standard-library parity.
