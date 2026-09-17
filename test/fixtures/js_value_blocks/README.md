# Value blocks followed by comments

This fixture checks static and local initializers that contain declarations,
mutation, and a final value. Comments after the closing brace must remain outside
the initializer. Object literals and ordinary statement blocks keep their own
behavior.

Run `haxe test/m14_js_value_block_integration_test.hxml` from the repository root.
The test runs this source with upstream Haxe, then uses the current Haxe-authored
parser, typer, and JavaScript backend to generate a program for Node. Both routes
must print `73`, `42`, `8`, `4`, and `7342`, each on its own line. The last two
numbers check that the four calls execute exactly once each, in source order.

The test also requires shared typed block nodes for both initializer positions.
It does not establish complete Haxe compatibility or replace the upstream suite.
