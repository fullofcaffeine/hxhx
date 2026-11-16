(* Seeded differential test: compares every HxString method with a naive
   reference that decodes the whole string into an array of characters.
   Inputs mix ASCII, two- to four-byte characters and ill-formed bytes, below
   and above the 64-byte cache threshold, in random access order. *)

let width s i =
  let n = String.length s in
  let b k = if k < n then Char.code s.[k] else -1 in
  let c k = let x = b k in x >= 0x80 && x <= 0xBF in
  let b0 = b i in
  if b0 < 0x80 then 1
  else if b0 >= 0xC2 && b0 <= 0xDF then (if c (i+1) then 2 else 0)
  else if b0 >= 0xE0 && b0 <= 0xEF then
    (let lo = if b0 = 0xE0 then 0xA0 else 0x80 in
     let x = b (i+1) in if x >= lo && x <= 0xBF && c (i+2) then 3 else 0)
  else if b0 >= 0xF0 && b0 <= 0xF4 then
    (let lo = if b0 = 0xF0 then 0x90 else 0x80 and hi = if b0 = 0xF4 then 0x8F else 0xBF in
     let x = b (i+1) in if x >= lo && x <= hi && c (i+2) && c (i+3) then 4 else 0)
  else 0

(* chars: (slice, code, wellformed) *)
let decode s =
  let n = String.length s in
  let out = ref [] in
  let i = ref 0 in
  while !i < n do
    let w = width s !i in
    let code, w', wf =
      if w = 0 then Char.code s.[!i], 1, false
      else
        let cp = Uchar.to_int (Uchar.utf_decode_uchar (String.get_utf_8_uchar s !i)) in
        (* surrogates: decoder replaces; compute manually *)
        let b k = Char.code s.[!i + k] in
        let cp = if w = 3 then ((b 0 land 0xF) lsl 12) lor ((b 1 land 0x3F) lsl 6) lor (b 2 land 0x3F) else cp in
        cp, w, true in
    out := (String.sub s !i w', code, wf) :: !out;
    i := !i + w'
  done;
  Array.of_list (List.rev !out)

let expand runs =
  let h = Hashtbl.create 4096 in
  let r = Array.length runs / 4 in
  for k = 0 to r - 1 do
    let f = runs.(4*k) and l = runs.(4*k+1) and st = runs.(4*k+2) and d = runs.(4*k+3) in
    let c = ref f in
    while !c <= l do Hashtbl.replace h !c (!c + d); c := !c + st done
  done; h
let up = expand HxString.upper_runs
let lo = expand HxString.lower_runs
let enc c = let b = Buffer.create 4 in Buffer.add_utf_8_uchar b (Uchar.unsafe_of_int c); Buffer.contents b
let enc c = if c >= 0xD800 && c <= 0xDFFF then
  let b = Buffer.create 3 in
  Buffer.add_char b (Char.chr (0xE0 lor (c lsr 12)));
  Buffer.add_char b (Char.chr (0x80 lor ((c lsr 6) land 0x3F)));
  Buffer.add_char b (Char.chr (0x80 lor (c land 0x3F))); Buffer.contents b else enc c

let ref_case h s =
  String.concat "" (Array.to_list (Array.map (fun (sl, c, wf) ->
    if not wf then sl else enc (try Hashtbl.find h c with Not_found -> c)) (decode s)))

let join a i j = String.concat "" (Array.to_list (Array.map (fun (x,_,_) -> x) (Array.sub a i (j - i))))
let matches a i sub = let m = Array.length sub in
  i + m <= Array.length a && (let ok = ref true in for k = 0 to m-1 do let (x,_,_) = a.(i+k) and (y,_,_) = sub.(k) in if x <> y then ok := false done; !ok)

let ref_indexOf s sub st =
  let a = decode s and b = decode sub in
  let slen = Array.length a and nlen = Array.length b in
  if st > slen then -1 else if nlen = 0 then max 0 st else
  let r = ref (-1) in let i = ref (max 0 st) in
  while !r < 0 && !i <= slen - nlen do if matches a !i b then r := !i; incr i done; !r
let ref_lastIndexOf s sub st =
  let a = decode s and b = decode sub in
  let slen = Array.length a and nlen = Array.length b in
  if nlen = 0 then (let idx = if st < 0 then slen else st in min idx slen) else
  let mp = slen - nlen in if mp < 0 then -1 else
  let idx = if st < 0 then slen else st in let start = min (min idx slen) mp in
  let r = ref (-1) in let i = ref start in
  while !r < 0 && !i >= 0 do if matches a !i b then r := !i; decr i done; !r
let ref_split s d =
  let a = decode s and b = decode d in let n = Array.length a and m = Array.length b in
  if String.length d = 0 then Array.to_list (Array.map (fun (x,_,_) -> x) a) else
  let out = ref [] and start = ref 0 and i = ref 0 in
  while !i <= n - m do
    if matches a !i b then (out := join a !start !i :: !out; i := !i + m; start := !i) else incr i done;
  List.rev (join a !start n :: !out)
let ref_substr s pos len =
  let a = decode s in let slen = Array.length a in
  let p = if pos < 0 then max 0 (slen + pos) else pos in
  if p >= slen then "" else let l0 = if len < 0 then slen - p else len in
  if l0 <= 0 then "" else join a p (p + min l0 (slen - p))
let ref_substring s st en =
  let a = decode s in let slen = Array.length a in
  let s0 = max 0 st and e0 = if en < 0 then 0 else min en slen in
  let x, y = if s0 > e0 then e0, s0 else s0, e0 in
  let y = min y slen in if x >= slen || y <= x then "" else join a x y

let pieces = [| "a"; "b"; "Z"; "x"; " "; "\xc3\xa9"; "\xc3\x83"; "\xc3\x89"; "\xe2\x82\xac"; "\xf0\x9f\x98\x80"; "\xd0\x96";
  "\x80"; "\xbf"; "\xc0"; "\xc1"; "\xc3"; "\xe2\x82"; "\xf0\x9f"; "\xf0\x9f\x98"; "\xf5"; "\xff"; "\xed\xa0\x80"; "\xe0\x80\x80";
  "\xe0\x9f\xbf"; "\xf4\x90\x80\x80"; "\xf4\x8f\xbf\xbf"; "\xf0\x80\x80\x80"; "\xe9"; "\xc7\x86"; "\xe1\xba\x9e" |]
let rnd_str maxp =
  let k = Random.int maxp in
  let b = Buffer.create 16 in
  for _ = 1 to k do Buffer.add_string b pieces.(Random.int (Array.length pieces)) done;
  Buffer.contents b
let nul : int = Obj.magic HxRuntime.hx_null
let rarg n = if Random.int 8 = 0 then nul else Random.int (n + 7) - 3
let deopt v d = if v == nul then d else v


(* Earlier implementation model (match start checked, end unchecked); used only
   to label a failure. *)
let starts s = let a = decode s in let o = Array.make (Array.length a + 1) 0 in
  Array.iteri (fun i (x,_,_) -> o.(i+1) <- o.(i) + String.length x) a; o
let bmatch s sub i = i + String.length sub <= String.length s && String.sub s i (String.length sub) = sub
let idx_of o b = let r = ref (-1) in Array.iteri (fun i x -> if x = b then r := i) o; !r
let m_indexOf s sub st =
  let o = starts s in let slen = Array.length o - 1 and nlen = Array.length (decode sub) in
  if st > slen then -1 else if nlen = 0 then max 0 st else
  let r = ref (-1) in for i = slen - 1 downto max 0 st do if bmatch s sub o.(i) then r := i done; !r
let m_lastIndexOf s sub st =
  let o = starts s in let slen = Array.length o - 1 and nlen = Array.length (decode sub) in
  if nlen = 0 then (let idx = if st < 0 then slen else st in min idx slen) else
  let mp = slen - nlen in if mp < 0 then -1 else
  let idx = if st < 0 then slen else st in let start = min (min idx slen) mp in
  let r = ref (-1) in for i = 0 to start do if bmatch s sub o.(i) then r := i done; !r
let m_split s d =
  if d = "" then ref_split s d else
  let o = starts s in let n = String.length s and m = String.length d in
  let out = ref [] and start = ref 0 and i = ref 0 in
  while !i <= n - m do
    if bmatch s d !i && idx_of o !i >= 0 then (out := String.sub s !start (!i - !start) :: !out; i := !i + m; start := !i) else incr i done;
  List.rev (String.sub s !start (n - !start) :: !out)
let fails = ref 0
let report what s extra exp act =
  incr fails;
  if !fails <= 4000 then Printf.printf "FAIL %s s=%S %s expected=%s actual=%s\n" what s extra exp act

let () =
  Random.init (try int_of_string Sys.argv.(1) with _ -> 1);
  for round = 1 to 400 do
    let pool = Array.init 10 (fun _ -> rnd_str (if Random.bool () then 12 else 80)) in
    for _ = 1 to 200 do
      let s = pool.(Random.int 10) in
      let a = decode s in let n = Array.length a in
      (match Random.int 9 with
      | 0 -> let e = n and g = HxString.length s in if e <> g then report "length" s "" (string_of_int e) (string_of_int g)
      | 1 -> let i = Random.int (n + 4) - 2 in
             let e = if i >= 0 && i < n then (let (x,_,_) = a.(i) in x) else "" in
             let g = HxString.charAt s i in if e <> g then report "charAt" s (string_of_int i) (Printf.sprintf "%S" e) (Printf.sprintf "%S" g)
      | 2 -> let i = Random.int (n + 4) - 2 in
             let e = if i >= 0 && i < n then (let (_,c,_) = a.(i) in c) else -1 in
             let g = HxString.cca s i in
             let o = HxString.charCodeAt s i in
             let g2 = if o == HxRuntime.hx_null then -1 else (Obj.obj o : int) in
             if e <> g || e <> g2 then report "cca" s (string_of_int i) (string_of_int e) (Printf.sprintf "%d/%d" g g2)
      | 3 -> let sub = if Random.bool () && n > 0 then (let i = Random.int n in let j = i + Random.int (min 4 (n - i) + 1) in join a i j) else rnd_str 3 in
             let st = rarg n in
             let e = ref_indexOf s sub (deopt st 0) and g = HxString.indexOf s sub st in
             if e <> g then report (if g = m_indexOf s sub (deopt st 0) then "indexOf-endb" else "indexOf-OTHER") s (Printf.sprintf "sub=%S st=%d" sub st) (string_of_int e) (string_of_int g)
      | 4 -> let sub = if Random.bool () && n > 0 then (let i = Random.int n in let j = i + Random.int (min 4 (n - i) + 1) in join a i j) else rnd_str 3 in
             let st = rarg n in
             let e = ref_lastIndexOf s sub (deopt st n) and g = HxString.lastIndexOf s sub st in
             if e <> g then report (if g = m_lastIndexOf s sub (deopt st n) then "lastIdx-endb" else "lastIdx-OTHER") s (Printf.sprintf "sub=%S st=%d" sub st) (string_of_int e) (string_of_int g)
      | 5 -> let d = if Random.bool () && n > 0 then (let i = Random.int n in join a i (i + 1)) else rnd_str 3 in
             let e = ref_split s d and g = (let arr = HxString.split s d in List.init (HxArray.length arr) (HxArray.get arr)) in
             if e <> g then report (if g = m_split s d then "split-endb" else "split-OTHER") s (Printf.sprintf "d=%S" d) (String.concat "|" (List.map (Printf.sprintf "%S") e)) (String.concat "|" (List.map (Printf.sprintf "%S") g))
      | 6 -> let p = rarg n and l = rarg n in
             let e = ref_substr s (deopt p 0) (deopt l (-1)) and g = HxString.substr s (deopt p 0) l in
             if e <> g then report "substr" s (Printf.sprintf "%d %d" p l) e g
      | 7 -> let p = Random.int (n+6) - 3 and l = rarg n in
             let e = ref_substring s p (deopt l n) and g = (try HxString.substring s p l with Invalid_argument _ -> "<EXN>") in
             if e <> g then report "substring" s (Printf.sprintf "%d %d" p l) e g
      | _ -> let e = ref_case up s and g = HxString.toUpperCase s () in
             if e <> g then report "upper" s "" (Printf.sprintf "%S" e) (Printf.sprintf "%S" g);
             let e = ref_case lo s and g = HxString.toLowerCase s () in
             if e <> g then report "lower" s "" (Printf.sprintf "%S" e) (Printf.sprintf "%S" g));
      ignore round
    done
  done;
  (* fromCharCode *)
  for c = -2 to 0x110001 do
    let g = HxString.fromCharCode c in
    let e = if c < 0 || c > 0x10FFFF then "" else enc c in
    if e <> g then report "fromCharCode" "" (string_of_int c) (Printf.sprintf "%S" e) (Printf.sprintf "%S" g);
    if e <> "" && (HxString.cca g 0 <> c || HxString.length g <> 1) then report "fromCharCode-roundtrip" g (string_of_int c) "" ""
  done;
  Printf.printf "fails=%d\n" !fails;
  if !fails = 0 then print_endline "HXSTRING_DIFFERENTIAL:PASS" else exit 1
