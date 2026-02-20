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
		- one or more `class <Name> { ... }` declarations
		  - we select a “main class” for the module (see `parseModule(expectedMainClass)`).
	  - a small subset of class members:
		- function declarations (name, modifiers, args, optional return type)
		- `return <expr>;` in function bodies (very small expression subset)

	How:
	- This is intentionally *not* the full Haxe grammar.
	- We grow coverage rung-by-rung while keeping acceptance fixtures runnable.
**/
class HxParser {
	/**
		Debug label for method-body parsing (native frontend seam).

		Why
		- When we parse raw method body slices via `parseFunctionBodyText`, any parse holes are
		  reported as `body_parse_error` statements.
		- During Gate bring-up, it is useful to know *which* method body hit the parse hole.

		How
		- `ParserStage.decodeMethodPayload` sets this to the method name immediately before
		  calling `parseFunctionBodyText`, and resets it afterwards.
		- Logging is gated by `HXHX_TRACE_BODY_STMT_PARSE_ERROR=1`.
	**/
	public static var debugBodyLabel:String = "";

	final lex:HxLexer;
	var cur:HxToken;
	var peeked1:Null<HxToken> = null;
	var peeked2:Null<HxToken> = null;
	var peeked3:Null<HxToken> = null;
	var capturedReturnStringLiteral:String = "";

	static function keywordText(k:HxKeyword):String {
		// IMPORTANT (bootstrap / backend independence)
		// - Do not use `Std.string(k)` here.
		// - In early bring-up, `Std.string` can flow through the target runtime's Dynamic
		//   printing path, which may stringify nullary enums as their OCaml integer tags.
		// - We need a stable mapping to the original source keyword text so diagnostics and
		//   placeholder `EUnsupported` payloads remain readable across targets.
		return switch (k) {
			case KPackage: "package";
			case KImport: "import";
			case KUsing: "using";
			case KAs: "as";
			case KClass: "class";
			case KPublic: "public";
			case KPrivate: "private";
			case KStatic: "static";
			case KInline: "inline";
			case KFunction: "function";
			case KReturn: "return";
			case KIf: "if";
			case KElse: "else";
			case KSwitch: "switch";
			case KCase: "case";
			case KDefault: "default";
			case KTry: "try";
			case KCatch: "catch";
			case KThrow: "throw";
			case KWhile: "while";
			case KDo: "do";
			case KFor: "for";
			case KIn: "in";
			case KBreak: "break";
			case KContinue: "continue";
			case KUntyped: "untyped";
			case KCast: "cast";
			case KVar: "var";
			case KFinal: "final";
			case KNew: "new";
			case KThis: "this";
			case KSuper: "super";
			case KTrue: "true";
			case KFalse: "false";
			case KNull: "null";
		};
	}

	static function isUpperStart(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		final c = name.charCodeAt(0);
		return c >= "A".code && c <= "Z".code;
	}

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

	/**
		Parse a function body statement list from standalone source text.

		Why
		- The native OCaml frontend seam can report method bodies as raw source slices
		  (`ast method_body`) without transmitting a full statement AST.
		- Stage 3 bring-up wants to validate "full body" lowering (e.g. `trace("HELLO");`)
		  while still using the native frontend for the rest of the module graph.

		What
		- Takes the raw text *inside* a function body (between `{` and `}`) and returns
		  the parsed statement list (`Array<HxStmt>`).

		How
		- Wraps the body in braces and reuses the same lexer/parser routines as normal
		  module parsing.
		- This is best-effort and only supports the current Stage 3 statement subset.
	**/
	public static function parseFunctionBodyText(bodySource:String):Array<HxStmt> {
		final src = "{\n" + (bodySource == null ? "" : bodySource) + "\n}";
		final p = new HxParser(src);
		if (!p.cur.kind.match(TLBrace))
			return [];
		p.bump(); // consume '{'
		return p.parseFunctionBodyStatementsBestEffort();
	}

	inline function bump():Void {
		if (peeked1 != null) {
			cur = peeked1;
			peeked1 = peeked2;
			peeked2 = peeked3;
			peeked3 = null;
		} else {
			cur = lex.next();
		}
	}

	function parseSwitchPattern():HxSwitchPattern {
		// Bring-up: support a very small pattern subset (see HxSwitchPattern docs),
		// including a shallow OR pattern (`case a | b:`) used by upstream harnesses.
		function parseAtom():HxSwitchPattern {
			return switch (cur.kind) {
				case TKeyword(KNull):
					bump();
					PNull;
				case TIdent("_"):
					bump();
					PWildcard;
				case TString(s):
					bump();
					PString(s);
				case TInt(v):
					bump();
					PInt(v);
				case TIdent(name):
					bump();
					isUpperStart(name) ? PEnumValue(name) : PBind(name);
				case _:
					// Best-effort: consume one token and treat it as a wildcard.
					bump();
					PWildcard;
			}
		}

		final first = parseAtom();
		var ors:Null<Array<HxSwitchPattern>> = null;
		while (acceptOtherChar("|")) {
			if (ors == null)
				ors = [first];
			ors.push(parseAtom());
		}
		return ors == null ? first : POr(ors);
	}

	inline function peek():HxToken {
		if (peeked1 == null)
			peeked1 = lex.next();
		return peeked1;
	}

	inline function peek2():HxToken {
		if (peeked1 == null)
			peeked1 = lex.next();
		if (peeked2 == null)
			peeked2 = lex.next();
		return peeked2;
	}

	inline function peek3():HxToken {
		if (peeked1 == null)
			peeked1 = lex.next();
		if (peeked2 == null)
			peeked2 = lex.next();
		if (peeked3 == null)
			peeked3 = lex.next();
		return peeked3;
	}

	inline function peekKind():HxTokenKind {
		return peek().kind;
	}

	inline function peekKind2():HxTokenKind {
		return peek2().kind;
	}

	inline function peekKind3():HxTokenKind {
		return peek3().kind;
	}

	inline function nextIsAdjacentOther(code:Int):Bool {
		final next = peek();
		return switch (next.kind) {
			case TOther(c) if (c == code):
				next.pos.getIndex() == cur.pos.getIndex() + 1;
			case _:
				false;
		}
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
		if (!ok)
			fail("Expected " + label);
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

	function readTypeHintText(stop:() -> Bool):String {
		// Bootstrap: type hints are kept as raw text until we implement a full type grammar.
		final parts = new Array<String>();
		while (true) {
			// Special-case structural/anonymous type hints that begin with `{ ... }`.
			//
			// Example (upstream runci/System.hx):
			//   static function commandResult(...):{ stdout:String, ... } { ... }
			//
			// In this case, the first `{` is part of the *type hint*, not the function body.
			// Our callers often use `stop()` predicates that stop on `{` (body start), so we
			// allow a leading `{` to be consumed into the type-hint text.
			if (stop() && !(parts.length == 0 && cur.kind.match(TLBrace)))
				break;
			switch (cur.kind) {
				case TEof:
					break;
				case TIdent(name):
					parts.push(name);
					bump();
				case TKeyword(k):
					parts.push(keywordText(k));
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
			case TLParen:
				// Parenthesized expression: `(expr)`.
				bump(); // '('
				final inner = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
				// Best-effort: resync to the closing `)`.
				if (!cur.kind.match(TRParen)) {
					while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
						bump();
				}
				if (cur.kind.match(TRParen))
					bump();
				inner;
			case TLBrace:
				parseAnonExpr();
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
				} else if (k == KThis) {
					bump();
					EThis;
				} else if (k == KSuper) {
					bump();
					ESuper;
				} else if (k == KNew) {
					bump();
					final typePath = readDottedPath();
					// Optional constructor type arguments: `new Foo<Bar,Baz>(...)`.
					//
					// Without consuming `<...>` here, the expression parser treats `<`/`>` as
					// binary operators and drifts into nonsense AST like:
					//   (new Foo) < ("Bar") > (...)
					//
					// Stage3 only needs the allocated runtime shape, so we intentionally drop
					// generic constructor type arguments in this bootstrap parser.
					if (isOtherChar("<")) {
						var angleDepth = 0;
						while (true) {
							switch (cur.kind) {
								case TOther(c) if (c == "<".code):
									angleDepth += 1;
									bump();
								case TOther(c) if (c == ">".code):
									angleDepth -= 1;
									bump();
									if (angleDepth <= 0) break;
								case TEof:
									break;
								case _:
									bump();
							}
						}
					}
					// `new Foo(...)` always takes parens; keep parsing permissive in case upstream-ish code
					// contains partially-supported constructs.
					if (!cur.kind.match(TLParen)) {
						ENew(typePath, []);
					} else {
						bump(); // '('
						final args = new Array<HxExpr>();
						if (cur.kind.match(TRParen)) {
							bump();
							ENew(typePath, args);
						} else {
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
							ENew(typePath, args);
						}
					}
				} else {
					// Best-effort: capture the keyword as a string.
					final raw = keywordText(k);
					bump();
					EUnsupported(raw);
				}
			case TString(s):
				bump();
				parseInterpolatedStringExpr(s);
			case TInt(v):
				bump();
				EInt(v);
			case TFloat(v):
				bump();
				EFloat(v);
			case TIdent(name):
				bump();
				// Stage 3 bring-up: treat some uppercase-start identifiers as enum-like value
				// tags (e.g. `Macro`), but keep others as normal identifiers.
				//
				// Heuristic:
				// - If the next token is `.`, we assume this is a type/module prefix and keep `EIdent`.
				// - Otherwise, treat *TitleCase* names as enum-like tags (`EEnumValue`) so the emitter
				//   can lower them without requiring a real enum runtime/type model.
				// - Treat ALL_CAPS constants (e.g. `TRIALS`, `UTF8`) as identifiers so arithmetic and
				//   comparisons don't accidentally become string operations.
				//
				// Note
				// - This is intentionally imperfect. It's a pragmatic bring-up choice to keep upstream
				//   harnesses compiling, not a full typing model.
				function hasLowerAlpha(s:String):Bool {
					if (s == null)
						return false;
					for (i in 0...s.length) {
						final c = s.charCodeAt(i);
						if (c >= "a".code && c <= "z".code)
							return true;
					}
					return false;
				}
				(isUpperStart(name) && !cur.kind.match(TDot) && hasLowerAlpha(name)) ? EEnumValue(name) : EIdent(name);
			case TOther(c) if (c == "[".code):
				parseArrayDeclExpr();
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

	function parseInterpolatedStringExpr(s:String):HxExpr {
		// String interpolation (bring-up subset):
		// - `$ident`
		// - `${ident}`
		//
		// Why
		// - Upstream harness code (RunCi) uses both forms (e.g. `'test ${test} failed'`).
		// - If we keep the `$...` text literal, programs still compile but their control-flow
		//   diagnostics become misleading, which hurts Gate bring-up.
		if (s == null)
			return EString("");
		if (s.indexOf("$") == -1)
			return EString(s);

		function isIdentStart(c:Int):Bool {
			return (c >= "A".code && c <= "Z".code) || (c >= "a".code && c <= "z".code) || c == "_".code;
		}
		function isIdentCont(c:Int):Bool {
			return isIdentStart(c) || (c >= "0".code && c <= "9".code);
		}
		function isSimpleIdent(text:String):Bool {
			if (text == null || text.length == 0)
				return false;
			if (!isIdentStart(text.charCodeAt(0)))
				return false;
			for (i in 1...text.length)
				if (!isIdentCont(text.charCodeAt(i)))
					return false;
			return true;
		}

		final parts = new Array<HxExpr>();
		var buf = new StringBuf();

		inline function stringifyIdentExpr(name:String):HxExpr {
			// Avoid emitting `Std.string(...)` in the bootstrap AST.
			//
			// Why
			// - Stage3's bootstrap OCaml emitter does not provide a `Std` runtime module.
			// - Interpolated strings often flow through non-print contexts (e.g. passed as args),
			//   so they must lower without relying on a runtime `Std.string`.
			//
			// How
			// - Force a string-concat context via `"" + ident`. Our Stage3 emitter recognizes
			//   `+` with a string operand and lowers it to OCaml `^`, stringifying primitives
			//   on the other side as needed.
			return EBinop("+", EString(""), EIdent(name));
		}

		function flushBuf():Void {
			if (buf.length > 0) {
				parts.push(EString(buf.toString()));
				buf = new StringBuf();
			}
		}

		var i = 0;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c != "$".code) {
				buf.addChar(c);
				i++;
				continue;
			}

			// Escape `$` as `$$`.
			if (i + 1 < s.length && s.charCodeAt(i + 1) == "$".code) {
				buf.addChar("$".code);
				i += 2;
				continue;
			}

			flushBuf();

			// `${ident}` form.
			if (i + 1 < s.length && s.charCodeAt(i + 1) == "{".code) {
				final start = i + 2;
				var j = start;
				while (j < s.length && s.charCodeAt(j) != "}".code)
					j++;
				if (j < s.length && s.charCodeAt(j) == "}".code) {
					final inner = StringTools.trim(s.substr(start, j - start));
					if (isSimpleIdent(inner)) {
						parts.push(stringifyIdentExpr(inner));
						i = j + 1;
						continue;
					}
				}
				// Best-effort fallback: treat `$` as literal.
				buf.addChar("$".code);
				i++;
				continue;
			}

			// `$ident` form.
			final j0 = i + 1;
			if (j0 < s.length && isIdentStart(s.charCodeAt(j0))) {
				var j = j0 + 1;
				while (j < s.length && isIdentCont(s.charCodeAt(j)))
					j++;
				final name = s.substr(j0, j - j0);
				parts.push(stringifyIdentExpr(name));
				i = j;
				continue;
			}

			// Fallback: literal `$`.
			buf.addChar("$".code);
			i++;
		}

		flushBuf();
		if (parts.length == 0)
			return EString(s);

		// Fold into left-associative `+` concatenation.
		var out = parts[0];
		for (k in 1...parts.length)
			out = EBinop("+", out, parts[k]);
		return out;
	}

	function parseArrayDeclExpr():HxExpr {
		// `[e1, e2, ...]`
		//
		// Best-effort: if we don't find the closing `]`, return the partial list.
		if (!cur.kind.match(TOther("[".code)))
			return EArrayDecl([]);
		bump(); // '['
		// Array comprehension: `[for (name in iterable) expr]`
		//
		// This is required by upstream `tests/RunCi.hx` for computing the `tests` list.
		if (cur.kind.match(TKeyword(KFor))) {
			bump(); // `for`
			expect(TLParen, "'('");
			// Some code bases allow `for (var x in ...)` in comprehensions; accept `var`/`final` if present.
			acceptKeyword(KVar);
			acceptKeyword(KFinal);
			final name = readIdent("comprehension variable name");
			expect(TKeyword(KIn), "'in'");

			inline function isTripleDotStart():Bool {
				return cur.kind.match(TDot) && peekKind().match(TDot) && peekKind2().match(TDot);
			}

			// Match `for (i in start...end)` in comprehensions (same bring-up shape as statement for-in).
			final startExpr = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof) || isTripleDotStart());
			var iterable:HxExpr = startExpr;
			if (isTripleDotStart()) {
				expect(TDot, "'.'");
				expect(TDot, "'.'");
				expect(TDot, "'.'");
				final endExpr = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
				iterable = ERange(startExpr, endExpr);
			}

			expect(TRParen, "')'");
			final yieldExpr = parseExpr(() -> cur.kind.match(TOther("]".code)) || cur.kind.match(TEof));
			if (cur.kind.match(TOther("]".code)))
				bump();
			return EArrayComprehension(name, iterable, yieldExpr);
		}

		final values = new Array<HxExpr>();
		if (cur.kind.match(TOther("]".code))) {
			bump();
			return EArrayDecl(values);
		}
		while (!cur.kind.match(TEof)) {
			if (cur.kind.match(TOther("]".code))) {
				bump();
				break;
			}
			final value = parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TOther("]".code)) || cur.kind.match(TEof));
			values.push(value);
			if (cur.kind.match(TComma)) {
				bump();
				continue;
			}
			if (cur.kind.match(TOther("]".code))) {
				bump();
				break;
			}
			// Best-effort: skip to likely separators.
			while (!cur.kind.match(TComma) && !cur.kind.match(TOther("]".code)) && !cur.kind.match(TEof))
				bump();
			if (cur.kind.match(TComma)) {
				bump();
				continue;
			}
			if (cur.kind.match(TOther("]".code))) {
				bump();
				break;
			}
		}
		return EArrayDecl(values);
	}

	function parseAnonExpr():HxExpr {
		// `{ name: expr, ... }`
		//
		// Stage 3: parse a conservative subset (identifier keys + expressions).
		final names = new Array<String>();
		final values = new Array<HxExpr>();
		expect(TLBrace, "'{'");
		if (cur.kind.match(TRBrace)) {
			bump();
			return EAnon(names, values);
		}
		while (!cur.kind.match(TEof)) {
			if (cur.kind.match(TRBrace)) {
				bump();
				break;
			}
			final name = readIdent("field name");
			expect(TColon, "':'");
			final value = parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
			names.push(name);
			values.push(value);
			if (cur.kind.match(TComma)) {
				bump();
				continue;
			}
			if (cur.kind.match(TRBrace)) {
				bump();
				break;
			}
			// Best-effort: recover by skipping to a likely separator.
			while (!cur.kind.match(TComma) && !cur.kind.match(TRBrace) && !cur.kind.match(TEof))
				bump();
			if (cur.kind.match(TComma)) {
				bump();
				continue;
			}
			if (cur.kind.match(TRBrace)) {
				bump();
				break;
			}
		}
		return EAnon(names, values);
	}

	static function binopPrec(op:String):Int {
		return switch (op) {
			case "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "<<=" | ">>=" | ">>>=" | "&=" | "|=" | "^=": 1;
			case "?": 2;
			case "||": 2;
			case "|": 2;
			case "&&": 3;
			case "&": 3;
			case "^": 3;
			case "==" | "!=": 4;
			case "<<" | ">>" | ">>>": 5;
			case "<" | "<=" | ">" | ">=": 5;
			case "+" | "-": 6;
			case "*" | "/" | "%": 7;
			case _:
				0;
		}
	}

	static function isAssignmentBinop(op:String):Bool {
		return switch (op) {
			case "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "<<=" | ">>=" | ">>>=" | "&=" | "|=" | "^=":
				true;
			case _:
				false;
		}
	}

	static function isRightAssoc(op:String):Bool {
		return isAssignmentBinop(op);
	}

	function parsePostfixExpr(stop:() -> Bool):HxExpr {
		var e = parsePrimaryExpr();

		inline function isTripleDotAhead():Bool {
			return cur.kind.match(TDot) && peekKind().match(TDot) && peekKind2().match(TDot);
		}

		while (!stop()) {
			switch (cur.kind) {
				case TDot if (isTripleDotAhead()):
					// Expression-level range: `start...end`.
					//
					// Why
					// - For-in and comprehension parsers already special-case ranges, but plain expression
					//   forms like `var items = 1...5` should also parse and lower in js-native.
					// - Without this branch, the first dot is interpreted as field access and fails with
					//   “Expected field name”.
					bump();
					bump();
					bump();
					final right = parseExpr(() -> stop() || cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TRBrace)
						|| cur.kind.match(TSemicolon) || cur.kind.match(TEof) || cur.kind.match(TKeyword(KCase)) || cur.kind.match(TKeyword(KDefault))
						|| cur.kind.match(TOther("]".code)));
					e = ERange(e, right);
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
				case TOther(c) if (c == "[".code):
					// Array access: `e[index]`.
					bump(); // '['
					final index = parseExpr(() -> cur.kind.match(TOther("]".code)) || cur.kind.match(TEof));
					// Best-effort: resync to closing bracket.
					if (!cur.kind.match(TOther("]".code))) {
						while (!cur.kind.match(TOther("]".code)) && !cur.kind.match(TEof))
							bump();
					}
					if (cur.kind.match(TOther("]".code)))
						bump();
					e = EArrayAccess(e, index);
				case TOther(c) if ((c == "+".code || c == "-".code) && nextIsAdjacentOther(c)):
					// Bring-up lowering: treat postfix increment/decrement as compound assignment.
					//
					// Scope
					// - This intentionally models statement-style usage (`i++`, `i--`) used in loops.
					// - Expression-level old/new value distinction is deferred.
					final op = (c == "+".code) ? "+=" : "-=";
					bump();
					bump();
					e = EBinop(op, e, EInt(1));
				case _:
					break;
			}
		}
		return e;
	}

	function parseUnaryExpr(stop:() -> Bool):HxExpr {
		return switch (cur.kind) {
			case TOther("@".code):
				// Expression-level metadata: `@:meta expr`.
				//
				// Bring-up semantics: ignore metadata and return the underlying expression.
				while (cur.kind.match(TOther("@".code))) {
					bump();
					if (cur.kind.match(TColon))
						bump();
					switch (cur.kind) {
						case TIdent(_), TKeyword(_):
							bump();
						case _:
					}
					if (cur.kind.match(TLParen)) {
						bump();
						try
							skipBalancedParens()
						catch (_:HxParseError) {}
					}
				}
				parseUnaryExpr(stop);
			case TKeyword(k) if (k == KCast):
				bump();
				// `cast expr` or `cast(expr, Type)`
				if (cur.kind.match(TLParen)) {
					bump();
					final inner = parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof));
					var hint = "";
					if (cur.kind.match(TComma)) {
						bump();
						hint = readTypeHintText(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
					}
					// Best-effort: resync to closing `)`.
					if (!cur.kind.match(TRParen)) {
						while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
							bump();
					}
					if (cur.kind.match(TRParen))
						bump();
					ECast(inner, hint);
				} else {
					ECast(parseUnaryExpr(stop), "");
				}
			case TKeyword(k) if (k == KUntyped):
				bump();
				EUntyped(parseUnaryExpr(stop));
			case TOther(c) if ((c == "+".code || c == "-".code) && nextIsAdjacentOther(c)):
				// Bring-up lowering: treat prefix increment/decrement as compound assignment.
				//
				// Scope
				// - This intentionally models loop-style usage (`++i`, `--i`) needed by js-native.
				// - Expression-level old/new value distinction is deferred.
				final op = (c == "+".code) ? "+=" : "-=";
				bump();
				bump();
				EBinop(op, parseUnaryExpr(stop), EInt(1));
			case TOther(c) if (c == "!".code || c == "-".code || c == "+".code):
				final op = String.fromCharCode(c);
				bump();
				EUnop(op, parseUnaryExpr(stop));
			case _:
				parsePostfixExpr(stop);
		}
	}

	function peekBinop(stop:() -> Bool):Null<{op:String, len:Int}> {
		if (stop())
			return null;
		inline function nextIsOther(code:Int):Bool {
			return switch (peekKind()) {
				case TOther(c) if (c == code):
					true;
				case _:
					false;
			}
		}
		inline function next2IsOther(code:Int):Bool {
			return switch (peekKind2()) {
				case TOther(c) if (c == code):
					true;
				case _:
					false;
			}
		}
		inline function next3IsOther(code:Int):Bool {
			return switch (peekKind3()) {
				case TOther(c) if (c == code):
					true;
				case _:
					false;
			}
		}
		return switch (cur.kind) {
			case TOther(c):
				switch (c) {
					case "=".code:
						nextIsOther("=".code) ? {op: "==", len: 2} : {op: "=", len: 1};
					case "!".code:
						nextIsOther("=".code) ? {op: "!=", len: 2} : null;
					case "<".code:
						if (nextIsOther("<".code)) {
							next2IsOther("=".code) ? {op: "<<=", len: 3} : {op: "<<", len: 2};
						} else {
							nextIsOther("=".code) ? {op: "<=", len: 2} : {op: "<", len: 1};
						}
					case ">".code:
						if (nextIsOther(">".code)) {
							if (next2IsOther(">".code)) {
								next3IsOther("=".code) ? {op: ">>>=", len: 4} : {op: ">>>", len: 3};
							} else {
								next2IsOther("=".code) ? {op: ">>=", len: 3} : {op: ">>", len: 2};
							}
						} else {
							nextIsOther("=".code) ? {op: ">=", len: 2} : {op: ">", len: 1};
						}
					case "&".code:
						if (nextIsOther("&".code)) {
							{op: "&&", len: 2};
						} else {
							nextIsOther("=".code) ? {op: "&=", len: 2} : {op: "&", len: 1};
						}
					case "|".code:
						if (nextIsOther("|".code)) {
							{op: "||", len: 2};
						} else {
							nextIsOther("=".code) ? {op: "|=", len: 2} : {op: "|", len: 1};
						}
					case "^".code:
						nextIsOther("=".code) ? {op: "^=", len: 2} : {op: "^", len: 1};
					case "+".code:
						nextIsOther("=".code) ? {op: "+=", len: 2} : {op: "+", len: 1};
					case "-".code:
						nextIsOther("=".code) ? {op: "-=", len: 2} : {op: "-", len: 1};
					case "*".code:
						nextIsOther("=".code) ? {op: "*=", len: 2} : {op: "*", len: 1};
					case "/".code:
						nextIsOther("=".code) ? {op: "/=", len: 2} : {op: "/", len: 1};
					case "%".code:
						nextIsOther("=".code) ? {op: "%=", len: 2} : {op: "%", len: 1};
					case _:
						null;
				}
			case _:
				null;
		}
	}

	function consumeBinop(len:Int):Void {
		for (_ in 0...len)
			bump();
	}

	function parseBinaryExpr(minPrec:Int, stop:() -> Bool):HxExpr {
		var left = parseUnaryExpr(stop);

		while (true) {
			if (stop())
				break;
			final peekedOp = peekBinop(stop);
			if (peekedOp == null) {
				break;
			}
			final op = peekedOp.op;
			final prec = binopPrec(op);
			if (prec < minPrec || prec == 0) {
				break;
			}

			consumeBinop(peekedOp.len);
			final nextMin = isRightAssoc(op) ? prec : (prec + 1);
			final right = parseBinaryExpr(nextMin, stop);
			left = EBinop(op, left, right);
		}

		return left;
	}

	function parseExpr(stop:() -> Bool):HxExpr {
		// Stage 3: small-but-real expression subset.
		// Includes calls/field access, prefix unary, and basic binary ops with precedence.
		// Stage 3 expansion: arrow-function expressions (`arg -> expr`).
		//
		// Why
		// - Upstream-ish code uses this pervasively for small callbacks.
		// - If we don't recognize it, the `-` token is misclassified as a binary op and the
		//   parser drifts into `EUnsupported("->")` placeholders.
		//
		// Bring-up scope
		// - Only supports the simplest form: a single identifier parameter.
		// - More complex forms (`(a, b) -> ...`, blocks, pattern args) are future work.
		if (!stop()) {
			switch (cur.kind) {
				case TIdent(name):
					if (peekKind().match(TOther("-".code)) && peekKind2().match(TOther(">".code))) {
						// Consume `name ->`.
						bump(); // ident
						bump(); // '-'
						bump(); // '>'
						final body = parseExpr(stop);
						return ELambda([name], body);
					}
				case _:
			}
		}

		// Stage 3 expansion: `try { ... } catch(...) { ... }` as an *expression*.
		//
		// Why
		// - Upstream code uses `try` in expression position (e.g. `var x = try { ... } catch ...;`).
		// - Treating `try` as unsupported causes the parser to drift early in otherwise parseable
		//   bodies, which then shows up as noisy `unsupported_exprs_total` in Gate2 diagnostics.
		//
		// Bring-up scope
		// - Only supports block-form try bodies and catch bodies:
		//     `try { <stmts> } catch(e:Dynamic) { <stmts> }`
		// - Does not yet support `try expr catch ...` or multiple catches with advanced patterns.
		if (!stop() && cur.kind.match(TKeyword(KTry))) {
			return parseTryCatchExpr(stop);
		}

		// Stage 3 expansion: `switch (...) { ... }` as an *expression*.
		//
		// Why
		// - Upstream orchestration code uses `switch` to compute values (e.g. choose targets).
		// - Gate2’s Stage3 emit-runner needs real switch control-flow to execute the upstream
		//   RunCi harness unmodified (no patching).
		//
		// Bring-up scope
		// - We implement only a small subset of patterns/case bodies (see `HxSwitchPattern`).
		if (!stop() && cur.kind.match(TKeyword(KSwitch))) {
			return parseSwitchExpr(stop);
		}

		// Stage 3 expansion: `if (cond) thenExpr else elseExpr` as an *expression*.
		//
		// Why
		// - Upstream harness code uses `static final X = if (...) ... else ...;` patterns
		//   (notably in runci/Config.hx and runci/System.hx).
		// - Without parsing this shape, class-scope constants fall back to `EUnsupported`,
		//   which forces the Stage3 emitter to collapse the value to bring-up poison.
		//
		// Bring-up scope
		// - Branches are expressions (not statement blocks).
		// - Missing `else` is treated as unsupported.
		if (!stop() && cur.kind.match(TKeyword(KIf))) {
			bump(); // `if`
			expect(TLParen, "'('");
			final cond = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
			// Best-effort resync to `)`.
			if (!cur.kind.match(TRParen)) {
				while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
					bump();
			}
			if (cur.kind.match(TRParen))
				bump();

			final thenExpr = parseExpr(() -> cur.kind.match(TKeyword(KElse)) || cur.kind.match(TEof));
			if (!acceptKeyword(KElse))
				return EUnsupported("if_missing_else");
			final elseExpr = parseExpr(stop);
			return ETernary(cond, thenExpr, elseExpr);
		}

		var e = parseBinaryExpr(1, stop);
		// Ternary conditional: `cond ? thenExpr : elseExpr`
		if (!stop() && acceptOtherChar("?")) {
			final thenExpr = parseExpr(() -> cur.kind.match(TColon) || cur.kind.match(TEof));
			expect(TColon, "':'");
			final elseExpr = parseExpr(stop);
			// Precedence fix (bring-up):
			// In `a = cond ? x : y`, the ternary binds to the *right-hand side* of the assignment.
			// Our parser handles `?:` after binary parsing, so we patch up this common shape here.
			e = switch (e) {
				case EBinop(op, left, right) if (isAssignmentBinop(op)):
					EBinop(op, left, ETernary(right, thenExpr, elseExpr));
				case _:
					ETernary(e, thenExpr, elseExpr);
			}
		}
		return e;
	}

	function parseSwitchExpr(stop:() -> Bool):HxExpr {
		// `switch (<expr>) { case <pat>: <expr>; ... }` or `switch <expr> { ... }`
		//
		// Bring-up semantics:
		// - Parse a small, structured subset so Stage3’s bootstrap emitter can execute
		//   harness-style programs (notably upstream RunCi).
		// - Keep parsing resilient: if we encounter unexpected shapes, we still consume
		//   balanced braces so later statements remain parseable.
		if (!cur.kind.match(TKeyword(KSwitch)))
			return EUnsupported("switch");

		bump(); // `switch`

		// Upstream-style code commonly omits the parentheses:
		//   switch Sys.systemName() { ... }
		// Haxe accepts this, so Stage3 bring-up must too.
		var scrutinee:HxExpr;
		if (cur.kind.match(TLParen)) {
			bump(); // '('
			scrutinee = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
			// Best-effort resync to `)`.
			if (!cur.kind.match(TRParen)) {
				while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
					bump();
			}
			if (cur.kind.match(TRParen))
				bump();
		} else {
			// Parse until the opening brace starts the switch block.
			scrutinee = parseExpr(() -> cur.kind.match(TLBrace) || cur.kind.match(TEof));
		}

		// `{ <cases> }`
		if (!cur.kind.match(TLBrace)) {
			// Nothing more to consume deterministically.
			return ESwitch(scrutinee, []);
		}
		bump(); // '{'

		final cases = new Array<{pattern:HxSwitchPattern, expr:HxExpr}>();
		while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof) && !stop()) {
			final pat:HxSwitchPattern = if (acceptKeyword(KCase)) {
				parseSwitchPattern();
			} else if (acceptKeyword(KDefault)) {
				// Haxe: `default:` (no pattern). Bring-up: treat as wildcard.
				PWildcard;
			} else {
				// Bring-up: skip unknown tokens until we find `case` or `}`.
				bump();
				continue;
			}
			expect(TColon, "':'");
			// Case body as a single expression; stop before the next `case`/`}`.
			final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof) || cur.kind.match(TKeyword(KCase))
				|| cur.kind.match(TKeyword(KDefault)));
			if (cur.kind.match(TSemicolon))
				bump();
			cases.push({pattern: pat, expr: expr});
		}
		if (cur.kind.match(TRBrace))
			bump();

		return ESwitch(scrutinee, cases);
	}

	function parseTryCatchExpr(stop:() -> Bool):HxExpr {
		// `try { ... } catch(name[:Type]) { ... } ...`
		//
		// IMPORTANT (OCaml bootstrap constraints)
		// - We intentionally do **not** parse try/catch blocks into `HxStmt` lists yet.
		// - Having `HxExpr` reference `HxStmt` creates an OCaml module dependency cycle
		//   in the Stage3 bootstrap snapshot (`HxStmt` already references `HxExpr`).
		//
		// Instead, we capture a canonical, token-based rendering of the entire expression.
		// This keeps Stage3 parsing deterministic and avoids `EUnsupported("try")` drift in Gate2
		// diagnostics, while deferring real semantics to later stages.

		if (!cur.kind.match(TKeyword(KTry)))
			return EUnsupported("try");

		final raw = new StringBuf();

		inline function tokText():String {
			return switch (cur.kind) {
				case TIdent(name):
					name;
				case TKeyword(k):
					keywordText(k);
				case TString(s):
					"\"" + s + "\"";
				case TInt(v):
					Std.string(v);
				case TFloat(v):
					Std.string(v);
				case TLParen:
					"(";
				case TRParen:
					")";
				case TLBrace:
					"{";
				case TRBrace:
					"}";
				case TSemicolon:
					";";
				case TColon:
					":";
				case TDot:
					".";
				case TComma:
					",";
				case TOther(c):
					String.fromCharCode(c);
				case TEof:
					"";
			};
		}

		function consumeBalancedBraces():Void {
			expect(TLBrace, "'{'");
			raw.add("{");
			var depth = 1;
			// IMPORTANT
			// - Do not use the outer `stop()` predicate here.
			// - Callers often pass `stop` functions that return true on `}` (statement boundaries),
			//   which would prematurely terminate brace consumption inside `try { ... }`.
			while (depth > 0) {
				switch (cur.kind) {
					case TEof:
						break;
					case TLBrace:
						raw.add("{");
						bump();
						depth++;
					case TRBrace:
						raw.add("}");
						bump();
						depth--;
					case _:
						raw.add(tokText());
						bump();
				}
			}
		}

		function consumeBalancedParens():Void {
			expect(TLParen, "'('");
			raw.add("(");
			var depth = 1;
			// Same rationale as `consumeBalancedBraces`: ignore the outer `stop()` predicate
			// so we can consume nested parentheses deterministically.
			while (depth > 0) {
				switch (cur.kind) {
					case TEof:
						break;
					case TLParen:
						raw.add("(");
						bump();
						depth++;
					case TRParen:
						raw.add(")");
						bump();
						depth--;
					case _:
						raw.add(tokText());
						bump();
				}
			}
		}

		// `try`
		raw.add("try");
		bump();

		// `{ ... }`
		if (!cur.kind.match(TLBrace))
			return EUnsupported("try_missing_block");
		consumeBalancedBraces();

		// One or more `catch (...) { ... }`.
		while (!stop() && cur.kind.match(TKeyword(KCatch))) {
			raw.add("catch");
			bump();
			consumeBalancedParens();
			if (!cur.kind.match(TLBrace)) {
				// Bring-up: malformed catch; stop consuming so outer parsing can recover.
				break;
			}
			consumeBalancedBraces();
		}

		return ETryCatchRaw(raw.toString());
	}

	function parseReturnStmt(pos:HxPos):HxStmt {
		// `return;` or `return <expr>;`
		if (cur.kind.match(TSemicolon)) {
			bump();
			return SReturnVoid(pos);
		}
		if (cur.kind.match(TRBrace)) {
			return SReturnVoid(pos);
		}

		// Stage 3 expansion: lower `return if (cond) { expr } else { expr }` into a statement-level
		// `if` with explicit returns in each branch.
		//
		// Why
		// - Upstream-ish code (e.g. utest) uses `return if (...) ... else ...` heavily.
		// - Our expression parser doesn't model `if`-expressions yet, but we can preserve
		//   semantics at the statement layer for bring-up typing.
		if (cur.kind.match(TKeyword(KIf))) {
			bump(); // 'if'
			expect(TLParen, "'('");
			final cond = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
			// Best-effort: if our expression parser stopped early, resync to the closing `)`.
			if (!cur.kind.match(TRParen)) {
				while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
					bump();
			}
			if (cur.kind.match(TRParen))
				bump();

			function ensureBranchReturns(s:HxStmt):HxStmt {
				return switch (s) {
					case SReturn(_, _) | SReturnVoid(_):
						s;
					case SExpr(e, p):
						SReturn(e, p);
					case SBlock(stmts, p):
						if (stmts.length == 0) {
							SBlock([SReturnVoid(p)], p);
						} else {
							final last = stmts[stmts.length - 1];
							switch (last) {
								case SReturn(_, _) | SReturnVoid(_):
									s;
								case SExpr(e, lp):
									final copy = stmts.copy();
									copy[copy.length - 1] = SReturn(e, lp);
									SBlock(copy, p);
								case _:
									final copy = stmts.copy();
									copy.push(SReturnVoid(p));
									SBlock(copy, p);
							}
						}
					case _:
						SBlock([s, SReturnVoid(pos)], pos);
				}
			}

			final thenBranch = ensureBranchReturns(parseStmt(() -> cur.kind.match(TEof)));
			if (!acceptKeyword(KElse)) {
				// Be permissive: missing else branch. Treat as a void return.
				//
				// Implementation detail:
				// Our OCaml backend represents `Null<T>` as `Obj.t` for many `T`s (including enums),
				// which means passing a non-null enum value directly can cause an OCaml type error.
				// This `true ? v : null` trick forces the value through the nullable path so the
				// generated OCaml uses `Obj.repr`.
				final elseBranch:Null<HxStmt> = true ? SReturnVoid(pos) : null;
				return SIf(cond, thenBranch, elseBranch, pos);
			}
			final elseBranch:Null<HxStmt> = true ? ensureBranchReturns(parseStmt(() -> cur.kind.match(TEof))) : null;
			return SIf(cond, thenBranch, elseBranch, pos);
		}

		if (capturedReturnStringLiteral.length == 0) {
			switch (cur.kind) {
				case TString(s):
					capturedReturnStringLiteral = s;
				case _:
			}
		}

		final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
		syncToStmtEnd();
		return SReturn(expr, pos);
	}

	function syncToStmtEnd():Void {
		// Best-effort resynchronization for statements.
		//
		// Why
		// - Our expression grammar is intentionally incomplete; it may stop before `;`.
		// - If we don't advance to the end of the statement, parsing can get stuck on
		//   the same token forever.
		while (!cur.kind.match(TSemicolon) && !cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
			switch (cur.kind) {
				case TLParen:
					bump();
					skipBalancedParens();
				case TLBrace:
					// Caller handles braces explicitly.
					return;
				case _:
					bump();
			}
		}
		if (cur.kind.match(TSemicolon))
			bump();
	}

	function parseVarStmt(pos:HxPos):HxStmt {
		// `var name[:Type] [= expr];`
		final name = readIdent("variable name");
		var typeHint = "";
		if (cur.kind.match(TColon)) {
			bump();
			typeHint = readTypeHintText(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof) || isOtherChar("="));
		}

		var init:Null<HxExpr> = null;
		if (acceptOtherChar("=")) {
			init = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof) || cur.kind.match(TRBrace));
		}
		syncToStmtEnd();
		return SVar(name, typeHint, init, pos);
	}

	function parseStmt(stop:() -> Bool):HxStmt {
		if (stop())
			return SExpr(EUnsupported("<eof-stmt>"), HxPos.unknown());

		final pos = cur.pos;
		return switch (cur.kind) {
			case TLBrace:
				bump();
				final ss = new Array<HxStmt>();
				while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
					ss.push(parseStmt(() -> cur.kind.match(TRBrace) || cur.kind.match(TEof)));
				}
				expect(TRBrace, "'}'");
				SBlock(ss, pos);
			case TKeyword(KReturn):
				bump();
				parseReturnStmt(pos);
			case TKeyword(KVar):
				bump();
				parseVarStmt(pos);
			case TKeyword(KFinal):
				// Stage 3 bring-up: treat `final name = expr;` like `var` for local binding purposes.
				//
				// Why
				// - Upstream harness code (RunCi) and helpers use `final` pervasively.
				// - If we don't bind the name, subsequent references become "unbound" and the emitter
				//   collapses control-flow to bring-up poison.
				bump();
				parseVarStmt(pos);
			case TKeyword(KIf):
				bump();
				expect(TLParen, "'('");
				final cond = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
				if (!cur.kind.match(TRParen)) {
					while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
						bump();
				}
				if (cur.kind.match(TRParen))
					bump();
				final thenBranch = parseStmt(stop);
				final elseBranch:Null<HxStmt> = if (acceptKeyword(KElse)) {
					// Keep nullable enum branches on the explicit `Null<T>` path so stage0 OCaml
					// generation keeps representation coercions consistent.
					true ? parseStmt(stop) : null;
				} else {
					null;
				}
				SIf(cond, thenBranch, elseBranch, pos);
			case TKeyword(KSwitch):
				// Bring-up: structured switch statement (minimal patterns).
				bump(); // `switch`
				// Upstream-style code commonly omits the parentheses:
				//   switch Sys.systemName() { ... }
				// Haxe accepts this, so Stage3 bring-up must too.
				final scrutinee = if (cur.kind.match(TLParen)) {
					bump(); // '('
					final e = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
					if (!cur.kind.match(TRParen)) {
						while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
							bump();
					}
					if (cur.kind.match(TRParen))
						bump();
					e;
				} else {
					parseExpr(() -> cur.kind.match(TLBrace) || cur.kind.match(TEof));
				};

				if (!cur.kind.match(TLBrace)) {
					syncToStmtEnd();
					SSwitch(scrutinee, [], pos);
				} else {
					bump(); // '{'
					final cases = new Array<{pattern:HxSwitchPattern, body:HxStmt}>();
					while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
						final pat:HxSwitchPattern = if (acceptKeyword(KCase)) {
							parseSwitchPattern();
						} else if (acceptKeyword(KDefault)) {
							PWildcard;
						} else {
							bump();
							continue;
						}
						expect(TColon, "':'");

						final stmts = new Array<HxStmt>();
						while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof) && !cur.kind.match(TKeyword(KCase)) && !cur.kind.match(TKeyword(KDefault))) {
							stmts.push(parseStmt(() -> cur.kind.match(TRBrace) || cur.kind.match(TEof) || cur.kind.match(TKeyword(KCase))
								|| cur.kind.match(TKeyword(KDefault))));
						}
						cases.push({pattern: pat, body: SBlock(stmts, pos)});
					}
					if (cur.kind.match(TRBrace))
						bump();
					SSwitch(scrutinee, cases, pos);
				}
			case TOther("@".code):
				// Expression-level metadata: `@:meta expr`.
				//
				// Why
				// - Upstream macro-heavy code uses e.g. `@:privateAccess foo.bar`.
				// - Treating `@` as an unsupported expression creates noisy Gate2 diagnostics and can
				//   lead to token drift when metadata appears in statement position.
				//
				// Bring-up semantics
				// - We ignore metadata and parse the following statement/expression.
				while (cur.kind.match(TOther("@".code))) {
					bump();
					// Optional `:` in `@:meta`.
					if (cur.kind.match(TColon))
						bump();
					// Meta name.
					switch (cur.kind) {
						case TIdent(_):
							bump();
						case TKeyword(_):
							// Some meta-like tokens are keywords in our lexer; accept them best-effort.
							bump();
						case _:
					}
					// Optional meta args: `@:meta(...)`.
					if (cur.kind.match(TLParen)) {
						bump();
						try
							skipBalancedParens()
						catch (_:HxParseError) {}
					}
				}
				// Parse the following statement now that metadata is consumed.
				parseStmt(stop);
			case TKeyword(KTry):
				bump();

				final tryBody:HxStmt = if (cur.kind.match(TLBrace)) {
					bump();
					final stmts = new Array<HxStmt>();
					while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
						stmts.push(parseStmt(() -> cur.kind.match(TRBrace) || cur.kind.match(TEof)));
					}
					if (cur.kind.match(TRBrace))
						bump();
					SBlock(stmts, pos);
				} else {
					// Best-effort: allow a single-statement try body even though upstream-style
					// harnesses always use the block form.
					parseStmt(stop);
				};

				final catches = new Array<{name:String, typeHint:String, body:HxStmt}>();
				while (acceptKeyword(KCatch)) {
					var catchName = "e";
					var catchTypeHint = "";
					if (cur.kind.match(TLParen)) {
						bump();
						switch (cur.kind) {
							case TIdent(_):
								catchName = readIdent("catch variable name");
							case _:
								// Best-effort fallback for malformed catch signatures.
						}
						if (cur.kind.match(TColon)) {
							bump();
							catchTypeHint = readTypeHintText(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
						}
						if (!cur.kind.match(TRParen)) {
							while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
								bump();
						}
						if (cur.kind.match(TRParen))
							bump();
					}
					final catchBody:HxStmt = if (cur.kind.match(TLBrace)) {
						bump();
						final stmts = new Array<HxStmt>();
						while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
							stmts.push(parseStmt(() -> cur.kind.match(TRBrace) || cur.kind.match(TEof)));
						}
						if (cur.kind.match(TRBrace))
							bump();
						SBlock(stmts, pos);
					} else {
						parseStmt(stop);
					};
					catches.push({name: catchName, typeHint: catchTypeHint, body: catchBody});
				}

				STry(tryBody, catches, pos);
			case TKeyword(KWhile):
				// Stage 3 bring-up: structured while loop support.
				bump(); // `while`
				if (!cur.kind.match(TLParen)) {
					syncToStmtEnd();
					return SExpr(EUnsupported("while"), pos);
				}
				bump(); // '('
				final cond = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
				if (!cur.kind.match(TRParen)) {
					while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
						bump();
				}
				if (cur.kind.match(TRParen))
					bump();
				final body = parseStmt(stop);
				SWhile(cond, body, pos);
			case TKeyword(KFor):
				// Stage 3 bring-up: support the Haxe `for (name in iterable) stmt` form.
				//
				// Why
				// - This is the dominant loop form in upstream test harness code.
				// - Even without a full iterator model, we can model the two most common iterables:
				//   - ranges: `start...end`
				//   - arrays: `[ ... ]` / local arrays
				//
				// Non-goal
				// - C-style `for (init; cond; step)` loops (deferred).
				bump();

				if (!cur.kind.match(TLParen)) {
					syncToStmtEnd();
					return SExpr(EUnsupported("for"), pos);
				}
				bump(); // consume '('

				// Detect and reject C-style `for` early (we keep parsing resilient).
				if (cur.kind.match(TSemicolon) || cur.kind.match(TKeyword(KVar))) {
					try
						skipBalancedParens()
					catch (_:HxParseError) {}
					if (cur.kind.match(TLBrace)) {
						bump();
						try
							skipBalancedBraces()
						catch (_:HxParseError) {}
					} else {
						parseStmt(stop);
					}
					return SExpr(EUnsupported("for"), pos);
				}

				final name = readIdent("for-in loop variable");
				if (!acceptKeyword(KIn)) {
					// Not a `for-in` loop (future work). Consume the remainder best-effort.
					try
						skipBalancedParens()
					catch (_:HxParseError) {}
					if (cur.kind.match(TLBrace)) {
						bump();
						try
							skipBalancedBraces()
						catch (_:HxParseError) {}
					} else {
						parseStmt(stop);
					}
					return SExpr(EUnsupported("for"), pos);
				}

				inline function isTripleDotStart():Bool {
					return cur.kind.match(TDot) && peekKind().match(TDot) && peekKind2().match(TDot);
				}

				// Parse the iterable with a tiny special-case for `start...end` ranges.
				final startExpr = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof) || isTripleDotStart());
				var iterable:HxExpr = startExpr;
				if (isTripleDotStart()) {
					expect(TDot, "'.'");
					expect(TDot, "'.'");
					expect(TDot, "'.'");
					final endExpr = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
					iterable = ERange(startExpr, endExpr);
				}

				// Consume ')', keeping behavior aligned with other bring-up branches.
				if (!cur.kind.match(TRParen)) {
					while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
						bump();
				}
				if (cur.kind.match(TRParen))
					bump();

				final body = parseStmt(stop);
				SForIn(name, iterable, body, pos);
			case TKeyword(KDo):
				// Stage 3 bring-up: structured do/while support.
				bump(); // `do`
				final body = parseStmt(stop);
				if (!acceptKeyword(KWhile)) {
					syncToStmtEnd();
					return SExpr(EUnsupported("do"), pos);
				}
				if (!cur.kind.match(TLParen)) {
					syncToStmtEnd();
					return SExpr(EUnsupported("do"), pos);
				}
				bump(); // '('
				final cond = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
				if (!cur.kind.match(TRParen)) {
					while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
						bump();
				}
				if (cur.kind.match(TRParen))
					bump();
				syncToStmtEnd();
				SDoWhile(body, cond, pos);
			case TKeyword(KThrow):
				bump();
				final thrown = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
				syncToStmtEnd();
				SThrow(thrown, pos);
			case TKeyword(KBreak):
				bump();
				syncToStmtEnd();
				SBreak(pos);
			case TKeyword(KContinue):
				bump();
				syncToStmtEnd();
				SContinue(pos);
			case _:
				final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
				syncToStmtEnd();
				SExpr(expr, pos);
		}
	}

	function parseFunctionBodyStatements():Array<HxStmt> {
		// Called after consuming '{' (function body open brace).
		final out = new Array<HxStmt>();
		while (true) {
			switch (cur.kind) {
				case TEof:
					fail("Unterminated function body");
				case TRBrace:
					bump();
					return out;
				case _:
					out.push(parseStmt(() -> cur.kind.match(TRBrace) || cur.kind.match(TEof)));
			}
		}
	}

	function parseFunctionBodyStatementsBestEffort():Array<HxStmt> {
		// Like `parseFunctionBodyStatements`, but never throws.
		//
		// Why
		// - The native frontend protocol transmits method bodies as raw source slices.
		// - Our statement/expression grammar is still incomplete; we want to recover as much
		//   structure as possible without hard-failing the whole module.
		//
		// How
		// - Parse statement-by-statement.
		// - On parse errors, resynchronize to `;` / `}` / EOF and continue.
		final out = new Array<HxStmt>();
		inline function curTokLabel():String {
			return switch (cur.kind) {
				case TEof: "eof";
				case TLBrace: "{";
				case TRBrace: "}";
				case TLParen: "(";
				case TRParen: ")";
				case TSemicolon: ";";
				case TColon: ":";
				case TDot: ".";
				case TComma: ",";
				case TIdent(name): "ident(" + name + ")";
				case TString(_): "string";
				case TInt(_): "int";
				case TFloat(_): "float";
				case TKeyword(k): "kw(" + keywordText(k) + ")";
				case TOther(c): "other(" + String.fromCharCode(c) + ")";
			};
		}
		inline function isWrapperCloseBrace():Bool {
			return cur.kind.match(TRBrace) && peekKind().match(TEof);
		}
		while (true) {
			switch (cur.kind) {
				case TEof:
					return out;
				case TRBrace:
					// Important: method bodies can contain nested blocks, so a stray `}` may appear
					// at top-level if we failed to parse a construct that contains braces.
					//
					// Our wrapper source is always:
					//   "{\n" + body + "\n}"
					// so the *real* end-of-body brace is the one immediately followed by TEof.
					if (isWrapperCloseBrace()) {
						bump();
						return out;
					}
					// Stray brace: consume it and continue so we don't silently truncate the body.
					bump();
					out.push(SExpr(EUnsupported("stray_rbrace"), HxPos.unknown()));
				case _:
					try {
						out.push(parseStmt(() -> cur.kind.match(TRBrace) || cur.kind.match(TEof)));
						0; // ensure try/catch has a concrete, consistent expression type across targets
					} catch (_:HxParseError) {
						if (Sys.getEnv("HXHX_TRACE_BODY_STMT_PARSE_ERROR") == "1") {
							try {
								final lbl = debugBodyLabel == null || debugBodyLabel.length == 0 ? "<unknown>" : debugBodyLabel;
								Sys.println("body_stmt_parse_error fn=" + lbl + " tok=" + curTokLabel());
							} catch (_:haxe.io.Error) {} catch (_:String) {}
						}
						// Surface that we hit a parse hole so later stages can diagnose why a body is partial.
						out.push(SExpr(EUnsupported("body_parse_error"), HxPos.unknown()));

						// Best-effort resync: advance until a plausible statement boundary.
						while (true) {
							switch (cur.kind) {
								case TEof:
									break;
								case TSemicolon:
									bump();
									break;
								case TRBrace:
									// Only treat the wrapper close brace as "end of body".
									if (isWrapperCloseBrace()) {
										break;
									}
									// Otherwise, consume and keep scanning.
									bump();
								case _:
									bump();
							}
						}
						0;
					} catch (_:String) {
						if (Sys.getEnv("HXHX_TRACE_BODY_STMT_PARSE_ERROR") == "1") {
							try {
								final lbl = debugBodyLabel == null || debugBodyLabel.length == 0 ? "<unknown>" : debugBodyLabel;
								Sys.println("body_stmt_parse_error fn=" + lbl + " tok=" + curTokLabel());
							} catch (_:haxe.io.Error) {} catch (_:String) {}
						}
						// Surface that we hit a parse hole so later stages can diagnose why a body is partial.
						out.push(SExpr(EUnsupported("body_parse_error"), HxPos.unknown()));

						// Best-effort resync: advance until a plausible statement boundary.
						while (true) {
							switch (cur.kind) {
								case TEof:
									break;
								case TSemicolon:
									bump();
									break;
								case TRBrace:
									// Only treat the wrapper close brace as "end of body".
									if (isWrapperCloseBrace()) {
										break;
									}
									// Otherwise, consume and keep scanning.
									bump();
								case _:
									bump();
							}
						}
						0;
					}
			}
		}
	}

	function parseFunctionDecl(visibility:HxVisibility, isStatic:Bool):HxFunctionDecl {
		capturedReturnStringLiteral = "";
		final name = switch (cur.kind) {
			case TKeyword(KNew):
				bump();
				"new";
			case _:
				readIdent("function name");
		}
		expect(TLParen, "'('");

		final args = new Array<HxFunctionArg>();
		if (!cur.kind.match(TRParen)) {
			while (true) {
				final isRest = cur.kind.match(TDot) && peekKind().match(TDot) && peekKind2().match(TDot);
				if (isRest) {
					// Rest argument: `...name:Type`
					//
					// Stage3 bring-up:
					// - We lower rest args to a single `Array<T>` parameter.
					// - Call sites are responsible for packing trailing arguments into an array.
					bump();
					bump();
					bump();
				}

				var isOptional = acceptOtherChar("?");
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

				if (isRest) {
					// Rest args are always omittable at call sites. Represent them as an `Array<T>`
					// so later stages can use array intrinsics (`concat`, `join`, ...) during bring-up.
					final inner = (argType == null || StringTools.trim(argType).length == 0) ? "Dynamic" : argType;
					argType = "Array<" + inner + ">";
					isOptional = true;
				}

				args.push(new HxFunctionArg(argName, argType, defaultValue, isOptional, isRest));
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
			returnType = readTypeHintText(() -> cur.kind.match(TLBrace) || cur.kind.match(TSemicolon) || cur.kind.match(TEof)
				|| cur.kind.match(TKeyword(KReturn)));
		}

		final body = new Array<HxStmt>();
		switch (cur.kind) {
			case TSemicolon:
				bump();
			case TLBrace:
				bump();
				for (s in parseFunctionBodyStatements())
					body.push(s);
			case _:
				// Expression-bodied function: `function f() return expr;`
				if (acceptKeyword(KReturn)) {
					body.push(parseReturnStmt(HxPos.unknown()));
				} else {
					final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof));
					if (cur.kind.match(TSemicolon))
						bump();
					body.push(SExpr(expr, HxPos.unknown()));
				}
		}

		return new HxFunctionDecl(name, visibility, isStatic, args, returnType, body, capturedReturnStringLiteral);
	}

	function parseClassMembers():{functions:Array<HxFunctionDecl>, fields:Array<HxFieldDecl>} {
		final funcs = new Array<HxFunctionDecl>();
		final fields = new Array<HxFieldDecl>();
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
						} else if (acceptKeyword(KInline)) {
							// Stage3 bring-up: accept `inline` as a modifier, but do not model it yet.
							//
							// Why
							// - Upstream harness code uses `public static inline function ...` heavily for small helpers
							//   (e.g. `runci.System.getDownloadPath()`).
							// - Without recognizing `inline`, we would treat it as an identifier, fail to match
							//   `function`, and skip the entire member, which then breaks wildcard imports
							//   (`import runci.System.*`) and can cause runtime segfaults in the Stage3 emit-runner.
							keep = true;
						}
					}

					if (acceptKeyword(KFunction)) {
						funcs.push(parseFunctionDecl(visibility, isStatic));
						continue;
					}

					if (acceptKeyword(KVar)) {
						// Class field: `var name[:Type] [= expr];` (subset; no properties yet).
						final name = readIdent("field name");
						var typeHint = "";
						var init:Null<HxExpr> = null;
						if (cur.kind.match(TColon)) {
							bump();
							typeHint = readTypeHintText(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof) || isOtherChar("="));
						}
						if (acceptOtherChar("=")) {
							init = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof) || cur.kind.match(TRBrace));
						}
						expect(TSemicolon, "';'");
						fields.push(new HxFieldDecl(name, visibility, isStatic, typeHint, init));
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
		return {functions: funcs, fields: fields};
	}

	/**
		Parse a Haxe module.

		Why
		- Real Haxe modules can contain multiple type declarations (multiple `class` blocks).
		- During bootstrap, our pipeline assumes each module has a “main class” whose members
		  represent the module’s surface for import/type resolution.
		- Upstream runci code relies on this: `tests/runci/System.hx` defines `CommandFailure`
		  before `System`, but imports refer to the module `runci.System`.

		What
		- Parses:
		  - optional `package ...;`
		  - `import` / `using`
		  - any number of `class` declarations (subset)
		- Chooses `mainClass` as:
		  - the class whose name matches `expectedMainClass` when provided, else
		  - the first parsed class, else
		  - `Unknown` placeholder.

		How
		- This is still not the full grammar: we skip non-class declarations and
		  tolerate unsupported constructs inside class bodies by skipping to the
		  next likely boundary.
	**/
	public function parseModule(?expectedMainClass:String):HxModuleDecl {
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

		// Bootstrap: scan the whole file looking for class declarations.
		//
		// Notes
		// - We still recognize module-level `function main(...)` for upstream unit tests.
		// - Non-class declarations (typedef/enum/abstract/etc.) are ignored for now.
		final classes = new Array<HxClassDecl>();
		while (!cur.kind.match(TEof)) {
			switch (cur.kind) {
				case TKeyword(KClass):
					bump(); // 'class'
					final className = readIdent("class name");
					// Skip `extends` / `implements` / generics / metadata until '{'.
					while (!cur.kind.match(TLBrace) && !cur.kind.match(TEof))
						bump();
					if (cur.kind.match(TEof))
						break;
					expect(TLBrace, "'{'");

					final members = parseClassMembers();
					final functions = members.functions == null ? [] : members.functions;
					final fields = members.fields == null ? [] : members.fields;
					var hasStaticMain = false;
					for (fn in functions) {
						if (HxFunctionDecl.getIsStatic(fn) && HxFunctionDecl.getName(fn) == "main") {
							hasStaticMain = true;
							break;
						}
					}

					classes.push(new HxClassDecl(className, hasStaticMain, functions, fields));
				// `parseClassMembers` consumes the closing `}`.
				case TKeyword(KFunction):
					// Detect module-level `function main(...)` entrypoint.
					bump();
					switch (cur.kind) {
						case TIdent("main"):
							hasToplevelMain = true;
						case _:
					}
				default:
					bump();
			}
		}

		expect(TEof, "end of input");

		final expected = expectedMainClass == null ? "" : StringTools.trim(expectedMainClass);
		var chosen:Null<HxClassDecl> = null;
		if (expected.length > 0) {
			for (c in classes) {
				if (c != null && HxClassDecl.getName(c) == expected) {
					chosen = c;
					break;
				}
			}
		}
		if (chosen == null && classes.length > 0)
			chosen = classes[0];
		final mainClass = chosen == null ? new HxClassDecl("Unknown", false, [], []) : chosen;
		return new HxModuleDecl(packagePath, imports, mainClass, classes, false, hasToplevelMain);
	}
}
