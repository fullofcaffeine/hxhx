# Second-pass review: duplicated String defaults

The repair covers two explicit compiler-output boundaries. It does not make
private runtime references generally reusable.

- Completed function assembly selects only `string-null-default`. Other roles
  remain unchanged and still fail if duplicated without their own owner.
- A copied catch-channel subtree can contain one source reference more than
  once. Each occurrence receives a deterministic numbered identity within that
  single copy call.
- Two separate copy calls with the same logical role still create the same
  identity and fail. This preserves the misuse check for accidental repeated
  publication.
- The reduced fixture was red for the same final-output diagnostic as the
  macro-host build. It is now green through OCaml compilation and execution.
- Upstream Haxe, String-null storage, and 19 exact catch-chain cases agree.

The macro-host artifact is still unproven until the full regeneration runs.
README Goals must remain unchanged before that proof.
