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

(* Intern table for boxed *constant* constructors.

   Why:
   - Constant enum constructors in OCaml compile to immediates (ints).
   - When those values are carried as `Obj.t`, we box them for typed catches.
   - If we allocate a fresh box every time, we accidentally break Haxe identity
     semantics for constants in `Dynamic` contexts (`var d1:Dynamic = E.A; var d2:Dynamic = E.A; d1 == d2` should be true).

   Strategy:
   - Intern boxed values when the payload is an immediate. For non-immediates
     (constructors with args), do *not* intern: each value should remain distinct
     by identity (and Haxe disallows direct `==` comparisons on typed enums-with-args anyway). *)
let intern_const : ((string * int), Obj.t) Hashtbl.t = Hashtbl.create 251

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
  else if Obj.is_int v then
    let i : int = Obj.obj v in
    (match Hashtbl.find_opt intern_const (name, i) with
    | Some b -> b
    | None ->
        let b = box name v in
        Hashtbl.add intern_const (name, i) b;
        b)
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

(* `Type.enumEq` support (minimal).

   Why
   - Haxe disallows `==` on enums with arguments, but provides `Type.enumEq` to
     compare enum values structurally (constructor + args).
   - Our backend represents enums as native OCaml variants for idiomatic codegen,
     which means we can inspect constructor tags/fields via `Obj`.

   Semantics (best-effort, aligns with static targets)
   - `null` only equals `null`.
   - Constant constructors compare by constructor index.
   - Constructors with args compare by tag + arity, then compare each argument
     using Haxe dynamic equality (`HxRuntime.dynamic_equals`) so object identity
     is preserved (and Int/Float/String behave like Haxe `==`).

   Note
   - This expects raw (unboxed) enum values (`Obj.repr` of the OCaml variant).
     When enum values are carried as `Obj.t` in Dynamic contexts, they may be
     boxed via `box_if_needed`; those callsites should unbox first if needed. *)

let enum_eq (a : Obj.t) (b : Obj.t) : bool =
  if HxRuntime.is_null a || HxRuntime.is_null b then
    HxRuntime.is_null a && HxRuntime.is_null b
  else if Obj.is_int a then
    Obj.is_int b && (Obj.obj a : int) = (Obj.obj b : int)
  else if Obj.is_int b then
    false
  else if Obj.tag a <> Obj.tag b then
    false
  else
    let sa = Obj.size a in
    let sb = Obj.size b in
    if sa <> sb then
      false
    else (
      let rec loop i =
        if i >= sa then true
        else if HxRuntime.dynamic_equals (Obj.field a i) (Obj.field b i) then loop (i + 1)
        else false
      in
      loop 0)
