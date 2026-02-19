(* Minimal file IO helpers for reflaxe.ocaml (WIP).

   This backs the portable `sys.io.File` API via compiler intrinsics.
   The initial implementation focuses on whole-file operations used by
   bootstrapping (read/write String + Bytes, plus copy). *)

let getContent (path : string) : string =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let len = in_channel_length ic in
      really_input_string ic len
    )

let saveContent (path : string) (content : string) : unit =
  let oc = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_string oc content)

let getBytes (path : string) : HxBytes.t =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let len = in_channel_length ic in
      let b = Bytes.create len in
      really_input ic b 0 len;
      b
    )

let saveBytes (path : string) (bytes : HxBytes.t) : unit =
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

