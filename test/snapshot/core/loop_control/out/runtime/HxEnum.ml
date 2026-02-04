(* Boxing helpers for enum values carried as `Obj.t`.

   Why this exists
   - reflaxe.ocaml represents Haxe enums as OCaml variants for idiomatic codegen.
   - When enum values flow through `Dynamic` / `Null<Enum>` / exception payloads,
     we must carry them as `Obj.t`.
   - OCaml cannot reliably identify an enum's type from its runtime shape:
     constant constructors compile to immediates (indistinguishable from `int`),
     and non-constant constructors are generic blocks.

   Strategy
   - When an enum value must be represented as `Obj.t`, we wrap it in a small
     "box" that carries the fully-qualified enum name plus the raw payload.
   - Runtime code (typed catches, `Std.isOfType`, etc.) can then match on the
     box marker and recover the enum name safely. *)

let enum_box_marker : Obj.t = Obj.repr (ref 0)

let is_box (v : Obj.t) : bool =
  (not (Obj.is_int v)) && Obj.size v = 3 && Obj.field v 0 == enum_box_marker

let box (name : string) (payload : Obj.t) : Obj.t =
  let o = Obj.new_block 0 3 in
  Obj.set_field o 0 enum_box_marker;
  Obj.set_field o 1 (Obj.repr name);
  Obj.set_field o 2 payload;
  o

let box_if_needed (name : string) (v : Obj.t) : Obj.t =
  if HxRuntime.is_null v then
    v
  else if is_box v then
    v
  else
    box name v

let name_opt (v : Obj.t) : string option =
  if is_box v then
    Some (Obj.obj (Obj.field v 1))
  else
    None

let unbox_or_obj (expected : string) (v : Obj.t) : Obj.t =
  if is_box v then
    let name : string = Obj.obj (Obj.field v 1) in
    if name = expected then Obj.field v 2 else v
  else
    v
