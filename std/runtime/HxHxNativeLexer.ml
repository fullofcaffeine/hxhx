(* Haxe-in-Haxe bring-up: native OCaml lexer stub.

   Why this exists:
   - Upstream Haxe (#6843) suggests keeping the lexer/parser in OCaml initially
     while the rest of the compiler is ported to Haxe.
   - This module is a small proof that `reflaxe.ocaml`-generated code can call
     “real” OCaml code via externs and link cleanly via dune.

   What it does (today):
   - Implements a tiny lexer for a very small Haxe subset used by
     `examples/hih-compiler`.
   - Returns tokens as a newline-separated string, so Haxe code can consume it
     without needing an OCaml<->Haxe data-marshalling layer yet.
*)

let is_space (c : char) : bool =
  match c with
  | ' ' | '\t' | '\n' | '\r' -> true
  | _ -> false

let is_ident_start (c : char) : bool =
  ('A' <= c && c <= 'Z') || ('a' <= c && c <= 'z') || c = '_'

let is_ident_cont (c : char) : bool =
  is_ident_start c || ('0' <= c && c <= '9')

let tokenize (src : string) : string =
  let len = String.length src in
  let idx = ref 0 in
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
        c
  in

  let add (s : string) =
    Buffer.add_string buf s;
    Buffer.add_char buf '\n'
  in

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
    if eof () then add "eof"
    else
      match peek 0 with
      | Some '{' ->
          ignore (bump ());
          add "sym:{";
          loop ()
      | Some '}' ->
          ignore (bump ());
          add "sym:}";
          loop ()
      | Some '(' ->
          ignore (bump ());
          add "sym:(";
          loop ()
      | Some ')' ->
          ignore (bump ());
          add "sym:)";
          loop ()
      | Some ';' ->
          ignore (bump ());
          add "sym:;";
          loop ()
      | Some ':' ->
          ignore (bump ());
          add "sym::";
          loop ()
      | Some '.' ->
          ignore (bump ());
          add "sym:.";
          loop ()
      | Some ',' ->
          ignore (bump ());
          add "sym:,";
          loop ()
      | Some '"' ->
          let s = read_string () in
          add ("string:" ^ s);
          loop ()
      | Some c when is_ident_start c -> (
          let text = read_ident () in
          (match text with
          | "package" | "import" | "class" | "static" | "function" ->
              add ("kw:" ^ text)
          | _ -> add ("ident:" ^ text));
          loop ())
      | Some c ->
          let msg =
            "HxHxNativeLexer: unexpected character: " ^ String.make 1 c
          in
          failwith msg
      | None -> add "eof"
  in
  loop ();

  Buffer.contents buf
