(* Haxe-in-Haxe bring-up: native OCaml parser stub.

   Why this exists:
   - Matches the upstream bootstrap strategy: keep lexer/parser native initially
     while porting the rest of the compiler pipeline into Haxe.

   What it does (today):
   - Consumes the token stream from `HxHxNativeLexer.tokenize`.
   - Parses a *very small* module subset (package/import/class + detect
     `static function main`), sufficient for `examples/hih-compiler`.
   - Returns a line-based “record” string so Haxe can reconstruct its own
     AST types without OCaml<->Haxe object marshalling.
*)

type token =
  | Kw of string
  | Ident of string
  | String of string
  | Sym of char
  | Eof

let starts_with (s : string) (prefix : string) : bool =
  let sl = String.length s in
  let pl = String.length prefix in
  sl >= pl && String.sub s 0 pl = prefix

let split_non_empty_lines (s : string) : string list =
  let lines = String.split_on_char '\n' s in
  List.filter (fun l -> l <> "") lines

let decode_tokens (s : string) : token array =
  let lines = split_non_empty_lines s in
  let toks =
    List.map
      (fun l ->
        if l = "eof" then Eof
        else if starts_with l "kw:" then Kw (String.sub l 3 (String.length l - 3))
        else if starts_with l "ident:" then
          Ident (String.sub l 6 (String.length l - 6))
        else if starts_with l "string:" then
          String (String.sub l 7 (String.length l - 7))
        else if starts_with l "sym:" then
          let rest = String.sub l 4 (String.length l - 4) in
          if String.length rest = 0 then failwith "HxHxNativeParser: empty sym"
          else Sym rest.[0]
        else failwith ("HxHxNativeParser: unknown token line: " ^ l))
      lines
  in
  Array.of_list toks

let parse_module_decl (src : string) : string =
  (* Ensure the lexer is callable and keep a stable integration seam. *)
  let tok_text = HxHxNativeLexer.tokenize src in
  let toks = decode_tokens tok_text in
  let i = ref 0 in

  let cur () : token =
    if !i < 0 || !i >= Array.length toks then Eof else toks.(!i)
  in
  let bump () = i := !i + 1 in
  let fail msg = failwith ("HxHxNativeParser: " ^ msg) in

  let expect_sym (c : char) =
    match cur () with
    | Sym d when d = c ->
        bump ();
        ()
    | _ -> fail ("expected symbol: " ^ String.make 1 c)
  in
  let expect_kw (k : string) =
    match cur () with
    | Kw kk when kk = k ->
        bump ();
        ()
    | _ -> fail ("expected keyword: " ^ k)
  in
  let read_ident () : string =
    match cur () with
    | Ident s ->
        bump ();
        s
    | _ -> fail "expected identifier"
  in
  let read_dotted_path () : string =
    let parts = ref [ read_ident () ] in
    while cur () = Sym '.' do
      bump ();
      parts := !parts @ [ read_ident () ]
    done;
    String.concat "." !parts
  in

  let package_path = ref "" in
  let imports = ref [] in

  (match cur () with
  | Kw "package" ->
      bump ();
      package_path := read_dotted_path ();
      expect_sym ';'
  | _ -> ());

  while cur () = Kw "import" do
    bump ();
    let path = read_dotted_path () in
    imports := !imports @ [ path ];
    expect_sym ';'
  done;

  expect_kw "class";
  let class_name = read_ident () in
  expect_sym '{';

  let has_static_main = ref false in
  let depth = ref 1 in
  let prev1 = ref None in
  let prev2 = ref None in

  let shift tok =
    prev2 := !prev1;
    prev1 := Some tok
  in

  while !depth > 0 do
    match cur () with
    | Eof -> fail "unexpected eof in class body"
    | Sym '{' ->
        depth := !depth + 1;
        shift (Sym '{');
        bump ()
    | Sym '}' ->
        depth := !depth - 1;
        shift (Sym '}');
        bump ()
    | tok ->
        (* Detect `static function main` without parsing full member grammar yet. *)
        (match (!prev2, !prev1, tok) with
        | Some (Kw "static"), Some (Kw "function"), Ident "main" ->
            has_static_main := true
        | _ -> ());
        shift tok;
        bump ()
  done;

  (match cur () with
  | Eof -> ()
  | _ -> ());

  let imports_str = String.concat "|" !imports in
  String.concat "\n"
    [
      "package:" ^ !package_path;
      "imports:" ^ imports_str;
      "class:" ^ class_name;
      "staticMain:" ^ (if !has_static_main then "1" else "0");
    ]

