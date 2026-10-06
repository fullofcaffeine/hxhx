# Standard string conversion through Dynamic

Run `haxe test/m14_cpp_standard_string_test.hxml` from the repository root.
The test checks upstream Haxe, generates managed C++, and runs the same assertions
with forced collection at `-O0` and `-O2` under address and undefined-behavior sanitizers.

The fixture passes Int, nullable Int, Bool, and String values through an authored
`Dynamic` parameter. Its independent output checks null text, Boolean identity,
UTF-8 bytes, an empty String, and exactly one evaluation of the counted input.
The test also rejects a changed standard declaration signature.

This proves primitive conversion only. Aggregate/object formatting, Float policy,
and using the standard function as a stored callable remain unfinished under
`haxe_ocaml-hcnk8`. README readiness estimates are unchanged.
