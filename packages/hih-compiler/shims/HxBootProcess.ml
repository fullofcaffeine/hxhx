(* hxhx(stage3) bootstrap shim: HxBootProcess *)

open Unix

type t = {
  exit_code : int;
  stdout : string;
  stderr : string;
}

let exitCode (p : t) : int = p.exit_code
let stdoutReadAll (p : t) : string = p.stdout
let stderrReadAll (p : t) : string = p.stderr

let stdout (_p : t) : Obj.t = Obj.repr (Obj.magic 0)
let stderr (_p : t) : Obj.t = Obj.repr (Obj.magic 0)

let status_to_code (st : process_status) : int =
  match st with
  | WEXITED c -> c
  | WSIGNALED s -> 128 + s
  | WSTOPPED s -> 128 + s

let run (cmd : string) (args : string HxBootArray.t) : t =
  (* Use /usr/bin/env so we resolve the command via PATH (Gate2 wrapper prepends a PATH entry). *)
  let argv = Array.of_list ("/usr/bin/env" :: cmd :: HxBootArray.to_list args) in
  let pid = create_process "/usr/bin/env" argv stdin stdout stderr in
  let (_pid, st) = waitpid [] pid in
  { exit_code = status_to_code st; stdout = ""; stderr = "" }

