# Expression metadata keeps its value

Expression metadata must not create a runtime function call. The JavaScript Map
iterator exposed this defect through its `@:nullSafety(Off)` value expression.

Run `haxe test/m14_expression_metadata_test.hxml` from the repository root.
The fixture compares upstream Haxe and local JavaScript execution. It checks
nested metadata, exact evaluation counts, inferred `Int` locals, and an early return.
The same command checks that typed quotation retains metadata names, argument
text, and nesting. Changes to metadata must change the typed revision identity.

Shared typing now represents metadata as a wrapper with one value child.
Syntax consumers retain that wrapper. Executable control lowering consumes it
and preserves the inner value and its control destination.

This regression proves metadata transport and execution. It does not establish
implementation of every compiler policy that a metadata name can request.
