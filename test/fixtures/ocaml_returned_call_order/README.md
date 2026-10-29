# Returned callable order

A factory with two parameters returns a callable through Dynamic. Its caller invokes the result with zero or two arguments.
Both unqualified and qualified factory calls are exercised.
The expected output checks factory evaluation before arguments, left-to-right argument evaluation, and one evaluation of each producer.
A typed callback parameter named `factory` checks local shadowing of the module function.

Run `haxe test/m14_stage3_returned_call_order_test.hxml` with the repository toolchain.
The same fixed output is checked against upstream Haxe and the generated native executable.
This fixture covers the observed zero- and two-argument boundary, not every Dynamic call form.
