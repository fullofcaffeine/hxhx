(* HXHX Stage 4 (Model A): Macro host RPC helper.

   Why:
   - Stage 4 executes macros natively. Model A runs macros out-of-process and
     communicates over a versioned protocol.
   - This module is the first rung: it implements a deterministic "selftest"
     used by CI to validate:
       - spawn + pipes
       - handshake
       - a couple of stubbed Context/Compiler calls

   What:
   - [selftest host_exe] returns a newline-delimited report:
       macro_host=ok
       macro_ping=pong
       macro_define=ok
       macro_defined=yes
       macro_definedValue=bar

   How:
   - Uses Unix.open_process_full for portability.
   - The macro host executable is built from Haxe sources in:
       packages/hxhx-macro-host/
   - Protocol details:
       docs/02-user-guide/HXHX_MACRO_HOST_PROTOCOL.md
*)

let proto_version = 1

let banner = "hxhx_macro_rpc_v=" ^ string_of_int proto_version

let escape_payload (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let unescape_payload (s : string) : string =
  let b = Buffer.create (String.length s) in
  let i = ref 0 in
  while !i < String.length s do
    match s.[!i] with
    | '\\' ->
        if !i + 1 >= String.length s then (
          Buffer.add_char b '\\';
          i := !i + 1)
        else (
          match s.[!i + 1] with
          | 'n' ->
              Buffer.add_char b '\n';
              i := !i + 2
          | 'r' ->
              Buffer.add_char b '\r';
              i := !i + 2
          | 't' ->
              Buffer.add_char b '\t';
              i := !i + 2
          | '\\' ->
              Buffer.add_char b '\\';
              i := !i + 2
          | c ->
              Buffer.add_char b c;
              i := !i + 2)
    | c ->
        Buffer.add_char b c;
        i := !i + 1
  done;
  Buffer.contents b

let encode_len (label : string) (value : string) : string =
  let enc = escape_payload value in
  Printf.sprintf "%s=%d:%s" label (String.length enc) enc

let decode_len_value (part : string) : string =
  (* part is `<label>=<len>:<payload...>` *)
  match String.index_opt part '=' with
  | None -> ""
  | Some eq -> (
      let rest =
        String.sub part (eq + 1) (String.length part - eq - 1)
      in
      match String.index_opt rest ':' with
      | None -> ""
      | Some colon ->
          let len_s = String.sub rest 0 colon in
          let payload =
            String.sub rest (colon + 1) (String.length rest - colon - 1)
          in
          let len =
            try int_of_string len_s with _ -> -1
          in
          if len < 0 || String.length payload < len then ""
          else unescape_payload (String.sub payload 0 len))

let split_spaces (s : string) : string list =
  s
  |> String.split_on_char ' '
  |> List.filter (fun x -> x <> "")

let kv_get (tail : string) (key : string) : string =
  tail |> split_spaces
  |> List.find_opt (fun p -> String.length p >= String.length key + 1 && String.sub p 0 (String.length key + 1) = key ^ "=")
  |> function
  | None -> ""
  | Some part -> decode_len_value part

let write_line (oc : out_channel) (s : string) : unit =
  output_string oc s;
  output_char oc '\n';
  flush oc

let read_line_opt (ic : in_channel) : string option =
  try Some (input_line ic) with End_of_file -> None

let call (ic : in_channel) (oc : out_channel) (id : int) (meth : string)
    (tail : string) : (string, string) result =
  let msg =
    if tail = "" then Printf.sprintf "req %d %s" id meth
    else Printf.sprintf "req %d %s %s" id meth tail
  in
  write_line oc msg;
  match read_line_opt ic with
  | None -> Error "macro host: eof"
  | Some line -> (
      match split_spaces line with
      | "res" :: rid_s :: status :: rest ->
          let rid = try int_of_string rid_s with _ -> -1 in
          if rid <> id then Error ("macro host: response id mismatch: " ^ line)
          else
            let tail = String.concat " " rest in
            if status = "ok" then Ok (kv_get tail "v")
            else Error (kv_get tail "m")
      | _ -> Error ("macro host: invalid response: " ^ line))

let selftest (host_exe : string) : string =
  let env = Unix.environment () in
  let ic, oc, ec = Unix.open_process_full host_exe env in
  let cleanup () =
    ignore (Unix.close_process_full (ic, oc, ec))
  in
  try
    (* Handshake *)
    let banner_line =
      match read_line_opt ic with
      | None -> failwith "macro host: eof during banner"
      | Some s -> s
    in
    if banner_line <> banner then
      failwith ("macro host: unsupported banner: " ^ banner_line);
    write_line oc ("hello proto=" ^ string_of_int proto_version);
    let ok_line =
      match read_line_opt ic with
      | None -> failwith "macro host: eof during handshake"
      | Some s -> s
    in
    if ok_line <> "ok" then failwith ("macro host: handshake failed: " ^ ok_line);

    let lines = ref [ "macro_host=ok" ] in

    (match call ic oc 1 "ping" "" with
    | Error e -> failwith ("macro host: ping failed: " ^ e)
    | Ok pong -> lines := !lines @ [ "macro_ping=" ^ pong ]);

    let define_tail = encode_len "n" "foo" ^ " " ^ encode_len "v" "bar" in
    (match call ic oc 2 "compiler.define" define_tail with
    | Error e -> failwith ("macro host: define failed: " ^ e)
    | Ok v -> lines := !lines @ [ "macro_define=" ^ v ]);

    (match call ic oc 3 "context.defined" (encode_len "n" "foo") with
    | Error e -> failwith ("macro host: defined failed: " ^ e)
    | Ok v ->
        lines :=
          !lines @ [ "macro_defined=" ^ if v = "1" then "yes" else "no" ]);

    (match call ic oc 4 "context.definedValue" (encode_len "n" "foo") with
    | Error e -> failwith ("macro host: definedValue failed: " ^ e)
    | Ok v -> lines := !lines @ [ "macro_definedValue=" ^ v ]);

    write_line oc "quit";
    cleanup ();
    String.concat "\n" !lines
  with
  | Failure msg ->
      cleanup ();
      msg
  | e ->
      cleanup ();
      raise e

let run (host_exe : string) (expr : string) : string =
  let env = Unix.environment () in
  let ic, oc, ec = Unix.open_process_full host_exe env in
  let cleanup () =
    ignore (Unix.close_process_full (ic, oc, ec))
  in
  try
    (* Handshake *)
    let banner_line =
      match read_line_opt ic with
      | None -> failwith "macro host: eof during banner"
      | Some s -> s
    in
    if banner_line <> banner then
      failwith ("macro host: unsupported banner: " ^ banner_line);
    write_line oc ("hello proto=" ^ string_of_int proto_version);
    let ok_line =
      match read_line_opt ic with
      | None -> failwith "macro host: eof during handshake"
      | Some s -> s
    in
    if ok_line <> "ok" then failwith ("macro host: handshake failed: " ^ ok_line);

    let tail = encode_len "e" expr in
    let result =
      match call ic oc 1 "macro.run" tail with
      | Error e -> failwith ("macro host: macro.run failed: " ^ e)
      | Ok v -> v
    in
    write_line oc "quit";
    cleanup ();
    result
  with
  | Failure msg ->
      cleanup ();
      msg
  | e ->
      cleanup ();
      raise e

let get_type (host_exe : string) (name : string) : string =
  let env = Unix.environment () in
  let ic, oc, ec = Unix.open_process_full host_exe env in
  let cleanup () =
    ignore (Unix.close_process_full (ic, oc, ec))
  in
  try
    (* Handshake *)
    let banner_line =
      match read_line_opt ic with
      | None -> failwith "macro host: eof during banner"
      | Some s -> s
    in
    if banner_line <> banner then
      failwith ("macro host: unsupported banner: " ^ banner_line);
    write_line oc ("hello proto=" ^ string_of_int proto_version);
    let ok_line =
      match read_line_opt ic with
      | None -> failwith "macro host: eof during handshake"
      | Some s -> s
    in
    if ok_line <> "ok" then failwith ("macro host: handshake failed: " ^ ok_line);

    let tail = encode_len "n" name in
    let result =
      match call ic oc 1 "context.getType" tail with
      | Error e -> failwith ("macro host: context.getType failed: " ^ e)
      | Ok v -> v
    in
    write_line oc "quit";
    cleanup ();
    result
  with
  | Failure msg ->
      cleanup ();
      msg
  | e ->
      cleanup ();
      raise e
