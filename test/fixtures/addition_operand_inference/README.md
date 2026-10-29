# Addition input inference

An omitted parameter receives the type required by addition in its body. Named callbacks retain that checked type. Dynamic and unused inputs remain distinct.

Run `node_modules/.bin/haxe test/m14_addition_operand_inference_test.hxml`. The test compares public upstream parameter types, candidate parameter types, and native output. It reuses the upstream macro observer from `method_parameter_dynamic_context`. The receiver-call integration test also runs this regression.

Goals status remains unchanged. This fixture proves the addition contract, not complete method inference or overall compiler parity.
