# Second-pass review: completed-function Array runtime identities

The change fixes an output-identity boundary. It does not change Haxe Array behavior or add a new runtime fallback.

- The source call still receives one sealed `standard-array-operation` permission.
- Syntax still checks the exact helper, receiver, arguments, and evaluation order.
- Temporary syntax renders no longer consume output identity.
- Only repeated Array references in one completed function receive checked copy identities.
- Other helper roles still fail when duplicated without an explicit owner.
- The reduced fixture is red under the old behavior and green under the corrected behavior.
- The official macro-host build passes the original reconciliation failure and reaches later Dune type errors.

The macro-host snapshot did not publish, so README Goals remain unchanged. The new Dune failures are not part of this Array-ownership fix.
