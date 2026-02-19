(* Minimal file system helpers for reflaxe.ocaml (WIP).

   This backs the portable `sys.FileSystem` API via compiler intrinsics.

   NOTE: `stat` returns a record that mirrors Haxe's `sys.FileStat` typedef.
   The `atime`/`mtime`/`ctime` fields are `Date.t` values implemented by the
   OCaml runtime module `Date` (see std/runtime/Date.ml). *)

type file_stat = {
  gid : int;
  uid : int;
  atime : Date.t;
  mtime : Date.t;
  ctime : Date.t;
  size : int;
  dev : int;
  ino : int;
  nlink : int;
  rdev : int;
  mode : int;
}

let exists (path : string) : bool =
  Sys.file_exists path

let rename (path : string) (newPath : string) : unit =
  Sys.rename path newPath

let stat (path : string) : file_stat =
  let s = Unix.stat path in
  let to_date (seconds : float) : Date.t = Date.fromTime (seconds *. 1000.0) in
  {
    gid = s.st_gid;
    uid = s.st_uid;
    atime = to_date s.st_atime;
    mtime = to_date s.st_mtime;
    ctime = to_date s.st_ctime;
    size = s.st_size;
    dev = s.st_dev;
    ino = s.st_ino;
    nlink = s.st_nlink;
    rdev = s.st_rdev;
    mode = s.st_perm;
  }

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
