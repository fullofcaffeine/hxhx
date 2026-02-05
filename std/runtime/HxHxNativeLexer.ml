(* Haxe-in-Haxe bring-up: native OCaml lexer stub.

   Why this exists:
   - Upstream Haxe (#6843) suggests keeping the lexer/parser in OCaml initially
     while the rest of the compiler is ported to Haxe.
   - This module is a small proof that `reflaxe.ocaml`-generated code can call
     “real” OCaml code via externs and link cleanly via dune.

   What it does (today):
   - Implements a tiny lexer for a very small Haxe subset used by
     `examples/hih-compiler`.
   - Returns tokens in a **versioned, line-based protocol** so Haxe code can
     decode them without an OCaml<->Haxe data-marshalling layer yet.
   - Each token includes a start position (index/line/column) to support
     meaningful parse errors early in bootstrapping.

   Protocol:
   - First line: `hxhx_frontend_v=1`
   - Token line: `tok <kind> <index> <line> <col> <len>:<payload>`
   - Terminal: `ok` or `err <index> <line> <col> <len>:<message>`
   - Payload uses a small escape layer to guarantee tokens fit on one line.
*)

let is_space (c : char) : bool =
  match c with
  | ' ' | '\t' | '\n' | '\r' -> true
  | _ -> false

let is_ident_start (c : char) : bool =
  ('A' <= c && c <= 'Z') || ('a' <= c && c <= 'z') || c = '_'

let is_ident_cont (c : char) : bool =
  is_ident_start c || ('0' <= c && c <= '9')

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

let tokenize (src : string) : string =
  let len = String.length src in
  let idx = ref 0 in
  let line = ref 1 in
  let col = ref 1 in
  let buf = Buffer.create (max 64 (len / 2)) in

  let eof () = !idx >= len in
  let peek (off : int) : char option =
    let i = !idx + off in
    if i < 0 || i >= len then None else Some (String.get src i)
  in
  let bump () : char =
    match peek 0 with
    | None -> '\000'
    | Some c ->
        idx := !idx + 1;
        if c = '\n' then (
          line := !line + 1;
          col := 1)
        else if c <> '\r' then col := !col + 1;
        c
  in

  let add_line (s : string) =
    Buffer.add_string buf s;
    Buffer.add_char buf '\n'
  in
  let add_tok (kind : string) (at_idx : int) (at_line : int) (at_col : int)
      (payload : string) =
    let enc = escape_payload payload in
    add_line
      (Printf.sprintf "tok %s %d %d %d %d:%s" kind at_idx at_line at_col
         (String.length enc) enc)
  in
  let add_err (at_idx : int) (at_line : int) (at_col : int) (message : string)
      =
    let enc = escape_payload message in
    add_line
      (Printf.sprintf "err %d %d %d %d:%s" at_idx at_line at_col
         (String.length enc) enc)
  in

  add_line "hxhx_frontend_v=1";

  let rec skip_ws_and_comments () =
    if eof () then ()
    else
      match peek 0 with
      | Some c when is_space c ->
          ignore (bump ());
          skip_ws_and_comments ()
      | Some '/' -> (
          match peek 1 with
          | Some '/' ->
              ignore (bump ());
              ignore (bump ());
              while (not (eof ())) && peek 0 <> Some '\n' do
                ignore (bump ())
              done;
              skip_ws_and_comments ()
          | Some '*' ->
              ignore (bump ());
              ignore (bump ());
              let rec loop () =
                if eof () then ()
                else
                  match bump () with
                  | '*' when peek 0 = Some '/' ->
                      ignore (bump ());
                      ()
                  | _ -> loop ()
              in
              loop ();
              skip_ws_and_comments ()
          | _ -> ())
      | _ -> ()
  in

  let read_ident () : string =
    let start = !idx in
    ignore (bump ());
    while
      (not (eof ()))
      &&
      match peek 0 with
      | Some c when is_ident_cont c -> true
      | _ -> false
    do
      ignore (bump ())
    done;
    String.sub src start (!idx - start)
  in

  let read_string () : string =
    (* Opening quote already present at cursor. *)
    ignore (bump ());
    let b = Buffer.create 16 in
    let rec loop () =
      if eof () then failwith "HxHxNativeLexer: unterminated string"
      else
        match bump () with
        | '"' -> Buffer.contents b
        | '\\' ->
            if eof () then failwith "HxHxNativeLexer: unterminated escape"
            else (
              match bump () with
              | '"' -> Buffer.add_char b '"'
              | '\\' -> Buffer.add_char b '\\'
              | 'n' -> Buffer.add_char b '\n'
              | 'r' -> Buffer.add_char b '\r'
              | 't' -> Buffer.add_char b '\t'
              | c -> Buffer.add_char b c);
            loop ()
        | c ->
            Buffer.add_char b c;
            loop ()
    in
    loop ()
  in

  let rec loop () =
    skip_ws_and_comments ();
    if eof () then (
      add_tok "eof" !idx !line !col "";
      Buffer.contents buf)
    else
      let at_idx = !idx in
      let at_line = !line in
      let at_col = !col in
      match peek 0 with
      | Some '"' -> (
          try
            let s = read_string () in
            add_tok "string" at_idx at_line at_col s;
            loop ()
          with Failure msg ->
            add_err at_idx at_line at_col msg;
            Buffer.contents buf)
      | Some c when is_ident_start c ->
          let text = read_ident () in
          (match text with
          | "package" | "import" | "using" | "as" | "class"
          | "public" | "private" | "static" | "function" | "return"
          | "var" | "final" | "new" | "true" | "false" | "null" ->
              add_tok "kw" at_idx at_line at_col text
          | _ -> add_tok "ident" at_idx at_line at_col text);
          loop ()
      | Some c ->
          (* Bootstrap behavior: emit any other character as a symbol token.
             This keeps the lexer permissive while the parser only cares about
             a very small subset of punctuation. *)
          ignore (bump ());
          add_tok "sym" at_idx at_line at_col (String.make 1 c);
          loop ()
      | None ->
          add_tok "eof" !idx !line !col "";
          Buffer.contents buf
  in
  ignore (loop ());

  Buffer.contents buf
