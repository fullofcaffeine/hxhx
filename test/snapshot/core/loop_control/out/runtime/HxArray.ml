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

let hx_null : Obj.t = HxRuntime.hx_null

(* Stage3 bring-up can temporarily route "poison" or `hx_null` through values that are
   statically typed as `HxArray.t` (via `Obj.magic` at codegen boundaries). Accessing
   record fields on such values would segfault.

   We defensively treat non-array values as "empty arrays" for bootstrapping so we
   can surface the *next* missing semantic as a Haxe/OCaml exception rather than a
   hard crash. *)
let unwrap_or_empty (a : 'a t) : 'a t option =
  (* IMPORTANT: use `Obj.magic` so the compiler cannot assume `a` is a well-typed
     record value. Stage3 codegen can and does route immediates (e.g. `Obj.magic 0`)
     through `'a t`, and relying on `Obj.repr` here can let the optimizer erase the
     `Obj.is_int` guard, reintroducing segfaults. *)
  let o : Obj.t = Obj.magic a in
  if o == hx_null then
    None
  else if Obj.is_int o then
    None
  else if Obj.size o <> 2 then
    None
  else
    Some (Obj.obj o)

let unwrap_optional_int (v : int) (default : int) : int =
  let raw : Obj.t = Obj.magic v in
  if raw == hx_null then
    default
  else
    v

let create () : 'a t =
  { data = [||]; length = 0 }

let length (a : 'a t) : int =
  match unwrap_or_empty a with
  | None -> 0
  | Some a -> a.length

let ensure_capacity (a : 'a t) (needed : int) : unit =
  let current = Stdlib.Array.length a.data in
  if current < needed then (
    let doubled = if current = 0 then 4 else current * 2 in
    let new_cap = if doubled < needed then needed else doubled in
    let next = Stdlib.Array.make new_cap hx_null in
    if a.length > 0 then Stdlib.Array.blit a.data 0 next 0 a.length;
    a.data <- next
  )

let get (a : 'a t) (i : int) : 'a =
  match unwrap_or_empty a with
  | None -> Obj.obj hx_null
  | Some a ->
    if i < 0 || i >= a.length then
      Obj.obj hx_null
    else
      Obj.obj (Stdlib.Array.get a.data i)

let set (a : 'a t) (i : int) (v : 'a) : 'a =
  match unwrap_or_empty a with
  | None -> v
  | Some a ->
    if i < 0 then
      v
    else (
      if i >= a.length then (
        ensure_capacity a (i + 1);
        for j = a.length to i - 1 do
          Stdlib.Array.set a.data j hx_null
        done;
        a.length <- i + 1
      );
      Stdlib.Array.set a.data i (Obj.repr v);
      v
    )

let push (a : 'a t) (v : 'a) : int =
  match unwrap_or_empty a with
  | None -> 0
  | Some a ->
    ensure_capacity a (a.length + 1);
    Stdlib.Array.set a.data a.length (Obj.repr v);
    a.length <- a.length + 1;
    a.length

let pop (a : 'a t) () : 'a =
  match unwrap_or_empty a with
  | None -> Obj.obj hx_null
  | Some a ->
    if a.length = 0 then
      Obj.obj hx_null
    else (
      let i = a.length - 1 in
      let v = Stdlib.Array.get a.data i in
      Stdlib.Array.set a.data i hx_null;
      a.length <- i;
      Obj.obj v
    )

let shift (a : 'a t) () : 'a =
  match unwrap_or_empty a with
  | None -> Obj.obj hx_null
  | Some a ->
    if a.length = 0 then
      Obj.obj hx_null
    else (
      let v = Stdlib.Array.get a.data 0 in
      if a.length > 1 then Stdlib.Array.blit a.data 1 a.data 0 (a.length - 1);
      Stdlib.Array.set a.data (a.length - 1) hx_null;
      a.length <- a.length - 1;
      Obj.obj v
    )

let unshift (a : 'a t) (v : 'a) : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    ensure_capacity a (a.length + 1);
    if a.length > 0 then Stdlib.Array.blit a.data 0 a.data 1 a.length;
    Stdlib.Array.set a.data 0 (Obj.repr v);
    a.length <- a.length + 1

let normalize_insert_pos (len : int) (pos : int) : int =
  if pos < 0 then
    max 0 (len + pos)
  else if pos > len then
    len
  else
    pos

let insert (a : 'a t) (pos : int) (v : 'a) : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    let p = normalize_insert_pos a.length pos in
    ensure_capacity a (a.length + 1);
    if p < a.length then Stdlib.Array.blit a.data p a.data (p + 1) (a.length - p);
    Stdlib.Array.set a.data p (Obj.repr v);
    a.length <- a.length + 1

let remove (a : 'a t) (x : 'a) : bool =
  match unwrap_or_empty a with
  | None -> false
  | Some a ->
    let rec find i =
      if i >= a.length then
        -1
      else if Obj.obj (Stdlib.Array.get a.data i) = x then
        i
      else
        find (i + 1)
    in
    let idx = find 0 in
    if idx < 0 then
      false
    else (
      let last = a.length - 1 in
      if idx < last then Stdlib.Array.blit a.data (idx + 1) a.data idx (last - idx);
      Stdlib.Array.set a.data last hx_null;
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
  match unwrap_or_empty a with
  | None -> create ()
  | Some a ->
    let len = a.length in
    let end_ = unwrap_optional_int end_ len in
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
        Stdlib.Array.set out.data i (Stdlib.Array.get a.data (p + i))
      done;
      out.length <- out_len;
      out
    )

let splice (a : 'a t) (pos : int) (len : int) : 'a t =
  match unwrap_or_empty a with
  | None -> create ()
  | Some a ->
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
          Stdlib.Array.set removed.data i (Stdlib.Array.get a.data (p + i))
        done;
        removed.length <- l;

        let tail = total - (p + l) in
        if tail > 0 then Stdlib.Array.blit a.data (p + l) a.data p tail;
        for i = total - l to total - 1 do
          Stdlib.Array.set a.data i hx_null
        done;
        a.length <- total - l;
        removed
      )
    )

let iter (a : 'a t) (f : 'a -> unit) : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    for i = 0 to a.length - 1 do
      f (Obj.obj (Stdlib.Array.get a.data i))
    done

let copy (a : 'a t) : 'a t =
  match unwrap_or_empty a with
  | None -> create ()
  | Some a ->
    let out = create () in
    if a.length = 0 then
      out
    else (
      ensure_capacity out a.length;
      Stdlib.Array.blit a.data 0 out.data 0 a.length;
      out.length <- a.length;
      out
    )

let concat (a : 'a t) (b : 'a t) : 'a t =
  match unwrap_or_empty a, unwrap_or_empty b with
  | None, None -> create ()
  | Some a, None -> copy a
  | None, Some b -> copy b
  | Some a, Some b ->
    let out = create () in
    let len_a = a.length in
    let len_b = b.length in
    let total = len_a + len_b in
    if total = 0 then
      out
    else (
      ensure_capacity out total;
      if len_a > 0 then Stdlib.Array.blit a.data 0 out.data 0 len_a;
      if len_b > 0 then Stdlib.Array.blit b.data 0 out.data len_a len_b;
      out.length <- total;
      out
    )

let reverse (a : 'a t) () : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    let i = ref 0 in
    let j = ref (a.length - 1) in
    while !i < !j do
      let tmp = Stdlib.Array.get a.data !i in
      Stdlib.Array.set a.data !i (Stdlib.Array.get a.data !j);
      Stdlib.Array.set a.data !j tmp;
      i := !i + 1;
      j := !j - 1
    done

let normalize_index_of_from (len : int) (fromIndex : int) : int =
  if fromIndex < 0 then
    let start = len + fromIndex in
    if start < 0 then 0 else start
  else if fromIndex >= len then
    len
  else
    fromIndex

let indexOf (a : 'a t) (x : 'a) (fromIndex : int) : int =
  match unwrap_or_empty a with
  | None -> -1
  | Some a ->
    let len = a.length in
    let fromIndex = unwrap_optional_int fromIndex 0 in
    let start = normalize_index_of_from len fromIndex in
    if start >= len then
      -1
    else (
      let rec loop i =
        if i >= len then
          -1
        else if Obj.obj (Stdlib.Array.get a.data i) = x then
          i
        else
          loop (i + 1)
      in
      loop start
    )

let normalize_last_index_of_from (len : int) (fromIndex : int) : int =
  if fromIndex < 0 then
    let start = len + fromIndex in
    if start < 0 then -1 else start
  else if fromIndex >= len then
    len - 1
  else
    fromIndex

let lastIndexOf (a : 'a t) (x : 'a) (fromIndex : int) : int =
  match unwrap_or_empty a with
  | None -> -1
  | Some a ->
    let len = a.length in
    let fromIndex = unwrap_optional_int fromIndex (len - 1) in
    if len = 0 then
      -1
    else (
      let start = normalize_last_index_of_from len fromIndex in
      if start < 0 then
        -1
      else (
        let rec loop i =
          if i < 0 then
            -1
          else if Obj.obj (Stdlib.Array.get a.data i) = x then
            i
          else
            loop (i - 1)
        in
        loop start
      )
    )

let contains (a : 'a t) (x : 'a) : bool =
  indexOf a x 0 >= 0

let join (a : 'a t) (sep : string) (to_string : 'a -> string) : string =
  match unwrap_or_empty a with
  | None -> ""
  | Some a ->
    if a.length = 0 then
      ""
    else if a.length = 1 then
      to_string (Obj.obj (Stdlib.Array.get a.data 0))
    else (
      let b = Buffer.create 64 in
      Buffer.add_string b (to_string (Obj.obj (Stdlib.Array.get a.data 0)));
      for i = 1 to a.length - 1 do
        Buffer.add_string b sep;
        Buffer.add_string b (to_string (Obj.obj (Stdlib.Array.get a.data i)))
      done;
      Buffer.contents b
    )

let map (a : 'a t) (f : 'a -> 'b) : 'b t =
  match unwrap_or_empty a with
  | None -> create ()
  | Some a ->
    let out = create () in
    if a.length = 0 then
      out
    else (
      ensure_capacity out a.length;
      for i = 0 to a.length - 1 do
        let v = f (Obj.obj (Stdlib.Array.get a.data i)) in
        Stdlib.Array.set out.data i (Obj.repr v)
      done;
      out.length <- a.length;
      out
    )

let filter (a : 'a t) (f : 'a -> bool) : 'a t =
  match unwrap_or_empty a with
  | None -> create ()
  | Some a ->
    let out = create () in
    if a.length = 0 then
      out
    else (
      for i = 0 to a.length - 1 do
        let v = Obj.obj (Stdlib.Array.get a.data i) in
        if f v then ignore (push out v) else ()
      done;
      out
    )

let resize (a : 'a t) (new_len : int) : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    if new_len < 0 then
      ()
    else if new_len = a.length then
      ()
    else if new_len < a.length then (
      for i = new_len to a.length - 1 do
        Stdlib.Array.set a.data i hx_null
      done;
      a.length <- new_len
    ) else (
      ensure_capacity a new_len;
      for i = a.length to new_len - 1 do
        Stdlib.Array.set a.data i hx_null
      done;
      a.length <- new_len
    )

let sort (a : 'a t) (cmp : 'a -> 'a -> int) : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    if a.length < 2 then
      ()
    else (
      let slice = Stdlib.Array.sub a.data 0 a.length in
      Stdlib.Array.sort
        (fun x y -> cmp (Obj.obj x) (Obj.obj y))
        slice;
      Stdlib.Array.blit slice 0 a.data 0 a.length
    )
