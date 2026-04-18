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

	final source:String;
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
		this.source = source == null ? "" : source;
		lex = new HxLexer(source);
		cur = lex.next();
	}

	inline function posIndex(pos:Null<HxPos>):Int {
		return pos == null ? 0 : pos.getIndex();
	}

	inline function currentIndex():Int {
		return posIndex(cur.getPos());
	}

	function sliceSource(start:Int, end:Int):String {
		final safeStart = start < 0 ? 0 : start;
		final safeEnd = end < safeStart ? safeStart : (end > source.length ? source.length : end);
		return source.substring(safeStart, safeEnd);
	}

	function parseMetadataText():String {
		if (!isOtherChar("@"))
			fail("Expected metadata");
		final start = currentIndex();
		bump(); // '@'
		if (cur.kind.match(TColon))
			bump();
		switch (cur.kind) {
			case TIdent(_) | TKeyword(_):
				bump();
			case _:
				fail("Expected metadata name");
		}
		while (cur.kind.match(TDot)) {
			bump();
			switch (cur.kind) {
				case TIdent(_) | TKeyword(_):
					bump();
				case _:
					fail("Expected metadata path segment");
			}
		}
		if (cur.kind.match(TLParen)) {
			bump();
			skipBalancedParens();
		}
		return StringTools.trim(sliceSource(start, currentIndex()));
	}

	function readMetadataHead():{name:String, endIndex:Int} {
		var metaName = "";
		var endIndex = currentIndex();
		switch (cur.kind) {
			case TIdent(name):
				final start = currentIndex();
				metaName = name;
				endIndex = start + name.length;
				bump();
			case TKeyword(k):
				final start = currentIndex();
				metaName = keywordText(k);
				endIndex = start + metaName.length;
				bump();
			case _:
		}
		while (cur.kind.match(TDot)) {
			bump();
			switch (cur.kind) {
				case TIdent(segment):
					final start = currentIndex();
					metaName += "." + segment;
					endIndex = start + segment.length;
					bump();
				case TKeyword(k):
					final start = currentIndex();
					final segment = keywordText(k);
					metaName += "." + segment;
					endIndex = start + segment.length;
					bump();
				case _:
					break;
			}
		}
		return {name: metaName, endIndex: endIndex};
	}

	function hasAttachedMetadataArgs(metaName:String, metaEndIndex:Int):Bool {
		return metaName != "privateAccess" && cur.kind.match(TLParen) && currentIndex() == metaEndIndex;
	}

	function readPropertyAccessorText():String {
		return switch (cur.kind) {
			case TIdent(name):
				bump();
				name;
			case TKeyword(k):
				final value = keywordText(k);
				bump();
				value;
			case TOther(c) if (c == "*".code):
				bump();
				"*";
			case _:
				fail("Expected property accessor");
		}
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
		final normalized =
			#if hxhx_stage0_no_source_normalize_extract
			normalizeDenseEscapedQuotesInline(source);
			#else
			HxParserSourceNormalize.normalizeDenseEscapedQuotes(source);
			#end
		final p = new HxParser(normalized);
		final e = p.parseExpr(() -> p.cur.kind.match(TEof));
		return e;
	}

	#if hxhx_stage0_no_source_normalize_extract
	/**
		Inline fallback for stage0 A/B measurement only.

		Why
		- We use this define to compare extracted-helper vs in-class-helper compile graphs under the
		  same stage0 profiler harness.
		- This path is not intended as a long-term behavior branch; it exists to generate parity A/B
		  evidence for `haxe.ocaml-a0pt.1.5`.
	**/
	static function normalizeDenseEscapedQuotesInline(source:String):String {
		if (source == null || source.length == 0)
			return source;
		var normalized = source;
		if (normalized.indexOf('"""') != -1) {
			final q = '"';
			final triple = q + q + q;
			final escapedQuoteString = q + "\\" + q + q;
			normalized = StringTools.replace(normalized, triple, escapedQuoteString);
		}
		normalized = normalizeDenseKeywordSpacingInline(normalized);
		return normalized;
	}

	static function normalizeDenseKeywordSpacingInline(source:String):String {
		if (source == null || source.length == 0)
			return source;
		final compactNewExpr = ~/(^|[^A-Za-z0-9_])new([A-Za-z_])/g;
		return compactNewExpr.map(source, function(re:EReg):String {
			return re.matched(1) + "new " + re.matched(2);
		});
	}
	#end

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
		final src = "{\n" + normalizeInlineJsConditionalMarkers(bodySource == null ? "" : bodySource) + "\n}";
		final p = new HxParser(src);
		if (!p.cur.kind.match(TLBrace))
			return [];
		p.bump(); // consume '{'
		return p.parseFunctionBodyStatementsBestEffort();
	}

	static function normalizeInlineJsConditionalMarkers(bodySource:String):String {
		// Stage3 body slices can still contain inline conditional-compilation markers,
		// notably upstream JS-specific assertions shaped like:
		//   expr #if js || js.Browser... #end
		//
		// Top-level directive lines are handled by statement parsing, but inline markers
		// appear in the middle of an expression and otherwise surface as `body_parse_error`.
		// Keep this intentionally narrow for the JS-native Gate3 path: remove only the
		// marker text and preserve the guarded JS expression tokens.
		if (bodySource == null || bodySource.indexOf("#") < 0)
			return bodySource == null ? "" : bodySource;
		var normalized = StringTools.replace(bodySource, "#if js", " ");
		normalized = StringTools.replace(normalized, "#end", " ");
		return normalized;
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
		// Bring-up: support the pattern subset documented in HxSwitchPattern. This
		// intentionally remains smaller than full Haxe matching, but it is recursive
		// enough for macro-expression shapes such as `{ expr : EConst(CString(s)) }`.
		final pattern = parseSwitchPatternCaseGroup();
		if (acceptKeyword(KIf)) {
			final guard = if (cur.kind.match(TLParen)) {
				bump();
				final expr = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
				if (cur.kind.match(TRParen))
					bump();
				expr;
			} else {
				parseExpr(() -> cur.kind.match(TColon) || cur.kind.match(TEof));
			}
			return switchPatternWithGuard(pattern, guard);
		}
		return pattern;
	}

	function switchPatternWithGuard(pattern:HxSwitchPattern, guard:HxExpr):HxSwitchPattern {
		return switch (guard) {
			case EBinop("==", EField(EIdent(name), "length"), EInt(length)):
				PLengthGuard(pattern, name, length);
			case ECall(EField(EIdent("StringTools"), "startsWith"), [EIdent(name), EString(prefix)]):
				PStartsWithGuard(pattern, name, prefix);
			case EBinop("==", EIdent(name), EInt(value)):
				PIntEqualsGuard(pattern, name, value);
			case _:
				PUnsupportedGuard(pattern);
		}
	}

	function parseSwitchPatternCaseGroup():HxSwitchPattern {
		final first = parseSwitchPatternOr();
		var ors:Null<Array<HxSwitchPattern>> = null;
		while (cur.kind.match(TComma)) {
			bump();
			if (ors == null)
				ors = [first];
			ors.push(parseSwitchPatternOr());
		}
		return ors == null ? first : POr(ors);
	}

	function parseSwitchPatternOr():HxSwitchPattern {
		final first = parseSwitchPatternAtom();
		var ors:Null<Array<HxSwitchPattern>> = null;
		while (acceptOtherChar("|")) {
			if (ors == null)
				ors = [first];
			ors.push(parseSwitchPatternAtom());
		}
		return ors == null ? first : POr(ors);
	}

	function parseSwitchPatternAtom():HxSwitchPattern {
		final extractor = tryParseSwitchExtractorPattern();
		if (extractor != null)
			return extractor;

		return switch (cur.kind) {
			case TKeyword(KNull):
				bump();
				PNull;
			case TKeyword(KTrue):
				bump();
				PBool(true);
			case TKeyword(KFalse):
				bump();
				PBool(false);
			case TKeyword(KVar):
				bump();
				switch (cur.kind) {
					case TIdent(name):
						bump();
						PBind(name);
					case _:
						PWildcard;
				}
			case TIdent("_"):
				bump();
				PWildcard;
			case TLBrace:
				bump();
				final fieldNames = new Array<String>();
				final fieldPatterns = new Array<HxSwitchPattern>();
				while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
					final fieldName = switch (cur.kind) {
						case TIdent(name):
							bump();
							name;
						case TString(name):
							bump();
							name;
						case _:
							bump();
							null;
					}
					if (fieldName == null) {
						if (cur.kind.match(TComma)) {
							bump();
							continue;
						}
						break;
					}
					if (cur.kind.match(TColon))
						bump();
					final fieldPattern = parseSwitchPatternOr();
					fieldNames.push(fieldName);
					fieldPatterns.push(fieldPattern);
					if (cur.kind.match(TComma)) {
						bump();
						continue;
					}
				}
				if (cur.kind.match(TRBrace))
					bump();
				PObject(fieldNames, fieldPatterns);
			case TLParen:
				bump();
				final inner = parseSwitchPatternOr();
				if (cur.kind.match(TRParen))
					bump();
				inner;
			case TOther(c) if (c == "[".code):
				bump();
				final items = new Array<HxSwitchPattern>();
				while (!cur.kind.match(TOther("]".code)) && !cur.kind.match(TEof)) {
					items.push(parseSwitchPatternOr());
					if (cur.kind.match(TComma)) {
						bump();
						continue;
					}
					break;
				}
				if (cur.kind.match(TOther("]".code)))
					bump();
				PArray(items);
			case TString(s):
				bump();
				PString(s);
			case TInt(v):
				bump();
				PInt(v);
			case TIdent(name) if (name == "macro" && peekKind().match(TColon)):
				parseMacroTypeSwitchPattern();
			case TIdent(name):
				bump();
				if (isUpperStart(name) && cur.kind.match(TLParen)) {
					bump();
					final args = new Array<HxSwitchPattern>();
					while (!cur.kind.match(TRParen) && !cur.kind.match(TEof)) {
						args.push(parseSwitchPatternOr());
						if (cur.kind.match(TComma)) {
							bump();
							continue;
						}
						break;
					}
					if (cur.kind.match(TRParen))
						bump();
					PEnumExtract(name, args);
				} else if (!isUpperStart(name) && acceptOtherChar("=")) {
					PCapture(name, parseSwitchPatternAtom());
				} else {
					isUpperStart(name) ? PEnumValue(name) : PBind(name);
				}
			case _:
				// Best-effort: consume one token and treat it as a wildcard.
				bump();
				PWildcard;
		}
	}

	function parseMacroTypeSwitchPattern():HxSwitchPattern {
		// `case macro:Type:` has two colons: one belongs to the macro complex-type
		// quote and the next one separates the case body. Consume only the quoted
		// type payload here so `parseSwitchExpr`/`parseStmt` can consume the case
		// separator normally.
		switch (cur.kind) {
			case TIdent("macro"):
				bump();
			case _:
				return PWildcard;
		}
		if (cur.kind.match(TColon))
			bump();
		final typeText = readTypeHintText(() -> cur.kind.match(TColon) || cur.kind.match(TComma) || cur.kind.match(TRBrace) || cur.kind.match(TEof)
			|| cur.kind.match(TKeyword(KIf)) || isOtherChar("|"));
		return PEnumValue("macro:" + typeText);
	}

	function isLikelyExtractorPatternStart():Bool {
		return switch (cur.kind) {
			case TIdent("_"):
				peekKind().match(TDot);
			case TIdent(name): final nextKind = peekKind(); // Qualified static extractors such as `Std.parseInt(_) => code`
				// appear inside upstream sys switch patterns.
				nextKind.match(TDot) || (!isUpperStart(name) && nextKind.match(TLParen));
			case _:
				false;
		}
	}

	function tryParseSwitchExtractorPattern():Null<HxSwitchPattern> {
		if (!isLikelyExtractorPatternStart())
			return null;
		final start = currentIndex();
		var parenDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		while (!cur.kind.match(TEof)) {
			final atTop = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0;
			if (atTop && (cur.kind.match(TColon) || cur.kind.match(TRParen) || cur.kind.match(TRBrace)))
				break;
			if (atTop && cur.kind.match(TOther("=".code)) && peekKind().match(TOther(">".code))) {
				final extractorText = StringTools.trim(sliceSource(start, currentIndex()));
				bump(); // `=`
				bump(); // `>`
				return PExtractor(extractorText, parseSwitchPatternOr());
			}
			switch (cur.kind) {
				case TLParen:
					parenDepth++;
				case TRParen:
					if (parenDepth > 0)
						parenDepth--;
				case TLBrace:
					braceDepth++;
				case TRBrace:
					if (braceDepth > 0)
						braceDepth--;
				case TOther(c) if (c == "[".code):
					bracketDepth++;
				case TOther(c) if (c == "]".code):
					if (bracketDepth > 0)
						bracketDepth--;
				case _:
			}
			bump();
		}
		return PUnsupportedGuard(PWildcard);
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
			case TKeyword(KAs):
				// `as` is a keyword for import aliases, but upstream code can still use it as a
				// value-level identifier. Keep the lexer keyworded and contextualize only where an
				// identifier is explicitly expected.
				bump();
				"as";
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

	function skipBalancedAngles():Void {
		// Called when current token is '<' and the caller wants to skip a balanced generic group.
		var depth = 0;
		while (true) {
			switch (cur.kind) {
				case TEof:
					fail("Unterminated angle bracket group");
				case TOther(c) if (c == "<".code):
					depth++;
					bump();
				case TOther(c) if (c == ">".code):
					depth--;
					bump();
					if (depth <= 0)
						return;
				case TLParen:
					bump();
					skipBalancedParens();
				case TLBrace:
					bump();
					skipBalancedBraces();
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
		var parenDepth = 0;
		var braceDepth = 0;
		var angleDepth = 0;
		var bracketDepth = 0;
		while (true) {
			// Special-case structural/anonymous type hints that begin with `{ ... }`.
			//
			// Example (upstream runci/System.hx):
			//   static function commandResult(...):{ stdout:String, ... } { ... }
			//
			// In this case, the first `{` is part of the *type hint*, not the function body.
			// Our callers often use `stop()` predicates that stop on `{` (body start), so we
			// allow a leading `{` to be consumed into the type-hint text.
			final atTopLevel = parenDepth == 0 && braceDepth == 0 && angleDepth == 0 && bracketDepth == 0;
			if (atTopLevel && stop() && !(parts.length == 0 && cur.kind.match(TLBrace)))
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
				case TRegex(pattern, flags):
					parts.push("~/" + pattern + "/" + flags);
					bump();
				case TLParen:
					parts.push("(");
					parenDepth++;
					bump();
				case TRParen:
					parts.push(")");
					if (parenDepth > 0)
						parenDepth--;
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
					braceDepth++;
					bump();
				case TRBrace:
					parts.push("}");
					if (braceDepth > 0)
						braceDepth--;
					bump();
				case TSemicolon:
					parts.push(";");
					bump();
				case TOther(c):
					final ch = String.fromCharCode(c);
					parts.push(ch);
					switch (ch) {
						case "<":
							angleDepth++;
						case ">":
							if (angleDepth > 0) angleDepth--;
						case "[":
							bracketDepth++;
						case "]":
							if (bracketDepth > 0) bracketDepth--;
						case _:
					}
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
				parseBraceExpr();
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
				} else if (k == KFunction) {
					parseFunctionExpr();
				} else if (k == KInline) {
					bump();
					parsePrimaryExpr();
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
								final arg = parseCallArg(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof));
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
				} else if (k == KFor) {
					parseForExprRaw();
				} else if (k == KThrow) {
					bump();
					final thrown = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof)
						|| cur.kind.match(TKeyword(KCase)) || cur.kind.match(TKeyword(KDefault)) || cur.kind.match(TComma) || cur.kind.match(TRParen));
					ECall(EIdent("__hxhx_throw"), [thrown]);
				} else if (k == KAs) {
					bump();
					EIdent("as");
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
			case TRegex(pattern, flags):
				bump();
				ENew("EReg", [EString(pattern), EString(flags)]);
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
			case TOther(c) if (c == "$".code):
				parseMacroReificationExpr();
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

	function parseMacroReificationExpr():HxExpr {
		// Macro reification splice: `$i{name}`, `$e{expr}`, `$b{expr}`, ...
		//
		// Bring-up scope
		// - Consume the balanced splice payload so macro quotes don't throw and
		//   become `body_parse_error`.
		// - Model identifier splices explicitly because generator code commonly uses
		//   `$i{name}(...)` to build calls to generated fields.
		if (!acceptOtherChar("$"))
			return EUnsupported("$");
		final spliceKind = switch (cur.kind) {
			case TIdent(name):
				bump();
				name;
			case _:
				"expr";
		}
		final payload = if (cur.kind.match(TLBrace)) {
			bump();
			final inner = parseExpr(() -> cur.kind.match(TRBrace) || cur.kind.match(TEof));
			if (cur.kind.match(TRBrace))
				bump();
			inner;
		} else {
			parseUnaryExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TRBrace) || cur.kind.match(TSemicolon)
				|| cur.kind.match(TEof));
		}
		return switch (spliceKind) {
			case "i":
				ECall(EIdent("__hxhx_macro_ident_splice"), [payload]);
			case "b":
				ECall(EIdent("__hxhx_macro_block_splice"), [payload]);
			case "e":
				ECall(EIdent("__hxhx_macro_expr_splice"), [payload]);
			case other:
				ECall(EIdent("__hxhx_macro_" + other + "_splice"), [payload]);
		}
	}

	function parseFunctionExpr():HxExpr {
		// Anonymous function expression:
		//   function(arg0, arg1) return expr
		//   function(arg0, arg1) { return expr; }
		//
		// Bring-up scope
		// - Parse arg names plus optional type/default syntax (ignored for Stage3 expression lowering).
		// - Lower to `ELambda(args, bodyExpr)` because JS emitter already supports this shape.
		// - Block bodies are accepted when they can be reduced to a single expression/return.
		if (!acceptKeyword(KFunction))
			fail("Expected 'function'");
		expect(TLParen, "'('");

		final args = new Array<String>();
		if (!cur.kind.match(TRParen)) {
			while (true) {
				final isRest = cur.kind.match(TDot) && peekKind().match(TDot) && peekKind2().match(TDot);
				if (isRest) {
					bump();
					bump();
					bump();
				}

				acceptOtherChar("?");
				final argName = readIdent("argument name");
				args.push(argName);

				if (cur.kind.match(TColon)) {
					bump();
					readTypeHintText(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof) || isOtherChar("="));
				}

				if (acceptOtherChar("=")) {
					parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof));
				}

				if (cur.kind.match(TComma)) {
					bump();
					continue;
				}
				break;
			}
		}
		expect(TRParen, "')'");

		if (cur.kind.match(TColon)) {
			bump();
			readTypeHintText(() -> cur.kind.match(TLBrace) || cur.kind.match(TKeyword(KReturn)) || cur.kind.match(TKeyword(KThrow))
				|| cur.kind.match(TSemicolon) || cur.kind.match(TEof));
		}

		final bodyExpr = if (acceptKeyword(KReturn)) {
			parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
		} else if (cur.kind.match(TLBrace)) {
			bump();
			lambdaBodyExprFromStmts(parseFunctionBodyStatements());
		} else {
			parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
		}

		return ELambda(args, bodyExpr);
	}

	function parseLocalFunctionStmt(pos:HxPos):HxStmt {
		// Local function declaration: `function name(args)[:Ret] { ... }`.
		//
		// Bring-up lowering
		// - Model it as a local binding to an `ELambda`, which is sufficient for
		//   Stage3 JS-native bodies that define a helper and immediately call it.
		if (!acceptKeyword(KFunction))
			fail("Expected 'function'");
		final name = readIdent("local function name");
		if (isOtherChar("<"))
			skipBalancedAngles();
		expect(TLParen, "'('");

		final args = new Array<String>();
		if (!cur.kind.match(TRParen)) {
			while (true) {
				final isRest = cur.kind.match(TDot) && peekKind().match(TDot) && peekKind2().match(TDot);
				if (isRest) {
					bump();
					bump();
					bump();
				}
				acceptOtherChar("?");
				final argName = readIdent("argument name");
				args.push(argName);

				if (cur.kind.match(TColon)) {
					bump();
					readTypeHintText(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof) || isOtherChar("="));
				}

				if (acceptOtherChar("="))
					parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof));

				if (cur.kind.match(TComma)) {
					bump();
					continue;
				}
				break;
			}
		}
		expect(TRParen, "')'");

		if (cur.kind.match(TColon)) {
			bump();
			readTypeHintText(() -> cur.kind.match(TLBrace) || cur.kind.match(TKeyword(KReturn)) || cur.kind.match(TKeyword(KThrow))
				|| cur.kind.match(TSemicolon) || cur.kind.match(TEof));
		}

		final bodyExpr = if (cur.kind.match(TLBrace)) {
			bump();
			lambdaBodyExprFromStmts(parseFunctionBodyStatements());
		} else if (acceptKeyword(KReturn)) {
			final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
			syncToStmtEnd();
			expr;
		} else {
			final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
			syncToStmtEnd();
			expr;
		}

		if (cur.kind.match(TSemicolon))
			bump();
		return SVar(name, "", ELambda(args, bodyExpr), pos);
	}

	function lambdaBodyExprFromStmts(stmts:Array<HxStmt>):HxExpr {
		if (stmts == null || stmts.length == 0)
			return ENull;

		var seqTempIndex = 0;
		var unsupportedStmtKind = "function";

		inline function stmtKindText(stmt:HxStmt):String {
			return switch (stmt) {
				case SBlock(_, _): "block";
				case SVar(_, _, _, _): "var";
				case SIf(_, _, _, _): "if";
				case SForIn(_, _, _, _): "for_in";
				case SForKeyValue(_, _, _, _, _): "for_key_value";
				case SWhile(_, _, _): "while";
				case SDoWhile(_, _, _): "do_while";
				case SSwitch(_, _, _, _): "switch";
				case STry(_, _, _): "try";
				case SBreak(_): "break";
				case SContinue(_): "continue";
				case SThrow(_, _): "throw";
				case SReturnVoid(_): "return_void";
				case SReturn(_, _): "return";
				case SExpr(_, _): "expr";
			};
		}
		inline function nextSeqTemp():String {
			final name = "__hxhx_lambda_seq_" + Std.string(seqTempIndex);
			seqTempIndex++;
			return name;
		}

		function lowerStmtWithContinuation(stmt:HxStmt, continuation:HxExpr):Null<HxExpr> {
			return switch (stmt) {
				case SReturn(expr, _):
					expr;
				case SReturnVoid(_):
					ENull;
				case SExpr(expr, _):
					final temp = nextSeqTemp();
					ECall(ELambda([temp], continuation), [expr]);
				case SVar(name, _, init, _):
					final initExpr:HxExpr = switch (init) {
						case null:
							ENull;
						case value:
							value;
					};
					ECall(ELambda([name], continuation), [initExpr]);
				case SBlock(inner, _):
					var acc = continuation;
					var index = inner.length - 1;
					while (index >= 0) {
						final lowered = lowerStmtWithContinuation(inner[index], acc);
						if (lowered == null)
							return null;
						acc = lowered;
						index--;
					}
					acc;
				case SIf(cond, thenBranch, elseBranch, _):
					final thenExpr = lowerStmtWithContinuation(thenBranch, continuation);
					if (thenExpr == null)
						return null;
					final elseExpr = if (elseBranch == null) {
						continuation;
					} else {
						final loweredElse = lowerStmtWithContinuation(elseBranch, continuation);
						if (loweredElse == null)
							return null;
						loweredElse;
					}
					ETernary(cond, thenExpr, elseExpr);
				case SSwitch(scrutinee, patterns, bodies, _):
					final loweredPatterns = new Array<HxSwitchPattern>();
					final loweredExprs = new Array<HxExpr>();
					var hasDefault = false;
					final count = patterns.length < bodies.length ? patterns.length : bodies.length;
					for (i in 0...count) {
						final pattern = patterns[i];
						switch (pattern) {
							case PWildcard:
								hasDefault = true;
							case _:
						}
						final branchExpr = lowerStmtWithContinuation(bodies[i], continuation);
						if (branchExpr == null)
							return null;
						loweredPatterns.push(pattern);
						loweredExprs.push(branchExpr);
					}
					if (!hasDefault) {
						loweredPatterns.push(PWildcard);
						loweredExprs.push(continuation);
					}
					ESwitch(scrutinee, loweredPatterns, loweredExprs);
				case SThrow(expr, _):
					ECall(EIdent("__hxhx_throw"), [expr]);
				case SForKeyValue(keyName, valueName, iterable, body, _):
					final bodyExpr = lowerStmtWithContinuation(body, ENull);
					if (bodyExpr == null)
						return null;
					ECall(EIdent("__hxhx_for_key_value"), [iterable, ELambda([keyName, valueName], bodyExpr), continuation]);
				case SForIn(valueName, iterable, body, _):
					final bodyExpr = lowerStmtWithContinuation(body, ENull);
					if (bodyExpr == null)
						return null;
					ECall(EIdent("__hxhx_for_in"), [iterable, ELambda([valueName], bodyExpr), continuation]);
				case SWhile(cond, body, _):
					final bodyExpr = lowerStmtWithContinuation(body, ENull);
					if (bodyExpr == null)
						return null;
					ECall(EIdent("__hxhx_while"), [ELambda([], cond), ELambda([], bodyExpr), continuation]);
				case STry(tryBody, catches, _):
					// Local function bodies are expression-lowered; preserve try/catch as a
					// private sentinel so target emitters can still produce statement-level try.
					final tryExpr = lowerStmtWithContinuation(tryBody, continuation);
					if (tryExpr == null)
						return null;
					final catchEntries = new Array<HxExpr>();
					for (c in catches) {
						final catchExpr = lowerStmtWithContinuation(c.body, continuation);
						if (catchExpr == null)
							return null;
						catchEntries.push(EArrayDecl([
							EString(c.name),
							EString(c.typeHint == null ? "" : c.typeHint),
							ELambda([c.name], catchExpr)
						]));
					}
					ECall(EIdent("__hxhx_try"), [ELambda([], tryExpr), EArrayDecl(catchEntries), continuation]);
				case _:
					unsupportedStmtKind = stmtKindText(stmt);
					null;
			}
		}

		var result:HxExpr = ENull;
		var index = stmts.length - 1;
		while (index >= 0) {
			final lowered = lowerStmtWithContinuation(stmts[index], result);
			if (lowered == null)
				return EUnsupported("function:" + unsupportedStmtKind);
			result = lowered;
			index--;
		}
		return result;
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

		inline function isFatArrowStart():Bool {
			return cur.kind.match(TOther("=".code)) && peekKind().match(TOther(">".code));
		}

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
			final yieldExpr = parseExpr(() -> isFatArrowStart() || cur.kind.match(TOther("]".code)) || cur.kind.match(TEof));
			var result:HxExpr = EArrayComprehension(name, iterable, yieldExpr);
			if (isFatArrowStart()) {
				bump(); // '='
				bump(); // '>'
				final valueExpr = parseExpr(() -> cur.kind.match(TOther("]".code)) || cur.kind.match(TEof));
				result = ECall(EIdent("__hxhx_map_comprehension"), [iterable, ELambda([name], EArrayDecl([yieldExpr, valueExpr]))]);
			}
			if (cur.kind.match(TOther("]".code)))
				bump();
			return result;
		}

		final values = new Array<HxExpr>();
		final mapNames = new Array<String>();
		final mapValues = new Array<HxExpr>();
		var sawMapEntry = false;

		if (cur.kind.match(TOther("]".code))) {
			bump();
			return EArrayDecl(values);
		}
		while (!cur.kind.match(TEof)) {
			if (cur.kind.match(TOther("]".code))) {
				bump();
				break;
			}
			final value = parseExpr(() -> isFatArrowStart() || cur.kind.match(TComma) || cur.kind.match(TOther("]".code)) || cur.kind.match(TEof));
			if (isFatArrowStart()) {
				sawMapEntry = true;
				bump(); // '='
				bump(); // '>'
				mapNames.push(mapLiteralKeyName(value));
				mapValues.push(parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TOther("]".code)) || cur.kind.match(TEof)));
			} else {
				values.push(value);
			}
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
		if (sawMapEntry)
			return EAnon(mapNames, mapValues);
		return EArrayDecl(values);
	}

	function mapLiteralKeyName(expr:HxExpr):String {
		return switch (expr) {
			case EString(v): v;
			case EInt(v): Std.string(v);
			case EFloat(v): Std.string(v);
			case EBool(v): v ? "true" : "false";
			case EIdent(name): name;
			case EEnumValue(name): name;
			case _:
				"__hx_key";
		}
	}

	function parseCallArg(stop:() -> Bool):HxExpr {
		if (cur.kind.match(TDot) && peekKind().match(TDot) && peekKind2().match(TDot)) {
			bump();
			bump();
			bump();
			return ECall(EIdent("__hxhx_spread"), [parseExpr(stop)]);
		}
		return parseExpr(stop);
	}

	function parseBraceExpr():HxExpr {
		// Expression-level `{ ... }` has two common shapes in upstream code:
		// - anonymous object literal: `{ field: value }`
		// - block expression initializer: `{ var h = ...; ...; h; }`
		//
		// Parse anon literals structurally. For block expressions, first try the same
		// continuation lowering used by local function bodies so callbacks and side
		// effects do not leak as raw Haxe syntax into JS-native output. If the statement
		// subset is still too rich, keep the old opaque fallback.
		final start = currentIndex();
		expect(TLBrace, "'{'");
		if (cur.kind.match(TRBrace)) {
			bump();
			return EAnon([], []);
		}

		final isAnonLiteral = switch (cur.kind) {
			case TIdent(_):
				peekKind().match(TColon);
			case TString(_):
				peekKind().match(TColon);
			case _:
				false;
		}
		if (isAnonLiteral)
			return parseAnonExprAfterOpen();

		final stmts = parseFunctionBodyStatementsBestEffort();
		final raw = "opaque_block_expr:" + StringTools.trim(sliceSource(start, currentIndex()));
		final lowered = blockExprFromStmts(stmts);
		return switch (lowered) {
			case EUnsupported(_):
				ETryCatchRaw(raw);
			case _:
				lowered;
		}
	}

	function parseAnonExpr():HxExpr {
		// `{ name: expr, ... }`
		//
		// Stage 3: parse a conservative subset (identifier keys + expressions).
		expect(TLBrace, "'{'");
		return parseAnonExprAfterOpen();
	}

	function parseAnonExprAfterOpen():HxExpr {
		final names = new Array<String>();
		final values = new Array<HxExpr>();
		if (cur.kind.match(TRBrace)) {
			bump();
			return EAnon(names, values);
		}
		while (!cur.kind.match(TEof)) {
			if (cur.kind.match(TRBrace)) {
				bump();
				break;
			}
			final name = readAnonFieldName();
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

	function readAnonFieldName():String {
		return switch (cur.kind) {
			case TString(s):
				bump();
				s;
			case _:
				readIdent("field name");
		}
	}

	static function binopPrec(op:String):Int {
		return switch (op) {
			case "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "<<=" | ">>=" | ">>>=" | "&=" | "|=" | "^=" | "??=": 1;
			case "?": 2;
			case "??": 2;
			case "||": 2;
			case "|": 2;
			case "&&": 3;
			case "&": 3;
			case "^": 3;
			case "==" | "!=" | "is": 4;
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
			case "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "<<=" | ">>=" | ">>>=" | "&=" | "|=" | "^=" | "??=":
				true;
			case _:
				false;
		}
	}

	static function isRightAssoc(op:String):Bool {
		return isAssignmentBinop(op);
	}

	function parsePostfixExpr(stop:() -> Bool):HxExpr {
		return parsePostfixSuffix(parsePrimaryExpr(), stop);
	}

	function parsePostfixSuffix(seed:HxExpr, stop:() -> Bool):HxExpr {
		var e = seed;

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
						final arg = parseCallArg(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof));
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
		final arrow = tryReadArrowLambdaExpr(stop);
		if (arrow != null)
			return arrow;

		return switch (cur.kind) {
			case TIdent(name) if (name == "macro"):
				bump();
				parseMacroQuoteExpr(stop);
			case TKeyword(k) if (k == KSwitch):
				parseSwitchExpr(stop);
			case TOther("@".code):
				// Expression-level metadata: `@:meta expr`.
				//
				// Bring-up semantics: ignore metadata and return the underlying expression.
				while (cur.kind.match(TOther("@".code))) {
					bump();
					if (cur.kind.match(TColon))
						bump();
					final meta = readMetadataHead();
					if (hasAttachedMetadataArgs(meta.name, meta.endIndex)) {
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
				var castExpr:HxExpr = null;
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
					castExpr = ECast(inner, hint);
				} else {
					castExpr = ECast(parseUnaryExpr(stop), "");
				}
				parsePostfixSuffix(castExpr, stop);
			case TKeyword(k) if (k == KUntyped):
				bump();
				parsePostfixSuffix(EUntyped(parseUnaryExpr(stop)), stop);
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
			case TOther(c) if (c == "!".code || c == "-".code || c == "+".code || c == "~".code):
				final op = String.fromCharCode(c);
				bump();
				EUnop(op, parseUnaryExpr(stop));
			case _:
				parsePostfixExpr(stop);
		}
	}

	function parseMacroQuoteExpr(stop:() -> Bool):HxExpr {
		final wrappers = new Array<String>();
		if (cur.kind.match(TKeyword(KUntyped))) {
			bump();
			wrappers.push("untyped");
		}

		if (cur.kind.match(TColon)) {
			bump();
			return HxExpr.EMacroType(readTypeHintText(stop));
		}

		if (cur.kind.match(TKeyword(KClass)))
			return parseMacroClassQuoteExpr();

		final quoted = if (cur.kind.match(TLParen)) {
			bump();
			wrappers.push("parenthesis");
			final inner = parseMacroQuotePayload(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
			if (cur.kind.match(TRParen))
				bump();
			inner;
		} else {
			parseMacroQuotePayload(stop);
		}
		return HxExpr.EMacroExpr(quoted, wrappers);
	}

	function parseMacroClassQuoteExpr():HxExpr {
		// `macro class Name ... { ... }` produces a `haxe.macro.TypeDefinition`, not
		// a normal expression quote. Stage3 only needs to consume the balanced class
		// quote and expose the object fields used by generator code (`name`, `fields`).
		if (!acceptKeyword(KClass))
			fail("Expected 'class'");

		var className = "__hxhx_macro_class";
		switch (cur.kind) {
			case TIdent(name):
				className = name;
				bump();
			case _:
				// Anonymous macro class quotes are valid; keep a stable placeholder name.
		}

		while (!cur.kind.match(TLBrace) && !cur.kind.match(TEof)) {
			switch (cur.kind) {
				case TLParen:
					bump();
					skipBalancedParens();
				case TOther(c) if (c == "<".code):
					skipBalancedAngles();
				case _:
					bump();
			}
		}
		if (cur.kind.match(TLBrace)) {
			bump();
			skipBalancedBraces();
		}

		return EAnon(["pack", "name", "pos", "meta", "params", "isExtern", "kind", "fields"], [
			EArrayDecl([]),
			EString(className),
			ENull,
			EArrayDecl([]),
			EArrayDecl([]),
			EBool(false),
			EAnon(["__hx_ctor", "__hx_index", "__hx_params"], [
				EString("TDClass"),
				EInt(0),
				EArrayDecl([ENull, EArrayDecl([]), EBool(false), EBool(false), EBool(false)])
			]),
			EArrayDecl([])
		]);
	}

	function parseMacroQuotePayload(stop:() -> Bool):HxExpr {
		if (cur.kind.match(TKeyword(KIf)))
			return parseMacroQuoteIfPayload(stop);

		final left = parseExpr(() -> stop() || cur.kind.match(TKeyword(KIn)));
		if (cur.kind.match(TKeyword(KIn))) {
			bump();
			final right = parseExpr(stop);
			return EBinop("in", left, right);
		}
		return left;
	}

	function parseMacroQuoteIfPayload(stop:() -> Bool):HxExpr {
		bump(); // `if`
		expect(TLParen, "'('");
		final cond = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
		if (!cur.kind.match(TRParen)) {
			while (!cur.kind.match(TRParen) && !cur.kind.match(TEof))
				bump();
		}
		if (cur.kind.match(TRParen))
			bump();

		final thenExpr = parseMacroQuotePayload(() -> stop() || cur.kind.match(TKeyword(KElse)));
		if (cur.kind.match(TSemicolon) && peekKind().match(TKeyword(KElse)))
			bump();
		final elseExpr = if (acceptKeyword(KElse)) {
			parseMacroQuotePayload(stop);
		} else {
			HxExpr.EIdent("__hxhx_macro_missing_else");
		}
		return HxExpr.ECall(HxExpr.EIdent("__hxhx_macro_if"), [cond, thenExpr, elseExpr]);
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
			case TIdent(name) if (name == "is"):
				{op: "is", len: 1};
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
					case "?".code:
						if (nextIsOther("?".code)) {
							next2IsOther("=".code) ? {op: "??=", len: 3} : {op: "??", len: 2};
						} else {
							null;
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
		// - Supports:
		//   - `name -> expr`
		//   - `(a) -> expr`
		//   - `(a, b) -> expr`
		//   - `() -> expr`
		// - Parameter forms remain identifier-only. Typed/default/pattern args are future work.
		if (!stop()) {
			final arrow = tryReadArrowLambdaExpr(stop);
			if (arrow != null)
				return arrow;
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
			if (cur.kind.match(TSemicolon) && peekKind().match(TKeyword(KElse)))
				bump();
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
		if (!stop() && cur.kind.match(TColon)) {
			bump();
			readTypeHintText(() -> stop() || cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TRBrace) || cur.kind.match(TSemicolon)
				|| cur.kind.match(TEof));
		}
		return e;
	}

	function tryReadArrowLambdaExpr(stop:() -> Bool):Null<HxExpr> {
		if (stop())
			return null;
		switch (cur.kind) {
			case TLParen:
				final parenLambda = tryReadParenthesizedLambdaArgs();
				if (parenLambda != null) {
					consumeUntilIndex(parenLambda.endIndex);
					final body = parseExpr(stop);
					return ELambda(parenLambda.args, body);
				}
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
		return null;
	}

	function tryReadParenthesizedLambdaArgs():Null<{args:Array<String>, endIndex:Int}> {
		if (!cur.kind.match(TLParen))
			return null;
		final start = currentIndex();
		if (start < 0 || start >= source.length || source.charCodeAt(start) != "(".code)
			return null;
		var i = start + 1;
		var depth = 1;
		while (i < source.length && depth > 0) {
			final c = source.charCodeAt(i);
			switch (c) {
				case "(".code:
					// Keep this narrow: parenthesized lambda params stay flat.
					return null;
				case ")".code:
					depth -= 1;
					if (depth == 0)
						break;
				case _:
			}
			i += 1;
		}
		if (depth != 0)
			return null;
		final closeIndex = i;
		var j = closeIndex + 1;
		while (j < source.length) {
			final code = source.charCodeAt(j);
			if (code == " ".code || code == "\t".code || code == "\n".code || code == "\r".code) {
				j += 1;
				continue;
			}
			break;
		}
		if (j + 1 >= source.length || source.charCodeAt(j) != "-".code || source.charCodeAt(j + 1) != ">".code)
			return null;

		final rawArgs = StringTools.trim(source.substring(start + 1, closeIndex));
		final args = new Array<String>();
		if (rawArgs.length > 0) {
			for (part in rawArgs.split(",")) {
				final arg = parseLambdaArgName(part);
				if (arg == null)
					return null;
				args.push(arg);
			}
		}
		return {args: args, endIndex: j + 2};
	}

	function parseLambdaArgName(raw:String):Null<String> {
		var arg = StringTools.trim(raw == null ? "" : raw);
		if (arg.length == 0)
			return null;
		if (StringTools.startsWith(arg, "?"))
			arg = StringTools.trim(arg.substr(1));
		final end = lambdaArgNameEnd(arg);
		if (end <= 0)
			return null;
		final name = StringTools.trim(arg.substr(0, end));
		return isValidLambdaArgName(name) ? name : null;
	}

	function lambdaArgNameEnd(arg:String):Int {
		for (i in 0...arg.length) {
			switch (arg.charCodeAt(i)) {
				case ":".code | "=".code | " ".code | "\t".code | "\n".code | "\r".code:
					return i;
				case _:
			}
		}
		return arg.length;
	}

	function isValidLambdaArgName(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		final first = name.charCodeAt(0);
		final firstOk = (first >= "A".code && first <= "Z".code) || (first >= "a".code && first <= "z".code) || first == "_".code;
		if (!firstOk)
			return false;
		for (i in 1...name.length) {
			final c = name.charCodeAt(i);
			final ok = (c >= "A".code && c <= "Z".code) || (c >= "a".code && c <= "z".code) || (c >= "0".code && c <= "9".code) || c == "_".code;
			if (!ok)
				return false;
		}
		return true;
	}

	function consumeUntilIndex(target:Int):Void {
		while (!cur.kind.match(TEof) && currentIndex() < target)
			bump();
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
			return ESwitch(scrutinee, [], []);
		}
		bump(); // '{'

		final patterns = new Array<HxSwitchPattern>();
		final exprs = new Array<HxExpr>();
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
			final caseStmts = new Array<HxStmt>();
			while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof) && !cur.kind.match(TKeyword(KCase)) && !cur.kind.match(TKeyword(KDefault))) {
				final braceStartsAnon = cur.kind.match(TLBrace)
					&& ((peekKind().match(TIdent(_)) || peekKind().match(TString(_))) && peekKind2().match(TColon));
				if (braceStartsAnon) {
					final exprPos = cur.pos;
					final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof)
						|| cur.kind.match(TKeyword(KCase)) || cur.kind.match(TKeyword(KDefault)));
					if (cur.kind.match(TSemicolon))
						bump();
					caseStmts.push(SExpr(expr, exprPos));
				} else {
					parseStmtInto(caseStmts,
						() -> cur.kind.match(TRBrace) || cur.kind.match(TEof) || cur.kind.match(TKeyword(KCase)) || cur.kind.match(TKeyword(KDefault)));
				}
			}
			patterns.push(pat);
			exprs.push(switchCaseExprFromStmts(caseStmts));
		}
		if (cur.kind.match(TRBrace))
			bump();

		return ESwitch(scrutinee, patterns, exprs);
	}

	function switchCaseExprFromStmts(stmts:Array<HxStmt>):HxExpr {
		// Expression-switch branches may contain setup statements before the final value:
		//
		//   case pattern:
		//     var detail = compute();
		//     trace(detail);
		//     false;
		//
		// Reuse the local-function sequence lowering by rewriting a trailing expression
		// statement into `return expr`; otherwise a final `false;` would be treated as a
		// side-effect-only statement and the branch value would become `null`.
		return blockExprFromStmts(stmts);
	}

	function blockExprFromStmts(stmts:Array<HxStmt>):HxExpr {
		if (stmts == null || stmts.length == 0)
			return ENull;

		function markTailValue(stmt:HxStmt):HxStmt {
			return switch (stmt) {
				case SExpr(expr, pos):
					SReturn(expr, pos);
				case SIf(cond, thenBranch, elseBranch, pos):
					var rewrittenElse:Null<HxStmt> = null;
					if (elseBranch != null)
						rewrittenElse = markTailValue(elseBranch);
					SIf(cond, markTailValue(thenBranch), rewrittenElse, pos);
				case SBlock(inner, pos) if (inner != null && inner.length > 0):
					final rewrittenInner = inner.copy();
					final lastInner = rewrittenInner.length - 1;
					rewrittenInner[lastInner] = markTailValue(rewrittenInner[lastInner]);
					SBlock(rewrittenInner, pos);
				case SSwitch(scrutinee, patterns, bodies, pos):
					final rewrittenBodies = new Array<HxStmt>();
					for (body in bodies)
						rewrittenBodies.push(markTailValue(body));
					SSwitch(scrutinee, patterns, rewrittenBodies, pos);
				case other:
					other;
			}
		}

		final rewritten = stmts.copy();
		final lastIndex = rewritten.length - 1;
		rewritten[lastIndex] = markTailValue(rewritten[lastIndex]);
		return lambdaBodyExprFromStmts(rewritten);
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
					final text = keywordText(k);
					if (text == "new" || text == "throw" || text == "return" || text == "var" || text == "final") text + " "; else text;
				case TString(s):
					"\"" + s + "\"";
				case TInt(v):
					Std.string(v);
				case TFloat(v):
					Std.string(v);
				case TRegex(pattern, flags):
					"~/" + pattern + "/" + flags;
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

		function consumeExpressionBlock(untilCatch:Bool):Void {
			raw.add("{");
			var parenDepth = 0;
			var braceDepth = 0;
			var bracketDepth = 0;
			while (!cur.kind.match(TEof)) {
				if (parenDepth == 0 && braceDepth == 0 && bracketDepth == 0) {
					if (untilCatch && cur.kind.match(TKeyword(KCatch)))
						break;
					if (!untilCatch && stop())
						break;
				}
				switch (cur.kind) {
					case TLParen:
						parenDepth++;
					case TRParen:
						if (parenDepth > 0)
							parenDepth--;
					case TLBrace:
						braceDepth++;
					case TRBrace:
						if (braceDepth > 0)
							braceDepth--;
					case TOther(c) if (c == "[".code):
						bracketDepth++;
					case TOther(c) if (c == "]".code):
						if (bracketDepth > 0)
							bracketDepth--;
					case _:
				}
				raw.add(tokText());
				bump();
			}
			raw.add(";}");
		}

		// `try`
		raw.add("try");
		bump();

		// `{ ... }` or single-expression `try expr catch(...) expr`.
		if (cur.kind.match(TLBrace)) {
			consumeBalancedBraces();
		} else {
			consumeExpressionBlock(true);
		}

		// One or more `catch (...) { ... }`.
		while (!stop() && cur.kind.match(TKeyword(KCatch))) {
			raw.add("catch");
			bump();
			consumeBalancedParens();
			if (cur.kind.match(TLBrace)) {
				consumeBalancedBraces();
			} else {
				consumeExpressionBlock(false);
			}
		}

		return ETryCatchRaw(raw.toString());
	}

	function parseForExprRaw():HxExpr {
		// Expression-position `for` is most commonly seen inside compile-time macro probes,
		// e.g. `HelperMacros.typeError(for (...) { })`. We do not model statement ASTs inside
		// HxExpr yet, so consume the full construct and leave a targeted placeholder for the
		// macro-call lowering seam instead of letting the body parser drift.
		if (!cur.kind.match(TKeyword(KFor)))
			return EUnsupported("for_expr");

		inline function isIdentKind(kind:HxTokenKind):Bool {
			return switch (kind) {
				case TIdent(_): true;
				case _: false;
			};
		}

		if (peekKind().match(TLParen) && isIdentKind(peekKind2()) && peekKind3().match(TKeyword(KIn))) {
			bump(); // `for`
			expect(TLParen, "'('");
			final name = readIdent("expression for-in loop variable");
			expect(TKeyword(KIn), "'in'");
			inline function isTripleDotStart():Bool {
				return cur.kind.match(TDot) && peekKind().match(TDot) && peekKind2().match(TDot);
			}
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
			final body = parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TSemicolon) || cur.kind.match(TRBrace)
				|| cur.kind.match(TEof));
			return ECall(EIdent("__hxhx_for_in"), [iterable, ELambda([name], body), ENull]);
		}

		final start = currentIndex();
		bump(); // `for`

		if (cur.kind.match(TLParen))
			consumeBalancedParensForExpr();

		if (cur.kind.match(TLBrace)) {
			consumeBalancedBracesForExpr();
		} else {
			while (!cur.kind.match(TEof) && !cur.kind.match(TComma) && !cur.kind.match(TRParen) && !cur.kind.match(TSemicolon) && !cur.kind.match(TRBrace))
				bump();
		}

		final raw = StringTools.trim(sliceSource(start, currentIndex()));
		return EUnsupported("for_expr:" + raw);
	}

	function consumeBalancedParensForExpr():Void {
		expect(TLParen, "'('");
		var depth = 1;
		while (depth > 0 && !cur.kind.match(TEof)) {
			switch (cur.kind) {
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

	function consumeBalancedBracesForExpr():Void {
		expect(TLBrace, "'{'");
		var depth = 1;
		while (depth > 0 && !cur.kind.match(TEof)) {
			switch (cur.kind) {
				case TLBrace:
					depth++;
					bump();
				case TRBrace:
					depth--;
					bump();
				case _:
					bump();
			}
		}
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

			final thenBranch = ensureBranchReturns(parseStmt(() -> cur.kind.match(TKeyword(KElse)) || cur.kind.match(TEof)));
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

	function syncToStmtEndUntil(stop:() -> Bool):Void {
		// Best-effort resynchronization for statements.
		//
		// Why
		// - Our expression grammar is intentionally incomplete; it may stop before `;`.
		// - If we don't advance to the end of the statement, parsing can get stuck on
		//   the same token forever.
		while (!stop() && !cur.kind.match(TSemicolon) && !cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
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

	function syncToStmtEnd():Void {
		syncToStmtEndUntil(() -> false);
	}

	function parseVarDecls(pos:HxPos):Array<HxStmt> {
		// `var a[:T] [= expr], b[:U] [= expr];`
		//
		// Why
		// - Upstream Haxe tests use grouped declarators heavily, e.g. `var a:Int64, b:Int64;`.
		// - Dropping tail declarators makes later assignments unbound in Stage3 emission.
		//
		// How
		// - Parse each declarator here.
		// - In statement-list contexts, callers flatten grouped declarators into the surrounding list.
		// - In single-statement contexts (e.g. `if (...) var a, b;`), we keep them wrapped in
		//   a local block so branch-local scope remains correct.
		function parseSingleVarDecl():HxStmt {
			final name = readIdent("variable name");
			var typeHint = "";
			if (cur.kind.match(TColon)) {
				bump();
				typeHint = readTypeHintText(() -> cur.kind.match(TComma) || cur.kind.match(TSemicolon) || cur.kind.match(TEof) || isOtherChar("="));
			}

			var init:Null<HxExpr> = null;
			if (acceptOtherChar("=")) {
				init = parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TSemicolon) || cur.kind.match(TEof) || cur.kind.match(TRBrace));
			}
			return SVar(name, typeHint, init, pos);
		}

		final decls = new Array<HxStmt>();
		decls.push(parseSingleVarDecl());
		while (cur.kind.match(TComma)) {
			bump();
			decls.push(parseSingleVarDecl());
		}
		final nextStartsStatement = switch (cur.kind) {
			case TKeyword(k):
				k == KIf
				|| k == KSwitch
				|| k == KTry
				|| k == KWhile
				|| k == KDo
				|| k == KFor
				|| k == KThrow
				|| k == KReturn
				|| k == KInline
				|| k == KFunction
				|| k == KVar
				|| k == KFinal
				|| k == KBreak
				|| k == KContinue;
			case TOther(c): c == "#".code || c == "@".code;
			case _:
				false;
		}
		if (nextStartsStatement)
			return decls;
		syncToStmtEnd();
		return decls;
	}

	function parseVarStmt(pos:HxPos):HxStmt {
		final decls = parseVarDecls(pos);
		return decls.length == 1 ? decls[0] : SBlock(decls, pos);
	}

	function parseStmtInto(out:Array<HxStmt>, stop:() -> Bool):Void {
		if (out == null || stop())
			return;
		if (cur.kind.match(TSemicolon)) {
			// Empty statements are valid separators after block expressions, e.g. `{ ... };`.
			// Skipping them prevents bootstrap targets from surfacing token-rendered
			// `EUnsupported` payloads in otherwise parsed bodies.
			bump();
			return;
		}
		if (cur.kind.match(TOther("#".code))) {
			consumePreprocessorLine();
			return;
		}
		final isVarDecl = cur.kind.match(TKeyword(KVar)) || cur.kind.match(TKeyword(KFinal));
		if (isVarDecl) {
			final pos = cur.pos;
			bump();
			final decls = parseVarDecls(pos);
			for (stmt in decls)
				out.push(stmt);
			return;
		}
		out.push(parseStmt(stop));
	}

	function consumePreprocessorLine():Void {
		final line = cur.pos.getLine();
		while (!cur.kind.match(TEof) && cur.pos.getLine() == line)
			bump();
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
					parseStmtInto(ss, () -> cur.kind.match(TRBrace) || cur.kind.match(TEof));
				}
				expect(TRBrace, "'}'");
				SBlock(ss, pos);
			case TKeyword(KReturn):
				bump();
				parseReturnStmt(pos);
			case TKeyword(KInline):
				// Local `inline function name(...) ...` is a modifier on a local helper.
				// Stage3 does not model inlining here; it lowers to the same lambda binding
				// as a normal local function so the body remains executable.
				bump();
				if (cur.kind.match(TKeyword(KFunction))) {
					parseLocalFunctionStmt(pos);
				} else {
					SExpr(EUnsupported("inline"), pos);
				}
			case TKeyword(KFunction):
				parseLocalFunctionStmt(pos);
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
				final thenBranch = parseStmt(() -> stop() || cur.kind.match(TKeyword(KElse)));
				// Keep nullable enum branches on the explicit `Null<T>` path so stage0 OCaml
				// generation keeps representation coercions consistent.
				var elseBranch:Null<HxStmt> = null;
				if (acceptKeyword(KElse))
					elseBranch = true ? parseStmt(stop) : null;
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
					SSwitch(scrutinee, [], [], pos);
				} else {
					bump(); // '{'
					final patterns = new Array<HxSwitchPattern>();
					final bodies = new Array<HxStmt>();
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
							parseStmtInto(stmts,
								() -> cur.kind.match(TRBrace) || cur.kind.match(TEof) || cur.kind.match(TKeyword(KCase)) || cur.kind.match(TKeyword(KDefault)));
						}
						patterns.push(pat);
						bodies.push(SBlock(stmts, pos));
					}
					if (cur.kind.match(TRBrace))
						bump();
					SSwitch(scrutinee, patterns, bodies, pos);
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
					final meta = readMetadataHead();
					// Optional attached meta args: `@:meta(...)`.
					if (hasAttachedMetadataArgs(meta.name, meta.endIndex)) {
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
						parseStmtInto(stmts, () -> cur.kind.match(TRBrace) || cur.kind.match(TEof));
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
							parseStmtInto(stmts, () -> cur.kind.match(TRBrace) || cur.kind.match(TEof));
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
				var keyName:Null<String> = null;
				var valueName = name;
				if (cur.kind.match(TOther("=".code)) && peekKind().match(TOther(">".code))) {
					keyName = name;
					bump(); // '='
					bump(); // '>'
					valueName = readIdent("for key/value loop value variable");
				}
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
				keyName == null ? SForIn(valueName, iterable, body, pos) : SForKeyValue(keyName, valueName, iterable, body, pos);
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
				final expr = parseExpr(() -> stop() || cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
				syncToStmtEndUntil(stop);
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
					parseStmtInto(out, () -> cur.kind.match(TRBrace) || cur.kind.match(TEof));
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
				case TRegex(_, _): "regex";
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
						parseStmtInto(out, () -> cur.kind.match(TRBrace) || cur.kind.match(TEof));
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

	function parseFunctionDecl(visibility:HxVisibility, isStatic:Bool, metadata:Array<String>, startPos:HxPos):HxFunctionDecl {
		capturedReturnStringLiteral = "";
		final name = switch (cur.kind) {
			case TKeyword(KNew):
				bump();
				"new";
			case _:
				readIdent("function name");
		}
		// Generic function declarations can carry a type-parameter group immediately after the
		// function name, e.g. `static function coalesce<T>(left:T, right:T):T;`.
		//
		// Drop the `<...>` group in this bootstrap parser, matching the existing constructor
		// behavior for `new Foo<Bar>(...)`. Stage3 only needs the callable surface here.
		if (isOtherChar("<"))
			skipBalancedAngles();
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
				var defaultValueText = "";

				if (cur.kind.match(TColon)) {
					bump();
					argType = readTypeHintText(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof) || isOtherChar("="));
				}

				if (acceptOtherChar("=")) {
					final defaultStart = currentIndex();
					defaultValue = HxDefaultValue.Default(parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof)));
					defaultValueText = StringTools.trim(sliceSource(defaultStart, currentIndex()));
				}

				if (isRest) {
					// Rest args are always omittable at call sites. Represent them as an `Array<T>`
					// so later stages can use array intrinsics (`concat`, `join`, ...) during bring-up.
					final inner = (argType == null || StringTools.trim(argType).length == 0) ? "Dynamic" : argType;
					argType = "Array<" + inner + ">";
					isOptional = true;
				}

				args.push(new HxFunctionArg(argName, argType, defaultValue, isOptional, isRest, defaultValueText));
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
				|| cur.kind.match(TKeyword(KReturn)) || cur.kind.match(TKeyword(KThrow)));
		}

		final body = new Array<HxStmt>();
		var bodyText = "";
		switch (cur.kind) {
			case TSemicolon:
				bump();
			case TLBrace:
				bump();
				final bodyStart = currentIndex();
				for (s in parseFunctionBodyStatements())
					body.push(s);
				final endIndex = currentIndex();
				var capturedBodyText = StringTools.trim(sliceSource(bodyStart, endIndex));
				if (StringTools.endsWith(capturedBodyText, "}"))
					capturedBodyText = StringTools.rtrim(capturedBodyText.substr(0, capturedBodyText.length - 1));
				bodyText = capturedBodyText;
			case _:
				// Expression-bodied function: `function f() return expr;`
				if (acceptKeyword(KReturn)) {
					final bodyStart = currentIndex();
					body.push(parseReturnStmt(HxPos.unknown()));
					bodyText = "return " + StringTools.trim(sliceSource(bodyStart, currentIndex()));
				} else {
					final bodyStart = currentIndex();
					final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof));
					if (cur.kind.match(TSemicolon))
						bump();
					body.push(SExpr(expr, HxPos.unknown()));
					bodyText = StringTools.trim(sliceSource(bodyStart, currentIndex()));
				}
		}

		return new HxFunctionDecl(name, visibility, isStatic, args, returnType, body, capturedReturnStringLiteral, metadata, startPos, cur.getPos(), bodyText);
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
					final memberStart = cur.getPos();
					var visibility:HxVisibility = Public;
					var isStatic = false;
					var sawFinal = false;
					final metadata = new Array<String>();

					// Modifiers (subset).
					var keep = true;
					while (keep) {
						keep = false;
						if (isOtherChar("@")) {
							metadata.push(parseMetadataText());
							keep = true;
						} else if (acceptKeyword(KPublic)) {
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
						} else if (acceptKeyword(KFinal)) {
							// Stage3 bring-up: support class-level finals:
							//   `static final NAME = expr;`
							//
							// Keep this as a modifier so `final function` still parses as a function
							// declaration, while bare `final name = ...` can be parsed as a field below.
							sawFinal = true;
							keep = true;
						} else {
							switch (cur.kind) {
								case TIdent(name) if (name == "macro"):
									// `macro` is context-sensitive in Haxe. Preserve it as function metadata
									// so targets can keep compile-time-only bodies out of runtime output.
									metadata.push("macro");
									bump();
									keep = true;
								case TIdent(name) if (name == "extern" || name == "override"):
									// These context-sensitive modifiers are accepted at class-member scope but
									// are not modeled in the current bring-up AST.
									bump();
									keep = true;
								case _:
							}
						}
					}

					if (acceptKeyword(KFunction)) {
						funcs.push(parseFunctionDecl(visibility, isStatic, metadata, memberStart));
						continue;
					}

					if (acceptKeyword(KVar) || sawFinal) {
						// Class field: `var name[(get,set)][:Type] [= expr];` (subset).
						final name = readIdent("field name");
						var propertyGet = "";
						var propertySet = "";
						var typeHint = "";
						var init:Null<HxExpr> = null;
						var initText = "";
						if (cur.kind.match(TLParen)) {
							bump();
							propertyGet = readPropertyAccessorText();
							expect(TComma, "','");
							propertySet = readPropertyAccessorText();
							expect(TRParen, "')'");
						}
						if (cur.kind.match(TColon)) {
							bump();
							typeHint = readTypeHintText(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof) || isOtherChar("="));
						}
						if (acceptOtherChar("=")) {
							final initStart = currentIndex();
							init = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof) || cur.kind.match(TRBrace));
							initText = StringTools.trim(sliceSource(initStart, currentIndex()));
						}
						if (cur.kind.match(TSemicolon)) {
							bump();
						} else if (init != null && isSemicolonlessFieldInitializer(init, initText) && isClassMemberBoundary()) {
							// Haxe permits semicolonless block-expression field initializers:
							// `var x = switch (...) { ... }` followed by the next member.
							// Accept that form so switch field initializers do not absorb the
							// rest of the class during Stage3 bring-up parsing.
						} else {
							expect(TSemicolon, "';'");
						}
						fields.push(new HxFieldDecl(name, visibility, isStatic, typeHint, init, metadata, memberStart, cur.getPos(), sawFinal, propertyGet,
							propertySet, initText));
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

	function isSemicolonlessFieldInitializer(expr:HxExpr, initText:String):Bool {
		final text = StringTools.trim(initText == null ? "" : initText);
		if (StringTools.startsWith(text, "{"))
			return true;
		return switch (expr) {
			case ESwitch(_, _, _) | ESwitchRaw(_) | ETryCatchRaw(_):
				true;
			case _:
				false;
		}
	}

	function isClassMemberBoundary():Bool {
		return switch (cur.kind) {
			case TRBrace:
				true;
			case TEof:
				true;
			case TKeyword(keyword):
				final text = keywordText(keyword);
				text == "public"
				|| text == "private"
				|| text == "static"
				|| text == "inline"
				|| text == "final"
				|| text == "var"
				|| text == "function";
			case TIdent(name): name == "macro" || name == "extern" || name == "override";
			case TOther(c):
				c == "@".code;
			case _:
				false;
		}
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
					var extendsPath = "";
					// Capture the simple superclass path while still ignoring generic
					// parameters and implements clauses in this bootstrap parser.
					while (!cur.kind.match(TLBrace) && !cur.kind.match(TEof)) {
						switch (cur.kind) {
							case TIdent(name) if (name == "extends"):
								bump();
								extendsPath = readDottedPath();
							case _:
								bump();
						}
					}
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

					classes.push(new HxClassDecl(className, hasStaticMain, functions, fields, extendsPath));
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
