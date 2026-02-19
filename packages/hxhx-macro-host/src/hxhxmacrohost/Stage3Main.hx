package hxhxmacrohost;

/**
	Stage 3 bring-up macro host entrypoint.

	Why
	- `scripts/hxhx/build-hxhx-macro-host.sh` aims to build a macro host **without**
	  a stage0 `haxe` binary when dynamic entrypoints/classpaths are requested.
	- Today, `hxhx --hxhx-stage3` can only emit a narrow Haxe subset. The full
	  Stage 4 macro host (`hxhxmacrohost.Main`) uses control-flow and stdlib
	  features that are intentionally *not* implemented in Stage 3 yet.
	- This file provides a **protocol-correct** macro host for the Stage 3 subset,
	  so Gate bring-up can be stage0-free while we evolve Stage3/Stage4.

	What
	- Implements the minimum server behavior required by `hxhx --hxhx-macro-selftest`:
	  - prints the banner `hxhx_macro_rpc_v=1`
	  - performs the `hello proto=1` handshake
	  - handles:
		- `ping`
		- `compiler.define`
		- `context.defined`
		- `context.definedValue`

	How
	- Uses `untyped __ocaml__("<expr>")` as a controlled, repo-internal escape hatch.
	- The injected OCaml implements the request loop and a small define store
	  (via `Hashtbl`) using the same length-prefixed payload encoding as the
	  Stage 4 protocol.

	Gotchas
	- This is **not** a long-term macro execution implementation.
	- Keep this file small and boring: it exists to unblock stage0-free gating,
	  not to become a second macro host implementation to maintain forever.
**/
class Stage3Main {
	static function main():Void {
		// Banner must be stable and printed first; the client validates this exact string.
		Sys.println("hxhx_macro_rpc_v=1");
		Sys.stdout().flush();

		// Stage3-only server loop + define store (OCaml).
		//
		// Note: this is an OCaml *expression* that returns `unit`, so it can be used as a
		// statement in a minimal Stage3-emitted function body.
		untyped __ocaml__("(\n"
			+ "  let is_space = function ' ' | '\\t' | '\\n' | '\\r' -> true | _ -> false in\n"
			+ "  let starts_with (prefix:string) (s:string) : bool =\n"
			+ "    let lp = String.length prefix in\n"
			+ "    let ls = String.length s in\n"
			+ "    lp <= ls && String.sub s 0 lp = prefix\n"
			+ "  in\n"
			+ "  let escape_payload (s:string) : string =\n"
			+ "    let b = Buffer.create (String.length s) in\n"
			+ "    String.iter (fun c ->\n"
			+ "      match c with\n"
			+ "      | '\\\\' -> Buffer.add_string b \"\\\\\\\\\"\n"
			+ "      | '\\n' -> Buffer.add_string b \"\\\\n\"\n"
			+ "      | '\\r' -> Buffer.add_string b \"\\\\r\"\n"
			+ "      | '\\t' -> Buffer.add_string b \"\\\\t\"\n"
			+ "      | _ -> Buffer.add_char b c\n"
			+ "    ) s;\n"
			+ "    Buffer.contents b\n"
			+ "  in\n"
			+ "  let unescape_payload (s:string) : string =\n"
			+ "    let b = Buffer.create (String.length s) in\n"
			+ "    let i = ref 0 in\n"
			+ "    let len = String.length s in\n"
			+ "    while !i < len do\n"
			+ "      let c = s.[!i] in\n"
			+ "      if c = '\\\\' && !i + 1 < len then (\n"
			+ "        let n = s.[!i + 1] in\n"
			+ "        (match n with\n"
			+ "        | 'n' -> Buffer.add_char b '\\n'\n"
			+ "        | 'r' -> Buffer.add_char b '\\r'\n"
			+ "        | 't' -> Buffer.add_char b '\\t'\n"
			+ "        | '\\\\' -> Buffer.add_char b '\\\\'\n"
			+ "        | _ -> Buffer.add_char b n);\n"
			+ "        i := !i + 2\n"
			+ "      ) else (\n"
			+ "        Buffer.add_char b c;\n"
			+ "        incr i\n"
			+ "      )\n"
			+ "    done;\n"
			+ "    Buffer.contents b\n"
			+ "  in\n"
			+ "  let encode_len (label:string) (value:string) : string =\n"
			+ "    let enc = escape_payload value in\n"
			+ "    label ^ \"=\" ^ string_of_int (String.length enc) ^ \":\" ^ enc\n"
			+ "  in\n"
			+ "  let kv_get (tail:string) (key:string) : string =\n"
			+ "    let len = String.length tail in\n"
			+ "    let is_digit c = c >= '0' && c <= '9' in\n"
			+ "    let i = ref 0 in\n"
			+ "    let rec scan () =\n"
			+ "      while !i < len && is_space tail.[!i] do incr i done;\n"
			+ "      if !i >= len then \"\" else (\n"
			+ "        let key_start = !i in\n"
			+ "        while !i < len && not (is_space tail.[!i]) && tail.[!i] <> '=' do incr i done;\n"
			+ "        if !i >= len || tail.[!i] <> '=' then (\n"
			+ "          while !i < len && not (is_space tail.[!i]) do incr i done;\n"
			+ "          scan ()\n"
			+ "        ) else (\n"
			+ "          let k = String.sub tail key_start (!i - key_start) in\n"
			+ "          incr i;\n"
			+ "          let len_start = !i in\n"
			+ "          while !i < len && is_digit tail.[!i] do incr i done;\n"
			+ "          if !i >= len || tail.[!i] <> ':' then (\n"
			+ "            while !i < len && not (is_space tail.[!i]) do incr i done;\n"
			+ "            scan ()\n"
			+ "          ) else (\n"
			+ "            let l = try int_of_string (String.sub tail len_start (!i - len_start)) with _ -> -1 in\n"
			+ "            incr i;\n"
			+ "            if l < 0 || !i + l > len then \"\" else (\n"
			+ "              let enc = String.sub tail !i l in\n"
			+ "              i := !i + l;\n"
			+ "              if k = key then unescape_payload enc else scan ()\n"
			+ "            )\n"
			+ "          )\n"
			+ "        )\n"
			+ "      )\n"
			+ "    in\n"
			+ "    scan ()\n"
			+ "  in\n"
			+ "  let split_req (line:string) : (int * string * string) option =\n"
			+ "    let len = String.length line in\n"
			+ "    let i = ref 0 in\n"
			+ "    let next_token () =\n"
			+ "      while !i < len && line.[!i] = ' ' do incr i done;\n"
			+ "      let start = !i in\n"
			+ "      while !i < len && line.[!i] <> ' ' do incr i done;\n"
			+ "      if !i <= start then \"\" else String.sub line start (!i - start)\n"
			+ "    in\n"
			+ "    let _req = next_token () in\n"
			+ "    let id_str = next_token () in\n"
			+ "    let meth = next_token () in\n"
			+ "    while !i < len && line.[!i] = ' ' do incr i done;\n"
			+ "    let tail = if !i < len then String.sub line !i (len - !i) else \"\" in\n"
			+ "    if id_str = \"\" || meth = \"\" then None else (\n"
			+ "      try Some (int_of_string id_str, meth, tail) with _ -> None\n"
			+ "    )\n"
			+ "  in\n"
			+ "  let reply_ok (id:int) (v:string) : unit =\n"
			+ "    print_endline (\"res \" ^ string_of_int id ^ \" ok \" ^ encode_len \"v\" v);\n"
			+ "    flush stdout\n"
			+ "  in\n"
			+ "  let reply_err (id:int) (msg:string) : unit =\n"
			+ "    print_endline (\"res \" ^ string_of_int id ^ \" err \" ^ encode_len \"m\" msg ^ \" \" ^ encode_len \"p\" \"\");\n"
			+ "    flush stdout\n"
			+ "  in\n"
			+ "  let defines : (string, string) Hashtbl.t = Hashtbl.create 16 in\n"
			+ "  let rec loop () : unit =\n"
			+ "    match (try Some (input_line stdin) with End_of_file -> None) with\n"
			+ "    | None -> ()\n"
			+ "    | Some line ->\n"
			+ "      let t = String.trim line in\n"
			+ "      if t = \"\" then loop () else if t = \"quit\" then () else if starts_with \"req \" t then (\n"
			+ "        match split_req t with\n"
			+ "        | None -> reply_err 0 \"missing id\"; loop ()\n"
			+ "        | Some (id, meth, tail) ->\n"
			+ "          (match meth with\n"
			+ "          | \"ping\" -> reply_ok id \"pong\"\n"
			+ "          | \"compiler.define\" ->\n"
			+ "            let n = kv_get tail \"n\" in\n"
			+ "            let v = kv_get tail \"v\" in\n"
			+ "            if n = \"\" then reply_err id \"compiler.define: missing name\" else (Hashtbl.replace defines n v; reply_ok id \"ok\")\n"
			+ "          | \"context.defined\" ->\n"
			+ "            let n = kv_get tail \"n\" in\n"
			+ "            reply_ok id (if Hashtbl.mem defines n then \"1\" else \"0\")\n"
			+ "          | \"context.definedValue\" ->\n"
			+ "            let n = kv_get tail \"n\" in\n"
			+ "            let v = try Hashtbl.find defines n with Not_found -> \"\" in\n"
			+ "            reply_ok id v\n"
			+ "          | _ -> reply_err id (\"unknown method: \" ^ meth)\n"
			+ "          );\n"
			+ "          loop ()\n"
			+ "      ) else (reply_err 0 \"unknown message\"; loop ())\n"
			+ "  in\n"
			+ "  (* Handshake: expect hello proto=1 then reply ok *)\n"
			+ "  match (try Some (input_line stdin) with End_of_file -> None) with\n"
			+ "  | None -> ()\n"
			+ "  | Some hello ->\n"
			+ "    let h = String.trim hello in\n"
			+ "    if not (starts_with \"hello\" h) then (print_endline (\"err \" ^ encode_len \"m\" \"missing hello\"); flush stdout)\n"
			+
			"    else if not (String.contains h '=') || not (String.contains h '1') then (print_endline (\"err \" ^ encode_len \"m\" \"unsupported proto\"); flush stdout)\n"
			+ "    else (print_endline \"ok\"; flush stdout; loop ())\n"
			+ ")\n");
	}
}
