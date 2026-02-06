(* Minimal Date runtime for reflaxe.ocaml (WIP).

   This module backs the OCaml-target `Date` extern (std/_std/Date.hx).

   Representation:
   - `time_ms` is milliseconds since Unix epoch (Float).

   Notes:
   - Haxe Date months are 0-based; OCaml/Unix months are also 0-based.
   - This is intentionally small and grows as we need more of the Date surface
     for bootstrapping workloads (e.g. sys.FileSystem.stat / sys.FileStat). *)

type t = { time_ms : float }

let seconds (self : t) : float =
  self.time_ms /. 1000.0

let local_tm (self : t) : Unix.tm =
  Unix.localtime (seconds self)

let utc_tm (self : t) : Unix.tm =
  Unix.gmtime (seconds self)

let create (year : int) (month0 : int) (day : int) (hour : int) (min : int)
    (sec : int) : t =
  let tm : Unix.tm =
    {
      tm_sec = sec;
      tm_min = min;
      tm_hour = hour;
      tm_mday = day;
      tm_mon = month0;
      tm_year = year - 1900;
      tm_wday = 0;
      tm_yday = 0;
      (* OCaml 4.13 uses a boolean `tm_isdst`. We don't currently model the
         "unknown" value here; treat as non-DST. *)
      tm_isdst = false;
    }
  in
  let seconds, _ = Unix.mktime tm in
  { time_ms = seconds *. 1000.0 }

let fromTime (t_ms : float) : t =
  { time_ms = t_ms }

let now () : t =
  { time_ms = Unix.gettimeofday () *. 1000.0 }

let getTime (self : t) () : float =
  self.time_ms

let getHours (self : t) () : int =
  (local_tm self).tm_hour

let getMinutes (self : t) () : int =
  (local_tm self).tm_min

let getSeconds (self : t) () : int =
  (local_tm self).tm_sec

let getFullYear (self : t) () : int =
  (local_tm self).tm_year + 1900

let getMonth (self : t) () : int =
  (local_tm self).tm_mon

let getDate (self : t) () : int =
  (local_tm self).tm_mday

let getDay (self : t) () : int =
  (local_tm self).tm_wday

let getUTCHours (self : t) () : int =
  (utc_tm self).tm_hour

let getUTCMinutes (self : t) () : int =
  (utc_tm self).tm_min

let getUTCSeconds (self : t) () : int =
  (utc_tm self).tm_sec

let getUTCFullYear (self : t) () : int =
  (utc_tm self).tm_year + 1900

let getUTCMonth (self : t) () : int =
  (utc_tm self).tm_mon

let getUTCDate (self : t) () : int =
  (utc_tm self).tm_mday

let getUTCDay (self : t) () : int =
  (utc_tm self).tm_wday

let getTimezoneOffset (self : t) () : int =
  (* Similar to JS Date#getTimezoneOffset: UTC - local, in minutes. *)
  let s = seconds self in
  let t_local = s in
  let t_utc_as_local, _ = Unix.mktime (Unix.gmtime s) in
  int_of_float ((t_utc_as_local -. t_local) /. 60.0)

let toString (self : t) () : string =
  (* Keep this stable and simple for now. *)
  Printf.sprintf "<Date %.0f>" self.time_ms
