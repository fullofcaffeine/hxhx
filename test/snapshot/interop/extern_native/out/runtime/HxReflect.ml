(* Dynamic reflection helpers for reflaxe.ocaml.

   Why this exists
   --------------
   Haxe's `Reflect` API provides a dynamic escape hatch that many libraries use
   for "soft" integration points (plugins, JSON-ish objects, dynamic calls).

   In portable mode, we already represent anonymous structures as a string-keyed
   table of `Obj.t` values (see `HxAnon`). `Reflect.callMethod` must be able to
   call a function value that flows through that dynamic surface.

   What we implement (M10 bring-up slice)
   -------------------------------------
   - `callMethod(obj, fn, args)` with a small fixed arity window (0..5).

   Notes / limitations
   -------------------
   - We ignore `obj` for now. Many Haxe targets use it to bind `this` for
     unbound method references, but our current codegen tends to produce bound
     closures for `obj.method` already.
   - This is intentionally conservative. Grow arity and semantics only when
     portable fixtures or upstream gates require it. *)

let callMethod (_obj : Obj.t) (fn : Obj.t) (args : Obj.t HxArray.t) : Obj.t =
  let len = HxArray.length args in
  let a i = HxArray.get args i in
  match len with
  | 0 -> (Obj.magic fn : unit -> Obj.t) ()
  | 1 -> (Obj.magic fn : Obj.t -> Obj.t) (a 0)
  | 2 -> (Obj.magic fn : Obj.t -> Obj.t -> Obj.t) (a 0) (a 1)
  | 3 -> (Obj.magic fn : Obj.t -> Obj.t -> Obj.t -> Obj.t) (a 0) (a 1) (a 2)
  | 4 -> (Obj.magic fn : Obj.t -> Obj.t -> Obj.t -> Obj.t -> Obj.t) (a 0) (a 1) (a 2) (a 3)
  | 5 ->
      (Obj.magic fn : Obj.t -> Obj.t -> Obj.t -> Obj.t -> Obj.t -> Obj.t)
        (a 0) (a 1) (a 2) (a 3) (a 4)
  | _ -> failwith ("Reflect.callMethod: unsupported arity: " ^ string_of_int len)

