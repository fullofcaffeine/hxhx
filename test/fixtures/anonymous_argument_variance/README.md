# Anonymous argument variance

An array built from object literals that omit an optional field, or add a field, is an array of the declared structure, as in Haxe 4.3.7: upstream checks two anonymous type arguments as an assignment when they are not equal. `haxe.macro.ExprTools.map` passes `{name, opt, type, value}` literals as `Array<FunctionArg>`, whose `?meta` they omit.

Run `node_modules/.bin/haxe test/m14_anonymous_argument_variance_test.hxml`. The test compares input types with upstream and runs the native output.
