# Generic Array results passed to concat

A generic module function returns an Array from a callback across an exception boundary. Passing that result to Array.concat must preserve the elements and evaluate the producer once. The fixture compares native output with upstream Haxe eval.

Run with `PORTABLE_FIXTURE_ALLOWLIST=array_generic_concat_result bash scripts/test-portable.sh` from the repository root.

Both receiver and argument can come from the generic function. The test also checks receiver-before-argument effects and that changing the result leaves both input arrays unchanged.
