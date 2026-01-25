(* Minimal Sys runtime helpers for reflaxe.ocaml (WIP).

   This module exists to provide the core `Sys.*` surface that portable Haxe
   programs expect, implemented in terms of OCaml's standard library and `Unix`.

   NOTE: Some Haxe semantics (notably nullable strings) are still evolving in
   this backend. For now, `getEnv` returns an empty string when the variable is
   missing (Haxe specifies `null`). *)

let args () : string HxArray.t =
  let out = HxArray.create () in
  let argv = Sys.argv in
  let n = Array.length argv in
  let i = ref 1 in
  while !i < n do
    ignore (HxArray.push out argv.(!i));
    i := !i + 1
  done;
  out

let getEnv (s : string) : string =
  match Sys.getenv_opt s with
  | Some v -> v
  | None -> ""

let putEnv (s : string) (v : string option) : unit =
  match v with
  | Some value -> Unix.putenv s value
  | None -> (
      (* OCaml 4.13 does not provide `Unix.unsetenv`. For now, approximate
         "removal" by setting the variable to an empty string. *)
      Unix.putenv s ""
    )

let sleep (seconds : float) : unit =
  ignore (Unix.select [] [] [] seconds)

let getCwd () : string =
  Sys.getcwd ()

let setCwd (s : string) : unit =
  Sys.chdir s

let systemName () : string =
  match Sys.os_type with
  | "Win32" | "Cygwin" -> "Windows"
  | _ ->
      (* OCaml 4.13's Unix module does not expose `uname` on all distros.
         Use a small heuristic that matches Haxe's coarse-grained names. *)
      if Sys.file_exists "/System/Library" then
        "Mac"
      else if Sys.file_exists "/proc" && Sys.is_directory "/proc" then
        "Linux"
      else
        "BSD"

let command (cmd : string) (args_opt : string HxArray.t option) : int =
  match args_opt with
  | None -> Sys.command cmd
  | Some args ->
      let len = HxArray.length args in
      let argv = Array.make (len + 1) "" in
      argv.(0) <- cmd;
      for i = 0 to len - 1 do
        argv.(i + 1) <- HxArray.get args i
      done;
      let pid = Unix.create_process cmd argv Unix.stdin Unix.stdout Unix.stderr in
      let _, status = Unix.waitpid [] pid in
      (match status with
      | Unix.WEXITED code -> code
      | Unix.WSIGNALED _ -> 1
      | Unix.WSTOPPED _ -> 1)

let exit (code : int) : unit =
  Stdlib.exit code

let time () : float =
  Unix.gettimeofday ()

let cpuTime () : float =
  Sys.time ()

let programPath () : string =
  let p = Sys.executable_name in
  try Unix.realpath p with _ ->
    if Filename.is_relative p then
      Filename.concat (Sys.getcwd ()) p
    else
      p

let getChar (echo : bool) : int =
  let c = input_char stdin in
  if echo then (
    output_char stdout c;
    flush stdout
  );
  Char.code c
