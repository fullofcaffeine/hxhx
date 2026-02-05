(* Minimal process + pipes runtime for reflaxe.ocaml.

   Why:
   - Stage 4 macro execution (Model A) needs a robust way to spawn a helper
     process and communicate over stdin/stdout pipes.
   - Early in bootstrapping, we prefer to keep the compiler and protocol logic
     in Haxe, but the OCaml target's portable stdlib surface does not yet ship
     a stable `sys.io.Process` implementation.
   - This module provides the low-level Unix plumbing (pipes + create_process)
     behind a small, Haxe-friendly API so we can:
       - implement `sys.io.Process` as an OCaml-target std override, and
       - later retire this shim once pure-Haxe process APIs are stable.

   Portability policy:
   - This is intentionally a *runtime shim*, not compiler-core logic.
   - Non-OCaml builds of `hxhx` (e.g. a future Rust/C++ host compiler) must
     provide an equivalent transport layer (prefer pure Haxe; otherwise a
     small target-specific shim).
*)

type proc = {
  pid : int;
  stdout_ic : in_channel;
  stderr_ic : in_channel;
  stdin_oc : out_channel;
  mutable closed : bool;
  mutable exit_code : int option;
}

let next_id = ref 1
let table : (int, proc) Hashtbl.t = Hashtbl.create 16

let null_string : string = Obj.magic HxRuntime.hx_null

let get_exn (id : int) : proc =
  match Hashtbl.find_opt table id with
  | Some p -> p
  | None -> failwith ("HxProcess: invalid handle " ^ string_of_int id)

let hx_array_to_list (a : string HxArray.t) : string list =
  let n = HxArray.length a in
  let rec loop i acc =
    if i >= n then List.rev acc else loop (i + 1) (HxArray.get a i :: acc)
  in
  loop 0 []

let spawn (cmd : string) (args : string HxArray.t) : int =
  let argv = Array.of_list (cmd :: hx_array_to_list args) in
  let env = Unix.environment () in

  (* stdin pipe: parent writes -> child reads *)
  let stdin_r, stdin_w = Unix.pipe () in
  (* stdout pipe: child writes -> parent reads *)
  let stdout_r, stdout_w = Unix.pipe () in
  (* stderr pipe: child writes -> parent reads *)
  let stderr_r, stderr_w = Unix.pipe () in

  let pid =
    Unix.create_process_env cmd argv env stdin_r stdout_w stderr_w
  in

  (* Parent: close child ends *)
  Unix.close stdin_r;
  Unix.close stdout_w;
  Unix.close stderr_w;

  let stdout_ic = Unix.in_channel_of_descr stdout_r in
  let stderr_ic = Unix.in_channel_of_descr stderr_r in
  let stdin_oc = Unix.out_channel_of_descr stdin_w in

  let id = !next_id in
  next_id := id + 1;
  Hashtbl.add table id
    { pid; stdout_ic; stderr_ic; stdin_oc; closed = false; exit_code = None };
  id

let read_byte (id : int) (stream : int) : int =
  let p = get_exn id in
  let ic = if stream = 2 then p.stderr_ic else p.stdout_ic in
  try input_byte ic with End_of_file -> -1

let read_line (id : int) (stream : int) : string =
  let p = get_exn id in
  let ic = if stream = 2 then p.stderr_ic else p.stdout_ic in
  try input_line ic with End_of_file -> null_string

let write_byte (id : int) (b : int) : unit =
  let p = get_exn id in
  output_byte p.stdin_oc b

let write_string (id : int) (s : string) : unit =
  let p = get_exn id in
  output_string p.stdin_oc s

let flush_stdin (id : int) : unit =
  let p = get_exn id in
  flush p.stdin_oc

let kill (id : int) : unit =
  let p = get_exn id in
  (* Best-effort: SIGKILL. *)
  (try Unix.kill p.pid Sys.sigkill with _ -> ())

let close (id : int) : int =
  let p = get_exn id in
  if p.closed then (
    match p.exit_code with Some c -> c | None -> 0)
  else (
    p.closed <- true;
    (try close_out_noerr p.stdin_oc with _ -> ());
    (try close_in_noerr p.stdout_ic with _ -> ());
    (try close_in_noerr p.stderr_ic with _ -> ());
    let _, status = Unix.waitpid [] p.pid in
    let code =
      match status with
      | Unix.WEXITED c -> c
      | Unix.WSIGNALED _ -> 1
      | Unix.WSTOPPED _ -> 1
    in
    p.exit_code <- Some code;
    Hashtbl.remove table id;
    code)
