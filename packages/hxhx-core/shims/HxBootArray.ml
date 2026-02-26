(* hxhx(stage3) bootstrap shim: HxBootArray

   Why
   - Stage3-emitted programs need a small `Array<T>` runtime surface for orchestration
     (RunCi, simple examples), but we don't want a second, incompatible array type.
   - The Stage3 emitter and other runtime helpers already use `HxArray.t` in some paths
     (e.g. `HxString.split`), so `HxBootArray.t` must unify with `HxArray.t` to keep the
     generated OCaml type-checkable.

   What
   - `HxBootArray.t` is a type alias of `HxArray.t`.
   - We provide a tiny convenience API (`of_list`, `to_list`) used by the Stage3 emitter
     to lower array literals and interop with OCaml stdlib functions.

   How
   - Most operations delegate to `HxArray`.
   - `to_list` uses only public `HxArray` operations (`length` + `get`) so it stays
     compatible when `HxArray` storage changes (for example adaptive typed stores).
*)

type 'a t = 'a HxArray.t

let hx_null : Obj.t =
  HxArray.hx_null

let create () : 'a t =
  HxArray.create ()

let length (a : 'a t) : int =
  HxArray.length a

let get (a : 'a t) (i : int) : 'a =
  HxArray.get a i

let set (a : 'a t) (i : int) (v : 'a) : 'a =
  HxArray.set a i v

let push (a : 'a t) (v : 'a) : int =
  HxArray.push a v

let iter (a : 'a t) (f : 'a -> unit) : unit =
  HxArray.iter a f

let of_list (xs : 'a list) : 'a t =
  let a = create () in
  List.iter (fun x -> ignore (push a x)) xs;
  a

let to_list (a : 'a t) : 'a list =
  let len = HxArray.length a in
  let rec loop i acc =
    if i < 0 then
      acc
    else
      loop (i - 1) (HxArray.get a i :: acc)
  in
  loop (len - 1) []

let copy (a : 'a t) : 'a t =
  HxArray.copy a

let concat (a : 'a t) (b : 'a t) : 'a t =
  HxArray.concat a b

let map (a : 'a t) (f : 'a -> 'b) : 'b t =
  HxArray.map a f

(* Stage3 emit-runner bridge for dynamic callbacks.

   Why
   - Upstream RunCi lowers some callback expressions through dynamic field lookups
     (for example `quoteWinArg.bind(null, true)`), so bootstrap emission sees them as
     dynamic values instead of statically typed `'a -> 'b` functions.

   What
   - Accept callback as `Obj.t` and bridge into `HxArray.map`.

   How
   - Coerce the array payload + callback to dynamic forms and delegate.
*)
let map_dyn (a : 'a t) (f : Obj.t) : Obj.t t =
  let arr : Obj.t t = Obj.magic a in
  let fn : Obj.t -> Obj.t = Obj.obj f in
  HxArray.map arr fn

(* Stage3 emit-runner bridge for Array.join with dynamic payloads. *)
let join_dyn (a : Obj.t t) (sep : string) : string =
  HxArray.join a sep (fun v -> HxRuntime.dynamic_toStdString (Obj.repr v))

let join_strict (a : 'a t) (sep : string) (to_string : 'a -> string) : string =
  HxArray.join a sep to_string

let join (a : 'a t) (sep : string) (to_string : 'a -> string) : string =
  (* Stage3 emit-runner bring-up: we sometimes end up joining arrays that are *meant* to be
     `Array<String>` but contain poison/null-ish values due to incomplete stdlib semantics.

     If we pass through `(fun (s:string) -> s)` (the usual lowering for `Array<String>.join`)
     then a poison value like `Obj.magic 0` becomes a "string" and the OCaml runtime will
     segfault when `Buffer.add_string` tries to treat it as a byte sequence.

     Using `dynamic_toStdString` here keeps the runner alive and lets Gate2 surface the next
     missing semantic as a deterministic error instead of a hard crash. *)
  ignore to_string;
  join_dyn (Obj.magic a) sep
