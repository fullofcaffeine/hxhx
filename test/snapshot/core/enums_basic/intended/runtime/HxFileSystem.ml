(* Minimal file system helpers for reflaxe.ocaml (WIP).

   This backs the portable `sys.FileSystem` API via compiler intrinsics.

   NOTE: `stat` is intentionally not implemented yet because it requires a
   stable representation of `sys.FileStat` (and `Date`). *)

let exists (path : string) : bool =
  Sys.file_exists path

let rename (path : string) (newPath : string) : unit =
  Sys.rename path newPath

let stat (_path : string) : Obj.t =
  HxRuntime.hx_throw (Obj.repr "sys.FileSystem.stat is not implemented yet")

let fullPath (relPath : string) : string =
  Unix.realpath relPath

let normalize_sep (p : string) : string =
  String.map (fun c -> if c = '\\' then '/' else c) p

let normalize_path (p : string) : string =
  let p = normalize_sep p in
  let is_abs = String.length p > 0 && p.[0] = '/' in
  let parts = String.split_on_char '/' p in
  let rec step stack = function
    | [] -> stack
    | "" :: rest -> step stack rest
    | "." :: rest -> step stack rest
    | ".." :: rest -> (
        match stack with
        | [] -> if is_abs then step [] rest else step [".."] rest
        | _ :: tail -> step tail rest
      )
    | x :: rest -> step (x :: stack) rest
  in
  let rev = List.rev (step [] parts) in
  let body = String.concat "/" rev in
  if is_abs then "/" ^ body else body

let absolutePath (relPath : string) : string =
  let base =
    if Filename.is_relative relPath then
      Filename.concat (Sys.getcwd ()) relPath
    else
      relPath
  in
  normalize_path base

let isDirectory (path : string) : bool =
  Sys.is_directory path

let rec createDirectory (path : string) : unit =
  if path = "" || path = "." then
    ()
  else if Sys.file_exists path then (
    if Sys.is_directory path then () else raise (Sys_error ("Not a directory: " ^ path))
  ) else (
    let parent = Filename.dirname path in
    if parent <> path && parent <> "." then createDirectory parent;
    Sys.mkdir path 0o755
  )

let deleteFile (path : string) : unit =
  Sys.remove path

let deleteDirectory (path : string) : unit =
  Sys.rmdir path

let readDirectory (path : string) : string HxArray.t =
  let out = HxArray.create () in
  let entries = Sys.readdir path in
  Array.iter (fun name -> ignore (HxArray.push out name)) entries;
  out
