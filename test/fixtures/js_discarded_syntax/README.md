# JavaScript statement fragments in discarded blocks

Run `haxe test/m14_discarded_control_test.hxml` from the repository root.
The test loads the real `js.Syntax` declaration and compares upstream and candidate
JavaScript execution with `expected.stdout`.

The split brace fragments reproduce the pattern in Haxe 4.3.7's JavaScript
`Reflect.fields` implementation. They must remain statements when their block's
result is unused. Assigning the closing brace to a temporary produces invalid
JavaScript. The final case consumes an expression result and must still print 9.

Raw JavaScript is intentional at this target-syntax boundary. It contains only
fixed test fragments and prints integer observations. No compiler code recognizes
these fragments or fixture names.
