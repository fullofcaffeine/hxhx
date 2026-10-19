# Bitwise parameter inference

An omitted parameter used by an integer bitwise operation must infer `Int`.
This covers all six binary operators, aliases and a Dynamic peer. Written
`Dynamic` parameters stay Dynamic; an unused parameter remains unresolved.

Run `haxe test/m14_bitwise_parameter_inference_test.hxml`. The test compares
upstream Haxe's public macro type observations with exact local parameter facts.
The nested-integer runtime observer in the Stage3 Dynamic operator integration
test checks the native consumer of these inferred inputs.
