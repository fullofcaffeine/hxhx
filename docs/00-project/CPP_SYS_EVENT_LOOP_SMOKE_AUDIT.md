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
methods are no-op, always-success, synchronous, or single-queue approximations.

Generated C++ now carries `hxhx-cpp-smoke-only` markers beside these support
blocks, and `test/M14CppNativeBackendSmokeIntegrationTest.hx` asserts the
markers survive generation. Those assertions are guardrails against accidental
parity wording; they are not runtime parity evidence.

## Inventory

| Surface | Classification | Current scope | Before expansion |
| --- | --- | --- | --- |
| `__hxhx_shift` | `bounded_bringup_support` | Removes the first item from a non-empty generated function queue used by `EntryPoint.processEvents`. | Oracle cases for `Array.shift`-style empty behavior are out of scope here; do not reuse this as general Array parity. |
| `Timer.stamp` | `bounded_bringup_support` | Monotonic seconds since generated-process startup via `std::chrono::steady_clock`. | Oracle cases for target-stable stamp origin, monotonicity, precision, and wall-clock assumptions. |
| `Timer.delay` | `bounded_bringup_support`, smoke-only | Accepts callback and delay arguments, ignores both, returns a `Timer` object. | Real scheduling behavior, delayed callback execution, cancellation, and exception propagation cases. |
| `Timer.stop` | `bounded_bringup_support`, smoke-only | No-op cleanup shape for current async timeout helpers. | Oracle-backed cancellation semantics tied to real `Timer.delay` support. |
| `Http` constructor and callback fields | `bounded_bringup_support`, smoke-only | Stores callback field types for generated assignment shape; ignores URL. | Behavior for URL parsing, invalid URLs, status/error callbacks, bytes/data callback interaction, redirects, and platform transport. |
| `Http.setPostData`, `setPostBytes`, `request` | `bounded_bringup_support`, smoke-only | Methods accept generated calls but ignore payloads and never perform transport. | Real request execution or explicit unsupported diagnostics; payload, method, header, error, and callback oracle cases. |
| `__hxhx_http_bytes` | `bounded_bringup_support`, smoke-only | Callback payload carrier with `size` and `get`; out-of-range `get` returns `0`. | Byte payload oracle cases and unsupported diagnostics for missing/invalid bytes. |
| `Lock.acquire`, `Lock.release` | `bounded_bringup_support`, smoke-only | No-op methods for compile shape. | Blocking semantics, release-before-wait behavior, timeouts, and cross-thread wakeups. |
| `Lock.wait` | `bounded_bringup_support`, smoke-only | Always returns `true` and ignores timeout. | Oracle-backed wait/timeout behavior or unsupported diagnostic. |
| `Mutex.acquire`, `Mutex.release` | `bounded_bringup_support`, smoke-only | No-op methods for compile shape. | Mutual exclusion, recursive/acquire failure behavior, and release error cases. |
| `Mutex.tryAcquire` | `bounded_bringup_support`, smoke-only | Always returns `true`. | Oracle-backed contention behavior or unsupported diagnostic. |
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
