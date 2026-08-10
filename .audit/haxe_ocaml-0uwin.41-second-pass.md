# Empty Rest call boundary — xhigh second pass

## Outcome

The change removes one invalid fallback without changing valid Haxe rest-call
behavior. Upstream Haxe 4.3.7 supplies a complete array argument before the
standalone target builds OCaml syntax. Empty ordinary calls, explicit
`haxe.Rest<Int>` calls, and an extern call all reach the existing `HxArray`
path and run successfully.

No Oracle escalation was needed. The first probe made the boundary simpler:
the installed Haxe compiler and the generated typed output agree on one normal
path, while history shows that the removed helper was added beside a separate
Stage3 parser/emitter test.

## Challenges and dispositions

### Did the first test actually reach the suspect helper?

No. This was the important diagnosis correction. The initial `count()` fixture
passed on unchanged `main` because Haxe had already produced an empty typed
array. Adding a function whose parameter is written explicitly as
`haxe.Rest<Int>` produced the same result.

An extern mapped to the real target function `HxArray.length` also received a
normal generated empty array. This proves that the standalone target does not
need to invent a missing rest value for this real extern boundary.

### Why delete the fallback instead of changing it to `HxArray.create`?

Changing the module name would preserve the wrong ownership rule. The target
would still repair an incomplete typed call after Haxe had already decided the
call shape. If a future typed call has fewer arguments than a non-optional
signature, the existing missing-required-argument diagnostic is safer than a
guessed value.

### Could this break the separate Stage3 compiler path?

No. The five deleted branches are in standalone `reflaxe.ocaml`'s
`OcamlBuilder`. The Stage3 parser/emitter and its focused
`test:m14:hih-local-rest-call-resolution` test remain unchanged and pass. That
lane still owns its temporary `HxBootArray` shim until the authentic shared
target hard cut removes the Stage3 semantic compiler.

### Does the new fixture prove observable behavior?

Yes. The installed Haxe 4.3.7 interpreter produces the manually retained
ordinary-rest output. The same source then compiles through standalone
`reflaxe.ocaml`, builds with Dune, and runs. Its extern call maps to
`HxArray.length`, so the real native process observes that the supplied rest
value is an empty runtime array.

Two clean fixture runs produced the same `Main.ml` and lowering-report digests.
The source check also rejects any restored `HxBootArray` or target-side rest
padding helper before the runtime fixture can be accepted.

### Is the runtime inventory reduction exact?

Yes. The inventory moved from 390 to 389 entries. Only the one-entry
`builder-boot-array` family disappeared. No existing `HxArray` occurrence was
reclassified or claimed by this task; valid rest arrays continue through their
existing typed array-literal plan.

### Did broader verification find another problem?

Yes, outside this slice. `haxe_core_bucket02_basic` reaches a separate plain
`HxAnon.get` reference while compiling `haxe.Template`. That failure belongs to
the remaining `builder-anon` runtime-authority family. The rest deletion cannot
select or construct `HxAnon`, and the focused rest, extern-core, call-plan, and
Stage3 tests pass. The failure remains visible for a follow-up runtime task.

## Verification

- installed Haxe version: `4.3.7`;
- Haxe 4.3.7 interpreter output matches `expected.oracle.stdout`;
- `rest_empty_call` compiles, Dune-builds, and runs twice;
- repeated `Main.ml` SHA-256:
  `717b06093acf19dd5d88b6e9b99989d56c080603cc2e3a0319bdc746c332a55a`;
- repeated lowering report SHA-256:
  `62688cbe96ce8f236a2d66ecd7b62a4ca1bcc4db38ca62b90e50895877098a74`;
- `haxe_extern_core_basic` passes;
- `call_exact_int_static` passes;
- `test:m14:hih-local-rest-call-resolution` passes;
- runtime-requirement and private-reference-inventory gates pass;
- changed-file and full repository Haxe formatting pass;
- mega-file, local-path, and diff checks pass.

## Readiness decision

README Goals remain unchanged. This removes one dormant Stage3 dependency from
the standalone target source. It does not complete runtime-reference authority,
the standalone target's 1.0 route, Full1, or the authentic shared-target hard
cut.
