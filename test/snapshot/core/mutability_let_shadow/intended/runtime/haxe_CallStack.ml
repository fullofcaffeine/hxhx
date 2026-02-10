(* Minimal `haxe.CallStack` runtime for reflaxe.ocaml bring-up.

   Why
   - Upstream-ish code (notably `utest`) calls `haxe.CallStack.exceptionStack()` and
     formats it via `haxe.CallStack.toString(stack)`.
   - The Stage3 bootstrap emitter links the repo-owned OCaml runtime (`std/runtime`)
     instead of compiling the full Haxe standard library, so these APIs must exist
     as target runtime shims.

   What
   - Represent a call stack as `HxArray.t string` of human-readable lines.
   - Provide `callStack`, `exceptionStack`, and `toString` with best-effort semantics.

   Non-goal
   - Full `StackItem` structure parity. Stage3 bring-up primarily needs stable,
     warning-clean compilation, not perfect stack fidelity. *)

type stackitem = string
type t = stackitem HxArray.t

let callStack () : t =
  (* Best-effort depth; enough for diagnostics without excessive allocation. *)
  HxBacktrace.callstack_lines 64

let exceptionStack () : t =
  HxBacktrace.exceptionstack_lines ()

let toString (stack : t) : string =
  let len = HxArray.length stack in
  if len = 0 then
    ""
  else (
    let buf = Buffer.create 128 in
    for i = 0 to len - 1 do
      let line = HxRuntime.dynamic_toStdString (Obj.repr (HxArray.get stack i)) in
      if i > 0 then Buffer.add_char buf '\n';
      Buffer.add_string buf line
    done;
    Buffer.contents buf
  )

(* Bring-up helper used by some std code paths; semantics are intentionally minimal. *)
let subtract (a : t) (_b : t) : t =
  a

