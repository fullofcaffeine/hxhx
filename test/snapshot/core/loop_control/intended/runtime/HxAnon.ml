(* Minimal anonymous-structure runtime for reflaxe.ocaml (WIP).

   Why this exists
   --------------
   Haxe anonymous structures are structural/dynamic objects:

     var o = { foo: 1, bar: "x" };
     trace(o.foo);
     o.foo = 2;

   In OCaml, there is no built-in structural object type with named fields that
   can be created ad-hoc without defining a concrete record type.

   The backend therefore represents anonymous structures as a string-keyed table
   of `Obj.t` values. This keeps the representation uniform across distinct
   structural types and allows interop with other permissive runtime shims.

   What we implement
   -----------------
   - `create`: allocate a fresh object (returned as `Obj.t` for easy embedding)
   - `get`: read a field as `Obj.t` (missing field => `HxRuntime.hx_null`)
   - `set`: write a field

   Notes / limitations
   -------------------
   - This is a portable-mode strategy; an OCaml-native mode may later map some
     well-known anonymous shapes to records for performance/typing.
   - There is no reflection surface yet (Type/Reflect are still guarded). *)

type t = (string, Obj.t) Hashtbl.t

let create () : Obj.t =
  Obj.repr (Hashtbl.create 8 : t)

let get (o : Obj.t) (field : string) : Obj.t =
  let tbl : t = Obj.obj o in
  match Hashtbl.find_opt tbl field with
  | Some v -> v
  | None -> HxRuntime.hx_null

let set (o : Obj.t) (field : string) (value : Obj.t) : unit =
  let tbl : t = Obj.obj o in
  Hashtbl.replace tbl field value

