# Cpp Sys/Event-Loop Smoke Audit

This note owns the `haxe_ocaml-zo90` checkpoint for Cpp sys/event-loop smoke
scaffolding. It classifies the target-owned support emitted by
`CppRuntimeSupport.sysEventLoopLines` and the related `CppTargetCore` type/param
lowering.

Strict Cpp Gate3 remains red. This audit is internal blocker burn-down only, so
README and North Star progress bars stay unchanged unless strict gates and
public usability evidence change.

## Current Decision

The Cpp sys/event-loop helpers remain `bounded_bringup_support`, not parity
support. They keep current Cpp smoke/strict-gate compile shapes moving, but many
methods are no-op, synchronous, or single-queue approximations.

Generated C++ carries visible `hxhx-cpp-smoke-only` or
`hxhx-cpp-bounded-bringup` markers beside these support blocks, and
`test/M14CppNativeBackendSmokeIntegrationTest.hx` asserts the markers survive
generation. Those assertions are guardrails against accidental parity wording;
they are not runtime parity evidence.

## Inventory

| Surface | Classification | Current scope | Before expansion |
| --- | --- | --- | --- |
| `__hxhx_shift` | `bounded_bringup_support` | Removes the first item from a non-empty generated function queue used by `EntryPoint.processEvents`. | Oracle cases for `Array.shift`-style empty behavior are out of scope here; do not reuse this as general Array parity. |
| `Timer.stamp` | `bounded_bringup_support` | Monotonic seconds since generated-process startup via `std::chrono::steady_clock`. | Oracle cases for target-stable stamp origin, monotonicity, precision, and wall-clock assumptions. |
| `Timer.delay` | `bounded_bringup_support`, smoke-only | Accepts callback and delay arguments, ignores both, returns a `Timer` object. | Real scheduling behavior, delayed callback execution, cancellation, and exception propagation cases. |
| `Timer.stop` | `bounded_bringup_support`, smoke-only | No-op cleanup shape for current async timeout helpers. | Oracle-backed cancellation semantics tied to real `Timer.delay` support. |
| `Http` constructor and callback fields | `bounded_bringup_support` | Stores URL plus callback field types for generated assignment shape. | Behavior for URL parsing, status/error callbacks, bytes/data callback interaction, redirects, and platform transport. |
| `Http.setPostData`, `setPostBytes` | `bounded_bringup_support` | Tracks which payload mode was selected but does not preserve/send payload bytes. | Payload, method, header, and callback oracle cases before transport support. |
| `Http.request` | `unsupported_diagnostic` | Performs no transport; calls `onError("hxhx cpp Http transport unsupported: <url>")` when available, otherwise throws. | Real request execution must be a separate transport bead with oracle cases. |
| `__hxhx_http_bytes` | `bounded_bringup_support`, smoke-only | Callback payload carrier with `size` and `get`; out-of-range `get` returns `0`. | Byte payload oracle cases and unsupported diagnostics for missing/invalid bytes. |
| `Lock.acquire` | `declaration_only_support`, smoke-only | Legacy compile-shape method; not part of the upstream `sys.thread.Lock` public API. | Remove from generated dependencies when the surrounding event-loop scaffold no longer needs it. |
| `Lock.wait`, `Lock.release` | `bounded_bringup_support` | Counting release semantics with optional timeout using target-owned `std::condition_variable` support. | Cross-thread wakeups through generated `sys.thread.Thread`/event-loop support before target-thread parity claims. |
| `Mutex.acquire`, `Mutex.release` | `bounded_bringup_support` | Uses target-owned `std::recursive_mutex` so owner-thread recursive acquire/release behavior is no longer a no-op. | Cross-thread ownership/invalid-release behavior and generated `Thread.create` interaction. |
| `Mutex.tryAcquire` | `bounded_bringup_support` | Uses `std::recursive_mutex::try_lock`, including owner-thread recursive success. | Oracle-backed contention false cases through generated Cpp threading support. |
| `MainEvent` | `bounded_bringup_support`, smoke-only | Carries a callback, linked-list pointers, priority, and `nextRun`; `wakeup` is no-op and `stop` unlinks from the local list. | Delay/stop/wakeup behavior with real scheduler state, priorities, and cancellation. |
| `MainLoop.add` / `hasEvents` | `bounded_bringup_support`, smoke-only | Adds to one static pending linked list and reports whether it is non-null. | Oracle-backed queue ordering, event ownership, priorities, and main-loop lifecycle. |
| `MainLoop.sortEvents` | `bounded_bringup_support`, smoke-only | No-op. | Priority and scheduled-time ordering oracle cases. |
| `MainLoop.tick` | `bounded_bringup_support`, smoke-only | Pops at most one pending event, runs it synchronously, and returns negative Infinity or the next event time. | Real event-loop timing, repeated ticks, exception handling, and delayed-event ordering. |
| `EntryPoint.runInMainThread` | `bounded_bringup_support`, smoke-only | Queues a callback in a vector and wakes a no-op lock. | Thread-main handoff semantics and ordering. |
| `EntryPoint.addThread` | `bounded_bringup_support`, smoke-only | Runs the callback synchronously while incrementing/decrementing `threadCount`. | Real thread creation, lifecycle, error propagation, and event-loop interaction. |
| `EntryPoint.processEvents` | `bounded_bringup_support`, smoke-only | Drains queued callbacks synchronously, then runs one `MainLoop.tick`. | Real process loop semantics, blocking/sleep behavior, pending thread interaction, and no-event behavior. |
| `CppTargetCore` known field/return/param lowering for these classes | `declaration_only_support` plus smoke routing | Preserves generated C++ types and callback coercions so smoke programs compile. | Runtime behavior must be owned by the support implementation or explicit diagnostics, not inferred from type routing. |

## Required Oracle Cases

Before any of these helpers are promoted beyond smoke support, add upstream Haxe
`4.3.7` oracle cases for the touched surface:

- `Timer.stamp`, `Timer.delay`, and `Timer.stop`: monotonic readings, callback
  execution, delay ordering, cancellation, nested timers, and thrown errors.
- `Http`: constructor URL behavior, post data/bytes, request invocation, data
  callback, bytes callback, error callback, status handling, and invalid
  endpoints.
- `Lock` and `Mutex`: wait/release ordering, timeout behavior, contention,
  cross-thread wakeups, `tryAcquire` false cases, and invalid release behavior.
- `MainEvent` and `MainLoop`: event add order, priority ordering, delay timing,
  stop/cancel behavior, `hasEvents`, `tick` return values, nested events, and
  no-event behavior.
- `EntryPoint`: run-in-main-thread ordering, process loop termination,
  thread-count interaction, synchronous vs asynchronous behavior, and exception
  propagation.

Each Cpp case must be recorded as `pass`, `unsupported_diagnostic`, or
`known_divergence`. Smoke-only no-ops must not silently become parity claims.

## Lock/Mutex Checkpoint

`haxe_ocaml-8rxy` selected the following upstream Haxe `4.3.7` black-box oracle
cases before changing Cpp support:

| Case | Upstream Haxe 4.3.7 observation | Cpp classification after this slice |
| --- | --- | --- |
| Fresh `Lock.wait(0.0)` | `false` | `pass` |
| `Lock.release()` before `wait(0.0)` | first wait returns `true`, second immediate wait returns `false` | `pass` |
| Multiple `Lock.release()` calls before waits | two releases allow two waits, then the next immediate wait returns `false` | `pass` |
| Cross-thread `Lock.release()` wakes `Lock.wait(1.0)` | `true` | `known_divergence` for generated Haxe threading until Cpp `Thread.create`/event-loop support exists; the primitive Lock support is not enough for parity |
| Owner-thread `Mutex.tryAcquire()` recursion | `true`, then `true`, then `true` after matching releases | `pass` |
| Another thread `Mutex.tryAcquire()` while owner holds the mutex | `false` | `known_divergence` until generated Cpp threading support can run the contention case |
| `Mutex.release()` by a non-owner | upstream API documents this as undefined behavior | `unsupported_diagnostic` if future generated Cpp surfaces expose an invalid-release path |

The implemented slice is deliberately limited to primitive Lock release counts,
Lock timeouts, and Mutex owner-thread recursion. It does not add generated Cpp
thread creation, scheduler behavior, or Full 1.0 target-thread parity evidence.
README and North Star progress bars stay unchanged.

## Http Checkpoint

`haxe_ocaml-am6x` selected these upstream Haxe `4.3.7` oracle cases and public
API observations before changing Cpp support:

| Case | Upstream Haxe 4.3.7 observation | Cpp classification after this slice |
| --- | --- | --- |
| Constructing `new haxe.Http(url)` | Stores URL; no request starts until `request()` is called | `pass` for stored diagnostic URL only |
| `setPostData()` and `setPostBytes()` | Select one request payload mode and overwrite the previous payload | `known_divergence` because Cpp records only the selected mode, not payload bytes |
| Invalid URL such as `"://"` | `onError("Invalid URL")` | `unsupported_diagnostic`; Cpp reports unsupported transport through `onError` instead of pretending URL validation exists |
| Inaccessible host | `onError(...)` with target-dependent connection/resolve text | `unsupported_diagnostic`; Cpp reports unsupported transport through `onError` |
| Successful `onData`, `onBytes`, status, headers, redirects, and real POST behavior | Target transport invokes success/status callbacks | `known_divergence`; no Cpp transport is implemented |

The implemented slice intentionally changes `request()` from a silent no-op to
an explicit unsupported diagnostic. It does not add sockets, TLS, redirects,
status callbacks, response bytes, headers, or payload transmission. README and
North Star progress bars stay unchanged.

## Validation

Local coverage for the current bounded support is intentionally shape-focused:

- generated C++ contains `hxhx-cpp-smoke-only` markers for Timer, Http,
  Lock/Mutex, MainLoop/MainEvent, and EntryPoint support;
- `test/M14CppNativeBackendSmokeIntegrationTest.hx` asserts those markers and the
  existing generated-call shapes;
- broad behavior work remains blocked until oracle cases and implementation
  beads classify the result.

These checks keep the scaffolding honest. They do not replace upstream Haxe
`4.3.7` oracle evidence or strict Full 1.0 gates.
