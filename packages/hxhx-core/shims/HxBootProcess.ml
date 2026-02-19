(* hxhx(stage3) bootstrap shim: HxBootProcess *)

open Unix

type t = {
  pid : int;
  mutable stdin_oc : out_channel option;
  mutable stdout_ic : in_channel option;
  mutable stderr_ic : in_channel option;
  mutable exit_code : int option;
  mutable stdout_all : string option;
  mutable stderr_all : string option;
  mutable stdout_pos : int;
  mutable stderr_pos : int;
}

let stdout (_p : t) : Obj.t = Obj.repr (Obj.magic 0)
let stderr (_p : t) : Obj.t = Obj.repr (Obj.magic 0)

let status_to_code (st : process_status) : int =
  match st with
  | WEXITED c -> c
  | WSIGNALED s -> 128 + s
  | WSTOPPED s -> 128 + s

let command_needs_shell (cmd : string) : bool =
  let len = String.length cmd in
  let rec loop i =
    if i >= len then false
    else
      match cmd.[i] with
      | ' ' | '\t' | '\n' | '\r' | '&' | '|' | ';' | '<' | '>' | '(' | ')' | '$' | '`' -> true
      | _ -> loop (i + 1)
  in
  loop 0

let command_line_argv (cmd : string) (args : string HxBootArray.t) : string array =
  Stdlib.Array.of_list ("/usr/bin/env" :: cmd :: HxBootArray.to_list args)

let rec waitpid_retry (pid : int) : process_status =
  try snd (waitpid [] pid) with
  | Unix_error (EINTR, _, _) -> waitpid_retry pid

let read_all (ic : in_channel) : string =
  let buf = Buffer.create 256 in
  let chunk = Bytes.create 4096 in
  let rec loop () =
    let n = input ic chunk 0 4096 in
    if n > 0 then (
      Buffer.add_subbytes buf chunk 0 n;
      loop ())
  in
  loop ();
  Buffer.contents buf

let ensure_waited (p : t) : unit =
  match p.exit_code with
  | Some _ -> ()
  | None ->
      (match p.stdin_oc with
      | Some oc ->
          close_out_noerr oc;
          p.stdin_oc <- None
      | None -> ());
      let st = waitpid_retry p.pid in
      p.exit_code <- Some (status_to_code st)

let ensure_cached (p : t) : unit =
  ensure_waited p;
  (match (p.stdout_all, p.stdout_ic) with
  | None, Some ic ->
      p.stdout_all <- Some (read_all ic);
      close_in_noerr ic;
      p.stdout_ic <- None
  | _ -> ());
  (match (p.stderr_all, p.stderr_ic) with
  | None, Some ic ->
      p.stderr_all <- Some (read_all ic);
      close_in_noerr ic;
      p.stderr_ic <- None
  | _ -> ())

let spawn (cmd : string) (args : string HxBootArray.t) : t =
  let use_shell = HxBootArray.length args = 0 && command_needs_shell cmd in
  let prog, argv =
    if use_shell then ("/bin/sh", [| "/bin/sh"; "-c"; cmd |])
    else ("/usr/bin/env", command_line_argv cmd args)
  in
  let stdin_r, stdin_w = pipe () in
  let stdout_r, stdout_w = pipe () in
  let stderr_r, stderr_w = pipe () in
  let pid = create_process prog argv stdin_r stdout_w stderr_w in
  close stdin_r;
  close stdout_w;
  close stderr_w;
  {
    pid;
    stdin_oc = Some (out_channel_of_descr stdin_w);
    stdout_ic = Some (in_channel_of_descr stdout_r);
    stderr_ic = Some (in_channel_of_descr stderr_r);
    exit_code = None;
    stdout_all = None;
    stderr_all = None;
    stdout_pos = 0;
    stderr_pos = 0;
  }

let run (cmd : string) (args : string HxBootArray.t) : t =
  let p = spawn cmd args in
  ignore (ensure_cached p);
  p

let exitCode (p : t) : int =
  ensure_waited p;
  match p.exit_code with
  | Some code -> code
  | None -> 0

let command (cmd : string) (args : string HxBootArray.t) : int =
  let p = spawn cmd args in
  let code = exitCode p in
  ensure_cached p;
  code

let kill (p : t) : unit =
  match p.exit_code with
  | Some _ -> ()
  | None ->
      (try Unix.kill p.pid Sys.sigkill with _ -> ())

let close (p : t) : unit =
  ensure_cached p;
  ()

let stdoutReadAll (p : t) : string =
  ensure_cached p;
  match p.stdout_all with
  | Some value -> value
  | None -> ""

let stderrReadAll (p : t) : string =
  ensure_cached p;
  match p.stderr_all with
  | Some value -> value
  | None -> ""

let read_line (buf : string) (pos : int) : (string * int) =
  let len = String.length buf in
  if pos >= len then ("", len)
  else
    let rec find_nl i =
      if i >= len then i else if buf.[i] = '\n' then i else find_nl (i + 1)
    in
    let nl = find_nl pos in
    if nl >= len then (String.sub buf pos (len - pos), len) else (String.sub buf pos (nl - pos), nl + 1)

let stdoutReadLine (p : t) : string =
  match p.stdout_all with
  | Some cache ->
      let line, next = read_line cache p.stdout_pos in
      p.stdout_pos <- next;
      line
  | None -> (
      match p.stdout_ic with
      | Some ic -> (
          try input_line ic with
          | End_of_file -> "")
      | None -> "")

let stderrReadLine (p : t) : string =
  match p.stderr_all with
  | Some cache ->
      let line, next = read_line cache p.stderr_pos in
      p.stderr_pos <- next;
      line
  | None -> (
      match p.stderr_ic with
      | Some ic -> (
          try input_line ic with
          | End_of_file -> "")
      | None -> "")
