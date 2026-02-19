(* OCaml backtrace helpers for reflaxe.ocaml.

   Why this exists
   - Haxe exposes stack information via `haxe.CallStack` and `haxe.Exception.stack`.
   - The upstream stdlib routes these APIs through `haxe.NativeStackTrace`, which is
     an `extern` and must be implemented per-target.
   - In OCaml, backtraces are opt-in and are represented as `Printexc.raw_backtrace`.

   Design notes
   - We keep this in a separate module so `HxRuntime` does not depend on `HxArray`,
     avoiding an OCaml module cycle (HxArray already depends on HxRuntime).
   - We return `HxArray.t string` so Haxe-side code can treat the result as
     `Array<String>` in target std overrides. *)

let () = Printexc.record_backtrace true

let split_lines (s : string) : string list =
  (* Normalize to non-empty lines. `Printexc.*_to_string` uses `\n` line breaks. *)
  let raw = String.split_on_char '\n' s in
  List.filter (fun line -> String.length line > 0) raw

let to_hx_array (lines : string list) : string HxArray.t =
  let a = HxArray.create () in
  List.iter (fun line -> ignore (HxArray.push a line)) lines;
  a

let callstack_lines (depth : int) : string HxArray.t =
  let depth = if depth <= 0 then 1 else depth in
  let bt = Printexc.get_callstack depth in
  to_hx_array (split_lines (Printexc.raw_backtrace_to_string bt))

let exceptionstack_lines () : string HxArray.t =
  (* Meaningful inside an exception handler; outside it may be empty. *)
  let bt = Printexc.get_raw_backtrace () in
  to_hx_array (split_lines (Printexc.raw_backtrace_to_string bt))

