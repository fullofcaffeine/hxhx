/**
	Haxe-in-Haxe parser (very small subset).

	Why:
	- This is the first “real” Stage 2 component: we parse a subset of actual
	  Haxe syntax into a structured module representation.
	- The end goal is to parse the real Haxe compiler sources, but we need an
	  incremental path that stays runnable in CI.

	What:
	- Parses:
	  - optional 'package <path>;'
	  - zero or more 'import <path>;' / 'using <path>;'
	  - a single 'class <Name> { ... }' (first class found; others ignored)
	  - a small subset of class members:
	    - function declarations (name, modifiers, args, optional return type)
	    - `return <expr>;` in function bodies (very small expression subset)

	How:
	- This is intentionally *not* the full Haxe grammar.
	- We grow coverage rung-by-rung while keeping acceptance fixtures runnable.
**/
class HxParser {
	final lex:HxLexer;
	var cur:HxToken;
	var capturedReturnStringLiteral:String = "";

	public function new(source:String) {
		lex = new HxLexer(source);
		cur = lex.next();
	}

	/**
		Parse a single expression from standalone source text.

		Why
		- The native OCaml frontend seam currently reports return expressions as raw text.
		- Stage 3 wants to recover a small, structured expression tree (`a.b(c)`) from that
		  text without implementing a full OCaml-side expression AST.

		What
		- Parses a tiny expression grammar:
		  - primary literals/idents
		  - field access chains (`a.b.c`)
		  - call suffixes (`f()`, `obj.m(x, y)`)

		How
		- Reuses the same lexer + `parseExpr` routine as module parsing, but stops at EOF.
	**/
	public static function parseExprText(source:String):HxExpr {
		final p = new HxParser(source);
		final e = p.parseExpr(() -> p.cur.kind.match(TEof));
		return e;
	}

	inline function bump():Void {
		cur = lex.next();
	}

	function fail<T>(message:String):T {
		throw new HxParseError(message, cur.pos);
	}

	function expect(kind:HxTokenKind, label:String):Void {
		final ok = switch [cur.kind, kind] {
			case [TEof, TEof]: true;
			case [TLBrace, TLBrace]: true;
			case [TRBrace, TRBrace]: true;
			case [TLParen, TLParen]: true;
			case [TRParen, TRParen]: true;
			case [TSemicolon, TSemicolon]: true;
			case [TColon, TColon]: true;
			case [TDot, TDot]: true;
			case [TComma, TComma]: true;
			case [TKeyword(a), TKeyword(b)]: a == b;
			case _: false;
		}
		if (!ok) fail("Expected " + label);
		bump();
	}

	function acceptKeyword(k:HxKeyword):Bool {
		return switch (cur.kind) {
			case TKeyword(kk) if (kk == k):
				bump();
				true;
			case _:
				false;
		}
	}

	function acceptOtherChar(ch:String):Bool {
		final code = ch.charCodeAt(0);
		return switch (cur.kind) {
			case TOther(c) if (c == code):
				bump();
				true;
			case _:
				false;
		}
	}

	function isOtherChar(ch:String):Bool {
		final code = ch.charCodeAt(0);
		return switch (cur.kind) {
			case TOther(c) if (c == code): true;
			case _: false;
		}
	}

	function readIdent(label:String):String {
		return switch (cur.kind) {
			case TIdent(name):
				bump();
				name;
			case _:
				fail("Expected " + label);
		}
	}

	function readDottedPath():String {
		final parts = new Array<String>();
		parts.push(readIdent("identifier"));
		while (true) {
			switch (cur.kind) {
				case TDot:
					bump();
					parts.push(readIdent("identifier"));
				case _:
					break;
			}
		}
		return parts.join(".");
	}

	function readImportPath():String {
		// Like `readDottedPath`, but accepts a trailing `.*` wildcard.
		final parts = new Array<String>();
		parts.push(readIdent("identifier"));
		while (true) {
			switch (cur.kind) {
				case TDot:
					bump();
					if (acceptOtherChar("*")) {
						parts.push("*");
						break;
					}
					parts.push(readIdent("identifier"));
				case _:
					break;
			}
		}
		return parts.join(".");
	}

	function skipBalancedParens():Void {
		// Called when current token is '(' already consumed by caller.
		var depth = 1;
		while (depth > 0) {
			switch (cur.kind) {
				case TEof:
					fail("Unterminated parenthesis group");
				case TLParen:
					depth++;
					bump();
				case TRParen:
					depth--;
					bump();
				case _:
					bump();
			}
		}
	}

	function skipBalancedBraces():Void {
		// Called when current token is '{' already consumed by caller.
		var depth = 1;
		while (depth > 0) {
			switch (cur.kind) {
				case TEof:
					fail("Unterminated brace block");
				case TLBrace:
					depth++;
					bump();
				case TRBrace:
					depth--;
					bump();
				case TLParen:
					bump();
					skipBalancedParens();
				case _:
					bump();
			}
		}
	}

	function readTypeHintText(stop:()->Bool):String {
		// Bootstrap: type hints are kept as raw text until we implement a full type grammar.
		final parts = new Array<String>();
		while (!stop()) {
			switch (cur.kind) {
				case TEof:
					break;
				case TIdent(name):
					parts.push(name);
					bump();
				case TKeyword(k):
					parts.push(Std.string(k));
					bump();
				case TString(s):
					parts.push('"' + s + '"');
					bump();
				case TInt(v):
					parts.push(Std.string(v));
					bump();
				case TFloat(v):
					parts.push(Std.string(v));
					bump();
				case TLParen:
					parts.push("(");
					bump();
				case TRParen:
					parts.push(")");
					bump();
				case TDot:
					parts.push(".");
					bump();
				case TComma:
					parts.push(",");
					bump();
				case TColon:
					parts.push(":");
					bump();
				case TLBrace:
					parts.push("{");
					bump();
				case TRBrace:
					parts.push("}");
					bump();
				case TSemicolon:
					parts.push(";");
					bump();
				case TOther(c):
					parts.push(String.fromCharCode(c));
					bump();
			}
		}
		return parts.join("");
	}

	function parsePrimaryExpr():HxExpr {
		return switch (cur.kind) {
			case TKeyword(k):
				if (k == KNull) {
					bump();
					ENull;
				} else if (k == KTrue) {
					bump();
					EBool(true);
				} else if (k == KFalse) {
					bump();
					EBool(false);
				} else {
					// Best-effort: capture the keyword as a string.
					final raw = Std.string(k);
					bump();
					EUnsupported(raw);
				}
			case TString(s):
				bump();
				EString(s);
			case TInt(v):
				bump();
				EInt(v);
			case TFloat(v):
				bump();
				EFloat(v);
			case TIdent(name):
				bump();
				EIdent(name);
			case TOther(c):
				final raw = String.fromCharCode(c);
				bump();
				EUnsupported(raw);
			case _:
				// Best-effort: capture a single token and keep going.
				final raw = Std.string(cur.kind);
				bump();
				EUnsupported(raw);
		}
	}

	function parseExpr(stop:()->Bool):HxExpr {
		// Very small expression subset:
		//   primary (("." ident) | ("(" args ")"))*
		var e = parsePrimaryExpr();
		while (!stop()) {
			switch (cur.kind) {
				case TDot:
					bump();
					final field = readIdent("field name");
					e = EField(e, field);
				case TLParen:
					bump();
					final args = new Array<HxExpr>();
					if (cur.kind.match(TRParen)) {
						bump();
						e = ECall(e, args);
						continue;
					}
					while (true) {
						final arg = parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof));
						args.push(arg);
						if (cur.kind.match(TComma)) {
							bump();
							continue;
						}
						expect(TRParen, "')'");
						break;
					}
					e = ECall(e, args);
				case _:
					break;
			}
		}
		return e;
	}

	function parseReturnStmt():HxStmt {
		// `return;` or `return <expr>;`
		if (cur.kind.match(TSemicolon)) {
			bump();
			return SReturnVoid;
		}
		if (cur.kind.match(TRBrace)) {
			return SReturnVoid;
		}

		if (capturedReturnStringLiteral.length == 0) {
			switch (cur.kind) {
				case TString(s):
					capturedReturnStringLiteral = s;
				case _:
			}
		}

		final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
		if (cur.kind.match(TSemicolon)) bump();
		return SReturn(expr);
	}

	function parseFunctionBodyStatements():Array<HxStmt> {
		// Called after consuming '{' (function body open brace).
		final out = new Array<HxStmt>();
		var depth = 1;
		while (depth > 0) {
			switch (cur.kind) {
				case TEof:
					fail("Unterminated function body");
				case TLBrace:
					depth++;
					bump();
				case TRBrace:
					depth--;
					bump();
				case TKeyword(KReturn) if (depth == 1):
					bump();
					out.push(parseReturnStmt());
				case TLParen:
					bump();
					skipBalancedParens();
				default:
					bump();
			}
		}
		return out;
	}

	function parseFunctionDecl(visibility:HxVisibility, isStatic:Bool):HxFunctionDecl {
		capturedReturnStringLiteral = "";
		final name = readIdent("function name");
		expect(TLParen, "'('");

		final args = new Array<HxFunctionArg>();
		if (!cur.kind.match(TRParen)) {
			while (true) {
				final argName = readIdent("argument name");
				var argType = "";
				var defaultValue:HxDefaultValue = HxDefaultValue.NoDefault;

				if (cur.kind.match(TColon)) {
					bump();
					argType = readTypeHintText(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof) || isOtherChar("="));
				}

				if (acceptOtherChar("=")) {
					defaultValue = HxDefaultValue.Default(parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof)));
				}

				args.push(new HxFunctionArg(argName, argType, defaultValue));
				if (cur.kind.match(TComma)) {
					bump();
					continue;
				}
				break;
			}
		}
		expect(TRParen, "')'");

		var returnType = "";
		if (cur.kind.match(TColon)) {
			bump();
			returnType = readTypeHintText(() -> cur.kind.match(TLBrace) || cur.kind.match(TSemicolon) || cur.kind.match(TEof) || cur.kind.match(TKeyword(KReturn)));
		}

		final body = new Array<HxStmt>();
		switch (cur.kind) {
			case TSemicolon:
				bump();
			case TLBrace:
				bump();
				for (s in parseFunctionBodyStatements()) body.push(s);
			case _:
				// Expression-bodied function: `function f() return expr;`
				if (acceptKeyword(KReturn)) {
					body.push(parseReturnStmt());
				} else {
					final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof));
					if (cur.kind.match(TSemicolon)) bump();
					body.push(SExpr(expr));
				}
		}

		return new HxFunctionDecl(name, visibility, isStatic, args, returnType, body, capturedReturnStringLiteral);
	}

	function parseClassFunctions():Array<HxFunctionDecl> {
		final funcs = new Array<HxFunctionDecl>();
		while (true) {
			switch (cur.kind) {
				case TRBrace:
					bump();
					break;
				case TEof:
					fail("Unexpected end of input in class body");
				case _:
					var visibility:HxVisibility = Public;
					var isStatic = false;

					// Modifiers (subset).
					var keep = true;
					while (keep) {
						keep = false;
						if (acceptKeyword(KPublic)) {
							visibility = Public;
							keep = true;
						} else if (acceptKeyword(KPrivate)) {
							visibility = Private;
							keep = true;
						} else if (acceptKeyword(KStatic)) {
							isStatic = true;
							keep = true;
						}
					}

					if (acceptKeyword(KFunction)) {
						funcs.push(parseFunctionDecl(visibility, isStatic));
						continue;
					}

					// Skip tokens until the next likely member boundary.
					switch (cur.kind) {
						case TLBrace:
							bump();
							skipBalancedBraces();
						case TLParen:
							bump();
							skipBalancedParens();
						default:
							bump();
					}
			}
		}
		return funcs;
	}

	public function parseModule():HxModuleDecl {
		var packagePath = "";
		final imports = new Array<String>();
		var hasToplevelMain = false;

		if (acceptKeyword(KPackage)) {
			// Haxe allows an empty package declaration: `package;`
			if (cur.kind.match(TSemicolon)) {
				packagePath = "";
				bump();
			} else {
				packagePath = readDottedPath();
				expect(TSemicolon, "';'");
			}
		}

		while (acceptKeyword(KImport) || acceptKeyword(KUsing)) {
			final path = readImportPath();
			// Accept `import Foo.Bar as Baz;` and ignore alias for now.
			if (acceptKeyword(KAs)) {
				readIdent("import alias");
			}
			imports.push(path);
			expect(TSemicolon, "';'");
		}

		// Bootstrap: scan forward until we find the first `class` declaration.
		// This lets us tolerate (for now):
		// - metadata like `@:build(...)`
		// - multiple type declarations per module
		// - top-level functions (only `main` is recognized as an entrypoint hint)
		var sawClass = false;
		while (true) {
			switch (cur.kind) {
				case TKeyword(KClass):
					sawClass = true;
					break;
				case TKeyword(KFunction):
					// Detect module-level `function main(...)` entrypoint.
					bump();
					switch (cur.kind) {
						case TIdent("main"):
							hasToplevelMain = true;
						case _:
					}
				case TEof:
					break;
				default:
					bump();
			}
			if (cur.kind.match(TEof) || cur.kind.match(TKeyword(KClass))) break;
		}

		var className = "Unknown";
		final functions = new Array<HxFunctionDecl>();
		var hasStaticMain = false;

		if (sawClass) {
			expect(TKeyword(KClass), "'class'");
			className = readIdent("class name");

			expect(TLBrace, "'{'");

			for (fn in parseClassFunctions()) functions.push(fn);
			for (fn in functions) {
				if (HxFunctionDecl.getIsStatic(fn) && HxFunctionDecl.getName(fn) == "main") {
					hasStaticMain = true;
					break;
				}
			}
		}

		// Bootstrap: ignore any trailing declarations after the first class.
		// Upstream code often contains multiple types per module (and metadata).
		while (true) {
			switch (cur.kind) {
				case TEof:
					break;
				default:
					bump();
			}
		}

		expect(TEof, "end of input");
		return new HxModuleDecl(packagePath, imports, new HxClassDecl(className, hasStaticMain, functions), false, hasToplevelMain);
	}
}
