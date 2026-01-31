(* Minimal Date runtime for reflaxe.ocaml (WIP).

   This module backs the OCaml-target `Date` extern (std/_std/Date.hx).

   Representation:
   - `time_ms` is milliseconds since Unix epoch (Float).

   Notes:
   - Haxe Date months are 0-based; OCaml/Unix months are also 0-based.
   - This is intentionally small and grows as we need more of the Date surface
     for bootstrapping workloads (e.g. sys.FileSystem.stat / sys.FileStat). *)

type t = { time_ms : float }

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

let toString (self : t) () : string =
  (* Keep this stable and simple for now. *)
  Printf.sprintf "<Date %.0f>" self.time_ms
