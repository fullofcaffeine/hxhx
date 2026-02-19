(* Standard IO runtime helpers for reflaxe.ocaml.

   Why
   - Portable Haxe programs expect `Sys.stdin()`, `Sys.stdout()`, and `Sys.stderr()`
     to return `haxe.io.Input` / `haxe.io.Output` streams.
   - Early in the OCaml backend bring-up, we keep the public Haxe API intact and
     implement the low-level byte/line operations in a tiny OCaml shim.

   What
   - Read helpers for stdin:
     - read_byte 0
     - read_line 0
   - Write helpers for stdout/stderr:
     - write_byte 1/2
     - write_string 1/2
     - flush 1/2

   Null strings
   - When returning `Null<String>` to Haxe, we represent `null` as the runtime
     sentinel `Obj.magic HxRuntime.hx_null`.
*)

let null_string : string = Obj.magic HxRuntime.hx_null

let stdin_stream = 0
let stdout_stream = 1
let stderr_stream = 2

let read_byte (stream : int) : int =
  if stream <> stdin_stream then
    -1
  else
    try input_byte stdin with End_of_file -> -1

let read_line (stream : int) : string =
  if stream <> stdin_stream then
    null_string
  else
    try input_line stdin with End_of_file -> null_string

let out_channel_for (stream : int) : out_channel =
  if stream = stderr_stream then stderr else stdout

let write_byte (stream : int) (b : int) : unit =
  output_byte (out_channel_for stream) b

let write_string (stream : int) (s : string) : unit =
  output_string (out_channel_for stream) s

let flush (stream : int) : unit =
  flush (out_channel_for stream)

