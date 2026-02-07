(* hxhx(stage3) bootstrap shim: HxBootArray *)

type 'a t = {
  mutable data : Obj.t array;
  mutable length : int;
}

let hx_null : Obj.t = Obj.repr (Obj.magic 0)

let create () : 'a t = { data = [||]; length = 0 }
let length (a : 'a t) : int = a.length

let ensure_capacity (a : 'a t) (needed : int) : unit =
  let current = Array.length a.data in
  if current < needed then (
    let doubled = if current = 0 then 4 else current * 2 in
    let new_cap = if doubled < needed then needed else doubled in
    let next = Array.make new_cap hx_null in
    if a.length > 0 then Array.blit a.data 0 next 0 a.length;
    a.data <- next
  )

let get (a : 'a t) (i : int) : 'a =
  if i < 0 || i >= a.length then Obj.magic 0 else Obj.obj a.data.(i)

let set (a : 'a t) (i : int) (v : 'a) : 'a =
  if i < 0 then v
  else (
    if i >= a.length then (
      ensure_capacity a (i + 1);
      for j = a.length to i - 1 do
        a.data.(j) <- hx_null
      done;
      a.length <- i + 1
    );
    a.data.(i) <- Obj.repr v;
    v
  )

let push (a : 'a t) (v : 'a) : int =
  ensure_capacity a (a.length + 1);
  a.data.(a.length) <- Obj.repr v;
  a.length <- a.length + 1;
  a.length

let of_list (xs : 'a list) : 'a t =
  let a = create () in
  List.iter (fun x -> ignore (push a x)) xs;
  a

let iter (a : 'a t) (f : 'a -> unit) : unit =
  for i = 0 to a.length - 1 do
    f (Obj.obj a.data.(i))
  done

let to_list (a : 'a t) : 'a list =
  let rec loop i acc = if i < 0 then acc else loop (i - 1) (Obj.obj a.data.(i) :: acc) in
  loop (a.length - 1) []

