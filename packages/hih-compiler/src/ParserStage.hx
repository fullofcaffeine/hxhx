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
	  while we reimplement the rest of the compiler pipeline in Haxe.
**/
class ParserStage {
	public function new() {}

	public static function parse(source:String, ?filePath:String):ParsedModule {
		final decl = #if hih_native_parser
			// Bring-up escape hatch: allow forcing the pure-Haxe parser even when the
			// native frontend is compiled in.
			//
			// Why
			// - The native frontend protocol v1 is intentionally "header/return only" and
			//   cannot represent full statement bodies.
			// - Some Stage3 bring-up rungs (e.g. `--hxhx-emit-full-bodies`) need bodies so
			//   we can validate statement lowering end-to-end.
			//
			// How
			// - `HIH_FORCE_HX_PARSER=1` selects the pure-Haxe frontend regardless of the
			//   compiled-in `hih_native_parser` define.
			((() -> {
				final v = Sys.getEnv("HIH_FORCE_HX_PARSER");
				if (v == "1" || v == "true" || v == "yes") return new HxParser(source).parseModule();
				try {
					return parseViaNativeHooks(source);
				} catch (eNative:Dynamic) {
					final strict = Sys.getEnv("HIH_NATIVE_PARSER_STRICT");
					if (strict == "1" || strict == "true" || strict == "yes") throw eNative;

					// Fallback: the pure-Haxe frontend is slower, but it can unblock bring-up when the
					// native lexer/parser cannot yet handle an upstream-shaped input.
					//
					// This is especially useful when widening the module graph for upstream suites
					// (e.g. enabling heuristic same-package type resolution).
					try {
						return new HxParser(source).parseModule();
					} catch (_:Dynamic) {
						// Prefer the native error (it is usually more specific about the failure mode).
						throw eNative;
					}
				}
			})());
		#else
			new HxParser(source).parseModule();
		#end
		final path = filePath == null || filePath.length == 0 ? "<memory>" : filePath;
		return new ParsedModule(source, decl, path);
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
					throw "Native frontend: missing/invalid protocol header";
				}

				var packagePath = "";
				final imports = new Array<String>();
				var className = "Unknown";
				var headerOnly = false;
				var hasToplevelMain = false;
				var hasStaticMain = false;
				final methodPayloads = new Array<String>();
				final methodBodies:Map<String, String> = [];
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
							case "header_only":
								headerOnly = payload == "1";
							case "toplevel_main":
								hasToplevelMain = payload == "1";
							case "method":
								methodPayloads.push(payload);
							case "method_body":
								// Payload format: "<methodName>\n<bodySource>"
								final nl = payload.indexOf("\n");
								if (nl > 0) {
									final name = payload.substr(0, nl);
									if (!methodBodies.exists(name)) {
										methodBodies.set(name, payload.substr(nl + 1));
									}
								}
							case _:
						}
						continue;
				}
			}

			if (!sawOk) {
					throw "Native frontend: missing terminal 'ok'";
				}

				for (mp in methodPayloads) {
					final name = {
						final parts = mp.split("|");
						parts.length == 0 ? "" : parts[0];
					};
					functions.push(decodeMethodPayload(mp, methodBodies.exists(name) ? methodBodies.get(name) : null));
				}

				return new HxModuleDecl(packagePath, imports, new HxClassDecl(className, hasStaticMain, functions), headerOnly, hasToplevelMain);
			}

		static function decodeMethodPayload(payload:String, methodBodySrc:Null<String>):HxFunctionDecl {
			// Bootstrap note: payload is a `|` separated list (unescaped for '|').
			//
			// v=1:
			//   name|vis|static|args|ret|retstr
		//
		// v=1 (backward-compatible extensions; optional fields):
		//   name|vis|static|args|ret|retstr|retid|argtypes|retexpr
		//
		// Where:
		// - args: comma-separated argument names
		// - retid: first detected `return <ident>` (if any)
		// - argtypes: comma-separated `name:type` pairs (no '|' characters)
		final parts = payload.split("|");
		while (parts.length < 9) parts.push("");

		final name = parts[0];
		final vis = parts[1] == "private" ? HxVisibility.Private : HxVisibility.Public;
		final isStatic = parts[2] == "1";

		final argTypes:Map<String, String> = [];
		final argTypesPayload = parts[7];
		if (argTypesPayload.length > 0) {
			for (entry in argTypesPayload.split(",")) {
				if (entry.length == 0) continue;
				final idx = entry.indexOf(":");
				if (idx <= 0) continue;
				final argName = entry.substr(0, idx);
				final ty = entry.substr(idx + 1);
				argTypes.set(argName, ty);
			}
		}

		final args = new Array<HxFunctionArg>();
		final argsPayload = parts[3];
		if (argsPayload.length > 0) {
			for (a in argsPayload.split(",")) {
				if (a.length == 0) continue;
				final ty = argTypes.exists(a) ? argTypes.get(a) : "";
				args.push(new HxFunctionArg(a, ty, HxDefaultValue.NoDefault));
			}
		}

		final returnTypeHint = parts[4];
		final retStr = parts[5];
		final retId = parts[6];
		final retExpr = parts[8];
			final body = new Array<HxStmt>();
			final pos = HxPos.unknown();
			// Prefer the richer `retexpr` field when present (it can represent `Util.ping()`),
			// but keep legacy fields for older protocol emitters.
			if (retExpr.length > 0) {
				body.push(SReturn(parseReturnExprText(retExpr), pos));
			} else if (retStr.length > 0) {
				body.push(SReturn(EString(retStr), pos));
			} else if (retId.length > 0) {
				body.push(SReturn(EIdent(retId), pos));
			}

			var outBody = body;
			if (methodBodySrc != null && methodBodySrc.length > 0) {
				// Best-effort: recover a structured statement list from the raw source slice.
				//
				// Why
				// - The native frontend protocol v1+ transmits method bodies as raw source
				//   (via `ast method_body`) rather than an OCaml-side statement AST.
				// - Stage3 bring-up wants bodies so it can validate full-body lowering.
				try {
					outBody = HxParser.parseFunctionBodyText(methodBodySrc);
				} catch (_:Dynamic) {
					// Fall back to the summary-only body.
					outBody = body;
				}
			}

			return new HxFunctionDecl(name, vis, isStatic, args, returnTypeHint, outBody, retStr);
		}

	static function parseReturnExprText(raw:String):HxExpr {
		final s = StringTools.trim(raw);
		if (s.length == 0) return EUnsupported("<empty-return-expr>");

		if (s == "null") return ENull;
		if (s == "true") return EBool(true);
		if (s == "false") return EBool(false);

		if (s.length >= 2 && StringTools.startsWith(s, "\"") && StringTools.endsWith(s, "\"")) {
			return EString(s.substr(1, s.length - 2));
		}

		// Integers: [-]?[0-9]+ (manual parse to avoid Null<Int> pitfalls in bootstrap output).
		{
			var i = 0;
			var sign = 1;
			if (s.length > 0 && s.charCodeAt(0) == "-".code) {
				sign = -1;
				i = 1;
			}

			var value = 0;
			var saw = false;
			while (i < s.length) {
				final c = s.charCodeAt(i);
				if (c < "0".code || c > "9".code) {
					saw = false;
					break;
				}
				saw = true;
				value = value * 10 + (c - "0".code);
				i++;
			}

			if (saw && i == s.length) return EInt(sign * value);
		}

		// Floats: best-effort via parseFloat if it contains '.'.
		if (s.indexOf(".") != -1) {
			final f = Std.parseFloat(s);
			if (!Math.isNaN(f)) return EFloat(f);
		}

		// Fallback: try to parse a small field/call chain (e.g. `Util.ping()`).
		return try {
			HxParser.parseExprText(s);
		} catch (_:Dynamic) {
			// Last resort: treat as unsupported so emitters don't attempt to print raw Haxe text as OCaml.
			EUnsupported(s);
		}
	}

	static function throwFromErrLine(line:String):Void {
		// err <index> <line> <col> <len>:<message>
		final parts = splitN(line, 4); // ["err", idx, line, col, tail]
		final idx = parts.length > 1 ? parseDecInt(parts[1]) : -1;
		final ln = parts.length > 2 ? parseDecInt(parts[2]) : -1;
		final col = parts.length > 3 ? parseDecInt(parts[3]) : -1;
		final tail = parts.length > 4 ? parts[4] : "";
		final msg = decodeLenPayload(tail);
		final idx0 = idx < 0 ? 0 : idx;
		final ln0 = ln < 0 ? 0 : ln;
		final col0 = col < 0 ? 0 : col;
		throw "Native frontend: " + msg + " (" + idx0 + ":" + ln0 + ":" + col0 + ")";
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
