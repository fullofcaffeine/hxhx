(* Cost and edge-case contract for the HxString runtime.

   Each check prints one PASS/FAIL line. The cost checks read HxString's work
   counters instead of timing, so they are deterministic on a loaded machine:
   - Strings of 64 bytes or more that are used in rotation must be scanned
     once each, not once per call (the cache must keep them).
   - A character-by-character loop over a short non-ASCII string must step over
     a linear number of characters, not a quadratic one.
   Timings are printed for information only. *)

let failures = ref 0

let check name ok detail =
  if ok then Printf.printf "PASS %s\n%!" name
  else (
    incr failures;
    Printf.printf "FAIL %s: %s\n%!" name detail)

let repeat n s =
  let b = Buffer.create (String.length s * n) in
  for _ = 1 to n do Buffer.add_string b s done;
  Buffer.contents b

let nul : int = Obj.magic HxRuntime.hx_null
let code s i = let v = HxString.charCodeAt s i in if v == HxRuntime.hx_null then -1 else (Obj.obj v : int)

let round_robin ~ascii k rounds =
  let strs =
    Array.init k (fun i ->
        if ascii then repeat 16 (Printf.sprintf "abc%d" i) else repeat 16 (Printf.sprintf "\xc3\xa9%d\xe6\xbc\xa2" i))
  in
  let before = !HxString.stats_scans in
  let t0 = Unix.gettimeofday () in
  let acc = ref 0 in
  for _ = 1 to rounds do
    for j = 0 to k - 1 do
      acc := !acc + HxString.cca (Array.get strs j) 40 + HxString.length (Array.get strs j)
    done
  done;
  let ms = (Unix.gettimeofday () -. t0) *. 1000.0 in
  (!HxString.stats_scans - before, ms, !acc)

let () =
  (* Round-robin over up to 12 long strings: each is scanned a bounded number of times. *)
  List.iter
    (fun ascii ->
      for k = 1 to 12 do
        let scans, ms, _ = round_robin ~ascii k 2000 in
        Printf.printf "info round-robin ascii=%b k=%d scans=%d %.2f ms\n" ascii k scans ms;
        check
          (Printf.sprintf "round-robin-%s-%d" (if ascii then "ascii" else "utf8") k)
          (scans <= 2 * k)
          (Printf.sprintf "%d scans for %d strings over 2000 rounds" scans k)
      done)
    [ true; false ];
  (* One hot source string survives a stream of single-use long strings. *)
  let source = repeat 200 "h\xc3\xa9llo " in
  ignore (HxString.length source);
  let before = !HxString.stats_scans in
  for i = 0 to 9999 do
    ignore (HxString.cca source (i mod 1000));
    ignore (HxString.length (string_of_int i ^ String.make 80 'z'))
  done;
  let scans = !HxString.stats_scans - before in
  check "hot-source-survives-stream" (scans <= 10000 + 2) (Printf.sprintf "%d scans" scans);
  (* Character loop over a short (< 64 byte) non-ASCII string stays linear. *)
  let short = repeat 6 "a\xc3\xa9\xe6\xbc\xa2\xf0\x9f\x98\x80" in
  let n = HxString.length short in
  let before = !HxString.stats_walked in
  for _ = 1 to 100 do
    for i = 0 to n - 1 do ignore (HxString.cca short i) done
  done;
  let walked = !HxString.stats_walked - before in
  check "short-utf8-loop-linear" (walked <= 100 * n * 2)
    (Printf.sprintf "%d characters walked for 100 passes over %d characters" walked n);
  (* ASCII string of 64+ bytes through the cache. *)
  let ascii = repeat 10 "abcdefghij" in
  check "ascii-long-length" (HxString.length ascii = 100) "";
  check "ascii-long-codes" (code ascii 0 = 97 && code ascii 99 = 106 && code ascii 100 = -1 && code ascii (-1) = -1) "";
  check "ascii-long-substr" (HxString.substr ascii 95 nul = "fghij" && HxString.substring ascii 3 5 = "de") "";
  check "ascii-long-search" (HxString.indexOf ascii "j" 10 = 19 && HxString.lastIndexOf ascii "a" nul = 90) "";
  (* substring with start past the end on ASCII (short and cached). *)
  check "ascii-substring-start-past-end" (HxString.substring "hello" 9 1 = "ello") (HxString.substring "hello" 9 1);
  check "ascii-long-substring-start-past-end" (HxString.substring ascii 500 98 = "ij") "";
  (* Ill-formed bytes in a cached string. *)
  let bad = repeat 10 "\xc3\xa9\xff\xe6\xbc\xa2x\xc3" in
  check "illformed-long-length" (HxString.length bad = 50) (string_of_int (HxString.length bad));
  check "illformed-long-codes" (code bad 0 = 233 && code bad 1 = 255 && code bad 2 = 0x6F22 && code bad 4 = 0xC3 && code bad 49 = 0xC3) "";
  check "illformed-long-search"
    (HxString.indexOf bad "\xc3" nul = 4 && HxString.lastIndexOf bad "\xff" nul = 46 && HxString.indexOf bad "x" 10 = 13) "";
  check "illformed-long-case" (HxString.toUpperCase bad () = repeat 10 "\xc3\x89\xff\xe6\xbc\xa2X\xc3") "";
  check "illformed-long-split" (HxArray.length (HxString.split bad "\xff") = 11) "";
  if !failures = 0 then print_endline "HXSTRING_RUNTIME_CONTRACT:PASS"
  else (
    Printf.printf "HXSTRING_RUNTIME_CONTRACT:FAIL failures=%d\n" !failures;
    exit 1)
