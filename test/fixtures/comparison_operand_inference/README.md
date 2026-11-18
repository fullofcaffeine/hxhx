# Comparison input inference

An omitted parameter used in a comparison or a range bound receives its type from that use. As in Haxe 4.3.7, an unknown operand of `==`, `!=`, `<`, `<=`, `>`, or `>=` takes the type of a known peer, and two unknown operands of an ordering become `Int`. Two unknown operands of `==`, or a `Dynamic` peer, stay unknown. A range bound becomes `Int`.

Run `node_modules/.bin/haxe test/m14_comparison_operand_inference_test.hxml`. The operations are in class `Ops`, declared before `Main`. The hxhx check types them with an empty `main`, and `main` does not call the cases that must stay unknown, so calls cannot supply the evidence. The upstream observer reads `Main.Ops`.

`main` does not call `equalsArray`: the Stage3 emitter crashes on `==` between two arrays (`haxe_ocaml-cohod`). Its parameter types are still compared.
