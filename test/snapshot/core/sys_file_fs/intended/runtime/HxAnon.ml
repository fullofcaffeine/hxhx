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

(* Runtime type identity:
   We must be able to accept an arbitrary `Obj.t` from Haxe `Dynamic` code and
   safely decide if it is one of our anonymous-structure objects.

   `Obj.obj` has no runtime checks and is unsafe on arbitrary values, so we use a
   small "header block" with a unique marker in field 0:

     block[0] = marker
     block[1] = Obj.repr <hashtbl>

   This lets `get/set/has` guard via `Obj.field` without casting first. *)

let marker : Obj.t = Obj.repr (ref 0)

let is_anon (o : Obj.t) : bool =
  Obj.is_block o && Obj.size o = 2 && Obj.field o 0 == marker

let create () : Obj.t =
  let tbl = (Hashtbl.create 8 : t) in
  let b = Obj.new_block 0 2 in
  Obj.set_field b 0 marker;
  Obj.set_field b 1 (Obj.repr tbl);
  b

let get (o : Obj.t) (field : string) : Obj.t =
  if not (is_anon o) then
    HxRuntime.hx_null
  else
    let tbl : t = Obj.obj (Obj.field o 1) in
    match Hashtbl.find_opt tbl field with
    | Some v -> v
    | None -> HxRuntime.hx_null

let set (o : Obj.t) (field : string) (value : Obj.t) : unit =
  if is_anon o then (
    let tbl : t = Obj.obj (Obj.field o 1) in
    Hashtbl.replace tbl field value
  )

let has (o : Obj.t) (field : string) : bool =
  if not (is_anon o) then
    false
  else
    let tbl : t = Obj.obj (Obj.field o 1) in
    Hashtbl.mem tbl field
