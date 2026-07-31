(* Shared Dynamic behavior for reflaxe.ocaml.

   Dynamic values use Obj.t, but target representation alone cannot decide how a
   value is displayed. This module owns the runtime interpretation used by
   Std.string and Haxe's print facades:

   - null, Bool, Int, String, and Float use their exact runtime tags;
   - anonymous structures enumerate their stable HxAnon fields recursively;
   - generated classes may register their real zero-argument toString method;
   - other reference-bearing values use the conservative "<object>" fallback.

   Generated class registrations carry only a class name and a typed adapter.
   The runtime never guesses a record layout or target method name. *)

let class_stringifiers : (string, Obj.t -> string) Hashtbl.t = Hashtbl.create 31

let register_class_stringifier (name : string) (stringifier : Obj.t -> string) : unit =
  Hashtbl.replace class_stringifiers name stringifier

let rec toStdString (value : Obj.t) : string =
  if HxRuntime.is_null value then
    "null"
  else if HxRuntime.is_boxed_bool value then
    string_of_bool (HxRuntime.unbox_bool_or_obj value)
  else if Obj.is_int value then
    string_of_int (Obj.obj value)
  else
    let tag = Obj.tag value in
    if tag = Obj.string_tag then
      let hx_null_string : string = Obj.magic HxRuntime.hx_null in
      let string_value : string = Obj.obj value in
      if string_value == hx_null_string then "null" else string_value
    else if tag = Obj.double_tag then
      string_of_float (Obj.obj value)
    else if HxAnon.is_anon value then
      anonymousToStdString value
    else
      classToStdString value

and anonymousToStdString (value : Obj.t) : string =
  let fields = HxAnon.fields value in
  let parts = ref [] in
  for index = 0 to HxArray.length fields - 1 do
    let name = HxArray.get fields index in
    let field_value = HxAnon.get value name in
    parts := (name ^ ": " ^ toStdString field_value) :: !parts
  done;
  "{" ^ Stdlib.String.concat ", " (List.rev !parts) ^ "}"

and classToStdString (value : Obj.t) : string =
  HxType.ensure_registry_initialized ();
  let class_value = HxType.getClass value in
  if HxRuntime.is_null class_value then
    "<object>"
  else
    let class_name = HxType.getClassName class_value in
    match Hashtbl.find_opt class_stringifiers class_name with
    | Some stringifier -> stringifier value
    | None -> class_name
