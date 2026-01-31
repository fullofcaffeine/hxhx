(* Minimal runtime scaffolding for reflaxe.ocaml (WIP).
   This will grow as std/_std overrides land. *)

exception Hx_exception of Obj.t
exception Hx_break
exception Hx_continue
exception Hx_return of Obj.t

(* Sentinel used to represent Haxe `null` across otherwise non-nullable OCaml types.
   Must be a heap block (not an immediate like `()`) so it doesn't collide with
   immediate values such as `int`/`bool`. *)
let hx_null : Obj.t = Obj.repr (ref 0)

let hx_throw (v : Obj.t) : 'a =
  raise (Hx_exception v)

let hx_try (f : unit -> 'a) (handler : Obj.t -> 'a) : 'a =
  try f () with
  | Hx_exception v -> handler v
  | Hx_break -> raise Hx_break
  | Hx_continue -> raise Hx_continue
  | Hx_return v -> raise (Hx_return v)
  | exn -> handler (Obj.repr exn)
