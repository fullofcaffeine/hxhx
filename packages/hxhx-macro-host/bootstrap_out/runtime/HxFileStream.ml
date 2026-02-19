(* File stream helpers for reflaxe.ocaml (WIP).

   Why
   - The portable `sys.io.FileInput` / `sys.io.FileOutput` API is used heavily by upstream
     unit fixtures (seek/tell/eof) and by real-world tooling workloads.
   - OCaml channels are the natural substrate for this, but we need a stable ABI surface
     that Haxe can call through via `@:native` externs.

   What
   - Open/close for input and output streams.
   - Byte-level read/write (sufficient for bootstrapping; higher-level buffering is in Haxe).
   - seek/tell/eof.

   How
   - Handles are passed through Haxe as opaque `Dynamic` values and represented here as
     `Obj.t` containing an `in_channel` or `out_channel`.
   - We keep behavior conservative and deterministic; error mapping to Haxe exceptions can be
     improved later (e.g. by translating Unix errors to `sys.io.File` exceptions). *)

type seek_kind = int

let seek_begin = 0
let seek_cur = 1
let seek_end = 2

let open_in (path : string) (_binary : bool) : Obj.t =
  Obj.repr (open_in_bin path)

let open_out (path : string) (_binary : bool) (append : bool) (update : bool) : Obj.t =
  (* Best-effort flags:
     - write(): trunc
     - append(): append
     - update(): no-trunc overwrite (seek/tell still work)
  *)
  let flags =
    if append then
      [ Open_wronly; Open_creat; Open_append; Open_binary ]
    else if update then
      [ Open_wronly; Open_creat; Open_binary ]
    else
      [ Open_wronly; Open_creat; Open_trunc; Open_binary ]
  in
  Obj.repr (open_out_gen flags 0o666 path)

let close_in (h : Obj.t) : unit =
  try close_in_noerr (Obj.obj h : in_channel) with _ -> ()

let close_out (h : Obj.t) : unit =
  try close_out_noerr (Obj.obj h : out_channel) with _ -> ()

let read_byte (h : Obj.t) : int =
  let ic = (Obj.obj h : in_channel) in
  try input_byte ic with End_of_file -> -1

let write_byte (h : Obj.t) (b : int) : unit =
  let oc = (Obj.obj h : out_channel) in
  output_byte oc b

let flush_out (h : Obj.t) : unit =
  let oc = (Obj.obj h : out_channel) in
  flush oc

let tell_in (h : Obj.t) : int =
  pos_in (Obj.obj h : in_channel)

let tell_out (h : Obj.t) : int =
  pos_out (Obj.obj h : out_channel)

let seek_in (h : Obj.t) (p : int) (kind : seek_kind) : unit =
  let ic = (Obj.obj h : in_channel) in
  let target =
    if kind = seek_begin then
      p
    else if kind = seek_cur then
      (pos_in ic) + p
    else
      (in_channel_length ic) + p
  in
  seek_in ic target

let file_size_of_out_channel (oc : out_channel) : int =
  try
    let fd = Unix.descr_of_out_channel oc in
    let st = Unix.fstat fd in
    st.st_size
  with _ ->
    0

let seek_out (h : Obj.t) (p : int) (kind : seek_kind) : unit =
  let oc = (Obj.obj h : out_channel) in
  let cur = pos_out oc in
  let target =
    if kind = seek_begin then
      p
    else if kind = seek_cur then
      cur + p
    else
      (file_size_of_out_channel oc) + p
  in
  seek_out oc target

let eof_in (h : Obj.t) : bool =
  let ic = (Obj.obj h : in_channel) in
  try
    pos_in ic >= in_channel_length ic
  with _ ->
    false
