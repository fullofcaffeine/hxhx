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
     - `ast method <len>:<payload>`         (payload is `name|vis|static|args|ret|retstr|retid|argtypes|retexpr`)
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

type visibility = Public | Private

type method_decl = {
  name : string;
  visibility : visibility;
  is_static : bool;
  args : (string * string option) list;
  return_type_hint : string option;
  return_string : string option;
  return_ident : string option;
  return_expr : string option;
  body_src : string option;
}

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

let parse_module_from_tokens (src : string) (toks : token array) :
    (string * string list * bool * string * bool * method_decl list) =
  let i = ref 0 in
  let cur () : token =
    if !i < 0 || !i >= Array.length toks then Eof { index = 0; line = 0; col = 0 }
    else toks.(!i)
  in
  let bump () = i := !i + 1 in
  let peek (n : int) : token =
    let j = !i + n in
    if j < 0 || j >= Array.length toks then Eof { index = 0; line = 0; col = 0 }
    else toks.(j)
  in

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
    | Kw ("new", _) ->
        (* Constructor name: `function new(...)` is tokenized as a keyword by the bootstrap lexer. *)
        bump ();
        "new"
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

  let read_import_path () : string =
    (* Like `read_dotted_path`, but also accepts a trailing `.*` wildcard:
         import a.b.*;
       The final `*` token is represented as the string segment "*" so the
       Haxe-side decoder can treat it as `"a.b.*"`. *)
    let parts = ref [ read_ident () ] in
    let done_ = ref false in
    while (not !done_) && token_eq_sym (cur ()) '.' do
      bump ();
      match cur () with
      | Sym ('*', _) ->
          bump ();
          parts := !parts @ [ "*" ];
          done_ := true
      | _ -> parts := !parts @ [ read_ident () ]
    done;
    String.concat "." !parts
  in

  let package_path = ref "" in
  let imports = ref [] in
  let has_toplevel_main = ref false in

  if token_eq_kw (cur ()) "package" then (
    bump ();
    (* Haxe allows an empty package declaration: `package;` *)
    if token_eq_sym (cur ()) ';' then (
      package_path := "";
      bump ())
    else (
      package_path := read_dotted_path ();
      expect_sym ';'));

  while token_eq_kw (cur ()) "import" || token_eq_kw (cur ()) "using" do
    (* For Stage2 bring-up we treat `using` like `import` and just record the module path.
       The typing stage can decide how to interpret it later. *)
    bump ();
    let path = read_import_path () in
    (* Support `import Foo.Bar as Baz;` (ignore alias for now). *)
    if token_eq_kw (cur ()) "as" then (
      bump ();
      ignore (read_ident ()));
    imports := !imports @ [ path ];
    expect_sym ';'
  done;

  (* Bootstrap: scan forward until we find the first `class` declaration.
     Upstream fixtures often contain metadata, multiple types, or other
     top-level declarations before the type we care about.

     Some modules contain no classes at all (typedef/enum/abstract-only). For those,
     we should still succeed (so Stage1 can traverse an import closure). *)
  let rec seek_class () : bool =
    (* Detect module-level `function main(...)` before we enter a class body. *)
    (match cur () with
    | Kw ("function", _) -> (
        match peek 1 with Ident ("main", _) -> has_toplevel_main := true | _ -> ())
    | _ -> ());
    if token_eq_kw (cur ()) "class" then
      true
    else
      match cur () with
      | Eof _ -> false
      | _ ->
          bump ();
          seek_class ()
  in

  let class_name = ref "" in
  let has_static_main = ref false in
  let methods : method_decl list ref = ref [] in

  if seek_class () then (
    expect_kw "class";
    class_name := read_ident ();

    (* Some declarations can omit a body; keep this permissive. *)
    if token_eq_sym (cur ()) '{' then (
      expect_sym '{';

      let depth = ref 1 in
      let cur_visibility : visibility ref = ref Public in
      let cur_static : bool ref = ref false in

      let reset_mods () =
        cur_visibility := Public;
        cur_static := false
      in

      let tok_to_text (t : token) : string =
        match t with
        | Kw (s, _) -> s
        | Ident (s, _) -> s
        | String (s, _) -> "\"" ^ s ^ "\""
        | Sym (c, _) -> String.make 1 c
        | Eof _ -> ""
      in

      let parse_param_list () : (string * string option) list =
        (* Called when current token is '(' already consumed by caller. *)
        let args = ref [] in
        let paren = ref 1 in
        let cur_name : string option ref = ref None in
        let cur_type_parts : string list ref = ref [] in
        let reading_type = ref false in

        let flush_arg () =
          match !cur_name with
          | None ->
              cur_type_parts := [];
              reading_type := false
          | Some name ->
              let ty = String.concat "" !cur_type_parts |> String.trim in
              args := !args @ [ (name, if ty = "" then None else Some ty) ];
              cur_name := None;
              cur_type_parts := [];
              reading_type := false
        in

        while !paren > 0 do
          match cur () with
          | Eof p -> raise (Parse_error (p, "unexpected eof in parameter list"))
          | Sym ('(', _) ->
              if !reading_type then cur_type_parts := !cur_type_parts @ [ "(" ];
              paren := !paren + 1;
              bump ()
          | Sym (')', _) ->
              if !paren = 1 then (
                flush_arg ();
                paren := 0;
                bump ())
              else (
                if !reading_type then cur_type_parts := !cur_type_parts @ [ ")" ];
                paren := !paren - 1;
                bump ())
          | Sym (',', _) when !paren = 1 ->
              flush_arg ();
              bump ()
          | Sym (':', _) when !paren = 1 && !cur_name <> None && not !reading_type
            ->
              reading_type := true;
              bump ()
          | Ident (name, _) when !paren = 1 && !cur_name = None && not !reading_type
            ->
              cur_name := Some name;
              bump ()
          | tok ->
              if !reading_type then
                cur_type_parts := !cur_type_parts @ [ tok_to_text tok ];
              bump ()
        done;
        !args
      in

      let parse_return_type_hint () : string option =
        if token_eq_sym (cur ()) ':' then (
          bump ();
          let parts = ref [] in
          while
            match cur () with
            | Eof _ -> false
            | Sym ('{', _) -> false
            | Sym (';', _) -> false
            | Kw ("return", _) -> false
            | _ -> true
          do
            parts := !parts @ [ tok_to_text (cur ()) ];
            bump ()
          done;
          let txt = String.concat "" !parts |> String.trim in
          if txt = "" then None else Some txt)
        else None
      in

      let parse_body_and_return_expr () :
          (string option * string option * string option * string option) =
        (* Supports:
             - `{ ... }` bodies (scan for `return "..."`)
             - `return "..." ;` expression bodies
             - `;` (no body)
        *)
        let capture_first_atom () : (string option * string option) =
          (* Peek-only: capture a "simple" atom that we still surface in the protocol
             as `retstr` / `retid` for cheap early typing. *)
          match cur () with
          | String (s, _) -> (Some s, None)
          | Ident (s, _) -> (None, Some s)
          | Kw ("new", _) -> (None, Some "new")
          | _ -> (None, None)
        in
        let capture_return_expr_text () : string option =
          (* Capture the full return expression text until ';' or '}' at the current brace depth.

             Why
             - Stage 3 bring-up wants to parse slightly more than literals/idents without
               implementing a full statement/expression AST in OCaml yet.
             - The Haxe-side decoder can parse a small chain grammar (`a.b(c)`) from this.

             What
             - Consumes tokens that belong to the expression.
             - Consumes a trailing ';' (when present).
             - Does NOT consume a terminating '}' (so the class-body parser sees it). *)
          let parts = Buffer.create 64 in
          let paren = ref 0 in
          let done_ = ref false in
          while not !done_ do
            match cur () with
            | Eof _ ->
                done_ := true
            | Sym (';', _) when !paren = 0 ->
                bump ();
                done_ := true
            | Sym ('}', _) when !paren = 0 ->
                done_ := true
            | Sym ('(', _) ->
                paren := !paren + 1;
                Buffer.add_string parts "(";
                bump ()
            | Sym (')', _) ->
                if !paren > 0 then paren := !paren - 1;
                Buffer.add_string parts ")";
                bump ()
            | tok ->
                Buffer.add_string parts (tok_to_text tok);
                bump ()
          done;
          let s = Buffer.contents parts |> String.trim in
          if s = "" then None else Some s
        in
        match cur () with
        | Sym (';', _) ->
            bump ();
            (None, None, None, None)
        | Sym ('{', open_p) ->
            (* Capture the raw body substring from the original source so Haxe-side
               bring-up code can parse statements without reconstituting token text.

               Indices are character offsets into `src` (0-based). We capture the
               region strictly between the braces (excluding '{' and '}'). *)
            let body_start = open_p.index + 1 in
            let body_end : int option ref = ref None in

            bump ();
            depth := !depth + 1;
            let found_str = ref None in
            let found_ident = ref None in
            let found_expr = ref None in
            while !depth > 1 do
              match cur () with
              | Eof p -> raise (Parse_error (p, "unexpected eof in function body"))
              | Sym ('{', _) ->
                  depth := !depth + 1;
                  bump ()
              | Sym ('}', close_p) ->
                  (* When we are at depth=2, this brace closes the function body. *)
                  if !depth = 2 && !body_end = None then body_end := Some close_p.index;
                  depth := !depth - 1;
                  bump ()
              | Kw ("return", _) -> (
                  bump ();
                  let str_opt, ident_opt = capture_first_atom () in
                  let expr_opt = capture_return_expr_text () in
                  (match (str_opt, !found_str) with
                  | Some s, None -> found_str := Some s
                  | _ -> ());
                  (match (ident_opt, !found_ident) with
                  | Some s, None -> found_ident := Some s
                  | _ -> ());
                  (match (expr_opt, !found_expr) with
                  | Some s, None -> found_expr := Some s
                  | _ -> ()))
              | _ -> bump ()
            done;
            let body_src =
              match !body_end with
              | None -> None
              | Some end_idx ->
                  if body_start < 0 || end_idx < body_start then None
                  else if end_idx > String.length src then None
                  else Some (String.sub src body_start (end_idx - body_start))
            in
            (!found_str, !found_ident, !found_expr, body_src)
        | Kw ("return", _) -> (
            bump ();
            let found_str, found_ident = capture_first_atom () in
            let found_expr = capture_return_expr_text () in
            (found_str, found_ident, found_expr, None))
        | _ ->
            (* Unknown body shape; consume until ';' or '{' to avoid infinite loops. *)
            while
              match cur () with
              | Eof _ -> false
              | Sym (';', _) ->
                  bump ();
                  false
              | Sym ('{', _) -> false
              | _ ->
                  bump ();
                  true
            do
              ()
            done;
            (None, None, None, None)
      in

      while !depth > 0 do
        match cur () with
        | Eof p -> raise (Parse_error (p, "unexpected eof in class body"))
        | tok ->
            if !depth = 1 then (
              match tok with
              | Kw ("public", _) ->
                  cur_visibility := Public;
                  bump ()
              | Kw ("private", _) ->
                  cur_visibility := Private;
                  bump ()
              | Kw ("static", _) ->
                  cur_static := true;
                  bump ()
              | Kw (("inline" | "override" | "final" | "macro" | "extern" | "dynamic"), _) ->
                  (* Common Haxe member modifiers we don't model yet. Treat them as no-ops so we can
                     still detect `function` declarations that follow. *)
                  bump ()
              | Kw ("function", _) -> (
                  bump ();
                  let name = read_ident () in
                  if !cur_static && name = "main" then has_static_main := true;

                  let args =
                    if token_eq_sym (cur ()) '(' then (
                      bump ();
                      parse_param_list ())
                    else []
                  in
                  let return_type_hint = parse_return_type_hint () in
                  let return_string, return_ident, return_expr, body_src =
                    parse_body_and_return_expr ()
                  in
                  methods :=
                    !methods
                    @ [
                        {
                          name;
                          visibility = !cur_visibility;
                          is_static = !cur_static;
                          args;
                          return_type_hint;
                          return_string;
                          return_ident;
                          return_expr;
                          body_src;
                        };
                      ];
                  reset_mods ())
              | Sym ('{', _) ->
                  depth := !depth + 1;
                  bump ();
                  reset_mods ()
              | Sym ('}', _) ->
                  depth := !depth - 1;
                  bump ();
                  reset_mods ()
              | _ -> bump ())
            else (
              if token_eq_sym tok '{' then depth := !depth + 1
              else if token_eq_sym tok '}' then depth := !depth - 1;
              bump ())
      done))
  else (
    class_name := "";
    has_static_main := false);

  (* Bootstrap: ignore any trailing declarations after the first class. *)
  while
    match cur () with
    | Eof _ -> false
    | _ -> true
  do
    bump ()
  done;

  (!package_path, !imports, !has_toplevel_main, !class_name, !has_static_main, !methods)

(* Best-effort header-only parser for upstream-scale modules.

   Why
   - The initial token-based parser above can fail on complex syntax inside class bodies.
   - For Stage2/Stage3 bring-up we still want to traverse import closures deterministically, so we
     fall back to parsing only: package + imports/using + first class name.

   What
   - Parses:
     - optional `package ...;`
     - repeated `import ...;` and `using ...;` (supports `as` aliases and `.*` wildcards)
     - first `class Name` (if any)
   - Ignores everything else.
*)
let parse_module_header_only (toks : token array) : (string * string list * bool * string) =
  let i = ref 0 in
  let cur () : token =
    if !i < 0 || !i >= Array.length toks then Eof { index = 0; line = 0; col = 0 }
    else toks.(!i)
  in
  let bump () = i := !i + 1 in
  let peek (n : int) : token =
    let j = !i + n in
    if j < 0 || j >= Array.length toks then Eof { index = 0; line = 0; col = 0 }
    else toks.(j)
  in

  let rec skip_until_semicolon () =
    match cur () with
    | Eof _ -> ()
    | _ when token_eq_sym (cur ()) ';' ->
        bump ()
    | _ ->
        bump ();
        skip_until_semicolon ()
  in

  let read_ident_opt () : string option =
    match cur () with
    | Ident (s, _) ->
        bump ();
        Some s
    | _ -> None
  in

  let read_dotted_path () : string =
    match read_ident_opt () with
    | None -> ""
    | Some first ->
        let parts = ref [ first ] in
        while token_eq_sym (cur ()) '.' do
          bump ();
          match read_ident_opt () with
          | Some s -> parts := !parts @ [ s ]
          | None -> ()
        done;
        String.concat "." !parts
  in

  let read_import_path () : string =
    match read_ident_opt () with
    | None -> ""
    | Some first ->
        let parts = ref [ first ] in
        let done_ = ref false in
        while (not !done_) && token_eq_sym (cur ()) '.' do
          bump ();
          match cur () with
          | Sym ('*', _) ->
              bump ();
              parts := !parts @ [ "*" ];
              done_ := true
          | _ -> (
              match read_ident_opt () with
              | Some s -> parts := !parts @ [ s ]
              | None -> done_ := true)
        done;
        String.concat "." !parts
  in

  let package_path = ref "" in
  let imports = ref [] in
  let has_toplevel_main = ref false in
  let class_name = ref "Unknown" in

  if token_eq_kw (cur ()) "package" then (
    bump ();
    if token_eq_sym (cur ()) ';' then bump ()
    else (
      package_path := read_dotted_path ();
      skip_until_semicolon ()));

  while token_eq_kw (cur ()) "import" || token_eq_kw (cur ()) "using" do
    bump ();
    let path = read_import_path () in
    if token_eq_kw (cur ()) "as" then (
      bump ();
      ignore (read_ident_opt ()));
    if path <> "" then imports := !imports @ [ path ];
    skip_until_semicolon ()
  done;

  let rec seek_toplevel_main () =
    match cur () with
    | Eof _ -> ()
    | _ when token_eq_kw (cur ()) "class" -> ()
    | Kw ("function", _) -> (
        (match peek 1 with Ident ("main", _) -> has_toplevel_main := true | _ -> ());
        bump ();
        seek_toplevel_main ())
    | _ ->
        bump ();
        seek_toplevel_main ()
  in
  seek_toplevel_main ();

  let rec seek_class () =
    match cur () with
    | Eof _ -> ()
    | _ when token_eq_kw (cur ()) "class" -> (
        bump ();
        match read_ident_opt () with Some s -> class_name := s | None -> ())
    | _ ->
        bump ();
        seek_class ()
  in
  seek_class ();

  (!package_path, !imports, !has_toplevel_main, !class_name)

let encode_ast_lines (package_path : string) (imports : string list)
    (class_name : string) (header_only : bool) (has_toplevel_main : bool)
    (has_static_main : bool) (methods : method_decl list) : string =
  let pkg_enc = escape_payload package_path in
  let imports_payload = String.concat "|" imports in
  let imports_enc = escape_payload imports_payload in
  let cls_enc = escape_payload class_name in
  let header_only_s = if header_only then "1" else "0" in
  let toplevel_s = if has_toplevel_main then "1" else "0" in
  let base =
    [
      Printf.sprintf "ast package %d:%s" (String.length pkg_enc) pkg_enc;
      Printf.sprintf "ast imports %d:%s" (String.length imports_enc) imports_enc;
      Printf.sprintf "ast class %d:%s" (String.length cls_enc) cls_enc;
      Printf.sprintf "ast header_only 1:%s" header_only_s;
      Printf.sprintf "ast toplevel_main 1:%s" toplevel_s;
      "ast static_main " ^ if has_static_main then "1" else "0";
    ]
  in
  let method_lines =
    List.map
      (fun (m : method_decl) ->
        let vis =
          match m.visibility with Public -> "public" | Private -> "private"
        in
        let static_s = if m.is_static then "1" else "0" in
        let args_payload = String.concat "," (List.map fst m.args) in
        let argtypes_payload =
          m.args
          |> List.filter_map (fun (n, t) ->
                 match t with None -> None | Some ty -> Some (n ^ ":" ^ ty))
          |> String.concat ","
        in
        let ret_payload = match m.return_type_hint with None -> "" | Some s -> s in
        let retstr_payload = match m.return_string with None -> "" | Some s -> s in
        let retid_payload = match m.return_ident with None -> "" | Some s -> s in
        let retexpr_payload = match m.return_expr with None -> "" | Some s -> s in
        (* Bootstrap note: payload is a '|' separated list and is not itself escaped for '|'. *)
        let payload =
          String.concat "|"
            [
              m.name;
              vis;
              static_s;
              args_payload;
              ret_payload;
              retstr_payload;
              retid_payload;
              argtypes_payload;
              retexpr_payload;
            ]
        in
        let enc = escape_payload payload in
        Printf.sprintf "ast method %d:%s" (String.length enc) enc)
      methods
  in
  let body_lines =
    methods
    |> List.filter_map (fun (m : method_decl) ->
           match m.body_src with
           | None -> None
           | Some body ->
               (* Payload format:
                    <methodName>\n<bodySource>

                  The entire payload is escaped + len-prefixed, so the body can contain
                  arbitrary characters including '|' (which would otherwise conflict with
                  `ast method`'s field separators). *)
               let payload = m.name ^ "\n" ^ body in
               let enc = escape_payload payload in
               Some (Printf.sprintf "ast method_body %d:%s" (String.length enc) enc))
  in
  String.concat "\n" (base @ method_lines @ body_lines)

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
  try
    let header_only_enabled () : bool =
      try
        match String.lowercase_ascii (Sys.getenv "HXHX_NATIVE_FRONTEND_HEADER_ONLY") with
        | "1" | "true" | "yes" -> true
        | _ -> false
      with Not_found -> false
    in

    let lex_stream = HxHxNativeLexer.tokenize src in
    match decode_lexer_stream lex_stream with
    | Error msg ->
        String.concat "\n"
          [
            "hxhx_frontend_v=1";
            encode_err_line { index = 0; line = 0; col = 0 } msg;
          ]
    | Ok ((_toks, Some _err_line)) ->
        (* Lexer already emitted a protocol error; pass it through. *)
        strip_terminal_ok lex_stream
    | Ok ((toks, None)) -> (
        let base = strip_terminal_ok lex_stream in
        try
          let package_path, imports, has_toplevel_main, class_name, has_static_main, methods =
            parse_module_from_tokens src toks
          in
          String.concat "\n"
            [
              base;
              encode_ast_lines package_path imports class_name false has_toplevel_main
                has_static_main methods;
              "ok";
            ]
        with
        | Parse_error (p, msg) ->
            if header_only_enabled () then
              (* Header-only fallback: for bootstrapping, we prefer keeping the resolver moving
                 (package/import/class) over failing on body-level syntax we don't support yet. *)
              let package_path, imports, has_toplevel_main, class_name =
                parse_module_header_only toks
              in
              String.concat "\n"
                [
                  base;
                  encode_ast_lines package_path imports class_name true has_toplevel_main
                    false [];
                  "ok";
                ]
            else
              String.concat "\n" [ base; encode_err_line p msg ]
        | _exn ->
            if header_only_enabled () then
              let package_path, imports, has_toplevel_main, class_name =
                parse_module_header_only toks
              in
              String.concat "\n"
                [
                  base;
                  encode_ast_lines package_path imports class_name true has_toplevel_main
                    false [];
                  "ok";
                ]
            else
              (* Surface the failure as a parse error to keep Stage1 deterministic. *)
              String.concat "\n"
                [
                  base;
                  encode_err_line { index = 0; line = 0; col = 0 }
                    "HxHxNativeParser: failed to parse module";
                ])
  with exn ->
    String.concat "\n"
      [
        "hxhx_frontend_v=1";
        encode_err_line { index = 0; line = 0; col = 0 } (Printexc.to_string exn);
      ]
