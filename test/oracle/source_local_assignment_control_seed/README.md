# Local assignments with control flow

An assignment writes its local binding only if its right-hand side completes normally.
A return or loop exit must keep its authored destination and must not perform the assignment.

StatementMain tests direct conditional assignment and return from an assignment block.
Main also tests the assignment value inside parentheses, nested-function returns, and loop exits.
The expected outputs are independent observations from upstream Haxe 4.3.7:

```sh
haxe -cp test/oracle/source_local_assignment_control_seed/src -main StatementMain --interp
haxe -cp test/oracle/source_local_assignment_control_seed/src -main Main --interp
```

Run both candidate native programs with:

```sh
haxe test/m14_source_local_assignment_control_test.hxml
```

The runner checks immutable source revisions and repeated lowering before native compilation and stdout comparison.
StatementMain passes. Main currently fails because the parser represents a parenthesized assignment as a synthetic call.
That source-syntax defect is tracked as haxe_ocaml-xq2ke. The complete runner must remain red until both programs pass.
These local-binding cases do not prove field/indexed assignment, compound assignment, or general capture lifetime.
