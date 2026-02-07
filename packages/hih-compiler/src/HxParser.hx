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
	var peeked1:Null<HxToken> = null;
	var peeked2:Null<HxToken> = null;
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
		if (!p.cur.kind.match(TLBrace)) return [];
		p.bump(); // consume '{'
		return p.parseFunctionBodyStatementsBestEffort();
	}

	inline function bump():Void {
		if (peeked1 != null) {
			cur = peeked1;
			peeked1 = peeked2;
			peeked2 = null;
		} else {
			cur = lex.next();
		}
	}

	inline function peek():HxToken {
		if (peeked1 == null) peeked1 = lex.next();
		return peeked1;
	}

	inline function peek2():HxToken {
		if (peeked1 == null) peeked1 = lex.next();
		if (peeked2 == null) peeked2 = lex.next();
		return peeked2;
	}

	inline function peekKind():HxTokenKind {
		return peek().kind;
	}

	inline function peekKind2():HxTokenKind {
		return peek2().kind;
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
			case TLParen:
				// Parenthesized expression: `(expr)`.
				bump(); // '('
				final inner = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
				// Best-effort: resync to the closing `)`.
				if (!cur.kind.match(TRParen)) {
					while (!cur.kind.match(TRParen) && !cur.kind.match(TEof)) bump();
				}
				if (cur.kind.match(TRParen)) bump();
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

	function parseArrayDeclExpr():HxExpr {
		// `[e1, e2, ...]`
		//
		// Best-effort: if we don't find the closing `]`, return the partial list.
		if (!cur.kind.match(TOther("[".code))) return EArrayDecl([]);
		bump(); // '['
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
			while (!cur.kind.match(TComma) && !cur.kind.match(TOther("]".code)) && !cur.kind.match(TEof)) bump();
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
			while (!cur.kind.match(TComma) && !cur.kind.match(TRBrace) && !cur.kind.match(TEof)) bump();
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
			case "=": 1;
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

	static function isRightAssoc(op:String):Bool {
		return op == "=";
	}

	function parsePostfixExpr(stop:()->Bool):HxExpr {
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
				case TOther(c) if (c == "[".code):
					// Array access: `e[index]`.
					bump(); // '['
					final index = parseExpr(() -> cur.kind.match(TOther("]".code)) || cur.kind.match(TEof));
					// Best-effort: resync to closing bracket.
					if (!cur.kind.match(TOther("]".code))) {
						while (!cur.kind.match(TOther("]".code)) && !cur.kind.match(TEof)) bump();
					}
					if (cur.kind.match(TOther("]".code))) bump();
					e = EArrayAccess(e, index);
				case _:
					break;
			}
		}
		return e;
	}

	function parseUnaryExpr(stop:()->Bool):HxExpr {
		return switch (cur.kind) {
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
						while (!cur.kind.match(TRParen) && !cur.kind.match(TEof)) bump();
					}
					if (cur.kind.match(TRParen)) bump();
					ECast(inner, hint);
				} else {
					ECast(parseUnaryExpr(stop), "");
				}
			case TKeyword(k) if (k == KUntyped):
				bump();
				EUntyped(parseUnaryExpr(stop));
			case TOther(c) if (c == "!".code || c == "-".code || c == "+".code):
				final op = String.fromCharCode(c);
				bump();
				EUnop(op, parseUnaryExpr(stop));
			case _:
				parsePostfixExpr(stop);
		}
	}

	function peekBinop(stop:()->Bool):Null<{op:String, len:Int}> {
		if (stop()) return null;
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
		return switch (cur.kind) {
			case TOther(c):
				switch (c) {
					case "=".code:
						nextIsOther("=".code) ? {op: "==", len: 2} : {op: "=", len: 1};
					case "!".code:
						nextIsOther("=".code) ? {op: "!=", len: 2} : null;
					case "<".code:
						if (nextIsOther("<".code)) {
							{op: "<<", len: 2};
						} else {
							nextIsOther("=".code) ? {op: "<=", len: 2} : {op: "<", len: 1};
						}
					case ">".code:
						if (nextIsOther(">".code)) {
							next2IsOther(">".code) ? {op: ">>>", len: 3} : {op: ">>", len: 2};
						} else {
							nextIsOther("=".code) ? {op: ">=", len: 2} : {op: ">", len: 1};
						}
					case "&".code:
						nextIsOther("&".code) ? {op: "&&", len: 2} : {op: "&", len: 1};
					case "|".code:
						nextIsOther("|".code) ? {op: "||", len: 2} : {op: "|", len: 1};
					case "^".code:
						{op: "^", len: 1};
					case "+".code:
						{op: "+", len: 1};
					case "-".code:
						{op: "-", len: 1};
					case "*".code:
						{op: "*", len: 1};
					case "/".code:
						{op: "/", len: 1};
					case "%".code:
						{op: "%", len: 1};
					case _:
						null;
				}
			case _:
				null;
		}
	}

	function consumeBinop(len:Int):Void {
		for (_ in 0...len) bump();
	}

	function parseBinaryExpr(minPrec:Int, stop:()->Bool):HxExpr {
		var left = parseUnaryExpr(stop);

		while (true) {
			if (stop()) break;
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

	function parseExpr(stop:()->Bool):HxExpr {
		// Stage 3: small-but-real expression subset.
		// Includes calls/field access, prefix unary, and basic binary ops with precedence.
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
				case EBinop("=", left, right):
					EBinop("=", left, ETernary(right, thenExpr, elseExpr));
				case _:
					ETernary(e, thenExpr, elseExpr);
			}
		}
		return e;
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
					while (!cur.kind.match(TRParen) && !cur.kind.match(TEof)) bump();
				}
				if (cur.kind.match(TRParen)) bump();

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
		if (cur.kind.match(TSemicolon)) bump();
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

	function parseStmt(stop:()->Bool):HxStmt {
		if (stop()) return SExpr(EUnsupported("<eof-stmt>"), HxPos.unknown());

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
			case TKeyword(KIf):
				bump();
				expect(TLParen, "'('");
				final cond = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
				if (!cur.kind.match(TRParen)) {
					while (!cur.kind.match(TRParen) && !cur.kind.match(TEof)) bump();
				}
				if (cur.kind.match(TRParen)) bump();
				final thenBranch = parseStmt(stop);
				final elseBranch = acceptKeyword(KElse) ? parseStmt(stop) : null;
				SIf(cond, thenBranch, elseBranch, pos);
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
		while (true) {
			switch (cur.kind) {
				case TEof:
					return out;
				case TRBrace:
					bump();
					return out;
				case _:
					try {
						out.push(parseStmt(() -> cur.kind.match(TRBrace) || cur.kind.match(TEof)));
						0; // ensure try/catch has a concrete, consistent expression type across targets
					} catch (_:Dynamic) {
						// Best-effort resync: advance until a plausible statement boundary.
						while (!cur.kind.match(TSemicolon) && !cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
							bump();
						}
						if (cur.kind.match(TSemicolon)) bump();
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
					body.push(parseReturnStmt(HxPos.unknown()));
				} else {
					final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof));
					if (cur.kind.match(TSemicolon)) bump();
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
		return { functions: funcs, fields: fields };
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
		final fields = new Array<HxFieldDecl>();
		var hasStaticMain = false;

		if (sawClass) {
			expect(TKeyword(KClass), "'class'");
			className = readIdent("class name");

			expect(TLBrace, "'{'");

			final members = parseClassMembers();
			for (fn in members.functions) functions.push(fn);
			for (f in members.fields) fields.push(f);
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
		return new HxModuleDecl(packagePath, imports, new HxClassDecl(className, hasStaticMain, functions, fields), false, hasToplevelMain);
	}
}
