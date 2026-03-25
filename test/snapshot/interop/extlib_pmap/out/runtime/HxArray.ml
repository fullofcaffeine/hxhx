(* Minimal Haxe Array runtime for reflaxe.ocaml.

   Adaptive representation strategy:
   - ObjStore    : generic `Obj.t array` fallback (fully dynamic, nullable slots)
   - IntStore    : unboxed int storage for dense integer arrays
   - FloatStore  : unboxed float storage for dense float arrays
   - StringStore : direct string storage for dense string arrays

   The runtime keeps Haxe semantics by using deterministic deopt rules:
   - Any operation that requires explicit `null` slots (sparse writes, grow-resize)
     deopts to ObjStore.
   - Any mixed-type write on a typed store deopts to ObjStore.
   - ObjStore can promote back to a typed store when all live slots are dense,
     non-null, and uniformly typed.

   This keeps portable mode semantics stable while reducing boxing overhead in
   hot typed loops (notably Array<Int> workloads). *)

type storage =
  | ObjStore of Obj.t array
  | IntStore of int array
  | FloatStore of float array
  | StringStore of string array

type 'a t = {
  mutable store : storage;
  mutable length : int;
  (* Number of hx_null slots in [0, length) while in ObjStore mode.
     For typed stores this stays at 0. *)
  mutable null_slots : int;
}

let hx_null : Obj.t = HxRuntime.hx_null

type raw_kind =
  | KindObj
  | KindInt
  | KindFloat
  | KindString

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
  else if Obj.size o <> 3 then
    None
  else
    Some (Obj.obj o)

let unwrap_optional_int (v : int) (default : int) : int =
  let raw : Obj.t = Obj.magic v in
  if raw == hx_null then
    default
  else
    v

let raw_kind_of (raw : Obj.t) : raw_kind =
  if raw == hx_null then
    KindObj
  else if Obj.is_int raw then
    KindInt
  else
    let tag = Obj.tag raw in
    if tag = Obj.double_tag then KindFloat else if tag = Obj.string_tag then KindString else KindObj

let is_non_null_raw (raw : Obj.t) : bool =
  raw != hx_null

let storage_capacity (store : storage) : int =
  match store with
  | ObjStore data -> Stdlib.Array.length data
  | IntStore data -> Stdlib.Array.length data
  | FloatStore data -> Stdlib.Array.length data
  | StringStore data -> Stdlib.Array.length data

let create () : 'a t =
  { store = ObjStore [||]; length = 0; null_slots = 0 }

let length (a : 'a t) : int =
  match unwrap_or_empty a with
  | None -> 0
  | Some a -> a.length

let ensure_obj_store (a : 'a t) : Obj.t array =
  match a.store with
  | ObjStore data -> data
  | IntStore ints ->
    let cap = Stdlib.Array.length ints in
    let next = Stdlib.Array.make cap hx_null in
    for i = 0 to a.length - 1 do
      Stdlib.Array.set next i (Obj.repr (Stdlib.Array.get ints i))
    done;
    a.store <- ObjStore next;
    a.null_slots <- 0;
    next
  | FloatStore floats ->
    let cap = Stdlib.Array.length floats in
    let next = Stdlib.Array.make cap hx_null in
    for i = 0 to a.length - 1 do
      Stdlib.Array.set next i (Obj.repr (Stdlib.Array.get floats i))
    done;
    a.store <- ObjStore next;
    a.null_slots <- 0;
    next
  | StringStore strings ->
    let cap = Stdlib.Array.length strings in
    let next = Stdlib.Array.make cap hx_null in
    for i = 0 to a.length - 1 do
      Stdlib.Array.set next i (Obj.repr (Stdlib.Array.get strings i))
    done;
    a.store <- ObjStore next;
    a.null_slots <- 0;
    next

let ensure_capacity (a : 'a t) (needed : int) : unit =
  let current = storage_capacity a.store in
  if current < needed then (
    let doubled = if current = 0 then 4 else current * 2 in
    let new_cap = if doubled < needed then needed else doubled in
    match a.store with
    | ObjStore data ->
      let next = Stdlib.Array.make new_cap hx_null in
      if a.length > 0 then Stdlib.Array.blit data 0 next 0 a.length;
      a.store <- ObjStore next
    | IntStore data ->
      let next = Stdlib.Array.make new_cap 0 in
      if a.length > 0 then Stdlib.Array.blit data 0 next 0 a.length;
      a.store <- IntStore next
    | FloatStore data ->
      let next = Stdlib.Array.make new_cap 0.0 in
      if a.length > 0 then Stdlib.Array.blit data 0 next 0 a.length;
      a.store <- FloatStore next
    | StringStore data ->
      let next = Stdlib.Array.make new_cap "" in
      if a.length > 0 then Stdlib.Array.blit data 0 next 0 a.length;
      a.store <- StringStore next
  )

let maybe_promote_obj_kind (data : Obj.t array) (len : int) : raw_kind =
  if len <= 0 then
    KindObj
  else
    let first = Stdlib.Array.get data 0 in
    let first_kind = raw_kind_of first in
    match first_kind with
    | KindObj -> KindObj
    | KindInt | KindFloat | KindString ->
      let rec loop i =
        if i >= len then
          first_kind
        else if raw_kind_of (Stdlib.Array.get data i) = first_kind then
          loop (i + 1)
        else
          KindObj
      in
      loop 1

let promote_obj_store_if_possible (a : 'a t) : unit =
  match a.store with
  | ObjStore data ->
    if a.length = 0 || a.null_slots <> 0 then
      ()
    else (
      let cap = Stdlib.Array.length data in
      match maybe_promote_obj_kind data a.length with
      | KindObj -> ()
      | KindInt ->
        let next = Stdlib.Array.make cap 0 in
        for i = 0 to a.length - 1 do
          Stdlib.Array.set next i (Obj.obj (Stdlib.Array.get data i))
        done;
        a.store <- IntStore next
      | KindFloat ->
        let next = Stdlib.Array.make cap 0.0 in
        for i = 0 to a.length - 1 do
          Stdlib.Array.set next i (Obj.obj (Stdlib.Array.get data i))
        done;
        a.store <- FloatStore next
      | KindString ->
        let next = Stdlib.Array.make cap "" in
        for i = 0 to a.length - 1 do
          Stdlib.Array.set next i (Obj.obj (Stdlib.Array.get data i))
        done;
        a.store <- StringStore next
    )
  | IntStore _ | FloatStore _ | StringStore _ -> ()

let maybe_promote_after_obj_write (a : 'a t) (raw : Obj.t) : unit =
  if is_non_null_raw raw && a.null_slots = 0 then promote_obj_store_if_possible a else ()

let get (a : 'a t) (i : int) : 'a =
  match unwrap_or_empty a with
  | None -> Obj.obj hx_null
  | Some a ->
    if i < 0 || i >= a.length then
      Obj.obj hx_null
    else
      (match a.store with
      | ObjStore data -> Obj.obj (Stdlib.Array.get data i)
      | IntStore data -> Obj.magic (Stdlib.Array.get data i)
      | FloatStore data -> Obj.magic (Stdlib.Array.get data i)
      | StringStore data -> Obj.magic (Stdlib.Array.get data i))

let set_obj_store_value (a : 'a t) (i : int) (raw : Obj.t) : unit =
  let data = ensure_obj_store a in
  if i >= a.length then (
    ensure_capacity a (i + 1);
    let data_after_capacity =
      match a.store with
      | ObjStore arr -> arr
      | IntStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected ObjStore after ensure_obj_store"
    in
    if i > a.length then (
      for j = a.length to i - 1 do
        Stdlib.Array.set data_after_capacity j hx_null
      done;
      a.null_slots <- a.null_slots + (i - a.length)
    );
    Stdlib.Array.set data_after_capacity i raw;
    if raw == hx_null then a.null_slots <- a.null_slots + 1;
    a.length <- i + 1;
    maybe_promote_after_obj_write a raw
  ) else (
    let previous = Stdlib.Array.get data i in
    Stdlib.Array.set data i raw;
    if previous == hx_null && raw != hx_null then
      a.null_slots <- a.null_slots - 1
    else if previous != hx_null && raw == hx_null then
      a.null_slots <- a.null_slots + 1;
    maybe_promote_after_obj_write a raw
  )

let set (a : 'a t) (i : int) (v : 'a) : 'a =
  match unwrap_or_empty a with
  | None -> v
  | Some a ->
    if i < 0 then
      v
    else
      let raw = Obj.repr v in
      match a.store with
      | ObjStore _ ->
        set_obj_store_value a i raw;
        v
      | IntStore ints ->
        if raw != hx_null && raw_kind_of raw = KindInt && i <= a.length then (
          ensure_capacity a (i + 1);
          (match a.store with
          | IntStore data -> Stdlib.Array.set data i (Obj.obj raw)
          | ObjStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected IntStore after ensure_capacity");
          if i = a.length then a.length <- a.length + 1;
          v
        ) else (
          ignore ints;
          set_obj_store_value a i raw;
          v
        )
      | FloatStore floats ->
        if raw != hx_null && raw_kind_of raw = KindFloat && i <= a.length then (
          ensure_capacity a (i + 1);
          (match a.store with
          | FloatStore data -> Stdlib.Array.set data i (Obj.obj raw)
          | ObjStore _ | IntStore _ | StringStore _ -> failwith "HxArray invariant: expected FloatStore after ensure_capacity");
          if i = a.length then a.length <- a.length + 1;
          v
        ) else (
          ignore floats;
          set_obj_store_value a i raw;
          v
        )
      | StringStore strings ->
        if raw != hx_null && raw_kind_of raw = KindString && i <= a.length then (
          ensure_capacity a (i + 1);
          (match a.store with
          | StringStore data -> Stdlib.Array.set data i (Obj.obj raw)
          | ObjStore _ | IntStore _ | FloatStore _ -> failwith "HxArray invariant: expected StringStore after ensure_capacity");
          if i = a.length then a.length <- a.length + 1;
          v
        ) else (
          ignore strings;
          set_obj_store_value a i raw;
          v
        )

let push_obj_store_value (a : 'a t) (raw : Obj.t) : int =
  ignore (ensure_obj_store a);
  ensure_capacity a (a.length + 1);
  (match a.store with
  | ObjStore data -> Stdlib.Array.set data a.length raw
  | IntStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected ObjStore after ensure_capacity");
  if raw == hx_null then a.null_slots <- a.null_slots + 1;
  a.length <- a.length + 1;
  maybe_promote_after_obj_write a raw;
  a.length

let push (a : 'a t) (v : 'a) : int =
  match unwrap_or_empty a with
  | None -> 0
  | Some a ->
    let raw = Obj.repr v in
    match a.store with
    | ObjStore _ ->
      push_obj_store_value a raw
    | IntStore _ ->
      if raw != hx_null && raw_kind_of raw = KindInt then (
        ensure_capacity a (a.length + 1);
        (match a.store with
        | IntStore data -> Stdlib.Array.set data a.length (Obj.obj raw)
        | ObjStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected IntStore after ensure_capacity");
        a.length <- a.length + 1;
        a.length
      ) else
        push_obj_store_value a raw
    | FloatStore _ ->
      if raw != hx_null && raw_kind_of raw = KindFloat then (
        ensure_capacity a (a.length + 1);
        (match a.store with
        | FloatStore data -> Stdlib.Array.set data a.length (Obj.obj raw)
        | ObjStore _ | IntStore _ | StringStore _ -> failwith "HxArray invariant: expected FloatStore after ensure_capacity");
        a.length <- a.length + 1;
        a.length
      ) else
        push_obj_store_value a raw
    | StringStore _ ->
      if raw != hx_null && raw_kind_of raw = KindString then (
        ensure_capacity a (a.length + 1);
        (match a.store with
        | StringStore data -> Stdlib.Array.set data a.length (Obj.obj raw)
        | ObjStore _ | IntStore _ | FloatStore _ -> failwith "HxArray invariant: expected StringStore after ensure_capacity");
        a.length <- a.length + 1;
        a.length
      ) else
        push_obj_store_value a raw

let pop (a : 'a t) () : 'a =
  match unwrap_or_empty a with
  | None -> Obj.obj hx_null
  | Some a ->
    if a.length = 0 then
      Obj.obj hx_null
    else (
      let i = a.length - 1 in
      match a.store with
      | ObjStore data ->
        let v = Stdlib.Array.get data i in
        Stdlib.Array.set data i hx_null;
        a.length <- i;
        if v == hx_null then a.null_slots <- a.null_slots - 1;
        Obj.obj v
      | IntStore data ->
        let v = Stdlib.Array.get data i in
        a.length <- i;
        Obj.magic v
      | FloatStore data ->
        let v = Stdlib.Array.get data i in
        a.length <- i;
        Obj.magic v
      | StringStore data ->
        let v = Stdlib.Array.get data i in
        Stdlib.Array.set data i "";
        a.length <- i;
        Obj.magic v
    )

let shift (a : 'a t) () : 'a =
  match unwrap_or_empty a with
  | None -> Obj.obj hx_null
  | Some a ->
    if a.length = 0 then
      Obj.obj hx_null
    else (
      match a.store with
      | ObjStore data ->
        let v = Stdlib.Array.get data 0 in
        if a.length > 1 then Stdlib.Array.blit data 1 data 0 (a.length - 1);
        Stdlib.Array.set data (a.length - 1) hx_null;
        a.length <- a.length - 1;
        if v == hx_null then a.null_slots <- a.null_slots - 1;
        Obj.obj v
      | IntStore data ->
        let v = Stdlib.Array.get data 0 in
        if a.length > 1 then Stdlib.Array.blit data 1 data 0 (a.length - 1);
        a.length <- a.length - 1;
        Obj.magic v
      | FloatStore data ->
        let v = Stdlib.Array.get data 0 in
        if a.length > 1 then Stdlib.Array.blit data 1 data 0 (a.length - 1);
        a.length <- a.length - 1;
        Obj.magic v
      | StringStore data ->
        let v = Stdlib.Array.get data 0 in
        if a.length > 1 then Stdlib.Array.blit data 1 data 0 (a.length - 1);
        Stdlib.Array.set data (a.length - 1) "";
        a.length <- a.length - 1;
        Obj.magic v
    )

let rec unshift (a : 'a t) (v : 'a) : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    let raw = Obj.repr v in
    match a.store with
    | ObjStore _ ->
      ensure_capacity a (a.length + 1);
      (match a.store with
      | ObjStore data ->
        if a.length > 0 then Stdlib.Array.blit data 0 data 1 a.length;
        Stdlib.Array.set data 0 raw
      | IntStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected ObjStore after ensure_capacity");
      a.length <- a.length + 1;
      if raw == hx_null then a.null_slots <- a.null_slots + 1;
      maybe_promote_after_obj_write a raw
    | IntStore _ ->
      if raw != hx_null && raw_kind_of raw = KindInt then (
        ensure_capacity a (a.length + 1);
        (match a.store with
        | IntStore data ->
          if a.length > 0 then Stdlib.Array.blit data 0 data 1 a.length;
          Stdlib.Array.set data 0 (Obj.obj raw)
        | ObjStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected IntStore after ensure_capacity");
        a.length <- a.length + 1
      ) else (
        ensure_obj_store a |> ignore;
        unshift a v
      )
    | FloatStore _ ->
      if raw != hx_null && raw_kind_of raw = KindFloat then (
        ensure_capacity a (a.length + 1);
        (match a.store with
        | FloatStore data ->
          if a.length > 0 then Stdlib.Array.blit data 0 data 1 a.length;
          Stdlib.Array.set data 0 (Obj.obj raw)
        | ObjStore _ | IntStore _ | StringStore _ -> failwith "HxArray invariant: expected FloatStore after ensure_capacity");
        a.length <- a.length + 1
      ) else (
        ensure_obj_store a |> ignore;
        unshift a v
      )
    | StringStore _ ->
      if raw != hx_null && raw_kind_of raw = KindString then (
        ensure_capacity a (a.length + 1);
        (match a.store with
        | StringStore data ->
          if a.length > 0 then Stdlib.Array.blit data 0 data 1 a.length;
          Stdlib.Array.set data 0 (Obj.obj raw)
        | ObjStore _ | IntStore _ | FloatStore _ -> failwith "HxArray invariant: expected StringStore after ensure_capacity");
        a.length <- a.length + 1
      ) else (
        ensure_obj_store a |> ignore;
        unshift a v
      )

let normalize_insert_pos (len : int) (pos : int) : int =
  if pos < 0 then
    max 0 (len + pos)
  else if pos > len then
    len
  else
    pos

let rec insert (a : 'a t) (pos : int) (v : 'a) : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    let raw = Obj.repr v in
    let p = normalize_insert_pos a.length pos in
    match a.store with
    | ObjStore _ ->
      ensure_capacity a (a.length + 1);
      (match a.store with
      | ObjStore data ->
        if p < a.length then Stdlib.Array.blit data p data (p + 1) (a.length - p);
        Stdlib.Array.set data p raw
      | IntStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected ObjStore after ensure_capacity");
      a.length <- a.length + 1;
      if raw == hx_null then a.null_slots <- a.null_slots + 1;
      maybe_promote_after_obj_write a raw
    | IntStore _ ->
      if raw != hx_null && raw_kind_of raw = KindInt then (
        ensure_capacity a (a.length + 1);
        (match a.store with
        | IntStore data ->
          if p < a.length then Stdlib.Array.blit data p data (p + 1) (a.length - p);
          Stdlib.Array.set data p (Obj.obj raw)
        | ObjStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected IntStore after ensure_capacity");
        a.length <- a.length + 1
      ) else (
        ensure_obj_store a |> ignore;
        insert a pos v
      )
    | FloatStore _ ->
      if raw != hx_null && raw_kind_of raw = KindFloat then (
        ensure_capacity a (a.length + 1);
        (match a.store with
        | FloatStore data ->
          if p < a.length then Stdlib.Array.blit data p data (p + 1) (a.length - p);
          Stdlib.Array.set data p (Obj.obj raw)
        | ObjStore _ | IntStore _ | StringStore _ -> failwith "HxArray invariant: expected FloatStore after ensure_capacity");
        a.length <- a.length + 1
      ) else (
        ensure_obj_store a |> ignore;
        insert a pos v
      )
    | StringStore _ ->
      if raw != hx_null && raw_kind_of raw = KindString then (
        ensure_capacity a (a.length + 1);
        (match a.store with
        | StringStore data ->
          if p < a.length then Stdlib.Array.blit data p data (p + 1) (a.length - p);
          Stdlib.Array.set data p (Obj.obj raw)
        | ObjStore _ | IntStore _ | FloatStore _ -> failwith "HxArray invariant: expected StringStore after ensure_capacity");
        a.length <- a.length + 1
      ) else (
        ensure_obj_store a |> ignore;
        insert a pos v
      )

let remove (a : 'a t) (x : 'a) : bool =
  match unwrap_or_empty a with
  | None -> false
  | Some a ->
    let data = ensure_obj_store a in
    let rec find i =
      if i >= a.length then
        -1
      else if Obj.obj (Stdlib.Array.get data i) = x then
        i
      else
        find (i + 1)
    in
    let idx = find 0 in
    if idx < 0 then
      false
    else (
      let removed = Stdlib.Array.get data idx in
      let last = a.length - 1 in
      if idx < last then Stdlib.Array.blit data (idx + 1) data idx (last - idx);
      Stdlib.Array.set data last hx_null;
      a.length <- last;
      if removed == hx_null then a.null_slots <- a.null_slots - 1;
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
    let data = ensure_obj_store a in
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
      (match out.store with
      | ObjStore out_data ->
        for i = 0 to out_len - 1 do
          let value = Stdlib.Array.get data (p + i) in
          Stdlib.Array.set out_data i value;
          if value == hx_null then out.null_slots <- out.null_slots + 1
        done
      | IntStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected ObjStore after ensure_capacity");
      out.length <- out_len;
      promote_obj_store_if_possible out;
      out
    )

let splice (a : 'a t) (pos : int) (len : int) : 'a t =
  match unwrap_or_empty a with
  | None -> create ()
  | Some a ->
    let data = ensure_obj_store a in
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
        (match removed.store with
        | ObjStore removed_data ->
          for i = 0 to l - 1 do
            let value = Stdlib.Array.get data (p + i) in
            Stdlib.Array.set removed_data i value;
            if value == hx_null then removed.null_slots <- removed.null_slots + 1
          done
        | IntStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected ObjStore after ensure_capacity");
        removed.length <- l;
        promote_obj_store_if_possible removed;

        let tail = total - (p + l) in
        if tail > 0 then Stdlib.Array.blit data (p + l) data p tail;
        let removed_nulls = ref 0 in
        for i = total - l to total - 1 do
          if Stdlib.Array.get data i == hx_null then removed_nulls := !removed_nulls + 1;
          Stdlib.Array.set data i hx_null
        done;
        a.length <- total - l;
        a.null_slots <- a.null_slots - !removed_nulls;
        removed
      )
    )

let iter (a : 'a t) (f : 'a -> unit) : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    for i = 0 to a.length - 1 do
      f (get a i)
    done

let copy (a : 'a t) : 'a t =
  match unwrap_or_empty a with
  | None -> create ()
  | Some a ->
    let out = create () in
    out.length <- a.length;
    out.null_slots <- a.null_slots;
    out.store <-
      (match a.store with
      | ObjStore data -> ObjStore (Stdlib.Array.copy data)
      | IntStore data -> IntStore (Stdlib.Array.copy data)
      | FloatStore data -> FloatStore (Stdlib.Array.copy data)
      | StringStore data -> StringStore (Stdlib.Array.copy data));
    out

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
      let data_a = ensure_obj_store a in
      let data_b = ensure_obj_store b in
      ensure_capacity out total;
      (match out.store with
      | ObjStore out_data ->
        if len_a > 0 then Stdlib.Array.blit data_a 0 out_data 0 len_a;
        if len_b > 0 then Stdlib.Array.blit data_b 0 out_data len_a len_b;
        out.null_slots <- a.null_slots + b.null_slots
      | IntStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected ObjStore after ensure_capacity");
      out.length <- total;
      promote_obj_store_if_possible out;
      out
    )

let reverse (a : 'a t) () : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    let i = ref 0 in
    let j = ref (a.length - 1) in
    while !i < !j do
      (match a.store with
      | ObjStore data ->
        let tmp = Stdlib.Array.get data !i in
        Stdlib.Array.set data !i (Stdlib.Array.get data !j);
        Stdlib.Array.set data !j tmp
      | IntStore data ->
        let tmp = Stdlib.Array.get data !i in
        Stdlib.Array.set data !i (Stdlib.Array.get data !j);
        Stdlib.Array.set data !j tmp
      | FloatStore data ->
        let tmp = Stdlib.Array.get data !i in
        Stdlib.Array.set data !i (Stdlib.Array.get data !j);
        Stdlib.Array.set data !j tmp
      | StringStore data ->
        let tmp = Stdlib.Array.get data !i in
        Stdlib.Array.set data !i (Stdlib.Array.get data !j);
        Stdlib.Array.set data !j tmp);
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
        else if get a i = x then
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
          else if get a i = x then
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
      to_string (get a 0)
    else (
      let b = Buffer.create 64 in
      Buffer.add_string b (to_string (get a 0));
      for i = 1 to a.length - 1 do
        Buffer.add_string b sep;
        Buffer.add_string b (to_string (get a i))
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
      for i = 0 to a.length - 1 do
        let v = f (get a i) in
        ignore (push out v)
      done;
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
        let v = get a i in
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
      (match a.store with
      | ObjStore data ->
        let removed_nulls = ref 0 in
        for i = new_len to a.length - 1 do
          if Stdlib.Array.get data i == hx_null then removed_nulls := !removed_nulls + 1;
          Stdlib.Array.set data i hx_null
        done;
        a.null_slots <- a.null_slots - !removed_nulls
      | IntStore _ -> ()
      | FloatStore _ -> ()
      | StringStore data ->
        for i = new_len to a.length - 1 do
          Stdlib.Array.set data i ""
        done);
      a.length <- new_len
    ) else (
      ensure_obj_store a |> ignore;
      ensure_capacity a new_len;
      (match a.store with
      | ObjStore data ->
        for i = a.length to new_len - 1 do
          Stdlib.Array.set data i hx_null
        done;
        a.null_slots <- a.null_slots + (new_len - a.length);
        a.length <- new_len
      | IntStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected ObjStore during grow-resize")
    )

let sort (a : 'a t) (cmp : 'a -> 'a -> int) : unit =
  match unwrap_or_empty a with
  | None -> ()
  | Some a ->
    if a.length < 2 then
      ()
    else (
      let slice = Stdlib.Array.init a.length (fun i -> Obj.repr (get a i)) in
      Stdlib.Array.sort
        (fun x y -> cmp (Obj.obj x) (Obj.obj y))
        slice;
      ensure_obj_store a |> ignore;
      (match a.store with
      | ObjStore data ->
        Stdlib.Array.blit slice 0 data 0 a.length;
        let nulls = ref 0 in
        for i = 0 to a.length - 1 do
          if Stdlib.Array.get data i == hx_null then nulls := !nulls + 1
        done;
        a.null_slots <- !nulls;
        promote_obj_store_if_possible a
      | IntStore _ | FloatStore _ | StringStore _ -> failwith "HxArray invariant: expected ObjStore after ensure_obj_store")
    )
