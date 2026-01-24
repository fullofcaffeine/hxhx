(* Minimal runtime scaffolding for reflaxe.ocaml (WIP).
   This will grow as std/_std overrides land. *)

exception Hx_exception of Obj.t

let hx_throw (v : Obj.t) : 'a =
  raise (Hx_exception v)

