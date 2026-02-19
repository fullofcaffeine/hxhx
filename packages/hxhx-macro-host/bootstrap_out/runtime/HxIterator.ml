(* Minimal iterator helpers for reflaxe.ocaml (WIP).

   Haxe's `Iterator<T>` is a structural type:
     typedef Iterator<T> = { function hasNext():Bool; function next():T; }

   For OCaml output, we represent iterators as a record of closures.
   This keeps call-sites simple:
     it.hasNext ()
     it.next ()
*)

type 'a t = {
  hasNext : unit -> bool;
  next : unit -> 'a;
}

(* Iterator primitives

   Why
   - Many generated modules call iterator operations via the Haxe surface:
       it.hasNext()
       it.next()
   - Emitting raw OCaml record-label access at callsites (`it.hasNext ()`) requires the
     record type defining those labels to be present in the module's typing environment.
     Some stdlib modules do not reference `HxIterator` directly and can fail under dune with:
       `Error: Unbound record field hasNext`

   How
   - Keep record-label access confined to this module.
   - Codegen lowers iterator operations to these helpers:
       `HxIterator.hasNext it`
       `HxIterator.next it` *)
let hasNext (it : 'a t) : bool =
  it.hasNext ()

let next (it : 'a t) : 'a =
  it.next ()

let of_array (a : 'a HxArray.t) : 'a t =
  let i = ref 0 in
  {
    hasNext = (fun () -> !i < HxArray.length a);
    next =
      (fun () ->
        let v = HxArray.get a (!i) in
        i := !i + 1;
        v);
  }
