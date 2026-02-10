(* hxhx(stage3) bootstrap shim: HxBootProcess *)

open Unix

type t = {
  exit_code : int;
  stdout_all : string;
  stderr_all : string;
  mutable stdout_pos : int;
  mutable stderr_pos : int;
}

let exitCode (p : t) : int = p.exit_code
let stdoutReadAll (p : t) : string = p.stdout_all
let stderrReadAll (p : t) : string = p.stderr_all

let stdout (_p : t) : Obj.t = Obj.repr (Obj.magic 0)
let stderr (_p : t) : Obj.t = Obj.repr (Obj.magic 0)

let close (_p : t) : unit = ()

let status_to_code (st : process_status) : int =
  match st with
  | WEXITED c -> c
  | WSIGNALED s -> 128 + s
  | WSTOPPED s -> 128 + s

let command_needs_shell (cmd : string) : bool =
  (* We treat a few obvious metacharacters as a signal that the caller intends to run via a shell
     (`&&`, `;`, redirects, etc). This is primarily for upstream-ish RunCi code which uses:

       Sys.command("export FOO=1 && haxe ...", null)

     When `args` is empty and the command string looks shell-ish, we run it through `/bin/sh -c`.
     Otherwise we use `/usr/bin/env <cmd> <args...>` to resolve via PATH. *)
  let len = String.length cmd in
  let rec loop i =
    if i >= len then false
    else
      match cmd.[i] with
      | ' ' | '\t' | '\n' | '\r' | '&' | '|' | ';' | '<' | '>' | '(' | ')' | '$' | '`' -> true
      | _ -> loop (i + 1)
  in
  loop 0

let read_file (path : string) : string =
  let ic = open_in_bin path in
  let len = in_channel_length ic in
  let s = really_input_string ic len in
  close_in_noerr ic;
  s

let safe_remove (path : string) : unit =
  try Unix.unlink path with _ -> ()

let command_line_argv (cmd : string) (args : string HxBootArray.t) : string array =
  Array.of_list ("/usr/bin/env" :: cmd :: HxBootArray.to_list args)

let run (cmd : string) (args : string HxBootArray.t) : t =
  (* Use /usr/bin/env so we resolve the command via PATH (Gate2 wrapper prepends a PATH entry). *)
  let use_shell = HxBootArray.length args = 0 && command_needs_shell cmd in
  let prog, argv =
    if use_shell then ("/bin/sh", [| "/bin/sh"; "-c"; cmd |])
    else ("/usr/bin/env", command_line_argv cmd args)
  in
  let out_path = Filename.temp_file "hxhx-boot" ".stdout" in
  let err_path = Filename.temp_file "hxhx-boot" ".stderr" in
  let out_fd = openfile out_path [ O_WRONLY; O_CREAT; O_TRUNC ] 0o600 in
  let err_fd = openfile err_path [ O_WRONLY; O_CREAT; O_TRUNC ] 0o600 in
  let pid = create_process prog argv stdin out_fd err_fd in
  let rec waitpid_retry () =
    try waitpid [] pid with
    | Unix_error (EINTR, _, _) -> waitpid_retry ()
  in
  let (_pid, st) = waitpid_retry () in
  Unix.close out_fd;
  Unix.close err_fd;
  let stdout_all = read_file out_path in
  let stderr_all = read_file err_path in
  safe_remove out_path;
  safe_remove err_path;
  {
    exit_code = status_to_code st;
    stdout_all;
    stderr_all;
    stdout_pos = 0;
    stderr_pos = 0;
  }

let command (cmd : string) (args : string HxBootArray.t) : int = (run cmd args).exit_code

let read_line (buf : string) (pos : int) : (string * int) =
  let len = String.length buf in
  if pos >= len then ("", len)
  else
    let rec find_nl i =
      if i >= len then i else if buf.[i] = '\n' then i else find_nl (i + 1)
    in
    let nl = find_nl pos in
    if nl >= len then (String.sub buf pos (len - pos), len)
    else (String.sub buf pos (nl - pos), nl + 1)

let stdoutReadLine (p : t) : string =
  let (line, next) = read_line p.stdout_all p.stdout_pos in
  p.stdout_pos <- next;
  line

let stderrReadLine (p : t) : string =
  let (line, next) = read_line p.stderr_all p.stderr_pos in
  p.stderr_pos <- next;
  line
