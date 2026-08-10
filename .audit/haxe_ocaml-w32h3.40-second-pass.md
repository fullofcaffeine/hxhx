# Second-pass review: nullable anonymous proof identity

## Outcome

The test-only change is safe for this bounded regression. The compiler's
version-4 anonymous-object model already produced the correct native behavior
and a complete result/control proof. The fixture failed because it still
expected the identifier from version 3.

The fix changes no compiler source and no generated OCaml. It updates the one
reviewed identifier and explains its exact input so the next intentional model
change cannot look like an unexplained snapshot refresh.

## Review findings and dispositions

1. **The expected value must not come only from the report under test.**
   The reviewed input is the model name
   `ocaml-anonymous-structure-v4`, a newline, and the normalized type
   `anonymous{file:String,line:Int}`. An independent Node SHA-256 calculation
   produced `f7e4f011fbcb9b3678770b4a` as the first 24 hexadecimal characters.
2. **Updating an internal identifier must not weaken the behavioral checks.**
   The fixture still names all three functions, requires the exact `Obj.t`
   identity conversion, checks both structure and representation revisions,
   checks all nine early returns, rebuilds the same program, runs the public
   inspector, and rejects six deliberately corrupted reports.
3. **A model revision is allowed to change this identifier.**
   The identifier includes the model revision by design. The fixture therefore
   keeps an exact reviewed value instead of accepting any well-formed hash.
   A future model revision must update the expectation and review the complete
   proof chain again.
4. **The successful runtime behavior was never the problem.**
   Before and after the edit, the native oracle passed three routes and four
   cases. The change repairs evidence maintenance only and does not expand
   nullable or anonymous-object support.
5. **The broader primitive-nullable failure is not part of this change.**
   While the affected checks ran, the separate in-progress Bead
   `haxe_ocaml-0uwin.43` removed a String materializer API before all callers
   had been migrated. Its partial work caused `nullable_return_control` to fail
   while compiling the target itself. This review does not count that command
   as green and does not modify the other task's files.
6. **No readiness claim changes.**
   The directly affected `nullable_anonymous_return_control` and
   `anon_struct_basic` fixtures pass. README Goals remain unchanged because
   this is a corrected test expectation, not new product behavior.

## Escalation decision

Oracle review was deliberately skipped. The failure had one deterministic
cause, the identity formula was explicit, and the complete focused fixture
could distinguish a correct update from weakened evidence. This written
second pass satisfies the inherited `thinking:xhigh` review requirement.
