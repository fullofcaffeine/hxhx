(* hxhx(stage3) bootstrap shim: HxBootArray *)

type 'a t = 'a HxArray.t

let create = HxArray.create
let length = HxArray.length
let get = HxArray.get
let set = HxArray.set
let push = HxArray.push
let iter = HxArray.iter

let of_list (xs : 'a list) : 'a t =
  let a = HxArray.create () in
  List.iter (fun x -> ignore (HxArray.push a x)) xs;
  a

let to_list (a : 'a t) : 'a list =
  let len = HxArray.length a in
  let rec loop i acc =
    if i < 0 then acc else loop (i - 1) (HxArray.get a i :: acc)
  in
  loop (len - 1) []
