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
  if is_anon o then
    let tbl : t = Obj.obj (Obj.field o 1) in
    match Hashtbl.find_opt tbl field with
    | Some v -> v
    | None -> HxRuntime.hx_null
  else if Obj.is_block o && Obj.size o = 2 && Obj.field o 0 != marker && Obj.is_int (Obj.field o 1) then
    let a : Obj.t HxArray.t = Obj.obj o in
    (match field with
    | "iterator" -> Obj.repr (fun () -> HxIterator.of_array a)
    | "length" -> Obj.repr (HxArray.length a)
    | "indexOf" -> Obj.repr (fun (x : Obj.t) (fromIndex : int) -> HxArray.indexOf a x fromIndex)
    | "lastIndexOf" -> Obj.repr (fun (x : Obj.t) (fromIndex : int) -> HxArray.lastIndexOf a x fromIndex)
    | "slice" -> Obj.repr (fun (pos : int) (end_ : int) -> HxArray.slice a pos end_)
    | _ -> HxRuntime.hx_null)
  else if Obj.is_block o && Obj.tag o = Obj.string_tag then
    (* Support String method dispatch through dynamic-field lookup.

       Stage3 bring-up still routes a subset of `s.method(...)` calls through
       `HxAnon.get (Obj.repr s) "method"`.

       Keep these bridges small and explicit so missing methods fail with `null`
       rather than segfaulting via non-callable values. *)
    let s : string = Obj.obj o in
    (match field with
    | "cca" -> Obj.repr (fun (i : int) -> HxString.cca s i)
    | "indexOf" -> Obj.repr (fun (sub : string) (startIndex : int) -> HxString.indexOf s sub startIndex)
    | "lastIndexOf" -> Obj.repr (fun (sub : string) (startIndex : int) -> HxString.lastIndexOf s sub startIndex)
    | "substr" -> Obj.repr (fun (pos : int) (len : int) -> HxString.substr s pos len)
    | "substring" -> Obj.repr (fun (startIndex : int) (endIndex : int) -> HxString.substring s startIndex endIndex)
    | _ -> HxRuntime.hx_null)
  else
    HxRuntime.hx_null

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

(* `Reflect.fields` support (minimal).

   Why
   - Portable Haxe code (and upstream test harnesses like utest) use `Reflect.fields`
     on anonymous structures to probe for "duck-typed" capabilities (e.g. iterator()).

   What
   - Returns the list of enumerable field names for `o` if it is an `HxAnon` object.
   - For non-anon values, returns an empty array.

   Notes
   - Order is unspecified (matches Haxe contract). *)
let fields (o : Obj.t) : string HxArray.t =
  if not (is_anon o) then
    HxArray.create ()
  else
    let tbl : t = Obj.obj (Obj.field o 1) in
    let out = HxArray.create () in
    Hashtbl.iter (fun k _v -> ignore (HxArray.push out k)) tbl;
    out

(* `Reflect.deleteField` support (minimal). *)
let delete (o : Obj.t) (field : string) : bool =
  if not (is_anon o) then
    false
  else
    let tbl : t = Obj.obj (Obj.field o 1) in
    let existed = Hashtbl.mem tbl field in
    if existed then Hashtbl.remove tbl field;
    existed

(* `Reflect.copy` support (minimal). *)
let copy (o : Obj.t) : Obj.t =
  if HxRuntime.is_null o then
    HxRuntime.hx_null
  else if not (is_anon o) then
    (* Only guaranteed for anonymous structures. Best-effort: return original. *)
    o
  else
    let tbl : t = Obj.obj (Obj.field o 1) in
    let out = create () in
    Hashtbl.iter (fun k v -> set out k v) tbl;
    out
