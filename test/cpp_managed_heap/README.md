# Native managed-memory primitive

Run `npm run test:m14:cpp-managed-heap` with Node and a sanitizer-capable C++17
compiler. The runner uses `clang++` by default. Set `CXX` to another compiler
executable when needed. Each compile and execution has a 60-second timeout.
For a focused edit, run `npm run test:m14:cpp-managed-heap -- ManagedCallableTest`.
The other selectable fixtures are `ManagedHeapTest`, `ManagedValueTest`,
`ManagedAllocationFailureTest`, `ManagedStaticRootTest`, and `ManagedStackTest`.
Unknown names fail instead of skipping checks.

The test compares a six-node graph against an independent reachability model.
It checks all 64 root sets, including cycles and disconnected nodes. It repeats
the cases with collection before every allocation. Reachable nodes must survive.
Unreachable nodes must be destroyed exactly once.

Additional checks cover mixed payloads, result handoff, copied roots, exception
unwinding, failed native construction, failed replacement, aligned payloads, and
heap teardown. A separate source must fail compilation because its payload has
no tracing declaration. Runtime checks use ASan and UBSan at `-O0` and `-O2`.

`ManagedValueTest.cpp` tests transport through a common tagged value. An erased
array must recover the original allocation, and writes through either alias must
reach the same storage. An owner-plus-index place survives vector buffer growth.
An erased array/record/environment cycle stays alive through its external root
and is collected after that root leaves. Recovery as the wrong physical payload
must fail before access. Descriptor values have static identity and own no instances.

Storage tags do not implement Haxe conversions or class membership. Array storage
checks its physical bounds; Haxe lowering must implement source indexing rules.
Reading an array element returns a value, never a native element reference. Root
that returned value before a collecting operation if it contains a managed edge.

`ManagedHeap.hpp` owns allocation, root registration, and graph collection.
Haxe compiler plans must still select payloads, roots, captures, and call boundaries.
An internal `Ref` does not keep an allocation alive by itself. A live root or a
traced edge from a live allocation must retain it before collection.

The heap supports one mutator and does not move allocations. Roots have stable
addresses and must leave scope before their heap. Native construction creates
trace-safe storage; authored initialization must run after publication into a root.
Tracing and destruction cannot execute Haxe, mutate roots, or access dead peers.
Vector element addresses are not stable across buffer growth.

`ManagedStackTest.cpp` checks explicit frame storage and immutable snapshots.
Native frame entry does not allocate. Scope exit and unwinding remove the active
frame. Capture copies source metadata and the current line into owned values;
later execution cannot change the snapshot. Separate execution contexts share
no frame state. Snapshots use the existing managed heap and survive collection
through an ordinary root. Releasing the roots permits collection.

`ManagedStack.hpp` stores only compiler-selected frames. Haxe must still choose
frame placement, debug policy, exception-origin timing, and conversion to
`haxe.CallStack.StackItem`. The primitive is packaged with the runtime. Raw
`NativeStackTrace.callStack` capture now runs through generated method frames.
Explicit Haxe throws replace the stored exception snapshot, which
`NativeStackTrace.exceptionStack` copies into an ordinary managed result.
See `npm run test:m14:cpp-native-stack-capture`. Full exception integration,
public frame conversion, source positions, and closure frames remain unfinished in
`haxe_ocaml-k9scs`. Passing the primitive test alone does not prove Haxe stack support.

`ManagedAllocationFailureTest.cpp` injects failure at the native allocator.
It checks that failed allocation preserves an existing root and that failed string
replacement preserves a managed edge. Collection after either failure must remain
safe. This is controlled failure evidence, not a host memory-exhaustion test.

`ManagedStaticRootTest.cpp` checks storage that stays rooted until its heap shuts
down. `allocateStaticInto` publishes one payload per generated native layout.
`requireStatic` retrieves that payload without running initialization. The layout
token selects physical storage; it does not represent a Haxe class descriptor.
Generated code must use a distinct payload type for each independent storage owner.
Separate heaps can publish the same layout and keep different field values.

The observer checks static cycles, field replacement, duplicate publication,
missing storage, failed construction, wrong-heap destinations, and shutdown.
Removing stack roots must preserve the static graph. Replacing its last edge
must allow the old graph to be collected. Heap shutdown destroys each payload
once. The allocation-failure observer separately fails registry and node allocation
and checks that neither failure changes the prior destination or registers a node.

Haxe plans must select static fields, defaults, startup order, and failure behavior.
These memory operations do not implement that policy or authorize dropping an
uncalled class's initializer. The normal C++ target still rejects unsupported
startup effects until compiler integration supplies those operations.

These native primitive tests do not prove generated Haxe lifetime behavior, host memory
exhaustion, external callback retention, or performance. Compiler integration and
the mixed object/callback witness remain open under `haxe_ocaml-9jezt`.

`ManagedCallableTest.cpp` checks traced callable environments and captured cells.
It covers recursion, shared copies, independent creators, replacement before and
during invocation, parameter roots, rooted result handoff, and exception unwinding.
It repeats collection before every allocation and inside call bodies. Destruction
counters and zero-live-node checks observe cleanup after the final root leaves.

`CellPayload` keeps unassigned state distinct from assigned null. Haxe chooses
write-once or replaceable storage. The native primitive enforces that choice; it
does not decide source mutability or project an unassigned value into Haxe null.
`ActiveCall` must exist before argument evaluation. Argument temporaries need
their own roots, and callee parameters need roots before collection can occur.
The callable payload stores a typed function pointer and one traced environment
edge. It does not hide captures inside `std::function`.

Run `npm run test:m14:cpp-managed-closure-abi` for the generated ABI check. Haxe
publishes callable types from exact typed closure signatures. The native fixture
checks those types independently, then invokes scalar, erased-value, and Void
callbacks under sanitizers. Returned arrays must retain their original identity.
Most callback bodies remain independent native observers. One authored Haxe
conditional-return body now passes through shared control lowering and managed
result publication. The fixture executes both branches and checks the returned
values. This does not prove complete Haxe function-body emission.

Parameter reads, Boolean conditions, and captured-cell returns now use
`CppManagedLocalAccess` in production code. The fixture no longer supplies those
value semantics. Its child closure's authored return reads the captured parameter
through the exact environment slot and preserves array identity after creator exit.
Compound expressions and additional allocation events still need explicit lowering.

The creator's authored `return function ...` also uses production emission.
`CppManagedRootedExpression` roots captured cells, constructs the environment and
callable, and publishes the callable before temporary roots leave scope. Two
creator invocations must retain independent arrays after both creators return.
The native fixture observes parameter lifetime and returned identity; it does
not construct the returned child. Releasing all result roots must collect every
allocation.

The typed projection records its own callable type annotations. The capture
catalog binds those annotations to exact published expression objects. Authored
casts and copied or replaced annotations cannot authorize implicit conversion.
This check does not establish ordinary C++ target integration or cast support.

`CppManagedLocalStorage` places roots and captured cells at source declarations.
The authored creator copies an input through an ordinary local into a captured
local, then returns a child. After creator exit, the child must return the same
array allocation with value 53. A separate authored named function returns
itself. Its cell initializes once, and the returned callable preserves identity.
After all external roots leave, collection must reclaim that self-reference cycle.
Both creator bodies and child bodies use the shared control renderer.

These checks cover initialized declarations with supported value expressions.
Uninitialized source locals, implicit conversions, loop/pattern/catch binding allocation,
static locals, compound updates, and general call adaptation remain separate work.
The original recursive counter still requires ordinary target integration.

Source assignments resolve a captured cell or a scoped value root before the
right-hand side runs. A selected cell gets its own temporary root. The assigned
value also stays rooted, and the assignment result is published after the write.
The fixture exercises chained assignments, ordinary locals, managed parameters,
and writes through copied escaped closures. Another branch replaces the captured
value with a newly allocated closure. The replacement returns itself after the
original closures leave, and the final collection must reclaim its cycle.
Named-function reassignment, implicit conversions, and direct leaf-parameter
writes fail explicitly. Source mutability checks still belong to the shared typer.

`CppManagedSourceCall` resolves callable locals from their exact typed bindings.
It prepares source operands for the same native call sequencer used by the ABI
checks. The fixture replaces its selected function in the first argument and
allocates a captured closure in the second. The original function must run, and
the returned child must retain the input array after the caller leaves.

Additional source cases cover nested calls, Boolean results, and Void calls.
For a null function, argument effects must run before invocation fails. Failure
must preserve the caller's previous result. These checks admit exact arity and
matching types or common-value erasure. Defaults, rest packing, other callee
forms, implicit conversions, and normal target integration remain unfinished.

An authored integer-returning function can return a collecting callback's result.
Its expression completes in rooted storage before the scalar return leaves scope.
The native observer checks zero, both signs, and the signed 32-bit limits.

String arguments and results use common value storage, which distinguishes null
from empty text. Direct `std::string` transport cannot preserve that distinction.
The generated caller preserves null, empty text, and long text across collection.
Bool, Int, and Float retain exact scalar transport through `CppManagedLeaf`.
This module does not implement conversions or arithmetic. Null literal lowering
and the original counter through normal C++ emission remain unfinished.

The counter's authored creator and recursive body now also run through managed
storage. A copied closure survives creator exit, consecutive calls return 3 and
5, a second creator has independent state, and collection reclaims the cycles.
The factory is read directly from the unchanged `source_named_function_seed`,
including its original `if (value == 0)` branch.
Production function emission supplies its nested entries and signatures; normal
target integration is pending.

`CppManagedInteger` emits exact Int addition, subtraction, and comparisons.
Operands finish left to right in rooted storage. Addition and subtraction use
64-bit intermediates, then wrap into the signed 32-bit range. Local and captured
Int updates retain the selected location and preserve prefix/postfix results.
Conditional expressions evaluate only the selected branch. Boundary expectations
come from `test/oracle/cpp_managed_integer_seed`; native callbacks also collect
between operand effects. Other numeric types and conversions are not admitted.

Boolean control tests complete their expression steps before choosing a branch
or loop iteration. A synchronous native expression scope retains temporary roots
through collecting callbacks, then returns only the Boolean. It cannot accept
source returns or coerce non-Boolean values. Native observers check true/false
branches, repeated `while` tests, `do-while` test timing, and exception cleanup.

`CppManagedFunctionOwner` distinguishes an ordinary method's exact projection
from a nested function's exact expression. Root parameters and local declarations
use the same storage emitters as closures. Their ABI has no closure-environment
operand. A native observer passes borrowed arrays into root parameter setup,
collects during capture promotion, then calls the returned child after root exit.
The child retains the original array. Foreign projections and mutated bodies
fail before storage can be selected.

The same observer now renders the complete authored root body, including child
construction and return publication. The recursive counter factory is also a
real root method. Root declarations, expressions, lexical blocks, branches, and
returns use `CppControlRegion`; ordinary returns use the exact typed method
destination. Scalar and void-returning methods pass native checks too. Root
loop/catch projection, receiver transport, and normal target integration remain
unfinished.

`CppManagedFunctionEmitter` generates complete native function units from the
checked projection and program-allocated root symbol. It owns closure entry
names, forward declarations, environment links, ABI signatures, parameter setup,
and bodies. Independent C++ type assertions check the root signatures. The
counter and root-method tests no longer write those signatures or link tables.
Both captured inputs remain observable after promotion and collection through
the returned child's Boolean selector. Repeated emission is deterministic;
mutated projections, colliding names, and unadapted defaults fail explicitly.
Receivers and normal target selection remain open.

`CppManagedProgramEmitter` links static methods by the exact declaration identity
published by shared typing. Calls use the same ordered argument and result
storage as callable-value calls. Native cases cover later declarations, an
escaped closure calling a static method, same-named methods on different classes,
collecting argument effects, managed result relay, and observable void effects.
Missing targets, wrong declaration resolution, copied call expressions, and stale
callee bodies are rejected. This does not admit arbitrary receiver expressions,
defaults, or legacy target carriers.

The check uses the repository's GNU timeout convention: `gtimeout` on macOS and
`timeout` on Linux. Each native compiler or observer has a 60-second bound.

Array and anonymous-object construction uses retained aggregate types from
`TypedBodyProjectionBuilder`. An occurrence owns exact projected children and
their source order. Equal-text copies, replaced children, and access from the
wrong lexical function cannot select its storage. Unresolved Array providers
and implicit child conversions fail explicitly.

`CppManagedAggregate` roots the new parent before evaluating children. Each
child finishes in a temporary root before insertion into the traced parent.
The emitter publishes the completed parent only after all children succeed.
`RecordPayload` supplies checked named-field storage without Haxe conversion
or reflection policy. String literals preserve exact UTF-8 bytes and embedded
zeroes through an explicit native byte count.

The aggregate observer uses the real Array provider and authored construction
methods in `test/oracle/cpp_managed_aggregate_seed`. It checks an object/array/
callback graph after creator exit, collecting initializer effects, copied
results, shared array identity, exceptions, and zero live allocations after
release. These methods use production managed emission. The ordinary C++ target
still requires the complete carrier and runtime replacement.

Compiler-created branch results use `LocalSlot` when they do not escape their
lexical scope. The slot registers a root immediately but rejects reads before
assignment. Assigning null satisfies the slot's presence requirement. Captured
locations keep the existing shared-cell representation. Exact compiler temporary
identities authorize deferred assignment; source names cannot authorize it.

`CppManagedSwitch` evaluates a scalar input once and selects one shared arm.
Default is a fallback regardless of its source position. The generated if/else
chain adds no loop or native switch, so source loop exits keep their destination.
Root method statements and nested function regions use the same selection
service. Literal Int, Bool, String, String null, and alternative patterns are
supported; patterns that create bindings remain explicit unsupported cases.

The control-value observer uses `test/oracle/cpp_managed_control_value_seed`.
Collecting callbacks return managed arrays or throw before a result completes.
Checks cover both conditional outcomes, every switch arm, nested switches,
early function returns, null results, and zero live allocations after release.
The primitive value test separately distinguishes unassigned storage from null.

The ABI check also generates environment fields and tracing functions from exact
capture identities. It covers captured cells, a receiver, and empty environments.
Collection during invocation must preserve each reachable cell and receiver.
After the final roots leave, the heap must contain no live allocations.
The native fixture compiles using only the published headers and generated file.

Construction blocks also come from the Haxe environment emitter. They select
capture fields by declaration identity, root the input cells, allocate the
environment, then allocate the callable while retaining that environment.
Forced collection checks shared mutable cells and receiver retention. Failed
construction must preserve the previous callable and release temporary storage
for collection. The emitter does not choose source binding allocation sites yet.

Generated cell operations preserve the selected place across right-hand-side
effects and collection. Reads copy into an existing root. Writes preserve shared
storage, and named-function cells accept only their initial value. The fixture
checks a recursive cell/environment/callable cycle, failed writes, and an assignment
whose right-hand side removes the cell's last external root. Allocation requires
the exact source event; placing that operation in ordinary emitted bodies remains
part of compiler integration.

Generated parameter entry code roots every incoming managed value before it
allocates cells for parameters captured by child functions. A focused observer
starts with borrowed inputs, forces collection during promotion, and calls a
returned child after the creator has left. The child must retain the original
array allocation. Source parameter identities and allocation events come from
the exact closure plan, not parameter spellings.

The same fixture uses generated call blocks to select a callable before evaluating
arguments. Later argument effects can release the caller's references and collect
the heap. Earlier arguments and the selected callable must survive those effects.
Argument and body failures must preserve the caller's previous result. A null
callable fails at invocation, after argument effects, matching the upstream probe
in `test/oracle/cpp_null_callable_seed`. These checks cover call-block generation;
normal Haxe function-body emission still needs integration.

`CppControlRegion` handles direct, Void, and caller-rooted return transport through
one control-flow renderer. A managed return publishes its value before local roots
leave scope. Exact return destinations, lexical scopes, branches, and loops retain
the same shared lowering contract used by ordinary C++ emission.

Run `npm run test:m14:cpp-managed-runtime-packaging` to check runtime publication.
The Haxe build macro embeds the authored headers and their SHA-256 hashes.
`ManagedOutput.hpp` supplies byte output without owning Haxe value formatting.
The real-provider output fixture checks exact bytes and native write failures;
see [the output fixture](../oracle/cpp_managed_output_seed/README.md).
A warm upstream compiler rebuild must observe a changed header. Previously built
publishers must retain their original snapshot after the isolated source is removed.
This test needs upstream Haxe and Neko; it does not prove native hxhx bootstrap
or native macro dependency invalidation. The test owns and stops its compiler server.

The native headers own C++ allocation, root lifetimes, and typed function-pointer
invocation. Generated Haxe plans must control when those operations occur. Complete
temporary-root planning and replacement of the old C++ emitter carriers remain
required before the original escaped-closure workload can pass.
