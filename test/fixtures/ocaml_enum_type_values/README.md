# Runtime type values in OCaml enum payloads

Run `npm run test:m14:stage3-enum-patterns` from the repository root.
Upstream Haxe and the native OCaml executable must match `expected.stdout`.

The observer obtains an existing class or enum descriptor from an instance.
It stores the descriptor in an enum payload, then checks its name and identity.
Optional and nullable payloads preserve both null and present values.
The two-argument constructor evaluates its class argument before its enum argument.
Creating the class instance must run its constructor exactly once.
The `Types` alias must select the same standard-library declarations as `Type`.

This regression belongs to `haxe_ocaml-ijqdu`. Native queries use the existing
runtime descriptor carried by generated class instances and boxed enum values.
They do not reconstruct a descriptor from a printed name. First-class class
literals remain unsupported. The class query rejects other instance
representations until their runtime contract is implemented.

The test prepares its root with the production dependency loader and inline
expansion, then emits that root. It does not prove that the entire exception
provider or standard-library dependency closure can compile. README Goals status
does not change; broader compatibility, CI, and release checks remain required.
