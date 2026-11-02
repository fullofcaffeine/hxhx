(* Minimal file IO helpers for reflaxe.ocaml (WIP).

   This backs the portable `sys.io.File` API via compiler intrinsics.
   The initial implementation focuses on whole-file operations used by
   bootstrapping (read/write String + Bytes, plus copy). *)

(* Upstream Haxe reports any failed whole-file read, such as a missing file or
   a directory path, with one message: `Could not read file <path>`. Haxe code
   catches it through `HxRuntime.catchable_exception`. *)
let read_whole_file (path : string) (read : in_channel -> int -> 'a) : 'a =
  try
    let ic = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> read ic (in_channel_length ic))
  with Sys_error _ | End_of_file -> raise (Sys_error ("Could not read file " ^ path))

let getContent (path : string) : string =
  read_whole_file path really_input_string

let saveContent (path : string) (content : string) : unit =
  let oc = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_string oc content)

let getBytes (path : string) : HxBytes.data =
  read_whole_file path (fun ic len ->
      let b = Bytes.create len in
      really_input ic b 0 len;
      b)

let saveBytes (path : string) (bytes : HxBytes.data) : unit =
  let oc = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_bytes oc bytes)

let copy (srcPath : string) (dstPath : string) : unit =
  let ic = open_in_bin srcPath in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let oc = open_out_bin dstPath in
      Fun.protect
        ~finally:(fun () -> close_out_noerr oc)
        (fun () ->
          let buf = Bytes.create 16384 in
          let rec loop () =
            let n = input ic buf 0 (Bytes.length buf) in
            if n = 0 then () else (output oc buf 0 n; loop ())
          in
          loop ()
        )
    )
