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
   - `to_list` reads the underlying representation directly; this is safe because the
     alias means both modules share the same record layout.
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
  (* `HxArray.t` is a record; the type alias lets us access the fields. *)
  let rec loop i acc =
    if i < 0 then acc else loop (i - 1) (Obj.obj a.data.(i) :: acc)
  in
  loop (a.length - 1) []

let copy (a : 'a t) : 'a t =
  HxArray.copy a

let concat (a : 'a t) (b : 'a t) : 'a t =
  HxArray.concat a b

let join (a : 'a t) (sep : string) (to_string : 'a -> string) : string =
  (* Stage3 emit-runner bring-up: we sometimes end up joining arrays that are *meant* to be
     `Array<String>` but contain poison/null-ish values due to incomplete stdlib semantics.

     If we pass through `(fun (s:string) -> s)` (the usual lowering for `Array<String>.join`)
     then a poison value like `Obj.magic 0` becomes a "string" and the OCaml runtime will
     segfault when `Buffer.add_string` tries to treat it as a byte sequence.

     Using `dynamic_toStdString` here keeps the runner alive and lets Gate2 surface the next
     missing semantic as a deterministic error instead of a hard crash. *)
  ignore to_string;
  HxArray.join a sep (fun v -> HxRuntime.dynamic_toStdString (Obj.repr v))
