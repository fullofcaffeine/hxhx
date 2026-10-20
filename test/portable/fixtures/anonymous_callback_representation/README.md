# Record callbacks with structural and generic results

A typed record callback accepts a rendering callback and returns an Array. The rendering callback obtains its result through a generic function in another module. A second record supplies a structural iterator.

Reading either callback must retain its callable shape without imposing a different runtime representation on its arguments or result. The fixture checks the rendered contents and iteration output against upstream Haxe. The existing anonymous_callback_capture fixture separately checks capture, identity, and once-only evaluation.

Run `PORTABLE_FIXTURE_ALLOWLIST=anonymous_callback_representation bash scripts/test-portable.sh` from the repository root. The runner builds and executes native output; the extra test compares upstream behavior with expected.stdout.
