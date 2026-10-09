# Standard string conversion through Dynamic and Any

Run `haxe test/m14_cpp_standard_string_test.hxml` from the repository root.
The test checks upstream Haxe, generates managed C++, and runs the same assertions
with forced collection at `-O0` and `-O2` under address and undefined-behavior sanitizers.

The fixture passes Int, nullable Int, Bool, and String values through an authored
`Dynamic` parameter. Its independent output checks null text, Boolean identity,
UTF-8 bytes, an empty String, and exactly one evaluation of the counted input.
The test also rejects a changed standard declaration signature.

An additional `Any` parameter checks Boolean, null, and String payloads through
the standard abstract's declared storage. This covers the conversion used by
real `haxe.ValueException` construction without giving arbitrary nominal types
a string conversion.

This fixture proves primitive conversion only. The neighboring
[instance contract](../cpp_object_string_seed/README.md) adds ordinary object
conversion. Aggregate and generic object formatting, Float policy, and using the
standard function as a stored callable remain unfinished under `haxe_ocaml-hcnk8`.
The combined package command includes the incomplete full comparison.
README readiness estimates are unchanged.
