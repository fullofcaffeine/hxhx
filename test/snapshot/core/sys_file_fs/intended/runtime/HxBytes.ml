(* Minimal Haxe Bytes runtime for reflaxe.ocaml (WIP).

   Representation:
   - OCaml `bytes` (mutable byte sequence).

   Notes:
   - Haxe `Bytes` operations throw `haxe.io.Error.OutsideBounds` on most targets.
     For now we throw a simple string via `HxRuntime.hx_throw`.
   - This is byte-based and currently assumes Haxe `String` maps to OCaml `string`
     without additional encoding conversions. *)

type t = bytes

let outside_bounds () : 'a =
  HxRuntime.hx_throw (Obj.repr "OutsideBounds")

let check_range (len_total : int) (pos : int) (len : int) : unit =
  if pos < 0 || len < 0 || pos + len > len_total then outside_bounds () else ()

let alloc (len : int) : t =
  if len < 0 then outside_bounds () else Bytes.make len '\000'

let length (b : t) : int =
  Bytes.length b

let get (b : t) (pos : int) : int =
  let len = Bytes.length b in
  if pos < 0 || pos >= len then outside_bounds () else Char.code (Bytes.get b pos)

let set (b : t) (pos : int) (v : int) : unit =
  let len = Bytes.length b in
  if pos < 0 || pos >= len then
    outside_bounds ()
  else
    let c = Char.chr (v land 0xFF) in
    Bytes.set b pos c

let blit (dst : t) (pos : int) (src : t) (srcpos : int) (len : int) : unit =
  check_range (Bytes.length dst) pos len;
  check_range (Bytes.length src) srcpos len;
  if len = 0 then () else Bytes.blit src srcpos dst pos len

let fill (b : t) (pos : int) (len : int) (value : int) : unit =
  check_range (Bytes.length b) pos len;
  let c = Char.chr (value land 0xFF) in
  for i = 0 to len - 1 do
    Bytes.set b (pos + i) c
  done

let sub (b : t) (pos : int) (len : int) : t =
  check_range (Bytes.length b) pos len;
  Bytes.sub b pos len

let compare (a : t) (b : t) : int =
  Bytes.compare a b

let ofString (s : string) () : t =
  Bytes.of_string s

let getString (b : t) (pos : int) (len : int) () : string =
  check_range (Bytes.length b) pos len;
  Bytes.sub_string b pos len

let toString (b : t) () : string =
  Bytes.to_string b

let getData (b : t) () : t =
  b

let ofData (b : t) () : t =
  b
