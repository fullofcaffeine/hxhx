# Switch syntax

Haxe 4.3.7 parses a switch as `ESwitch(subject, cases, default)`. Each case holds its pattern expressions (`case 2, 3:` has two), an optional guard, and a body that is a block, or null when the case is empty. A written `default:` is the separate default. Specs that the upstream unit suite reads through `Context.parseInlineString` use switches in their own code.

hxhx keeps a switch as `HxExpr.ESwitch(subject, patterns, bodies, ?defaultArm)`, with patterns as `HxSwitchPattern`. A comma list is `POr(alternatives, true)`. `MacroSyntaxExport` exports it in upstream's shape, and `MacroSyntaxImport` turns it back into the same parser form.

`Syntax.show` prints each switch on one line with the shape of its cases; `expected.stdout` is upstream's output. Run `node_modules/.bin/haxe test/m14_switch_syntax_test.hxml`.
