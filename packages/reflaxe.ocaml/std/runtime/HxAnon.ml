(* Anonymous-structure runtime for reflaxe.ocaml.

   Design summary
   --------------
   Portable Haxe anonymous structures are represented with a shape/slot layout:

   - Shape metadata maps field names to stable slot indexes.
   - Values are stored in slot arrays (`Obj.t array`) for compact access.
   - Presence is tracked separately (`bool array`) so `null` values are distinct
     from missing fields.
   - A tiny per-object repeated-field cache (`last_field`/`last_index`) keeps hot
     loops (`o.x = o.x + 1`) on a fast path.

   This keeps portable semantics while reducing repeated `Hashtbl` value lookups.

   Runtime type identity
   ---------------------
   We wrap the internal object record in a small marker block:

     block[0] = marker
     block[1] = Obj.repr <t>

   This allows `get/set/has/...` to validate arbitrary `Obj.t` safely before cast. *)

type shape = {
  index_by_name : (string, int) Hashtbl.t;
  mutable names : string array;
  mutable size : int;
}

type t = {
  mutable shape : shape;
  mutable values : Obj.t array;
  mutable present : bool array;
  mutable field_count : int;
  mutable cache_valid : bool;
  mutable last_field : string;
  mutable last_index : int;
}

let marker : Obj.t = Obj.repr (ref 0)

let create_shape () : shape =
  {
    index_by_name = Hashtbl.create 8;
    names = [||];
    size = 0;
  }

let ensure_shape_capacity (s : shape) (needed : int) : unit =
  let current = Stdlib.Array.length s.names in
  if current < needed then (
    let doubled = if current = 0 then 4 else current * 2 in
    let next_cap = if doubled < needed then needed else doubled in
    let next = Stdlib.Array.make next_cap "" in
    if s.size > 0 then Stdlib.Array.blit s.names 0 next 0 s.size;
    s.names <- next
  )

let ensure_value_capacity (obj : t) (needed : int) : unit =
  let current = Stdlib.Array.length obj.values in
  if current < needed then (
    let doubled = if current = 0 then 4 else current * 2 in
    let next_cap = if doubled < needed then needed else doubled in
    let next_values = Stdlib.Array.make next_cap HxRuntime.hx_null in
    let next_present = Stdlib.Array.make next_cap false in
    if obj.shape.size > 0 then (
      Stdlib.Array.blit obj.values 0 next_values 0 obj.shape.size;
      Stdlib.Array.blit obj.present 0 next_present 0 obj.shape.size
    );
    obj.values <- next_values;
    obj.present <- next_present
  )

let update_cache (obj : t) (field : string) (idx : int) : unit =
  obj.cache_valid <- true;
  obj.last_field <- field;
  obj.last_index <- idx

let invalidate_cache (obj : t) : unit =
  obj.cache_valid <- false;
  obj.last_field <- "";
  obj.last_index <- 0

let slot_index (obj : t) (field : string) : int =
  if obj.cache_valid && (obj.last_field == field || obj.last_field = field) then
    obj.last_index
  else
    match Hashtbl.find_opt obj.shape.index_by_name field with
    | Some idx ->
      update_cache obj field idx;
      idx
    | None -> -1

let add_slot (obj : t) (field : string) : int =
  let idx = obj.shape.size in
  ensure_shape_capacity obj.shape (idx + 1);
  ensure_value_capacity obj (idx + 1);
  Stdlib.Array.set obj.shape.names idx field;
  Hashtbl.replace obj.shape.index_by_name field idx;
  obj.shape.size <- idx + 1;
  update_cache obj field idx;
  idx

let is_anon (o : Obj.t) : bool =
  Obj.is_block o && Obj.size o = 2 && Obj.field o 0 == marker

let create () : Obj.t =
  let obj : t =
    {
      shape = create_shape ();
      values = [||];
      present = [||];
      field_count = 0;
      cache_valid = false;
      last_field = "";
      last_index = 0;
    }
  in
  let b = Obj.new_block 0 2 in
  Obj.set_field b 0 marker;
  Obj.set_field b 1 (Obj.repr obj);
  b

let anon_of_obj (o : Obj.t) : t =
  Obj.obj (Obj.field o 1)

let get (o : Obj.t) (field : string) : Obj.t =
  if is_anon o then
    let obj = anon_of_obj o in
    let idx = slot_index obj field in
    if idx >= 0 && Stdlib.Array.get obj.present idx then Stdlib.Array.get obj.values idx else HxRuntime.hx_null
  (* Use the array runtime's marker instead of inspecting a guessed record layout.
     Other blocks, including strings, can have the same size as an old array record. *)
  else if HxArray.is_value o then
    let a : Obj.t HxArray.t = Obj.obj o in
    (match field with
    | "iterator" -> Obj.repr (fun () -> HxIterator.of_array a)
    | "length" -> Obj.repr (HxArray.length a)
    | "indexOf" -> Obj.repr (fun (x : Obj.t) (fromIndex : int) -> HxArray.indexOf a x fromIndex)
    | "lastIndexOf" -> Obj.repr (fun (x : Obj.t) (fromIndex : int) -> HxArray.lastIndexOf a x fromIndex)
    | "slice" -> Obj.repr (fun (pos : int) (end_ : int) -> HxArray.slice a pos end_)
    | _ -> HxRuntime.hx_null)
  else if Obj.is_block o && Obj.tag o = Obj.string_tag then
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
    let obj = anon_of_obj o in
    let current_idx = slot_index obj field in
    let idx = if current_idx >= 0 then current_idx else add_slot obj field in
    if not (Stdlib.Array.get obj.present idx) then obj.field_count <- obj.field_count + 1;
    Stdlib.Array.set obj.present idx true;
    Stdlib.Array.set obj.values idx value;
    update_cache obj field idx
  )

let has (o : Obj.t) (field : string) : bool =
  if not (is_anon o) then
    false
  else
    let obj = anon_of_obj o in
    let idx = slot_index obj field in
    idx >= 0 && Stdlib.Array.get obj.present idx

(* `Reflect.fields` support (minimal).

   Why
   - Portable Haxe code (and upstream test harnesses like utest) use `Reflect.fields`
     on anonymous structures to probe for "duck-typed" capabilities (e.g. iterator()).

   What
   - Returns the list of enumerable field names for `o` if it is an `HxAnon` object.
   - For non-anon values, returns an empty array.

   Notes
   - Order is insertion-slot order (stable for existing fields). *)
let fields (o : Obj.t) : string HxArray.t =
  if not (is_anon o) then
    HxArray.create ()
  else
    let obj = anon_of_obj o in
    let out = HxArray.create () in
    if obj.shape.size > 0 then
      for idx = 0 to obj.shape.size - 1 do
        if Stdlib.Array.get obj.present idx then ignore (HxArray.push out (Stdlib.Array.get obj.shape.names idx))
      done;
    out

(* `Reflect.deleteField` support (minimal). *)
let delete (o : Obj.t) (field : string) : bool =
  if not (is_anon o) then
    false
  else
    let obj = anon_of_obj o in
    let idx = slot_index obj field in
    if idx < 0 then
      false
    else if Stdlib.Array.get obj.present idx then (
      Stdlib.Array.set obj.present idx false;
      Stdlib.Array.set obj.values idx HxRuntime.hx_null;
      obj.field_count <- obj.field_count - 1;
      true
    ) else
      false

(* `Reflect.copy` support (minimal). *)
let copy (o : Obj.t) : Obj.t =
  if HxRuntime.is_null o then
    HxRuntime.hx_null
  else if not (is_anon o) then
    o
  else
    let src = anon_of_obj o in
    let out = create () in
    let dst = anon_of_obj out in
    if src.shape.size > 0 then (
      ensure_shape_capacity dst.shape src.shape.size;
      ensure_value_capacity dst src.shape.size;
      for idx = 0 to src.shape.size - 1 do
        let name = Stdlib.Array.get src.shape.names idx in
        Stdlib.Array.set dst.shape.names idx name;
        Hashtbl.replace dst.shape.index_by_name name idx;
        if Stdlib.Array.get src.present idx then (
          Stdlib.Array.set dst.present idx true;
          Stdlib.Array.set dst.values idx (Stdlib.Array.get src.values idx);
          dst.field_count <- dst.field_count + 1
        )
      done;
      dst.shape.size <- src.shape.size
    );
    out
