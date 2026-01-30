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

