# JavaScript try and block values

Run `haxe test/m14_js_expr_emitter_try_catch_integration_test.hxml` from the repository root.
The test compiles this same source with upstream Haxe and with the candidate JavaScript backend.
Both programs must finish without output or failed assertions.

Coverage preserves the former raw-emitter test: ordinary and private-access exception stack reads,
typed map locals, nested block values, object literals, ordered conditional effects, and a terminal
while loop. The loop runs in a Void function because a Void-valued block cannot initialize an
ordinary Haxe variable. Its captured result proves that the loop executes. A trailing documentation
comment also must not become generated JavaScript syntax.

The candidate loads real Exception and StringMap providers before typing and lowering.
No fixture replaces these providers or repairs generated JavaScript.
