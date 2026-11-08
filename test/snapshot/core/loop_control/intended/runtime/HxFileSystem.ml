(* Minimal file system helpers for reflaxe.ocaml (WIP).

   This backs the portable `sys.FileSystem` API through its checked typed
   Haxe extern boundary.

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

(* Run one `Unix` call and report its failure the way upstream Haxe does:
   `<error text>(<call>, <path>)`, for example
   `No such file or directory(rmdir, missing)`. The result is a `Sys_error`,
   which Haxe code catches as a `String` through
   `HxRuntime.catchable_exception`. *)
let unix_call (f : unit -> 'a) : 'a =
  try f () with
  | Unix.Unix_error (error, operation, argument) ->
      raise (Sys_error (Unix.error_message error ^ "(" ^ operation ^ ", " ^ argument ^ ")"))

let exists (path : string) : bool =
  Stdlib.Sys.file_exists path

let rename (path : string) (newPath : string) : unit =
  Stdlib.Sys.rename path newPath

let stat (path : string) : file_stat =
  let s = unix_call (fun () -> Unix.stat path) in
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

(* Upstream Haxe reports every failed `fullPath` with the same fixed text,
   `Failure("get_full_path")`. Raise it as a `Sys_error` so Haxe code can
   catch it; a real OCaml `Failure` is reserved for runtime invariants. *)
let fullPath (relPath : string) : string =
  try Unix.realpath relPath with Unix.Unix_error _ -> raise (Sys_error "Failure(\"get_full_path\")")

let normalize_sep (p : string) : string =
  Stdlib.String.map (fun c -> if c = '\\' then '/' else c) p

let normalize_path (p : string) : string =
  let p = normalize_sep p in
  let is_abs = Stdlib.String.length p > 0 && (Stdlib.String.get p (0)) = '/' in
  let parts = Stdlib.String.split_on_char '/' p in
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
  let rev = Stdlib.List.rev (step [] parts) in
  let body = Stdlib.String.concat "/" rev in
  if is_abs then "/" ^ body else body

(* Haxe `absolutePath` keeps an absolute input unchanged, including `..` and
   `.` segments; only a relative input is joined to the working directory. *)
let absolutePath (relPath : string) : string =
  if Filename.is_relative relPath then
    normalize_path (Filename.concat (Stdlib.Sys.getcwd ()) relPath)
  else
    relPath

(* Haxe `isDirectory` answers false for a missing path instead of failing. *)
let isDirectory (path : string) : bool =
  Stdlib.Sys.file_exists path && Stdlib.Sys.is_directory path

(* Drop trailing `/` characters, keeping a root `/`. Upstream's `mkdir` error
   names the directory without them. *)
let rec strip_trailing_slashes (path : string) : string =
  let n = Stdlib.String.length path in
  if n > 1 && Stdlib.String.get path (n - 1) = '/' then
    strip_trailing_slashes (Stdlib.String.sub path 0 (n - 1))
  else
    path

(* Haxe `createDirectory` creates missing parents first and does nothing for a
   path that already exists, even a regular file. A path below a regular file
   fails in `mkdir`, for example `Not a directory(mkdir, file/sub)`. *)
let rec createDirectory (path : string) : unit =
  let path = strip_trailing_slashes path in
  if path = "" || path = "." || Stdlib.Sys.file_exists path then
    ()
  else (
    let parent = Filename.dirname path in
    if parent <> path && parent <> "." then createDirectory parent;
    unix_call (fun () -> Unix.mkdir path 0o755)
  )

let deleteFile (path : string) : unit =
  Stdlib.Sys.remove path

let deleteDirectory (path : string) : unit =
  unix_call (fun () -> Unix.rmdir path)

(* A missing path keeps the host `<path>: <error text>` message; an existing
   path that is not a directory reports `No such directory`, as upstream does. *)
let readDirectory (path : string) : string HxArray.t =
  let out = HxArray.create () in
  if not (Stdlib.Sys.is_directory path) then raise (Sys_error "No such directory");
  let entries = Stdlib.Sys.readdir path in
  Stdlib.Array.iter (fun name -> ignore (HxArray.push out name)) entries;
  out
