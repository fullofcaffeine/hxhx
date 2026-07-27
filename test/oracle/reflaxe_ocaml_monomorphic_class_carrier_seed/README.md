# Monomorphic class-carrier oracle seed

This source freezes Haxe 4.3.7 behavior for the smallest user-class family
that does not need inheritance or interface dispatch.

The output makes constructor argument order, constructor execution, receiver
evaluation, method argument order, alias identity, shared field mutation, and
method results observable. The runner executes the same source through Haxe's
interpreter, JavaScript, and Neko routes.

This is behavior-oracle evidence only. The hxhx/reflaxe.ocaml implementation
must remain clean-room and may not copy upstream compiler code.
