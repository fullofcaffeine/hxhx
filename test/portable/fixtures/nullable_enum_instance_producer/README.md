# Return a produced enum through a nullable instance result

An instance method returns null on one path and calls an exact enum producer
on its normal path. The present result must preserve its payload. The early
null result must remain null.

Before the correction, native compilation expected Obj.t for the nullable
result but received the native enum variant from the producer call.

Run `PORTABLE_FIXTURE_ALLOWLIST=nullable_enum_instance_producer bash scripts/test-portable.sh`.
The runner compiles and executes native output against expected.stdout. The
extra test compares the same program with upstream Haxe eval.
