(* Minimal Haxe Map runtime for reflaxe.ocaml (WIP).

   Goals (M6):
   - Provide usable baseline semantics for `haxe.ds.Map` specializations
     (StringMap / IntMap / ObjectMap) so we can bootstrap larger codebases
     (eventually including Haxe-in-Haxe).
   - Keep representation simple and reasonably efficient on OCaml 4.13+.

   Notes:
   - Values are stored as `Obj.t` so we can support generic `'v` maps.
   - For ObjectMap we use physical equality (`==`) to approximate Haxe object
     identity semantics.
   - `get` returns a "null-like" value when the key is missing. This matches
     Haxe's `Null<T>` behavior where `get` returns null for missing keys.
*)

let hx_null : Obj.t = Obj.repr ()

type 'v string_map = (string, Obj.t) Hashtbl.t
type 'v int_map = (int, Obj.t) Hashtbl.t

module ObjKey = struct
  type t = Obj.t
  let equal (a : t) (b : t) : bool = a == b
  let hash (x : t) : int = Hashtbl.hash x
end

module ObjTbl = Hashtbl.Make (ObjKey)
type ('k, 'v) obj_map = Obj.t ObjTbl.t

let create_string () : 'v string_map =
  Hashtbl.create 16

let create_int () : 'v int_map =
  Hashtbl.create 16

let create_object () : ('k, 'v) obj_map =
  ObjTbl.create 16

let set_string (m : 'v string_map) (key : string) (value : 'v) : unit =
  Hashtbl.replace m key (Obj.repr value)

let set_int (m : 'v int_map) (key : int) (value : 'v) : unit =
  Hashtbl.replace m key (Obj.repr value)

let set_object (m : ('k, 'v) obj_map) (key : 'k) (value : 'v) : unit =
  ObjTbl.replace m (Obj.repr key) (Obj.repr value)

let get_string (m : 'v string_map) (key : string) : 'v =
  try Obj.obj (Hashtbl.find m key) with Not_found -> Obj.obj hx_null

let get_int (m : 'v int_map) (key : int) : 'v =
  try Obj.obj (Hashtbl.find m key) with Not_found -> Obj.obj hx_null

let get_object (m : ('k, 'v) obj_map) (key : 'k) : 'v =
  try Obj.obj (ObjTbl.find m (Obj.repr key)) with Not_found -> Obj.obj hx_null

let exists_string (m : 'v string_map) (key : string) : bool =
  Hashtbl.mem m key

let exists_int (m : 'v int_map) (key : int) : bool =
  Hashtbl.mem m key

let exists_object (m : ('k, 'v) obj_map) (key : 'k) : bool =
  ObjTbl.mem m (Obj.repr key)

let remove_string (m : 'v string_map) (key : string) : bool =
  let had = Hashtbl.mem m key in
  if had then Hashtbl.remove m key else ();
  had

let remove_int (m : 'v int_map) (key : int) : bool =
  let had = Hashtbl.mem m key in
  if had then Hashtbl.remove m key else ();
  had

let remove_object (m : ('k, 'v) obj_map) (key : 'k) : bool =
  let k = Obj.repr key in
  let had = ObjTbl.mem m k in
  if had then ObjTbl.remove m k else ();
  had

let clear_string (m : 'v string_map) : unit =
  Hashtbl.clear m

let clear_int (m : 'v int_map) : unit =
  Hashtbl.clear m

let clear_object (m : ('k, 'v) obj_map) : unit =
  ObjTbl.clear m

let copy_string (m : 'v string_map) : 'v string_map =
  Hashtbl.copy m

let copy_int (m : 'v int_map) : 'v int_map =
  Hashtbl.copy m

let copy_object (m : ('k, 'v) obj_map) : ('k, 'v) obj_map =
  ObjTbl.copy m

let keys_string (m : 'v string_map) : string HxArray.t =
  let out = HxArray.create () in
  Hashtbl.iter (fun k _ -> ignore (HxArray.push out k)) m;
  out

let keys_int (m : 'v int_map) : int HxArray.t =
  let out = HxArray.create () in
  Hashtbl.iter (fun k _ -> ignore (HxArray.push out k)) m;
  out

let keys_object (m : ('k, 'v) obj_map) : 'k HxArray.t =
  let out = HxArray.create () in
  ObjTbl.iter (fun k _ -> ignore (HxArray.push out (Obj.obj k))) m;
  out

let values_string (m : 'v string_map) : 'v HxArray.t =
  let out = HxArray.create () in
  Hashtbl.iter (fun _ v -> ignore (HxArray.push out (Obj.obj v))) m;
  out

let values_int (m : 'v int_map) : 'v HxArray.t =
  let out = HxArray.create () in
  Hashtbl.iter (fun _ v -> ignore (HxArray.push out (Obj.obj v))) m;
  out

let values_object (m : ('k, 'v) obj_map) : 'v HxArray.t =
  let out = HxArray.create () in
  ObjTbl.iter (fun _ v -> ignore (HxArray.push out (Obj.obj v))) m;
  out

let pairs_string (m : 'v string_map) : (string * 'v) HxArray.t =
  let out = HxArray.create () in
  Hashtbl.iter (fun k v -> ignore (HxArray.push out (k, (Obj.obj v)))) m;
  out

let pairs_int (m : 'v int_map) : (int * 'v) HxArray.t =
  let out = HxArray.create () in
  Hashtbl.iter (fun k v -> ignore (HxArray.push out (k, (Obj.obj v)))) m;
  out

let pairs_object (m : ('k, 'v) obj_map) : ('k * 'v) HxArray.t =
  let out = HxArray.create () in
  ObjTbl.iter (fun k v -> ignore (HxArray.push out ((Obj.obj k), (Obj.obj v)))) m;
  out

let toString_string (m : 'v string_map) : string =
  "<StringMap size=" ^ string_of_int (Hashtbl.length m) ^ ">"

let toString_int (m : 'v int_map) : string =
  "<IntMap size=" ^ string_of_int (Hashtbl.length m) ^ ">"

let toString_object (m : ('k, 'v) obj_map) : string =
  "<ObjectMap size=" ^ string_of_int (ObjTbl.length m) ^ ">"

