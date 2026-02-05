/**
	Stage 2 parser skeleton.

	What:
	- For now, this does *not* implement the Haxe grammar.
	- It exists to establish the module boundary and the “AST in / AST out” flow.

	How:
	- We return a tiny placeholder ParsedModule so downstream stages can be
	  written and tested without waiting for a full parser.

	Native hook:
	- When `-D hih_native_parser` is enabled, we call into the OCaml “native”
	  lexer/parser stubs (`HxHxNativeLexer` / `HxHxNativeParser`) via externs.
	  This matches the upstream bootstrap strategy: keep the frontend native
	  while we port the rest of the compiler pipeline into Haxe.
**/
class ParserStage {
	public function new() {}

	public static function parse(source:String):ParsedModule {
		final decl = #if hih_native_parser
			parseViaNativeHooks(source);
		#else
			new HxParser(source).parseModule();
		#end
		return new ParsedModule(source, decl);
	}

	#if hih_native_parser
	static function parseViaNativeHooks(source:String):HxModuleDecl {
		final encoded = native.NativeParser.parseModuleDecl(source);
		return decodeNativeProtocol(encoded);
	}

	/**
		Decode the native frontend protocol emitted by the OCaml lexer/parser stubs.

		Why:
		- This is our “bootstrap seam” for Haxe-in-Haxe: we want to keep the
		  frontend native initially, but keep the rest of the compiler in Haxe.

		What:
		- Produces a `HxModuleDecl` for Stage 2 from the protocol output.

		How:
		- The protocol is intentionally simple and line-based so it can be produced
		  from OCaml without dependencies and decoded from Haxe without a JSON
		  runtime.
		- See `docs/02-user-guide/HXHX_NATIVE_FRONTEND_PROTOCOL.md:1` for the exact
		  wire format and versioning rules.
	**/
	static function decodeNativeProtocol(encoded:String):HxModuleDecl {
		final lines = encoded.split("\n").filter(l -> l.length > 0);
		if (lines.length == 0 || lines[0] != "hxhx_frontend_v=1") {
			throw new HxParseError("Native frontend: missing/invalid protocol header", new HxPos(0, 0, 0));
		}

		var packagePath = "";
		final imports = new Array<String>();
		var className = "Unknown";
		var hasStaticMain = false;
		final functions = new Array<HxFunctionDecl>();
		var sawOk = false;

		for (i in 1...lines.length) {
			final line = lines[i];
			if (line == "ok") {
				sawOk = true;
				continue;
			}

			if (StringTools.startsWith(line, "err ")) {
				throwFromErrLine(line);
				return null;
			}

			if (StringTools.startsWith(line, "ast ")) {
				if (StringTools.startsWith(line, "ast static_main ")) {
					hasStaticMain = line.substr("ast static_main ".length) == "1";
					continue;
				}

				final rest = line.substr("ast ".length);
				final firstSpace = rest.indexOf(" ");
				if (firstSpace <= 0) continue;
				final key = rest.substr(0, firstSpace);
				final payload = decodeLenPayload(rest.substr(firstSpace + 1));
				switch (key) {
					case "package":
						packagePath = payload;
					case "imports":
						if (payload.length > 0) {
							for (p in payload.split("|")) if (p.length > 0) imports.push(p);
						}
					case "class":
						className = payload;
					case "method":
						functions.push(decodeMethodPayload(payload));
					case _:
				}
				continue;
			}
		}

		if (!sawOk) {
			throw new HxParseError("Native frontend: missing terminal 'ok'", new HxPos(0, 0, 0));
		}

		return new HxModuleDecl(packagePath, imports, new HxClassDecl(className, hasStaticMain, functions));
	}

	static function decodeMethodPayload(payload:String):HxFunctionDecl {
		// Bootstrap note: payload is `name|vis|static|args|ret|retstr` (unescaped for '|').
		final parts = payload.split("|");
		while (parts.length < 6) parts.push("");

		final name = parts[0];
		final vis = parts[1] == "private" ? HxVisibility.Private : HxVisibility.Public;
		final isStatic = parts[2] == "1";

		final args = new Array<HxFunctionArg>();
		final argsPayload = parts[3];
		if (argsPayload.length > 0) {
			for (a in argsPayload.split(",")) {
				if (a.length == 0) continue;
				args.push(new HxFunctionArg(a, "", HxDefaultValue.NoDefault));
			}
		}

		final returnTypeHint = parts[4];
		final retStr = parts[5];
		final body = new Array<HxStmt>();
		if (retStr.length > 0) {
			body.push(SReturn(EString(retStr)));
		}

		return new HxFunctionDecl(name, vis, isStatic, args, returnTypeHint, body, retStr);
	}

	static function throwFromErrLine(line:String):Void {
		// err <index> <line> <col> <len>:<message>
		final parts = splitN(line, 4); // ["err", idx, line, col, tail]
		final idx = parts.length > 1 ? parseDecInt(parts[1]) : -1;
		final ln = parts.length > 2 ? parseDecInt(parts[2]) : -1;
		final col = parts.length > 3 ? parseDecInt(parts[3]) : -1;
		final tail = parts.length > 4 ? parts[4] : "";
		final msg = decodeLenPayload(tail);
		throw new HxParseError(msg, new HxPos(idx < 0 ? 0 : idx, ln < 0 ? 0 : ln, col < 0 ? 0 : col));
	}

	static function decodeLenPayload(s:String):String {
		final colon = s.indexOf(":");
		if (colon <= 0) return "";
		final len = parseDecInt(s.substr(0, colon));
		if (len < 0) return "";
		final payload = s.substr(colon + 1);
		final raw = payload.substr(0, len);
		return unescapePayload(raw);
	}

	static function parseDecInt(s:String):Int {
		if (s == null) return -1;
		var i = 0;
		// Trim leading spaces (defensive).
		while (i < s.length && s.charCodeAt(i) == " ".code) i++;
		if (i >= s.length) return -1;
		var value = 0;
		var saw = false;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c < "0".code || c > "9".code) break;
			saw = true;
			value = value * 10 + (c - "0".code);
			i++;
		}
		return saw ? value : -1;
	}

	static function unescapePayload(s:String):String {
		final out = new StringBuf();
		var i = 0;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c == "\\".code && i + 1 < s.length) {
				final n = s.charCodeAt(i + 1);
				switch (n) {
					case "n".code: out.addChar("\n".code);
					case "r".code: out.addChar("\r".code);
					case "t".code: out.addChar("\t".code);
					case "\\".code: out.addChar("\\".code);
					case _: out.addChar(n);
				}
				i += 2;
				continue;
			}
			out.addChar(c);
			i++;
		}
		return out.toString();
	}

	static function splitN(s:String, n:Int):Array<String> {
		// Split into exactly `n` space-separated fields, plus a final "tail" field (may contain spaces).
		final head = new Array<String>();
		var i = 0;
		var start = 0;
		while (head.length < n && i <= s.length) {
			if (i == s.length || s.charCodeAt(i) == " ".code) {
				if (i > start) head.push(s.substr(start, i - start));
				while (i < s.length && s.charCodeAt(i) == " ".code) i++;
				start = i;
				continue;
			}
			i++;
		}
		while (head.length < n) head.push("");
		final tail = start <= s.length ? s.substr(start) : "";
		head.push(tail);
		return head;
	}
	#end
}
