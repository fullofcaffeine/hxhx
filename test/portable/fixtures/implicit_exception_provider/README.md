This fixture catches a thrown String as `haxe.Exception` with full dead-code elimination enabled.
The generated catch constructs `haxe.ValueException`, although the authored program never names that class.
Its constructor and payload field must survive elimination together.

The fixture also checks that catching an existing exception preserves its identity and message.
A String catch preserves the raw thrown value.
The expected output is independently checked with upstream Haxe 4.3.7.

Run `PORTABLE_FIXTURE_ALLOWLIST=implicit_exception_provider npm run test:portable` from the repository root.
