(* Minimal runtime scaffolding for reflaxe.ocaml (WIP).
   This will grow as std/_std overrides land. *)

exception Hx_exception of Obj.t

let hx_throw (v : Obj.t) : 'a =
  raise (Hx_exception v)

let hx_try (f : unit -> 'a) (handler : Obj.t -> 'a) : 'a =
  try f () with
  | Hx_exception v -> handler v
  | exn -> handler (Obj.repr exn)
