# Locals assigned after declaration

These fixtures check that a local can receive its first value after declaration.
Repeated writes, shadowed names, and captured variables must keep distinct,
correct storage locations.

Run the focused compiler and native checks:

```sh
npm run test:m14:cpp-uninitialized-local
```

The native observer uses forced collection, AddressSanitizer, and
UndefinedBehaviorSanitizer at O0 and O2. It checks temporary-root cleanup after
normal completion and after a rejected read. The storage-plan test also rejects
omitting an initializer that was present in the source.

UninitializedLocals must finish successfully. UnassignedRead must fail with
`managed local slot is unassigned`. CapturedUnassignedRead must fail with
`managed cell is unassigned`.

Compare upstream Haxe 4.3.7 behavior with:

```sh
haxe -cp test/oracle/cpp_uninitialized_local_seed -main UninitializedLocals --interp
haxe -cp test/oracle/cpp_uninitialized_local_seed -main UnassignedRead --interp
haxe -cp test/oracle/cpp_uninitialized_local_seed -main CapturedUnassignedRead --interp
```

Upstream accepts the positive case and rejects the direct read during checking.
For the captured read, upstream warns with WVarInit and execution reaches the
fixture assertion. Native checked storage deliberately rejects the read itself.
This is a safety boundary, not complete diagnostic or runtime parity.
Task haxe_ocaml-mjz6e owns the shared definite-assignment rules.

Task haxe_ocaml-71qn2 owns the managed storage work. These fixtures do not change
README Goals readiness or establish a complete release candidate.
