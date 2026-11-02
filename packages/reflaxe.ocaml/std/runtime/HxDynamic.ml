(* Shared Dynamic behavior for reflaxe.ocaml.

   Dynamic values use Obj.t, but target representation alone cannot decide how a
   value is displayed. This module owns the runtime interpretation used by
   Std.string and Haxe's print facades:

   - null, Bool, Int, String, and Float use their exact runtime tags;
   - boxed enum values print their constructor name and arguments;
   - anonymous structures enumerate their stable HxAnon fields recursively;
   - generated classes may register their real zero-argument toString method,
     whether they are native records or Stage3's class-tagged HxAnon objects;
   - other reference-bearing values use the conservative "<object>" fallback.

   Generated class registrations carry only a class name and a typed adapter.
   The runtime never guesses a record layout or target method name. *)

let class_stringifiers : (string, Obj.t -> string) Hashtbl.t = Hashtbl.create 31

let register_class_stringifier (name : string) (stringifier : Obj.t -> string) : unit =
  Hashtbl.replace class_stringifiers name stringifier

(* Enum payloads store a Bool argument as a raw OCaml bool, which has the same
   runtime shape as an int. Generated enum modules register which argument
   positions of each constructor are Bool (or Null<Bool>), so enum text prints
   `Flagged(true)`, not `Flagged(1)`. *)
let enum_bool_arguments : (string * string, int list) Hashtbl.t = Hashtbl.create 31

let register_enum_bool_arguments (enum_name : string) (constructor : string) (positions : int list) : unit =
  Hashtbl.replace enum_bool_arguments (enum_name, constructor) positions

(* Checked unary operations for values that cross Haxe's Dynamic boundary.

   The Haxe-authored Stage3 emitter selects the operation. This runtime code
   only checks the value category and applies the selected primitive. Each
   Obj.obj call follows a matching runtime-tag check in the same branch. *)

let invalid_operator (operation : string) (expected : string) : 'a =
  HxRuntime.hx_throw_typed
    (Obj.repr ("Invalid Dynamic " ^ operation ^ " operand; expected " ^ expected))
    [ "String"; "Dynamic" ]

let logicalNot (value : Obj.t) : Obj.t =
  if HxRuntime.is_boxed_bool value then
    HxRuntime.box_bool (not (HxRuntime.unbox_bool_or_obj value))
  else
    invalid_operator "logical-not" "Bool"

let negate (value : Obj.t) : Obj.t =
  if Obj.is_int value && not (HxRuntime.is_null value) then
    Obj.repr (HxInt.neg (Obj.obj value : int))
  else if not (Obj.is_int value) && Obj.tag value = Obj.double_tag then
    Obj.repr (-. (Obj.obj value : float))
  else
    invalid_operator "negation" "Int or Float"

let bitwiseNot (value : Obj.t) : Obj.t =
  if Obj.is_int value && not (HxRuntime.is_null value) then
    Obj.repr (HxInt.lognot (Obj.obj value : int))
  else
    invalid_operator "bitwise-complement" "Int"

let booleanValue (value : Obj.t) : bool =
  if HxRuntime.is_boxed_bool value then
    HxRuntime.unbox_bool_or_obj value
  else
    invalid_operator "Boolean" "Bool"

type numeric_value =
  | DynamicInt of int
  | DynamicFloat of float

let numeric_value (operation : string) (value : Obj.t) : numeric_value =
  if Obj.is_int value && not (HxRuntime.is_null value) then
    DynamicInt (Obj.obj value : int)
  else if not (Obj.is_int value) && Obj.tag value = Obj.double_tag then
    DynamicFloat (Obj.obj value : float)
  else
    invalid_operator operation "Int or Float"

(* Convert a Dynamic value at a compiler-selected Float boundary.

   The Haxe-authored emitter chooses this helper only when an exact call
   declaration requires Float but the typed argument remains Dynamic. The
   runtime validates the carrier before unboxing it and applies Haxe's ordinary
   Int-to-Float widening. *)
let floatValue (value : Obj.t) : float =
  match numeric_value "Float conversion" value with
  | DynamicInt value -> float_of_int value
  | DynamicFloat value -> value

let subtract (left : Obj.t) (right : Obj.t) : Obj.t =
  match numeric_value "subtraction" left, numeric_value "subtraction" right with
  | DynamicInt a, DynamicInt b -> Obj.repr (HxInt.sub a b)
  | DynamicInt a, DynamicFloat b -> Obj.repr (float_of_int a -. b)
  | DynamicFloat a, DynamicInt b -> Obj.repr (a -. float_of_int b)
  | DynamicFloat a, DynamicFloat b -> Obj.repr (a -. b)

let multiply (left : Obj.t) (right : Obj.t) : Obj.t =
  match numeric_value "multiplication" left, numeric_value "multiplication" right with
  | DynamicInt a, DynamicInt b -> Obj.repr (HxInt.mul a b)
  | DynamicInt a, DynamicFloat b -> Obj.repr (float_of_int a *. b)
  | DynamicFloat a, DynamicInt b -> Obj.repr (a *. float_of_int b)
  | DynamicFloat a, DynamicFloat b -> Obj.repr (a *. b)

let divide (left : Obj.t) (right : Obj.t) : Obj.t =
  match numeric_value "division" left, numeric_value "division" right with
  | DynamicInt a, DynamicInt b -> Obj.repr (float_of_int a /. float_of_int b)
  | DynamicInt a, DynamicFloat b -> Obj.repr (float_of_int a /. b)
  | DynamicFloat a, DynamicInt b -> Obj.repr (a /. float_of_int b)
  | DynamicFloat a, DynamicFloat b -> Obj.repr (a /. b)

let remainder (left : Obj.t) (right : Obj.t) : Obj.t =
  match numeric_value "remainder" left, numeric_value "remainder" right with
  | DynamicInt a, DynamicInt b -> Obj.repr (HxInt.rem a b)
  | DynamicInt a, DynamicFloat b -> Obj.repr (mod_float (float_of_int a) b)
  | DynamicFloat a, DynamicInt b -> Obj.repr (mod_float a (float_of_int b))
  | DynamicFloat a, DynamicFloat b -> Obj.repr (mod_float a b)

let compare_numeric (operation : string) (compare : float -> float -> bool)
    (left : Obj.t) (right : Obj.t) : bool =
  let left_value = numeric_value operation left in
  let right_value = numeric_value operation right in
  let as_float = function
    | DynamicInt value -> float_of_int value
    | DynamicFloat value -> value
  in
  compare (as_float left_value) (as_float right_value)

let lessThan left right = compare_numeric "comparison" ( < ) left right
let lessThanOrEqual left right = compare_numeric "comparison" ( <= ) left right
let greaterThan left right = compare_numeric "comparison" ( > ) left right
let greaterThanOrEqual left right = compare_numeric "comparison" ( >= ) left right

let int_pair (operation : string) (left : Obj.t) (right : Obj.t) : int * int =
  match numeric_value operation left, numeric_value operation right with
  | DynamicInt a, DynamicInt b -> a, b
  | _ -> invalid_operator operation "Int"

let bitwiseAnd left right = let a, b = int_pair "bitwise-and" left right in Obj.repr (HxInt.logand a b)
let bitwiseOr left right = let a, b = int_pair "bitwise-or" left right in Obj.repr (HxInt.logor a b)
let bitwiseXor left right = let a, b = int_pair "bitwise-xor" left right in Obj.repr (HxInt.logxor a b)
let shiftLeft left right = let a, b = int_pair "left-shift" left right in Obj.repr (HxInt.shl a b)
let shiftRight left right = let a, b = int_pair "right-shift" left right in Obj.repr (HxInt.shr a b)
let unsignedShiftRight left right = let a, b = int_pair "unsigned-right-shift" left right in Obj.repr (HxInt.ushr a b)

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
      HxRuntime.float_toStdString (Obj.obj value)
    else if HxEnum.is_box value then
      enumToStdString value
    else if HxArray.is_value value then
      HxArray.to_dynamic_string (Obj.obj value) toStdString
    else if HxAnon.is_anon value then
      (* Stage3 stores a class instance as an HxAnon object tagged with its
         class. It prints through the class's registered toString adapter,
         or its class name, like any other class instance. *)
      if HxRuntime.is_null (HxAnon.class_value value) then
        anonymousToStdString value
      else
        classToStdString value
    else
      classToStdString value

(* A boxed enum value prints as Haxe does: its constructor name, followed by
   its arguments in parentheses when it has any (`Red`, `Rgb(1,2,3)`). An
   argument is converted by its runtime shape, except the Bool positions that
   the enum module registered with register_enum_bool_arguments. *)
and enumToStdString (value : Obj.t) : string =
  let name = HxType.enumConstructor value in
  if HxRuntime.is_null (Obj.repr name) then
    "<object>"
  else
    let parameters = HxType.enumParameters value in
    if HxArray.length parameters = 0 then
      name
    else
      let bools =
        match HxEnum.name_opt value with
        | Some enum_name -> (
            match Hashtbl.find_opt enum_bool_arguments (enum_name, name) with
            | Some positions -> positions
            | None -> [])
        | None -> []
      in
      let argument index =
        let raw = HxArray.get parameters index in
        if Stdlib.List.mem index bools && not (HxRuntime.is_null raw || HxRuntime.is_boxed_bool raw) then
          HxRuntime.box_bool (Obj.obj raw)
        else
          raw
      in
      let parts = ref [] in
      for index = HxArray.length parameters - 1 downto 0 do
        parts := toStdString (argument index) :: !parts
      done;
      name ^ "(" ^ Stdlib.String.concat "," !parts ^ ")"

and anonymousToStdString (value : Obj.t) : string =
  let fields = HxAnon.fields value in
  let parts = ref [] in
  for index = 0 to HxArray.length fields - 1 do
    let name = HxArray.get fields index in
    let field_value = HxAnon.get value name in
    parts := (name ^ ": " ^ toStdString field_value) :: !parts
  done;
  "{" ^ Stdlib.String.concat ", " (Stdlib.List.rev !parts) ^ "}"

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

let is_string_value (value : Obj.t) : bool =
  not (Obj.is_int value) && Obj.tag value = Obj.string_tag

let add (left : Obj.t) (right : Obj.t) : Obj.t =
  if is_string_value left || is_string_value right then
    Obj.repr (toStdString left ^ toStdString right)
  else
    match numeric_value "addition" left, numeric_value "addition" right with
    | DynamicInt a, DynamicInt b -> Obj.repr (HxInt.add a b)
    | DynamicInt a, DynamicFloat b -> Obj.repr (float_of_int a +. b)
    | DynamicFloat a, DynamicInt b -> Obj.repr (a +. float_of_int b)
    | DynamicFloat a, DynamicFloat b -> Obj.repr (a +. b)
