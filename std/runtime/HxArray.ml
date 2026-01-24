(* Minimal Haxe Array runtime for reflaxe.ocaml (WIP).

   Representation:
   - Backing store is `Obj.t array` so we can store mixed values.
   - API uses polymorphic `'a` and performs `Obj.repr`/`Obj.obj` casts at the boundary.

   NOTE: This is intentionally permissive and focuses on behavior needed for
   bootstrapping; it will evolve alongside std/_std overrides and better null/equality
   semantics. *)

type 'a t = {
  mutable data : Obj.t array;
  mutable length : int;
}

let hx_null : Obj.t = Obj.repr ()

let create () : 'a t =
  { data = [||]; length = 0 }

let length (a : 'a t) : int =
  a.length

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
  if i < 0 || i >= a.length then
    Obj.obj hx_null
  else
    Obj.obj a.data.(i)

let set (a : 'a t) (i : int) (v : 'a) : 'a =
  if i < 0 then
    v
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

let pop (a : 'a t) () : 'a =
  if a.length = 0 then
    Obj.obj hx_null
  else (
    let i = a.length - 1 in
    let v = a.data.(i) in
    a.data.(i) <- hx_null;
    a.length <- i;
    Obj.obj v
  )

let shift (a : 'a t) () : 'a =
  if a.length = 0 then
    Obj.obj hx_null
  else (
    let v = a.data.(0) in
    if a.length > 1 then Array.blit a.data 1 a.data 0 (a.length - 1);
    a.data.(a.length - 1) <- hx_null;
    a.length <- a.length - 1;
    Obj.obj v
  )

let unshift (a : 'a t) (v : 'a) : unit =
  ensure_capacity a (a.length + 1);
  if a.length > 0 then Array.blit a.data 0 a.data 1 a.length;
  a.data.(0) <- Obj.repr v;
  a.length <- a.length + 1

let normalize_insert_pos (len : int) (pos : int) : int =
  if pos < 0 then
    max 0 (len + pos)
  else if pos > len then
    len
  else
    pos

let insert (a : 'a t) (pos : int) (v : 'a) : unit =
  let p = normalize_insert_pos a.length pos in
  ensure_capacity a (a.length + 1);
  if p < a.length then Array.blit a.data p a.data (p + 1) (a.length - p);
  a.data.(p) <- Obj.repr v;
  a.length <- a.length + 1

let remove (a : 'a t) (x : 'a) : bool =
  let rec find i =
    if i >= a.length then
      -1
    else if Obj.obj a.data.(i) = x then
      i
    else
      find (i + 1)
  in
  let idx = find 0 in
  if idx < 0 then
    false
  else (
    let last = a.length - 1 in
    if idx < last then Array.blit a.data (idx + 1) a.data idx (last - idx);
    a.data.(last) <- hx_null;
    a.length <- last;
    true
  )

let normalize_slice_pos (len : int) (pos : int) : int =
  if pos < 0 then
    let p = len + pos in
    if p < 0 then 0 else p
  else
    pos

let slice (a : 'a t) (pos : int) (end_ : int) : 'a t =
  let len = a.length in
  let p = normalize_slice_pos len pos in
  let e =
    let raw = if end_ < 0 then len + end_ else end_ in
    let clamped = if raw > len then len else raw in
    if clamped < 0 then 0 else clamped
  in
  if p >= len || e <= p then
    create ()
  else (
    let out_len = e - p in
    let out = create () in
    ensure_capacity out out_len;
    for i = 0 to out_len - 1 do
      out.data.(i) <- a.data.(p + i)
    done;
    out.length <- out_len;
    out
  )

let splice (a : 'a t) (pos : int) (len : int) : 'a t =
  if len < 0 then
    create ()
  else (
    let total = a.length in
    let p0 = normalize_slice_pos total pos in
    let p = if p0 > total then total else p0 in
    let l = if p + len > total then total - p else len in
    if l <= 0 then
      create ()
    else (
      let removed = create () in
      ensure_capacity removed l;
      for i = 0 to l - 1 do
        removed.data.(i) <- a.data.(p + i)
      done;
      removed.length <- l;

      let tail = total - (p + l) in
      if tail > 0 then Array.blit a.data (p + l) a.data p tail;
      for i = total - l to total - 1 do
        a.data.(i) <- hx_null
      done;
      a.length <- total - l;
      removed
    )
  )

let iter (a : 'a t) (f : 'a -> unit) : unit =
  for i = 0 to a.length - 1 do
    f (Obj.obj a.data.(i))
  done

