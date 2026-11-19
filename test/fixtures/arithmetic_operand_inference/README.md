# Arithmetic input inference

An omitted parameter receives the type that `-`, `*`, `/`, or `%` requires in its body. As in Haxe 4.3.7, an unknown operand beside a number, `Dynamic`, or another unknown operand becomes `Int`, also beside a `Float` (`value - 1.5` gives `value : Int`). Dynamic and unused inputs stay as they are.

Run `node_modules/.bin/haxe test/m14_arithmetic_operand_inference_test.hxml`. The operations are in class `Ops`, declared before `Main`, so the calls in `main` cannot supply the evidence. The upstream observer reads `Main.Ops`. The test compares the upstream parameter types, the hxhx parameter types, and the native output. It reuses the upstream macro observer from `method_parameter_dynamic_context`.
