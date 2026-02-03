(* Haxe-in-Haxe bring-up: native OCaml parser stub.

   Why this exists:
   - Matches the upstream bootstrap strategy: keep lexer/parser native initially
     while porting the rest of the compiler pipeline into Haxe.

   What it does (today):
   - Calls `HxHxNativeLexer.tokenize` to obtain tokens (with positions).
   - Parses a *very small* module subset (package/import/class + detect
     `static function main`), sufficient for `examples/hih-compiler`.
   - Emits a **versioned, line-based protocol** designed for gradual expansion:
     - tokens + positions
     - minimal module “AST summary”
     - parse errors (without throwing)

   Protocol (v=1):
   - First line: `hxhx_frontend_v=1`
   - Token line: `tok <kind> <index> <line> <col> <len>:<payload>`
   - AST lines:
     - `ast package <len>:<payload>`
     - `ast imports <len>:<payload>`        (payload uses '|' separator for now)
     - `ast class <len>:<payload>`
     - `ast static_main 0|1`
   - Terminal:
     - `ok`
     - OR `err <index> <line> <col> <len>:<message>`

   Notes:
   - Payload is escaped to keep each record on one physical line.
   - This is a bootstrap seam: the format is intentionally simple and will
     evolve alongside Stage 2.
*)

type pos = { index : int; line : int; col : int }

type token =
  | Kw of string * pos
  | Ident of string * pos
  | String of string * pos
  | Sym of char * pos
  | Eof of pos

exception Parse_error of pos * string

let starts_with (s : string) (prefix : string) : bool =
  let sl = String.length s in
  let pl = String.length prefix in
  sl >= pl && String.sub s 0 pl = prefix

let split_non_empty_lines (s : string) : string list =
  let lines = String.split_on_char '\n' s in
  List.filter (fun l -> l <> "") lines

let escape_payload (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let unescape_payload (s : string) : string =
  let b = Buffer.create (String.length s) in
  let i = ref 0 in
  while !i < String.length s do
    match s.[!i] with
    | '\\' ->
        if !i + 1 >= String.length s then (
          Buffer.add_char b '\\';
          i := !i + 1)
        else (
          match s.[!i + 1] with
          | 'n' ->
              Buffer.add_char b '\n';
              i := !i + 2
          | 'r' ->
              Buffer.add_char b '\r';
              i := !i + 2
          | 't' ->
              Buffer.add_char b '\t';
              i := !i + 2
          | '\\' ->
              Buffer.add_char b '\\';
              i := !i + 2
          | c ->
              Buffer.add_char b c;
              i := !i + 2)
    | c ->
        Buffer.add_char b c;
        i := !i + 1
  done;
  Buffer.contents b

let parse_len_payload (s : string) : string =
  (* s is "<len>:<payload...>" (payload may contain spaces). *)
  match String.index_opt s ':' with
  | None -> failwith "HxHxNativeParser: missing ':' in len payload"
  | Some colon ->
      let len_s = String.sub s 0 colon in
      let payload = String.sub s (colon + 1) (String.length s - colon - 1) in
      let expected = int_of_string len_s in
      if String.length payload < expected then
        failwith "HxHxNativeParser: payload shorter than expected length"
      else unescape_payload (String.sub payload 0 expected)

let parse_tok_line (l : string) : token =
  (* tok <kind> <index> <line> <col> <len>:<payload> *)
  let parts = String.split_on_char ' ' l in
  match parts with
  | "tok" :: kind :: idx_s :: line_s :: col_s :: rest ->
      let at =
        {
          index = int_of_string idx_s;
          line = int_of_string line_s;
          col = int_of_string col_s;
        }
      in
      let payload = String.concat " " rest in
      let value = parse_len_payload payload in
      (match kind with
      | "kw" -> Kw (value, at)
      | "ident" -> Ident (value, at)
      | "string" -> String (value, at)
      | "sym" ->
          if String.length value = 0 then failwith "HxHxNativeParser: empty sym";
          Sym (value.[0], at)
      | "eof" -> Eof at
      | _ -> failwith ("HxHxNativeParser: unknown tok kind: " ^ kind))
  | _ -> failwith ("HxHxNativeParser: invalid tok line: " ^ l)

let decode_lexer_stream (s : string) :
    ((token array * string option), string) result =
  let lines = split_non_empty_lines s in
  match lines with
  | [] -> Error "HxHxNativeParser: empty lexer stream"
  | header :: _ when header <> "hxhx_frontend_v=1" ->
      Error "HxHxNativeParser: unexpected lexer header"
  | _header :: rest ->
      let toks = ref [] in
      let err = ref None in
      List.iter
        (fun l ->
          if starts_with l "tok " then toks := !toks @ [ parse_tok_line l ]
          else if starts_with l "err " then err := Some l
          else ())
        rest;
      Ok (Array.of_list !toks, !err)

let pos_of (t : token) : pos =
  match t with
  | Kw (_, p) -> p
  | Ident (_, p) -> p
  | String (_, p) -> p
  | Sym (_, p) -> p
  | Eof p -> p

let token_eq_kw (t : token) (k : string) : bool =
  match t with
  | Kw (kk, _) when kk = k -> true
  | _ -> false

let token_eq_sym (t : token) (c : char) : bool =
  match t with
  | Sym (cc, _) when cc = c -> true
  | _ -> false

let parse_module_from_tokens (toks : token array) :
    (string * string list * string * bool) =
  let i = ref 0 in
  let cur () : token =
    if !i < 0 || !i >= Array.length toks then Eof { index = 0; line = 0; col = 0 }
    else toks.(!i)
  in
  let bump () = i := !i + 1 in

  let expect_kw (k : string) =
    if token_eq_kw (cur ()) k then bump ()
    else raise (Parse_error (pos_of (cur ()), "expected keyword: " ^ k))
  in
  let expect_sym (c : char) =
    if token_eq_sym (cur ()) c then bump ()
    else raise (Parse_error (pos_of (cur ()), "expected symbol: " ^ String.make 1 c))
  in
  let read_ident () : string =
    match cur () with
    | Ident (s, _) ->
        bump ();
        s
    | _ -> raise (Parse_error (pos_of (cur ()), "expected identifier"))
  in
  let read_dotted_path () : string =
    let parts = ref [ read_ident () ] in
    while token_eq_sym (cur ()) '.' do
      bump ();
      parts := !parts @ [ read_ident () ]
    done;
    String.concat "." !parts
  in

  let package_path = ref "" in
  let imports = ref [] in

  if token_eq_kw (cur ()) "package" then (
    bump ();
    package_path := read_dotted_path ();
    expect_sym ';');

  while token_eq_kw (cur ()) "import" do
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
  let prev1 : token option ref = ref None in
  let prev2 : token option ref = ref None in

  let shift (tok : token) =
    prev2 := !prev1;
    prev1 := Some tok
  in

  while !depth > 0 do
    match cur () with
    | Eof p -> raise (Parse_error (p, "unexpected eof in class body"))
    | tok ->
        (* Detect `static function main` without parsing full member grammar yet. *)
        (match (!prev2, !prev1, tok) with
        | Some (Kw ("static", _)), Some (Kw ("function", _)), Ident ("main", _) ->
            has_static_main := true
        | _ -> ());

        shift tok;
        if token_eq_sym tok '{' then depth := !depth + 1
        else if token_eq_sym tok '}' then depth := !depth - 1;
        bump ()
  done;

  (!package_path, !imports, class_name, !has_static_main)

let encode_ast_lines (package_path : string) (imports : string list)
    (class_name : string) (has_static_main : bool) : string =
  let pkg_enc = escape_payload package_path in
  let imports_payload = String.concat "|" imports in
  let imports_enc = escape_payload imports_payload in
  let cls_enc = escape_payload class_name in
  String.concat "\n"
    [
      Printf.sprintf "ast package %d:%s" (String.length pkg_enc) pkg_enc;
      Printf.sprintf "ast imports %d:%s" (String.length imports_enc) imports_enc;
      Printf.sprintf "ast class %d:%s" (String.length cls_enc) cls_enc;
      "ast static_main " ^ if has_static_main then "1" else "0";
    ]

let encode_err_line (p : pos) (msg : string) : string =
  let enc = escape_payload msg in
  Printf.sprintf "err %d %d %d %d:%s" p.index p.line p.col (String.length enc) enc

let strip_terminal_ok (lex_stream : string) : string =
  let lines = split_non_empty_lines lex_stream in
  let kept =
    List.filter
      (fun l -> l <> "ok")
      lines
  in
  String.concat "\n" kept

let parse_module_decl (src : string) : string =
  let lex_stream = HxHxNativeLexer.tokenize src in
  match decode_lexer_stream lex_stream with
  | Error msg ->
      String.concat "\n"
        [ "hxhx_frontend_v=1"; encode_err_line { index = 0; line = 0; col = 0 } msg ]
  | Ok ((_toks, Some _err_line)) ->
      (* Lexer already emitted a protocol error; pass it through. *)
      strip_terminal_ok lex_stream
  | Ok ((toks, None)) -> (
      let base = strip_terminal_ok lex_stream in
      try
        let package_path, imports, class_name, has_static_main =
          parse_module_from_tokens toks
        in
        String.concat "\n"
          [ base; encode_ast_lines package_path imports class_name has_static_main; "ok" ]
      with
      | Parse_error (p, msg) -> String.concat "\n" [ base; encode_err_line p msg ])
