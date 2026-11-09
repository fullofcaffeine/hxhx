(* Calls of class methods through a `Dynamic` value in Stage3 native programs.

   Haxe allows `final d:Dynamic = new Late(); d.pick();` and finds the method
   when the program runs. A Stage3 class instance keeps its fields in HxAnon
   storage, and its methods are module-level OCaml functions that take the
   receiver first, so reading "pick" from the instance finds nothing.

   Each generated class registers one adapter per method it declares. Haxe
   chooses, for each method parameter, which argument kind below applies, so
   this module never reads a Haxe signature. An adapter converts the supplied
   values to what the method's OCaml function expects. `call` finds the adapter
   on the receiver's class or its nearest ancestor and runs it.

   A call that cannot reach a method raises a Haxe error that `try`/`catch` can
   handle and that names the method. Tables are written only while modules
   initialize, so lookups read them without a lock.

   Arguments are a list, not an array: OCaml stores an array whose first element
   is a boxed float as a flat float array, which would corrupt later values. *)

type argument_kind =
  | Value_argument
  | Int_argument
  | Float_argument
  | Bool_argument
  | String_argument
  | Nullable_int_argument
  | Nullable_float_argument
  | Optional_bool_argument

type method_entry = {
  parameter_count : int;
  adapter : Obj.t -> Obj.t list -> Obj.t;
}

let tables : (string, (string, method_entry) Hashtbl.t) Hashtbl.t = Hashtbl.create 31

let fail message : 'a = HxRuntime.hx_throw_typed (Obj.repr message) [ "String"; "Dynamic" ]

let register name entries =
  let methods = Hashtbl.create (Stdlib.List.length entries) in
  Stdlib.List.iter
    (fun (key, parameter_count, adapter) -> Hashtbl.replace methods key { parameter_count; adapter })
    entries;
  Hashtbl.replace tables name methods

let to_float_box value =
  if Obj.is_int value then Some (Obj.repr (float_of_int (Obj.obj value : int)))
  else if Obj.tag value = Obj.double_tag then Some value
  else None

(* Read one argument for an adapter. A missing argument reads as null, as it
   does in upstream Haxe. The kinds that OCaml stores unboxed must hold a value
   of that kind, because a wrong value would be read as memory. *)
let argument name position kind arguments =
  let value =
    match Stdlib.List.nth_opt arguments position with
    | Some supplied -> supplied
    | None -> HxRuntime.hx_null
  in
  let reject expected =
    fail
      ("Stage3 cannot call method " ^ name ^ " through a Dynamic value: argument "
      ^ string_of_int (position + 1) ^ " must be " ^ expected)
  in
  let is_null = HxRuntime.is_null value in
  match kind with
  | Value_argument -> value
  | String_argument ->
      if is_null || ((not (Obj.is_int value)) && Obj.tag value = Obj.string_tag) then value
      else reject "a String"
  | Int_argument -> if Obj.is_int value then value else reject "an Int"
  | Nullable_int_argument -> if is_null || Obj.is_int value then value else reject "an Int or null"
  | Float_argument -> (
      if is_null then reject "a Float"
      else match to_float_box value with Some box -> box | None -> reject "a Float")
  | Nullable_float_argument -> (
      if is_null then value
      else match to_float_box value with Some box -> box | None -> reject "a Float or null")
  | Bool_argument -> if is_null then reject "a Bool" else Obj.repr (HxRuntime.unbox_bool_or_obj value)
  | Optional_bool_argument ->
      (* Bool parameters read a plain OCaml bool. Null stays null, which selects
         a declared default or reads as `Null<Bool>` in the method body. *)
      if is_null then value else Obj.repr (HxRuntime.unbox_bool_or_obj value)

(* The arguments from `position` onward, each read as `kind`, for a rest parameter. *)
let rest_arguments name position kind arguments =
  Stdlib.List.mapi
    (fun offset _ -> argument name (position + offset) kind arguments)
    (Stdlib.List.filteri (fun index _ -> index >= position) arguments)

(* Apply a stored function value. A function of no arguments takes OCaml's `()`.
   The compiler converts the arguments of this path, because a stored function
   keeps its typed OCaml parameters and its parameter types are unknown here. *)
let apply name callable arguments =
  if Obj.is_int callable || (Obj.tag callable <> Obj.closure_tag && Obj.tag callable <> Obj.infix_tag)
  then fail ("Stage3 cannot call " ^ name ^ " through a Dynamic value: it is not a function")
  else if arguments = [] then (Obj.obj callable : unit -> Obj.t) ()
  else Stdlib.List.fold_left (fun current value -> (Obj.obj current : Obj.t -> Obj.t) value) callable arguments

let call_class_method receiver class_name field arguments =
  let classes =
    match Hashtbl.find_opt HxType.class_tags class_name with
    | Some tags -> tags
    | None -> [ class_name ]
  in
  let found =
    Stdlib.List.find_map
      (fun owner -> Option.bind (Hashtbl.find_opt tables owner) (fun methods -> Hashtbl.find_opt methods field))
      classes
  in
  match found with
  | Some entry when Stdlib.List.length arguments > entry.parameter_count ->
      fail
        ("Stage3 cannot call method " ^ field ^ " of class " ^ class_name
       ^ " through a Dynamic value: too many arguments")
  | Some entry -> entry.adapter receiver arguments
  | None ->
      fail
        ("Stage3 cannot call method " ^ field ^ " of class " ^ class_name
       ^ " through a Dynamic value (no such method, or it has no generated body)")

(* A class instance answers through its method adapters, unless the object
   stores a function under this field. A replaced `dynamic` method is one such
   stored function. Every other receiver uses `apply_stored`. *)
let is_method receiver field =
  HxAnon.is_anon receiver
  && (not (HxAnon.has receiver field))
  && not (HxRuntime.is_null (HxAnon.class_value receiver))

let call_method receiver field arguments =
  call_class_method receiver (HxType.getClassName (HxAnon.class_value receiver)) field arguments

let apply_stored receiver field arguments =
  if HxRuntime.is_null receiver then fail "Null Access"
  else
    let callable = HxAnon.get receiver field in
    if HxRuntime.is_null callable then
      fail ("Stage3 cannot call method " ^ field ^ " through a Dynamic value: the value has no such method")
    else apply field callable arguments

(* An Int argument for a stored function's Float parameter. *)
let stored_float_argument value =
  if Obj.is_int value then Obj.repr (float_of_int (Obj.obj value : int)) else value

(* A Dynamic call result has two Bool forms: class adapters box it, and a stored
   function returns a plain OCaml bool. Convert either to the Dynamic box where
   the result enters a Bool use. A stored function's 0 or 1 cannot be told from
   a Bool here, so an Int result of 0 or 1 is read as a Bool. *)
let bool_carrier value =
  if Obj.is_int value && ((Obj.obj value : int) = 0 || (Obj.obj value : int) = 1) then
    HxRuntime.box_bool (Obj.obj value : bool)
  else value
