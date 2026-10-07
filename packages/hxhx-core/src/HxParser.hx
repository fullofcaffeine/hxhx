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
	final source:String;
	final lex:HxLexer;
	var cur:HxToken;
	var peeked1:Null<HxToken> = null;
	var peeked2:Null<HxToken> = null;
	var peeked3:Null<HxToken> = null;
	var capturedReturnStringLiteral:String = "";
	var inMacroQuote:Bool = false;

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

	function unsupportedKeywordDetail(raw:String):String {
		final index = currentIndex();
		var tail = "";
		if (source != null && index >= 0 && index < source.length) {
			final len = source.length - index > 48 ? 48 : source.length - index;
			tail = source.substr(index, len);
			tail = StringTools.replace(StringTools.replace(tail, "\n", "\\n"), "\r", "\\r");
		}
		return raw + "@idx=" + Std.string(index) + "@near=" + tail;
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
		- Some Haxe-authored compiler stages retain an expression as an exact source slice
		  before they need its structured form.
		- Reusing the canonical Haxe lexer/parser keeps that recovery inside the same
		  frontend that parses complete modules.

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
		Parse one expression and require the complete input to belong to it.

		Semantic metadata loaders use this stricter entry point so malformed text
		cannot be accepted merely because a valid expression prefix was parsed.
	**/
	public static function parseCompleteExprText(source:String):HxExpr {
		final parser = new HxParser(source);
		final expression = parser.parseExpr(() -> parser.cur.kind.match(TEof));
		if (!parser.cur.kind.match(TEof))
			parser.fail("Unexpected trailing input after expression");
		return expression;
	}

	/**
		Parse a complete expression from a retained source slice for typed recovery.
		Try bodies use the same source structure as ordinary parsing; this boundary
		never creates helper functions or reconstructs control from generated code.
	**/
	public static function parseStructuralExprText(source:String):HxExpr {
		final parser = new HxParser(source);
		final expression = parser.parseExpr(() -> parser.cur.kind.match(TEof));
		if (!parser.cur.kind.match(TEof))
			parser.fail("Unexpected trailing input after structural expression");
		return expression;
	}

	/**
		Parse a function body statement list from standalone source text.

		Why
		- Best-effort declaration recovery can retain method bodies as exact source slices.
		- Later Haxe-authored stages need a structured statement list without creating a
		  second parser or target-side semantic repair.

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

	/**
		Parse a raw function-body slice and rebase statement positions to the original module.

		Why
		- Best-effort declaration recovery can retain bodies as source slices.
		  `parseFunctionBodyText` wraps those slices in synthetic braces, which makes every
		  recovered statement position relative to the wrapper instead of the user's `.hx` file.
		- Diagnostics that rely on statement positions, such as ambiguous overload errors, must
		  report the real call site to match upstream Haxe behavior.

		What
		- Parses the body exactly like `parseFunctionBodyText`.
		- If the caller provides the original source and the slice's absolute start index, shifts
		  every statement position back into that source.

		How
		- `parseFunctionBodyText` prepends `"{\n"` before parsing. Rebasing subtracts that
		  synthetic line/index before adding the original slice start.
	**/
	public static function parseFunctionBodyTextAt(bodySource:String, originalSource:String, bodyStartIndex:Int):Array<HxStmt> {
		final stmts = parseFunctionBodyText(bodySource);
		if (originalSource == null || bodyStartIndex < 0 || bodyStartIndex > originalSource.length)
			return stmts;
		final base = sourcePosAt(originalSource, bodyStartIndex);
		final shifted = new Array<HxStmt>();
		for (stmt in stmts)
			shifted.push(rebaseFunctionBodyStmt(stmt, base, bodyStartIndex));
		return shifted;
	}

	/**
		Read one unbraced function body with the ordinary statement grammar.
		Declaration recovery needs the same closing boundary as the parser, including
		braces inside a switch scrutinee. Keep the following declaration outside the
		body and rebase source positions exactly as for a braced body slice.
	 */
	public static function parseUnbracedFunctionBodyAt(originalSource:String, start:Int):{
		body:Array<HxStmt>,
		bodyText:String,
		nextPos:Int,
		hasBody:Bool
	} {
		final parser = new HxParser("{\n" + originalSource.substr(start));
		parser.bump();
		final statement = parser.parseStmt(() -> parser.cur.kind.match(TEof));
		if (parser.cur.kind.match(TSemicolon))
			parser.bump();
		final nextPos = start + parser.currentIndex() - 2;
		final body = [rebaseFunctionBodyStmt(statement, sourcePosAt(originalSource, start), start)];
		return {
			body: body,
			bodyText: StringTools.trim(originalSource.substring(start, nextPos)),
			nextPos: nextPos,
			hasBody: true
		};
	}

	static function sourcePosAt(source:String, index:Int):HxPos {
		var line = 1;
		var lineStart = 0;
		var i = 0;
		while (i < index) {
			final c = source.charCodeAt(i);
			i += 1;
			if (c == "\n".code) {
				line += 1;
				lineStart = i;
			}
		}
		return new HxPos(index, line, index - lineStart + 1);
	}

	static function rebaseFunctionBodyPos(pos:HxPos, base:HxPos, bodyStartIndex:Int):HxPos {
		if (pos == null || pos.getLine() <= 0)
			return HxPos.unknown();
		final bodyIndex = pos.getIndex() - 2; // parseFunctionBodyText prepends "{\n".
		final bodyLine = pos.getLine() - 1;
		final absoluteLine = base.getLine() + bodyLine - 1;
		final absoluteColumn = bodyLine <= 1 ? base.getColumn() + pos.getColumn() - 1 : pos.getColumn();
		return new HxPos(bodyStartIndex + (bodyIndex < 0 ? 0 : bodyIndex), absoluteLine, absoluteColumn);
	}

	static function rebaseFunctionBodyStmt(stmt:HxStmt, base:HxPos, bodyStartIndex:Int):HxStmt {
		return switch (stmt) {
			case STargetScope(_, _, _): throw "native target scope is not valid in this source or target phase";
			case SBlock(stmts, pos):
				final shifted = new Array<HxStmt>();
				for (s in stmts)
					shifted.push(rebaseFunctionBodyStmt(s, base, bodyStartIndex));
				SBlock(shifted, rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SVar(name, typeHint, init, pos, metadata):
				SVar(name, typeHint, rebaseFunctionBodyExpr(init, base, bodyStartIndex), rebaseFunctionBodyPos(pos, base, bodyStartIndex),
					metadata == null ? [] : metadata.copy());
			case SIf(cond, thenBranch, elseBranch, pos):
				var shiftedElse:Null<HxStmt> = null;
				if (elseBranch != null)
					shiftedElse = rebaseFunctionBodyStmt(elseBranch, base, bodyStartIndex);
				SIf(cond, rebaseFunctionBodyStmt(thenBranch, base, bodyStartIndex), shiftedElse, rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SForIn(name, iterable, body, pos):
				SForIn(name, iterable, rebaseFunctionBodyStmt(body, base, bodyStartIndex), rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SForKeyValue(keyName, valueName, iterable, body, pos):
				SForKeyValue(keyName, valueName, iterable, rebaseFunctionBodyStmt(body, base, bodyStartIndex),
					rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SWhile(cond, body, pos):
				SWhile(cond, rebaseFunctionBodyStmt(body, base, bodyStartIndex), rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SDoWhile(body, cond, pos):
				SDoWhile(rebaseFunctionBodyStmt(body, base, bodyStartIndex), cond, rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SSwitch(scrutinee, patterns, bodies, pos, exhaustive):
				final shiftedBodies = new Array<HxStmt>();
				for (body in bodies)
					shiftedBodies.push(rebaseFunctionBodyStmt(body, base, bodyStartIndex));
				SSwitch(scrutinee, patterns, shiftedBodies, rebaseFunctionBodyPos(pos, base, bodyStartIndex), exhaustive);
			case STry(tryBody, catches, pos):
				final shiftedCatches = new Array<{name:String, typeHint:String, body:HxStmt}>();
				for (c in catches)
					shiftedCatches.push({name: c.name, typeHint: c.typeHint, body: rebaseFunctionBodyStmt(c.body, base, bodyStartIndex)});
				STry(rebaseFunctionBodyStmt(tryBody, base, bodyStartIndex), shiftedCatches, rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SBreak(pos):
				SBreak(rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SContinue(pos):
				SContinue(rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SThrow(expr, pos):
				SThrow(rebaseFunctionBodyExpr(expr, base, bodyStartIndex), rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SReturnVoid(pos):
				SReturnVoid(rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SReturn(expr, pos):
				SReturn(rebaseFunctionBodyExpr(expr, base, bodyStartIndex), rebaseFunctionBodyPos(pos, base, bodyStartIndex));
			case SExpr(expr, pos):
				SExpr(rebaseFunctionBodyExpr(expr, base, bodyStartIndex), rebaseFunctionBodyPos(pos, base, bodyStartIndex));
		}
	}

	static function rebaseFunctionBodyExpr(expr:Null<HxExpr>, base:HxPos, bodyStartIndex:Int):Null<HxExpr> {
		if (expr == null)
			return null;
		return rebaseFunctionBodyExprValue(expr, base, bodyStartIndex);
	}

	static function rebaseFunctionBodyExprValue(expr:HxExpr, base:HxPos, bodyStartIndex:Int):HxExpr {
		return switch (expr) {
			case EPrivateAccess(inner, position):
				EPrivateAccess(rebaseFunctionBodyExprValue(inner, base, bodyStartIndex), rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case EParenthesized(inner, position):
				EParenthesized(rebaseFunctionBodyExprValue(inner, base, bodyStartIndex), rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case ESourceTry(catches, bodies, position):
				ESourceTry([
					for (entry in catches)
						new HxSourceCatch(entry.getName(), entry.getTypeHint(), rebaseFunctionBodyPos(entry.getPosition(), base, bodyStartIndex))
				],
					[for (body in bodies) rebaseFunctionBodyExprValue(body, base, bodyStartIndex)], rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case ESourceFor(binding, iterable, body, position):
				ESourceFor(binding, rebaseFunctionBodyExprValue(iterable, base, bodyStartIndex), rebaseFunctionBodyExprValue(body, base, bodyStartIndex),
					rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case ESourceIf(condition, whenTrue, whenFalse, position):
				ESourceIf(rebaseFunctionBodyExprValue(condition, base, bodyStartIndex), rebaseFunctionBodyExprValue(whenTrue, base, bodyStartIndex),
					whenFalse == null ? null : rebaseFunctionBodyExprValue(whenFalse, base, bodyStartIndex),
					rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case EThrow(value, position):
				EThrow(rebaseFunctionBodyExprValue(value, base, bodyStartIndex), rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case ELoweredControl(kind, target, children, position):
				ELoweredControl(kind, target, [for (child in children) rebaseFunctionBodyExprValue(child, base, bodyStartIndex)],
					rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case ESourceGroup(children, position):
				ESourceGroup([for (child in children) rebaseFunctionBodyExprValue(child, base, bodyStartIndex)],
					rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case ESourceFunction(facts, body, defaults, position):
				ESourceFunction(facts, rebaseFunctionBodyExprValue(body, base, bodyStartIndex),
					[for (value in defaults) rebaseFunctionBodyExprValue(value, base, bodyStartIndex)], rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case ECall(EIdent(name), args) if (StringTools.startsWith(name, "__hxhx_trace_at_")):
				final line = Std.parseInt(name.substr("__hxhx_trace_at_".length));
				final rebased = line == null ? 0 : base.getLine() + line - 2;
				ECall(EIdent("__hxhx_trace_at_" + Std.string(rebased)), [for (arg in args) rebaseFunctionBodyExprValue(arg, base, bodyStartIndex)]);
			case ECall(callee, args):
				ECall(rebaseFunctionBodyExprValue(callee, base, bodyStartIndex), [for (arg in args) rebaseFunctionBodyExprValue(arg, base, bodyStartIndex)]);
			case EDiscardThen(effect, continuation):
				EDiscardThen(rebaseFunctionBodyExprValue(effect, base, bodyStartIndex), rebaseFunctionBodyExprValue(continuation, base, bodyStartIndex));
			case EReturn(value):
				EReturn(value == null ? null : rebaseFunctionBodyExprValue(value, base, bodyStartIndex));
			case EVars(declarations):
				EVars([
					for (declaration in declarations)
						HxExprVarDecl.make(HxExprVarDecl.getName(declaration), HxExprVarDecl.getTypeHint(declaration),
							HxExprVarDecl.getInitializer(declaration) == null ? null : rebaseFunctionBodyExprValue(HxExprVarDecl.getInitializer(declaration),
								base, bodyStartIndex),
							rebaseFunctionBodyPos(HxExprVarDecl.getPosition(declaration), base, bodyStartIndex), HxExprVarDecl.getIsFinal(declaration),
							HxExprVarDecl.getIsStatic(declaration))
				]);
			case EVariableDeclaration(name, typeHint, initializer, position, isFinal, isStatic):
				HxExprVarDecl.make(name, typeHint, initializer == null ? null : rebaseFunctionBodyExprValue(initializer, base, bodyStartIndex),
					rebaseFunctionBodyPos(position, base, bodyStartIndex), isFinal, isStatic);
			case EWhile(condition, body, bodyIsBlock, position, loopKind):
				EWhile(rebaseFunctionBodyExprValue(condition, base, bodyStartIndex),
					[for (entry in body) rebaseFunctionBodyExprValue(entry, base, bodyStartIndex)], bodyIsBlock,
					rebaseFunctionBodyPos(position, base, bodyStartIndex), loopKind);
			case EBreak(position):
				EBreak(rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case EContinue(position):
				EContinue(rebaseFunctionBodyPos(position, base, bodyStartIndex));
			case EField(obj, field):
				EField(rebaseFunctionBodyExprValue(obj, base, bodyStartIndex), field);
			case ENullSafeField(obj, field):
				ENullSafeField(rebaseFunctionBodyExprValue(obj, base, bodyStartIndex), field);
			case EBinop(op, left, right):
				EBinop(op, rebaseFunctionBodyExprValue(left, base, bodyStartIndex), rebaseFunctionBodyExprValue(right, base, bodyStartIndex));
			case EUnop(op, fixity, value):
				EUnop(op, fixity, rebaseFunctionBodyExprValue(value, base, bodyStartIndex));
			case ELambda(args, body, signature):
				ELambda(args, rebaseFunctionBodyExprValue(body, base, bodyStartIndex), signature);
			case EArrayDecl(values):
				EArrayDecl([for (value in values) rebaseFunctionBodyExprValue(value, base, bodyStartIndex)]);
			case EArrayAccess(left, right):
				EArrayAccess(rebaseFunctionBodyExprValue(left, base, bodyStartIndex), rebaseFunctionBodyExprValue(right, base, bodyStartIndex));
			case ECast(inner, hint):
				ECast(rebaseFunctionBodyExprValue(inner, base, bodyStartIndex), hint);
			case EUntyped(inner):
				EUntyped(rebaseFunctionBodyExprValue(inner, base, bodyStartIndex));
			case _:
				expr;
		};
	}

	public static function offsetFunctionBodyColumns(stmts:Array<HxStmt>, delta:Int):Array<HxStmt> {
		if (stmts == null || delta == 0)
			return stmts;
		final shifted = new Array<HxStmt>();
		for (stmt in stmts)
			shifted.push(offsetFunctionBodyStmtColumns(stmt, delta));
		return shifted;
	}

	static function offsetFunctionBodyPosColumn(pos:HxPos, delta:Int):HxPos {
		if (pos == null || pos.getLine() <= 0)
			return HxPos.unknown();
		return new HxPos(pos.getIndex(), pos.getLine(), pos.getColumn() + delta);
	}

	static function offsetFunctionBodyExprColumns(expr:Null<HxExpr>, delta:Int):Null<HxExpr> {
		if (expr == null)
			return null;
		return switch (expr) {
			case ESourceTry(catches, bodies, position):
				ESourceTry([
					for (entry in catches)
						new HxSourceCatch(entry.getName(), entry.getTypeHint(), offsetFunctionBodyPosColumn(entry.getPosition(), delta))
				],
					[for (body in bodies) offsetFunctionBodyExprColumns(body, delta)], offsetFunctionBodyPosColumn(position, delta));
			case ESourceFor(binding, iterable, body, position):
				ESourceFor(binding, offsetFunctionBodyExprColumns(iterable, delta), offsetFunctionBodyExprColumns(body, delta),
					offsetFunctionBodyPosColumn(position, delta));
			case ESourceIf(condition, whenTrue, whenFalse, position):
				ESourceIf(offsetFunctionBodyExprColumns(condition, delta), offsetFunctionBodyExprColumns(whenTrue, delta),
					offsetFunctionBodyExprColumns(whenFalse, delta), offsetFunctionBodyPosColumn(position, delta));
			case EThrow(value, position):
				EThrow(offsetFunctionBodyExprColumns(value, delta), offsetFunctionBodyPosColumn(position, delta));
			case ELoweredControl(kind, target, children, position):
				ELoweredControl(kind, target, [for (child in children) offsetFunctionBodyExprColumns(child, delta)],
					offsetFunctionBodyPosColumn(position, delta));
			case ESourceGroup(children, position):
				ESourceGroup([for (child in children) offsetFunctionBodyExprColumns(child, delta)], offsetFunctionBodyPosColumn(position, delta));
			case ESourceFunction(facts, body, defaults, position):
				ESourceFunction(facts, offsetFunctionBodyExprColumns(body, delta), [for (value in defaults) offsetFunctionBodyExprColumns(value, delta)],
					offsetFunctionBodyPosColumn(position, delta));
			case ECall(callee, args):
				ECall(offsetFunctionBodyExprColumns(callee, delta), [for (arg in args) offsetFunctionBodyExprColumns(arg, delta)]);
			case EDiscardThen(effect, continuation):
				EDiscardThen(offsetFunctionBodyExprColumns(effect, delta), offsetFunctionBodyExprColumns(continuation, delta));
			case EReturn(value):
				EReturn(offsetFunctionBodyExprColumns(value, delta));
			case EVars(declarations):
				EVars([
					for (declaration in declarations)
						HxExprVarDecl.make(HxExprVarDecl.getName(declaration), HxExprVarDecl.getTypeHint(declaration),
							offsetFunctionBodyExprColumns(HxExprVarDecl.getInitializer(declaration), delta),
							offsetFunctionBodyPosColumn(HxExprVarDecl.getPosition(declaration), delta), HxExprVarDecl.getIsFinal(declaration),
							HxExprVarDecl.getIsStatic(declaration))
				]);
			case EVariableDeclaration(name, typeHint, initializer, position, isFinal, isStatic):
				HxExprVarDecl.make(name, typeHint, offsetFunctionBodyExprColumns(initializer, delta), offsetFunctionBodyPosColumn(position, delta), isFinal,
					isStatic);
			case EWhile(condition, body, bodyIsBlock, position, loopKind):
				EWhile(offsetFunctionBodyExprColumns(condition, delta), [for (entry in body) offsetFunctionBodyExprColumns(entry, delta)], bodyIsBlock,
					offsetFunctionBodyPosColumn(position, delta), loopKind);
			case EBreak(position):
				EBreak(offsetFunctionBodyPosColumn(position, delta));
			case EContinue(position):
				EContinue(offsetFunctionBodyPosColumn(position, delta));
			case EField(object, field):
				EField(offsetFunctionBodyExprColumns(object, delta), field);
			case ENullSafeField(object, field):
				ENullSafeField(offsetFunctionBodyExprColumns(object, delta), field);
			case EMacroExpr(inner, wrappers):
				EMacroExpr(offsetFunctionBodyExprColumns(inner, delta), wrappers);
			case ELambda(arguments, body, signature):
				ELambda(arguments, offsetFunctionBodyExprColumns(body, delta), signature);
			case ESwitch(scrutinee, patterns, expressions):
				ESwitch(offsetFunctionBodyExprColumns(scrutinee, delta), patterns, [for (branch in expressions) offsetFunctionBodyExprColumns(branch, delta)]);
			case ENew(typePath, arguments):
				ENew(typePath, [for (argument in arguments) offsetFunctionBodyExprColumns(argument, delta)]);
			case EUnop(op, fixity, inner):
				EUnop(op, fixity, offsetFunctionBodyExprColumns(inner, delta));
			case EBinop(op, left, right):
				EBinop(op, offsetFunctionBodyExprColumns(left, delta), offsetFunctionBodyExprColumns(right, delta));
			case ETernary(condition, whenTrue, whenFalse):
				ETernary(offsetFunctionBodyExprColumns(condition, delta), offsetFunctionBodyExprColumns(whenTrue, delta),
					offsetFunctionBodyExprColumns(whenFalse, delta));
			case EAnon(fieldNames, values):
				EAnon(fieldNames, [for (value in values) offsetFunctionBodyExprColumns(value, delta)]);
			case EArrayComprehension(name, iterable, guard, value):
				EArrayComprehension(name, offsetFunctionBodyExprColumns(iterable, delta), offsetFunctionBodyExprColumns(guard, delta),
					offsetFunctionBodyExprColumns(value, delta));
			case EArrayDecl(values):
				EArrayDecl([for (value in values) offsetFunctionBodyExprColumns(value, delta)]);
			case EArrayAccess(array, index):
				EArrayAccess(offsetFunctionBodyExprColumns(array, delta), offsetFunctionBodyExprColumns(index, delta));
			case ERange(start, end):
				ERange(offsetFunctionBodyExprColumns(start, delta), offsetFunctionBodyExprColumns(end, delta));
			case ECast(inner, typeHint):
				ECast(offsetFunctionBodyExprColumns(inner, delta), typeHint);
			case EUntyped(inner):
				EUntyped(offsetFunctionBodyExprColumns(inner, delta));
			case EParenthesized(inner, position):
				EParenthesized(offsetFunctionBodyExprColumns(inner, delta), offsetFunctionBodyPosColumn(position, delta));
			case _:
				expr;
		};
	}

	static function offsetFunctionBodyStmtColumns(stmt:HxStmt, delta:Int):HxStmt {
		return switch (stmt) {
			case STargetScope(_, _, _): throw "native target scope is not valid in this source or target phase";
			case SBlock(stmts, pos):
				final shifted = new Array<HxStmt>();
				for (s in stmts)
					shifted.push(offsetFunctionBodyStmtColumns(s, delta));
				SBlock(shifted, offsetFunctionBodyPosColumn(pos, delta));
			case SVar(name, typeHint, init, pos, metadata):
				SVar(name, typeHint, offsetFunctionBodyExprColumns(init, delta), offsetFunctionBodyPosColumn(pos, delta),
					metadata == null ? [] : metadata.copy());
			case SIf(cond, thenBranch, elseBranch, pos):
				var shiftedElse:Null<HxStmt> = null;
				if (elseBranch != null)
					shiftedElse = offsetFunctionBodyStmtColumns(elseBranch, delta);
				SIf(offsetFunctionBodyExprColumns(cond, delta), offsetFunctionBodyStmtColumns(thenBranch, delta), shiftedElse,
					offsetFunctionBodyPosColumn(pos, delta));
			case SForIn(name, iterable, body, pos):
				SForIn(name, offsetFunctionBodyExprColumns(iterable, delta), offsetFunctionBodyStmtColumns(body, delta),
					offsetFunctionBodyPosColumn(pos, delta));
			case SForKeyValue(keyName, valueName, iterable, body, pos):
				SForKeyValue(keyName, valueName, offsetFunctionBodyExprColumns(iterable, delta), offsetFunctionBodyStmtColumns(body, delta),
					offsetFunctionBodyPosColumn(pos, delta));
			case SWhile(cond, body, pos):
				SWhile(offsetFunctionBodyExprColumns(cond, delta), offsetFunctionBodyStmtColumns(body, delta), offsetFunctionBodyPosColumn(pos, delta));
			case SDoWhile(body, cond, pos):
				SDoWhile(offsetFunctionBodyStmtColumns(body, delta), offsetFunctionBodyExprColumns(cond, delta), offsetFunctionBodyPosColumn(pos, delta));
			case SSwitch(scrutinee, patterns, bodies, pos, exhaustive):
				final shiftedBodies = new Array<HxStmt>();
				for (body in bodies)
					shiftedBodies.push(offsetFunctionBodyStmtColumns(body, delta));
				SSwitch(offsetFunctionBodyExprColumns(scrutinee, delta), patterns, shiftedBodies, offsetFunctionBodyPosColumn(pos, delta), exhaustive);
			case STry(tryBody, catches, pos):
				final shiftedCatches = new Array<{name:String, typeHint:String, body:HxStmt}>();
				for (c in catches)
					shiftedCatches.push({name: c.name, typeHint: c.typeHint, body: offsetFunctionBodyStmtColumns(c.body, delta)});
				STry(offsetFunctionBodyStmtColumns(tryBody, delta), shiftedCatches, offsetFunctionBodyPosColumn(pos, delta));
			case SBreak(pos):
				SBreak(offsetFunctionBodyPosColumn(pos, delta));
			case SContinue(pos):
				SContinue(offsetFunctionBodyPosColumn(pos, delta));
			case SThrow(expr, pos):
				SThrow(offsetFunctionBodyExprColumns(expr, delta), offsetFunctionBodyPosColumn(pos, delta));
			case SReturnVoid(pos):
				SReturnVoid(offsetFunctionBodyPosColumn(pos, delta));
			case SReturn(expr, pos):
				SReturn(offsetFunctionBodyExprColumns(expr, delta), offsetFunctionBodyPosColumn(pos, delta));
			case SExpr(expr, pos):
				SExpr(offsetFunctionBodyExprColumns(expr, delta), offsetFunctionBodyPosColumn(pos, delta));
		}
	}

	static function normalizeInlineJsConditionalMarkers(bodySource:String):String {
		// Stage3 body slices can still contain inline conditional-compilation markers,
		// notably upstream JS-specific assertions shaped like:
		//   expr #if js || js.Browser... #end
		// and stdlib rethrow forms shaped like:
		//   #if neko neko.Lib.rethrow #else throw #end (e)
		//
		// Top-level directive lines are handled by statement parsing, but inline markers
		// appear in the middle of an expression and otherwise surface as `body_parse_error`.
		// Keep this intentionally narrow for the JS-native Gate3 path: remove only the
		// marker text and preserve the guarded JS expression tokens.
		if (bodySource == null || bodySource.indexOf("#") < 0)
			return bodySource == null ? "" : bodySource;
		var normalized = normalizeInlineNekoElseConditionalMarkers(bodySource);
		normalized = normalizeInlineStdCppLengthConditionalMarkers(normalized);
		normalized = normalizeInlineStdHxSerializeConditionalMarkers(normalized);
		normalized = normalizeInlineStdClassSwitchConditionalMarkers(normalized);
		normalized = StringTools.replace(normalized, "#if js", " ");
		normalized = StringTools.replace(normalized, "#end", " ");
		return normalized;
	}

	static function normalizeInlineStdCppLengthConditionalMarkers(source:String):String {
		if (source == null || source.indexOf("#elseif cpp") < 0 || source.indexOf("#end") < 0)
			return source;
		var out = source;
		var search = 0;
		while (search < out.length) {
			final idxIf = out.indexOf("#if", search);
			if (idxIf < 0)
				break;
			final idxElseIfCpp = out.indexOf("#elseif cpp", idxIf + 3);
			final idxEnd = out.indexOf("#end", idxIf + 3);
			if (idxElseIfCpp < 0 || idxEnd < 0 || idxElseIfCpp > idxEnd)
				break;
			final idxElse = out.indexOf("#else", idxElseIfCpp + 12);
			final cppPayloadEnd = idxElse >= 0 && idxElse < idxEnd ? idxElse : idxEnd;
			final cppPayload = StringTools.trim(out.substr(idxElseIfCpp + 12, cppPayloadEnd - (idxElseIfCpp + 12)));
			if (cppPayload != "v.__length()") {
				search = idxEnd + 4;
				continue;
			}
			final conditionalText = out.substr(idxIf, idxEnd + 4 - idxIf);
			if (conditionalText.indexOf("v.length") < 0 && conditionalText.indexOf("__getField") < 0) {
				search = idxEnd + 4;
				continue;
			}
			final prefix = out.substr(0, idxIf);
			final suffix = out.substr(idxEnd + 4);
			out = prefix + cppPayload + suffix;
			search = prefix.length + cppPayload.length;
		}
		return out;
	}

	static function normalizeInlineStdHxSerializeConditionalMarkers(source:String):String {
		if (source == null || source.indexOf("hxSerialize") < 0 || source.indexOf("#else") < 0 || source.indexOf("#end") < 0)
			return source;
		var out = source;
		var search = 0;
		while (search < out.length) {
			final idxIf = out.indexOf("#if", search);
			if (idxIf < 0)
				break;
			final idxEnd = out.indexOf("#end", idxIf + 3);
			if (idxEnd < 0)
				break;
			final conditionalText = out.substr(idxIf, idxEnd + 4 - idxIf);
			if (conditionalText.indexOf("hxSerialize") < 0
				|| conditionalText.indexOf("Reflect.hasField") < 0
				|| conditionalText.indexOf("method_exists") < 0) {
				search = idxEnd + 4;
				continue;
			}
			final idxElse = conditionalText.lastIndexOf("#else");
			if (idxElse < 0) {
				search = idxEnd + 4;
				continue;
			}
			final elsePayload = StringTools.trim(conditionalText.substr(idxElse + 5, conditionalText.length - 4 - (idxElse + 5)));
			if (elsePayload != "v.hxSerialize != null") {
				search = idxEnd + 4;
				continue;
			}
			final prefix = out.substr(0, idxIf);
			final suffix = out.substr(idxEnd + 4);
			out = prefix + elsePayload + suffix;
			search = prefix.length + elsePayload.length;
		}
		return out;
	}

	static function normalizeInlineStdClassSwitchConditionalMarkers(source:String):String {
		if (source == null || source.indexOf("#if") < 0 || source.indexOf("#else") < 0 || source.indexOf("#end") < 0)
			return source;
		var out = source;
		var search = 0;
		while (search < out.length) {
			final idxIf = out.indexOf("#if", search);
			if (idxIf < 0)
				break;
			final idxElse = out.indexOf("#else", idxIf + 3);
			final idxEnd = out.indexOf("#end", idxIf + 3);
			if (idxElse < 0 || idxEnd < 0 || idxElse > idxEnd)
				break;
			final thenPayload = out.substr(idxIf, idxElse - idxIf);
			final replacement = if (thenPayload.indexOf("Type.getClassName(c)") >= 0) {
				"Type.getClassName(c)";
			} else if (thenPayload.indexOf('"Array"') >= 0) {
				'"Array"';
			} else {
				null;
			}
			if (replacement == null) {
				search = idxEnd + 4;
				continue;
			}
			final prefix = out.substr(0, idxIf);
			final suffix = out.substr(idxEnd + 4);
			out = prefix + replacement + suffix;
			search = prefix.length + replacement.length;
		}
		return out;
	}

	static function normalizeInlineNekoElseConditionalMarkers(source:String):String {
		if (source == null || source.indexOf("#if neko") < 0 || source.indexOf("#else") < 0 || source.indexOf("#end") < 0)
			return source;
		var out = source;
		var search = 0;
		while (search < out.length) {
			final idxIf = out.indexOf("#if neko", search);
			if (idxIf < 0)
				break;
			final idxElse = out.indexOf("#else", idxIf + 8);
			final idxEnd = out.indexOf("#end", idxIf + 8);
			if (idxElse < 0 || idxEnd < 0 || idxElse > idxEnd)
				break;
			final lineEnd = out.indexOf("\n", idxIf);
			if (lineEnd >= 0 && idxEnd > lineEnd)
				break;
			final prefix = out.substr(0, idxIf);
			final elsePayload = out.substr(idxElse + 5, idxEnd - (idxElse + 5));
			final suffix = out.substr(idxEnd + 4);
			out = prefix + elsePayload + suffix;
			search = prefix.length + elsePayload.length;
		}
		return out;
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
			case EBinop(op, EIdent(name), EInt(value)) if (isIntCompareGuardOp(op)):
				PIntCompareGuard(pattern, name, op, value);
			case ESwitch(EBinop("*", ECall(EField(EIdent("Std"), "parseInt"), [EIdent(name)]), EInt(multiplier)), patterns, exprs):
				switchParsedIntGuard(pattern, name, multiplier, patterns, exprs);
			case _:
				PUnsupportedGuard(pattern);
		}
	}

	function isIntCompareGuardOp(op:String):Bool {
		return op == "<" || op == "<=" || op == ">" || op == ">=";
	}

	function switchParsedIntGuard(pattern:HxSwitchPattern, name:String, multiplier:Int, patterns:Array<HxSwitchPattern>, exprs:Array<HxExpr>):HxSwitchPattern {
		if (patterns != null && exprs != null) {
			final count = patterns.length < exprs.length ? patterns.length : exprs.length;
			for (i in 0...count) {
				switch [patterns[i], exprs[i]] {
					case [PInt(value), EBool(true)]:
						return PParsedIntSwitchGuard(pattern, name, multiplier, value);
					case _:
				}
			}
		}
		return PUnsupportedGuard(pattern);
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

	function parseSwitchPatternAtom(allowExtractor:Bool = true):HxSwitchPattern {
		final extractor = allowExtractor ? tryParseSwitchExtractorPattern() : null;
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
						// Explicit `var` always captures, even when an enum member has this name.
						PCapture(name, PWildcard);
					case _:
						PWildcard;
				}
			case TKeyword(KCast):
				// Upstream stdlib uses class-value switch cases like `case cast Array:`
				// after target-specific conditional compilation chooses the native branch.
				bump();
				final typeText = StringTools.trim(readTypeHintText(() -> cur.kind.match(TColon) || cur.kind.match(TComma) || cur.kind.match(TRBrace)
					|| cur.kind.match(TEof) || cur.kind.match(TKeyword(KIf)) || isOtherChar("|")));
				typeText.length == 0 ? PWildcard : PEnumValue(typeText);
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
						case TString(name, _):
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
			case TString(s, _):
				bump();
				if (cur.kind.match(TDot)) {
					switch (peekKind()) {
						case TIdent("code"):
							// Haxe std target overrides commonly use char-code case patterns:
							// `case '+'.code:` and `case ['2'.code, '1'.code]:`.
							// Treat the string literal's first code unit as the pattern value so
							// parser bring-up can keep these switches structured.
							bump(); // `.`
							bump(); // `code`
							PInt(s == null || s.length == 0 ? -1 : s.charCodeAt(0));
						case _:
							PString(s);
					}
				} else {
					PString(s);
				}
			case TInt(v):
				bump();
				PInt(v);
			case TIdent(name) if (name == "macro" && peekKind().match(TColon)):
				parseMacroTypeSwitchPattern();
			case TIdent(name) if (name == "macro"):
				parseMacroExprSwitchPattern();
			case TIdent(name):
				bump();
				// Preserve the owner so typing can reject a constructor from another
				// enum even when both declarations use the same member name.
				var patternName = name;
				while (cur.kind.match(TDot)) {
					bump();
					switch (cur.kind) {
						case TIdent(segment):
							patternName += "." + segment;
							bump();
						case _:
							fail("Expected pattern member after '.'");
					}
				}
				final qualified = patternName != name;
				if ((qualified || isUpperStart(name)) && cur.kind.match(TLParen)) {
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
					PEnumExtract(patternName, args);
				} else if (!qualified && !isUpperStart(name) && acceptOtherChar("=")) {
					PCapture(name, parseSwitchPatternAtom());
				} else {
					qualified
					|| isUpperStart(name) ? PEnumValue(patternName) : PBind(name);
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

	function parseMacroExprSwitchPattern():HxSwitchPattern {
		// `case macro <expr>:` is a Haxe macro-pattern quote. Full macro-pattern
		// matching is larger than the Stage3 switch subset, but the parser must
		// consume the quote as one case pattern so metadata like `@:markup` and
		// splice forms like `$v{...}` do not make the case separator look missing.
		switch (cur.kind) {
			case TIdent("macro"):
				bump();
			case _:
				return PUnsupportedGuard(PWildcard);
		}

		var parenDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		var previousTokenWasAt = false;
		while (!cur.kind.match(TEof)) {
			final atTop = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0;
			if (atTop && cur.kind.match(TColon) && !previousTokenWasAt && !peekKind().match(TOther("$".code)))
				break;
			if (atTop && (cur.kind.match(TComma) || cur.kind.match(TKeyword(KIf)) || cur.kind.match(TRBrace) || isOtherChar("|")))
				break;

			final currentWasAt = cur.kind.match(TOther("@".code));
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
			previousTokenWasAt = currentWasAt;
		}
		return PUnsupportedGuard(PWildcard);
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
			if (atTop
				&& (cur.kind.match(TColon) || cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TRBrace) || cur.kind.match(TKeyword(KIf))
					|| isOtherChar("|")))
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
		// A qualified constructor and a static extractor share the same prefix.
		// Without an arrow, parse the consumed slice with the ordinary pattern
		// grammar. Disable only this outer probe so it cannot call itself again.
		final memberParser = new HxParser(sliceSource(start, currentIndex()));
		final memberPattern = memberParser.parseSwitchPatternAtom(false);
		if (memberParser.cur.kind.match(TEof))
			return memberPattern;
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

	inline function nextIsAdjacentDot():Bool {
		final next = peek();
		return next.kind.match(TDot) && next.pos.getIndex() == cur.pos.getIndex() + 1;
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

	function readHeaderTypePath():String {
		final out = new StringBuf();
		out.add(readDottedPath());
		if (!isOtherChar("<"))
			return out.toString();
		var depth = 0;
		while (!cur.kind.match(TEof)) {
			switch (cur.kind) {
				case TIdent(name):
					out.add(name);
					bump();
				case TDot:
					out.add(".");
					bump();
				case TComma:
					out.add(",");
					bump();
				case TKeyword(k):
					out.add(keywordText(k));
					bump();
				case TOther(c) if (c == "<".code):
					out.add("<");
					bump();
					depth += 1;
				case TOther(c) if (c == ">".code):
					out.add(">");
					bump();
					depth -= 1;
					if (depth <= 0)
						return out.toString();
				case _:
					bump();
			}
		}
		return out.toString();
	}

	function skipHeaderTypeParameters():Void {
		if (!isOtherChar("<"))
			return;
		var depth = 0;
		while (!cur.kind.match(TEof)) {
			if (isOtherChar("<")) {
				bump();
				depth += 1;
				continue;
			}
			if (isOtherChar(">")) {
				bump();
				depth -= 1;
				if (depth <= 0)
					return;
				continue;
			}
			bump();
		}
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

	function readBalancedParenBodyText():String {
		// Called when current token is '(' and the caller needs the raw body text.
		if (!cur.kind.match(TLParen))
			fail("Expected parenthesis group");
		bump();
		final bodyStart = currentIndex();
		var bodyEnd = bodyStart;
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
					if (depth == 0) {
						bodyEnd = currentIndex();
						bump();
					} else {
						bump();
					}
				case _:
					bump();
			}
		}
		return StringTools.trim(sliceSource(bodyStart, bodyEnd));
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
				case TOther(c) if (c == "-".code && peekKind().match(TOther(">".code))):
					bump();
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

	function readTypeHintText(stop:() -> Bool, stopAtExpressionBody:Bool = false):String {
		// Bootstrap: type hints are kept as raw text until we implement a full type grammar.
		final parts = new Array<String>();
		var parenDepth = 0;
		var braceDepth = 0;
		var angleDepth = 0;
		var bracketDepth = 0;
		var previousCanEndType = false;
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
			final isIdentifier = cur.kind.match(TIdent(_));
			// Without type punctuation, a second top-level name starts the function body.
			if (stopAtExpressionBody && atTopLevel && previousCanEndType && isIdentifier)
				break;
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
				case TString(s, _):
					parts.push('"' + s + '"');
					bump();
				case TInt(v):
					parts.push(cur.numericText != null ? cur.numericText + (cur.numericSuffix == null ? "" : cur.numericSuffix) : Std.string(v));
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
			final last = parts.length == 0 ? "" : parts[parts.length - 1];
			previousCanEndType = isIdentifier
				|| last == ")"
				|| last == "}"
				|| (last == ">" && (parts.length < 2 || parts[parts.length - 2] != "-"));
		}
		return parts.join("");
	}

	function readFunctionReturnTypeHint(stop:() -> Bool):String {
		// In signatures like `function f():Bytes untyped { ... }`, `untyped`
		// modifies the function body. Leave the token for the body parser so
		// the syntax tree retains the permission to use untyped expressions.
		// Abstract constructors may use a semicolonless `this = value` body, so
		// `this` is also a body boundary and can never be part of a type hint.
		// Body metadata must reach the statement parser with its permission scope intact.
		final hint = readTypeHintText(() -> stop() || isOtherChar("@") || cur.kind.match(TKeyword(KUntyped)) || cur.kind.match(TKeyword(KThis))
			|| cur.kind.match(TKeyword(KSwitch)) || cur.kind.match(TKeyword(KIf)) || cur.kind.match(TKeyword(KFor)) || cur.kind.match(TKeyword(KWhile))
			|| cur.kind.match(TKeyword(KDo)) || cur.kind.match(TKeyword(KTry)),
			true);
		return hint;
	}

	function parsePrimaryExpr():HxExpr {
		return switch (cur.kind) {
			case TLParen:
				// Parenthesized expression: `(expr)`.
				final position = cur.pos;
				bump(); // '('
				final inner = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
				if (!cur.kind.match(TRParen))
					fail("Expected closing parenthesis");
				bump();
				EParenthesized(inner, position);
			case TLBrace:
				parseBraceExpr();
			case TKeyword(k):
				if (k == KVar
					|| k == KFinal
					|| (k == KStatic && (peekKind().match(TKeyword(KVar)) || peekKind().match(TKeyword(KFinal))))) {
					parseExpressionVariableDeclarations();
				} else if (k == KNull) {
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
				} else if (k == KReturn) {
					// Macro arguments are source expressions, so valid Haxe can contain shapes
					// such as `expectError(return (null : Null<String>))`. Preserve the return
					// and its value structurally; the outer call still owns its closing `)`.
					bump();
					final value = if (cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TSemicolon) || cur.kind.match(TRBrace)
						|| cur.kind.match(TEof)) null; else parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TSemicolon)
						|| cur.kind.match(TRBrace) || cur.kind.match(TEof));
					EReturn(value);
				} else if (k == KInline) {
					bump();
					cur.kind.match(TKeyword(KFunction)) ? parseFunctionExpr(Value, true) : parsePrimaryExpr();
				} else if (k == KNew) {
					bump();
					var typePath = readConstructorTypePath();
					if (isOtherChar("<")) {
						final typeArgs = readTypeHintText(() -> cur.kind.match(TLParen) || cur.kind.match(TEof));
						if (typeArgs.length > 0)
							typePath += typeArgs;
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
					parseSourceForExpr(() -> false);
				} else if (k == KDo) {
					parseDoWhileExpr();
				} else if (k == KThrow) {
					parseThrowExpr(() -> false);
				} else if (k == KAs) {
					bump();
					EIdent("as");
				} else {
					// Best-effort: capture the keyword as a string.
					final raw = keywordText(k);
					final detail = unsupportedKeywordDetail(raw);
					bump();
					EUnsupported(detail);
				}
			case TString(s, interpolate): bump(); // The literal-only code operation checks decoded source text before interpolation.
				// Keep its field-access syntax intact for macro quotation and later typing.
				final literalCode = cur.kind.match(TDot) && peekKind().match(TIdent("code")); interpolate && !literalCode ? parseInterpolatedStringExpr(s) : EString(s);
			case TInt(v):
				final raw = cur.numericText;
				final suffix = cur.numericSuffix;
				bump();
				intLiteralExpr(v, raw, suffix);
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
				// - Keep underscore-bearing helper names as identifiers. The bootstrap compiler uses
				//   generated helpers such as `TitleCase_Helper`, which are calls rather than enum tags.
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
				(isUpperStart(name) && !cur.kind.match(TDot) && hasLowerAlpha(name) && name.indexOf("_") == -1) ? EEnumValue(name) : EIdent(name);
			case TOther(c) if (c == "[".code):
				parseArrayDeclExpr();
			case TOther(c) if (c == "$".code):
				parseDollarExpression();
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

	/** Keep the body and trailing condition in the original loop, without helper callables. */
	function parseDoWhileExpr():HxExpr {
		final position = cur.getPos();
		bump(); // `do`
		final bodyIsBlock = cur.kind.match(TLBrace);
		final body = parseWhileBody(() -> cur.kind.match(TSemicolon) || cur.kind.match(TKeyword(KWhile)) || cur.kind.match(TEof));
		if (!acceptKeyword(KWhile))
			fail("Expected while after do body");
		expect(TLParen, "'(' after do/while");
		final condition = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
		expect(TRParen, "')' after do/while condition");
		return EWhile(condition, body, bodyIsBlock, position, DoWhile);
	}

	/**
		Preserve a while loop passed to a macro as source expression syntax.

		The outer expression parser owns commas and closing call parentheses. A brace
		body is parsed into an ordered expression list so the macro bridge can rebuild
		an actual Haxe `EBlock`; an empty block is therefore not confused with `{}` as
		an anonymous-object value.
	**/
	function parseWhileExpr(stop:() -> Bool):HxExpr {
		final position = cur.getPos();
		bump(); // `while`
		expect(TLParen, "'(' after while");
		final condition = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
		expect(TRParen, "')' after while condition");
		final bodyIsBlock = cur.kind.match(TLBrace);
		return EWhile(condition, parseWhileBody(stop), bodyIsBlock, position, Normal);
	}

	/** Both loop kinds retain the same ordered brace body and single-expression body contract. */
	function parseWhileBody(stop:() -> Bool):Array<HxExpr> {
		final body = new Array<HxExpr>();
		final bodyIsBlock = cur.kind.match(TLBrace);
		if (bodyIsBlock) {
			bump(); // '{'
			while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
				final entry = parseAuthoredControl(() -> parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof)));
				body.push(entry);
				if (cur.kind.match(TSemicolon)) {
					bump();
				} else if (!cur.kind.match(TRBrace) && !endsWithSourceBrace(entry)) {
					fail("Expected ';' or '}' after while body expression");
				}
			}
			expect(TRBrace, "'}' after while body");
		} else {
			if (stop() || cur.kind.match(TEof))
				fail("Expected while body");
			body.push(parseAuthoredControl(() -> parseExpr(stop)));
		}
		return body;
	}

	/**
		Dollar names are primitive identifiers in ordinary expressions and value
		splices inside a macro quote. Braced splice payloads are ordinary expressions.
	**/
	function parseDollarExpression():HxExpr {
		// Macro reification splice: `$i{name}`, `$e{expr}`, `$b{expr}`, ...
		//
		// Bring-up scope
		// - Consume the balanced splice payload so macro quotes don't throw and
		//   become `body_parse_error`.
		// - Model identifier splices explicitly because generator code commonly uses
		//   `$i{name}(...)` to build calls to generated fields.
		// - Model unbraced expression splices (`$value`, `$receiver.field`) as expression
		//   splice markers and let normal postfix parsing consume field/call suffixes.
		if (!acceptOtherChar("$"))
			return EUnsupported("$");
		final dollarName = switch (cur.kind) {
			case TIdent(name): name;
			case TKeyword(keyword): keywordText(keyword);
			case _: "";
		}
		if (dollarName.length > 0 && !peekKind().match(TLBrace)) {
			bump();
			return inMacroQuote ? ECall(EIdent("__hxhx_macro_expr_splice"), [EIdent(dollarName)]) : EIdent("$" + dollarName);
		}
		if (!inMacroQuote)
			fail("Reification is not allowed outside of a macro expression");
		final spliceKind = switch (cur.kind) {
			case TIdent(name):
				bump();
				name;
			case _:
				"expr";
		}
		final payload = if (cur.kind.match(TLBrace)) {
			bump();
			final inner = withMacroQuoteContext(false, () -> parseExpr(() -> cur.kind.match(TRBrace) || cur.kind.match(TEof)));
			if (cur.kind.match(TRBrace))
				bump();
			inner;
		} else {
			withMacroQuoteContext(false,
				() -> parseUnaryExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TRBrace) || cur.kind.match(TSemicolon)
					|| cur.kind.match(TEof)));
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

	/**
		Keep full functions in their authored form until shared typing resolves control.

		Defaults are parameter-entry expressions, not replacements for parameter reads.
		An explicit return stays inside its original brace group so macros and lowering
		can distinguish it from a normally completed value expression.
	**/
	function parseFunctionExpr(placement:HxSourceFunction.HxSourceFunctionPlacement = Value, isInline:Bool = false):HxExpr {
		final position = cur.getPos();
		if (!acceptKeyword(KFunction))
			fail("Expected 'function'");
		final name = switch cur.kind {
			case TIdent(name):
				bump();
				name;
			case _: null;
		};
		final generics = new HxSourceFunctionGenerics(new HxTypedefParser(this).parameters());
		if (isInline && name == null)
			fail("Inline source functions require a name");
		final inputs = parseSourceFunctionParameters();
		var returnType = "";
		if (cur.kind.match(TColon)) {
			bump();
			returnType = readFunctionReturnTypeHint(() -> cur.kind.match(TLBrace) || cur.kind.match(TKeyword(KReturn)) || cur.kind.match(TKeyword(KThrow))
				|| cur.kind.match(TSemicolon) || cur.kind.match(TEof));
		}
		final body = parseAuthoredControl(() -> parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TComma) || cur.kind.match(TRParen)
			|| cur.kind.match(TRBrace) || cur.kind.match(TEof)));
		final facts = new HxSourceFunction({
			kind: name == null ? Anonymous : Named(name, isInline),
			placement: placement,
			generics: generics,
			arguments: inputs.arguments,
			signature: new HxLambdaSignature(inputs.parameters, returnType.length == 0 ? null : returnType)
		});
		return ESourceFunction(facts, body, inputs.defaults, position);
	}

	/** Named statements retain their function syntax until shared typing and lowering. */
	function parseLocalFunctionStmt(pos:HxPos, isInline:Bool = false):HxStmt {
		final expression = parseFunctionExpr(Declaration, isInline);
		if (cur.kind.match(TSemicolon))
			bump();
		return SExpr(expression, pos);
	}

	function lambdaBodyExprFromStmts(stmts:Array<HxStmt>, distinguishVoidCompletion:Bool = false):HxExpr {
		// A function that falls through has no result. Keep the selected Void
		// ascription distinct from an authored `return null` before typing.
		final noValue:HxExpr = distinguishVoidCompletion ? ECast(ENull, "Void") : ENull;
		if (stmts == null || stmts.length == 0)
			return noValue;

		var unsupportedStmtKind = "function";

		inline function stmtKindText(stmt:HxStmt):String {
			return switch (stmt) {
				case STargetScope(_, _, _): throw "native target scope is not valid in this source or target phase";
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
		function lowerStmtWithContinuation(stmt:HxStmt, continuation:HxExpr):Null<HxExpr> {
			return switch (stmt) {
				case SReturn(expr, _):
					expr;
				case SReturnVoid(_):
					noValue;
				case SExpr(expr, _):
					EDiscardThen(expr, continuation);
				case SVar(name, typeHint, init, _):
					final initExpr:HxExpr = switch (init) {
						case null:
							ENull;
						case value:
							value;
					};
					// The lambda transports a source local. Keep its written type so
					// immediate-call inference cannot narrow an explicit Dynamic binding.
					final signature = new HxLambdaSignature([
						{
							typeHint: typeHint == null || StringTools.trim(typeHint).length == 0 ? null : typeHint,
							isOptional: false,
							isRest: false,
							hasDefault: false
						}
					]);
					ECall(ELambda([name], continuation, signature), [initExpr]);
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
				case SThrow(expr, position):
					EThrow(expr, position);
				case SBreak(_) | SContinue(_):
					// Expression-lowered callback bodies use a continuation chain. During source
					// target bring-up, preserve parseability for switch/loop branches that end in
					// `break`/`continue` by terminating that branch without forcing an opaque raw block.
					ENull;
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

		var result:HxExpr = noValue;
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

	function intLiteralExpr(value:Int, raw:Null<String>, suffix:Null<String>):HxExpr {
		if (raw == null || suffix == null)
			return EInt(value);
		final normalizedSuffix = suffix.toLowerCase();
		if (normalizedSuffix == "i32" || normalizedSuffix == "u32" || normalizedSuffix == "i64" || normalizedSuffix == "u64")
			return ECall(EIdent("__hxhx_int_literal"), [EString(raw), EString(normalizedSuffix)]);
		return EInt(value);
	}

	function parseInterpolatedStringExpr(s:String):HxExpr {
		// String interpolation (bring-up subset):
		// - `$ident`
		// - `${ident}`
		// - `${this.field}` / `${ident.field}`
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

		function parseInterpolationPayload(text:String):Null<HxExpr> {
			if (text == null)
				return null;
			final trimmed = StringTools.trim(text);
			if (trimmed.length == 0)
				return null;
			final names = trimmed.split(".");
			var isSimplePath = names.length > 0;
			for (name in names)
				if (!isSimpleIdent(name))
					isSimplePath = false;
			if (isSimplePath) {
				var expr:HxExpr = names[0] == "this" ? EThis : EIdent(names[0]);
				for (i in 1...names.length)
					expr = EField(expr, names[i]);
				return expr;
			}
			return try {
				switch (HxParser.parseExprText(trimmed)) {
					case EUnsupported(_): null;
					case expr: expr;
				}
			} catch (_:Dynamic) {
				null;
			};
		}

		inline function stringifyExpr(expr:HxExpr):HxExpr {
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
			return EBinop("+", EString(""), expr);
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
					final payload = parseInterpolationPayload(s.substr(start, j - start));
					if (payload != null) {
						parts.push(stringifyExpr(payload));
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
				parts.push(stringifyExpr(name == "this" ? EThis : EIdent(name)));
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

		// Comprehensions are authored array contents, not calls to a synthetic helper.
		// The ordinary for parser preserves nested loops, guards, bindings, and groups.
		if (cur.kind.match(TKeyword(KFor))) {
			final loop = parseSourceForExpr(() -> cur.kind.match(TOther("]".code)) || cur.kind.match(TEof));
			if (!cur.kind.match(TOther("]".code)))
				fail("Expected ']' after comprehension");
			bump();
			return EArrayDecl([loop]);
		}

		final values = new Array<HxExpr>();
		final mapEntries = new Array<HxExpr>();
		var sawMapEntry = false;

		if (cur.kind.match(TOther("]".code))) {
			bump();
			return EArrayDecl(values);
		}
		while (!cur.kind.match(TEof)) {
			if (cur.kind.match(TOther("#".code))) {
				consumePreprocessorLine();
				continue;
			}
			if (cur.kind.match(TOther("]".code))) {
				bump();
				break;
			}
			final value = parseExpr(() -> isFatArrowStart() || cur.kind.match(TComma) || cur.kind.match(TOther("]".code)) || cur.kind.match(TEof));
			if (isFatArrowStart()) {
				sawMapEntry = true;
				bump(); // '='
				bump(); // '>'
				final mapValue = parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TOther("]".code)) || cur.kind.match(TEof));
				mapEntries.push(EBinop("=>", value, mapValue));
			} else {
				values.push(value);
			}
			if (cur.kind.match(TComma)) {
				bump();
				if (cur.kind.match(TOther("#".code)))
					consumePreprocessorLine();
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
				if (cur.kind.match(TOther("#".code)))
					consumePreprocessorLine();
				continue;
			}
			if (cur.kind.match(TOther("]".code))) {
				bump();
				break;
			}
		}
		if (sawMapEntry)
			return EArrayDecl(mapEntries);
		return EArrayDecl(values);
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

	/**
		Reports whether the current opening brace starts an anonymous-object value.

		Haxe uses the same braces for statement blocks and anonymous objects. A field
		name followed by `:` is the structural distinction needed by statement-level
		branches such as `if (condition) { value: expression } else ...`.
	**/
	function braceStartsAnonLiteral():Bool {
		if (!cur.kind.match(TLBrace))
			return false;
		return switch (peekKind()) {
			case TIdent(_) | TString(_, _):
				peekKind2().match(TColon);
			case _:
				false;
		};
	}

	/**
		Parse declarations passed to a macro as source syntax.

		The outer call still owns its closing parenthesis. A comma followed by another
		identifier belongs to the same Haxe `EVars` expression; malformed input fails
		here instead of being reinterpreted as an unrelated runtime argument.
	**/
	function parseExpressionVariableDeclarations():HxExpr {
		var isStatic = false;
		if (cur.kind.match(TKeyword(KStatic))) {
			isStatic = true;
			bump();
		}
		final isFinal = cur.kind.match(TKeyword(KFinal));
		if (!acceptKeyword(KVar) && !acceptKeyword(KFinal))
			fail("Expected 'var' or 'final'");

		final declarations = new Array<HxExpr>();
		while (true) {
			final position = cur.getPos();
			final name = readIdent("variable name");
			var typeHint = "";
			if (cur.kind.match(TColon)) {
				bump();
				typeHint = readTypeHintText(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TSemicolon) || cur.kind.match(TEof)
					|| isOtherChar("="));
			}
			var initializer:Null<HxExpr> = null;
			if (acceptOtherChar("="))
				initializer = parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TSemicolon) || cur.kind.match(TRBrace)
					|| cur.kind.match(TEof));
			declarations.push(HxExprVarDecl.make(name, typeHint, initializer, position, isFinal, isStatic));
			if (!cur.kind.match(TComma))
				break;
			bump();
		}
		return EVars(declarations);
	}

	/**
		Preserve source braces as recursive groups; field-bearing braces remain objects.

		Each child is parsed directly as source syntax. This avoids statement-to-value
		rewrites that used to flatten groups and redirect returns through artificial lambdas.
	**/
	function parseBraceExpr():HxExpr {
		final position = cur.getPos();
		expect(TLBrace, "'{'");
		final isAnonLiteral = switch (cur.kind) {
			case TIdent(_) | TString(_, _): peekKind().match(TColon);
			case _: false;
		}
		if (isAnonLiteral)
			return parseAnonExprAfterOpen();
		final children = new Array<HxExpr>();
		while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
			if (cur.kind.match(TSemicolon)) {
				bump();
				continue;
			}
			final start = currentIndex();
			final child = parseAuthoredControl(() -> parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof)));
			children.push(child);
			if (currentIndex() == start)
				fail("Expected source group expression");
			if (cur.kind.match(TSemicolon))
				bump();
			else if (!cur.kind.match(TRBrace)) {
				if (!endsWithSourceBrace(child))
					fail("Expected ';' after source group expression");
			}
		}
		expect(TRBrace, "'}' after source group");
		return ESourceGroup(children, position);
	}

	/** A final source brace terminates an expression, including a function's returned block; parentheses do not. */
	static function endsWithSourceBrace(expression:HxExpr):Bool {
		return switch expression {
			case ESourceTry(_, bodies, _): bodies.length > 0 && endsWithSourceBrace(bodies[bodies.length - 1]);
			case ESourceGroup(_, _) | ESwitch(_, _, _): true;
			case ESourceFunction(_, body, _, _): endsWithSourceBrace(body);
			case EReturn(value): value != null && endsWithSourceBrace(value);
			case ESourceIf(_, whenTrue, whenFalse, _): endsWithSourceBrace(whenFalse == null ? whenTrue : whenFalse);
			case EWhile(_, body, bodyIsBlock, _, loopKind): loopKind == Normal && (bodyIsBlock
					|| (body.length == 1 && endsWithSourceBrace(body[0])));
			case ESourceFor(_, _, body, _): endsWithSourceBrace(body);
			case EVars(declarations): final initializer = declarations.length == 0 ? null : HxExprVarDecl.getInitializer(declarations[declarations.length - 1]); initializer != null && endsWithSourceBrace(initializer);
			case _: false;
		};
	}

	/** Preserve a named function's declaration placement when it appears as a body entry. */
	function parseAuthoredControl(parse:Void->HxExpr):HxExpr {
		final startsFunction = cur.kind.match(TKeyword(KFunction)) || cur.kind.match(TKeyword(KInline));
		final result = parse();
		return switch result {
			case ESourceFunction(facts, body, defaults, position) if (startsFunction && facts.getDeclaredName() != null):
				ESourceFunction(new HxSourceFunction({
					kind: facts.getKind(),
					placement: Declaration,
					arguments: facts.getArguments(),
					signature: facts.getSignature()
				}), body, defaults, position);
			case _: result;
		};
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
			case TString(s, _):
				bump();
				s;
			case _:
				readIdent("field name");
		}
	}

	static function binopPrec(op:String):Int {
		return switch (op) {
			case "=>" | "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "<<=" | ">>=" | ">>>=" | "&=" | "|=" | "^=" | "??=": 1;
			case "?": 2;
			case "??": 2;
			case "||": 2;
			case "&&": 3;
			case "==" | "!=" | "is": 4;
			case "|" | "&" | "^": 5;
			case "<<" | ">>" | ">>>": 5;
			case "<" | "<=" | ">" | ">=": 5;
			case "+" | "-": 6;
			case "*" | "/": 7;
			case "%": 8;
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
		return op == "=>" || isAssignmentBinop(op);
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
				case TKeyword(KIn):
					// Upstream binds 'in' to the immediately preceding expression,
					// then reads its binary RHS before an outer ternary conditional.
					bump();
					e = EBinop("in", e, parseBinaryExpr(1, stop));
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
					final field = readPostfixFieldName();
					e = EField(e, field);
				case TOther(c) if (c == "?".code && nextIsAdjacentDot()):
					// Null-safe access is one postfix operation. If `?` is left for
					// `parseExpr`, it is misread as the start of a ternary expression.
					bump();
					bump();
					final field = readPostfixFieldName();
					e = ENullSafeField(e, field);
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
					final op = (c == "+".code) ? HxUnaryOperator.Increment : HxUnaryOperator.Decrement;
					bump();
					bump();
					e = EUnop(op, HxUnaryFixity.Postfix, e);
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
			case TKeyword(k) if (k == KBreak):
				final position = cur.getPos();
				bump();
				EBreak(position);
			case TKeyword(k) if (k == KContinue):
				final position = cur.getPos();
				bump();
				EContinue(position);
			case TKeyword(k) if (k == KWhile):
				parseWhileExpr(stop);
			case TKeyword(KDo):
				parseDoWhileExpr();
			case TKeyword(KFor):
				parseSourceForExpr(stop);
			case TKeyword(k) if (k == KIf):
				parseIfExpr(stop);
			case TKeyword(k) if (k == KThrow):
				parseThrowExpr(stop);
			case TKeyword(k) if (k == KSwitch):
				parseSwitchExpr(stop);
			case TKeyword(k) if (k == KTry):
				// Assignment and binary operands enter here without passing through parseExpr.
				// Reuse the same try body, catch boundaries, and structural recovery.
				parseSourceTryExpr(stop);
			case TOther("@".code):
				// Expression-level metadata: `@:meta expr`.
				//
				// Bring-up semantics: retain a small marker so known helper macros such as
				// `unit.HelperMacros.getMeta(@foo expr)` can observe the metadata. Normal
				// runtime emission unwraps the marker and keeps the underlying expression.
				final metadata = new Array<{
					name:String,
					args:String,
					position:HxPos,
					privateAccess:Bool
				}>();
				while (cur.kind.match(TOther("@".code))) {
					final position = cur.getPos();
					bump();
					final compilerMetadata = cur.kind.match(TColon);
					if (compilerMetadata)
						bump();
					final meta = readMetadataHead();
					var argsText = "";
					if (hasAttachedMetadataArgs(meta.name, meta.endIndex)) {
						argsText = readBalancedParenBodyText();
					}
					metadata.push({
						name: meta.name,
						args: argsText,
						position: position,
						privateAccess: compilerMetadata && meta.name == "privateAccess"});
				}
				var inner = parseUnaryExpr(stop);
				var i = metadata.length - 1;
				while (i >= 0) {
					final entry = metadata[i];
					inner = entry.privateAccess ? EPrivateAccess(inner,
						entry.position) : ECall(EIdent("__hxhx_expr_meta"), [EString(entry.name), EString(entry.args), inner]);
					i--;
				}
				inner;
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
				final op = (c == "+".code) ? HxUnaryOperator.Increment : HxUnaryOperator.Decrement;
				bump();
				bump();
				EUnop(op, HxUnaryFixity.Prefix, parseUnaryExpr(stop));
			case TOther(c) if (c == "!".code || c == "-".code || c == "~".code):
				final op = switch (c) {
					case "!".code: HxUnaryOperator.LogicalNot;
					case "-".code: HxUnaryOperator.Negate;
					case "~".code: HxUnaryOperator.BitwiseNot;
					case _: throw "unreachable unary operator";
				};
				bump();
				// The minimum Int has an unsigned magnitude that the host's parseInt
				// cannot represent. Upstream also exposes this signed literal as one
				// CInt constant to macros, so retain its value before parsing an operand.
				if (op == HxUnaryOperator.Negate
					&& cur.kind.match(TInt(_))
					&& cur.numericText == "2147483648"
					&& (cur.numericSuffix == null || cur.numericSuffix.length == 0)) {
					bump();
					EInt(-2147483647 - 1);
				} else {
					EUnop(op, HxUnaryFixity.Prefix, parseUnaryExpr(stop));
				}
			case TOther(c) if (c == "+".code):
				fail("Unexpected unary +");
			case _:
				parsePostfixExpr(stop);
		}
	}

	function readPostfixFieldName():String {
		if (acceptOtherChar("$")) {
			final name = readIdent("field splice name");
			return "__hxhx_macro_field_splice:" + name;
		}
		return readIdent("field name");
	}

	function readConstructorTypePath():String {
		if (acceptOtherChar("$")) {
			final name = readIdent("type path splice name");
			return "__hxhx_macro_type_path_splice:" + name;
		}
		return readDottedPath();
	}

	/** Restores quote context after successful parsing or a recoverable parser error. */
	function withMacroQuoteContext(quoted:Bool, parse:() -> HxExpr):HxExpr {
		final previous = inMacroQuote;
		inMacroQuote = quoted;
		try {
			final expression = parse();
			inMacroQuote = previous;
			return expression;
		} catch (error:HxParseError) {
			inMacroQuote = previous;
			throw error;
		} catch (error:String) {
			inMacroQuote = previous;
			throw error;
		}
	}

	function parseMacroQuoteExpr(stop:() -> Bool):HxExpr {
		return withMacroQuoteContext(true, () -> parseMacroQuoteContents(stop));
	}

	function parseMacroQuoteContents(stop:() -> Bool):HxExpr {
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

		final quoted = parseMacroQuotePayload(stop);
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

		return parseExpr(stop);
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
						nextIsOther("=".code) ? {op: "==", len: 2} : nextIsOther(">".code) ? {op: "=>", len: 2} : {op: "=", len: 1};
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

	/** Assignment permission covers its RHS without widening ordinary binary operands. */
	function binaryExpression(op:String, left:HxExpr, right:HxExpr):HxExpr {
		return switch left {
			case EPrivateAccess(inner, position) if (isAssignmentBinop(op)):
				EPrivateAccess(binaryExpression(op, inner, right), position);
			case _: EBinop(op, left, right);
		};
	}

	/** Preserve assignment precedence through source permission wrappers. */
	function isAssignmentExpression(expression:HxExpr):Bool {
		return switch expression {
			case EPrivateAccess(inner, _): isAssignmentExpression(inner);
			case EBinop(op, _, _): isAssignmentBinop(op) || op == "=>";
			case _: false;
		};
	}

	/** Attach the conditional to the assignment value, including nested permissions. */
	function ternaryExpression(condition:HxExpr, whenTrue:HxExpr, whenFalse:HxExpr):HxExpr {
		return switch condition {
			case EBinop(op, left, right) if (isAssignmentBinop(op) || op == "=>"):
				EBinop(op, left, ETernary(right, whenTrue, whenFalse));
			case EPrivateAccess(inner, position) if (isAssignmentExpression(inner)):
				EPrivateAccess(ternaryExpression(inner, whenTrue, whenFalse), position);
			case _: ETernary(condition, whenTrue, whenFalse);
		};
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
			left = binaryExpression(op, left, right);
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
			return parseSourceTryExpr(stop);
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

		if (!stop() && cur.kind.match(TKeyword(KIf))) {
			return parseIfExpr(stop);
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
			e = ternaryExpression(e, thenExpr, elseExpr);
		}
		if (!stop() && cur.kind.match(TColon)) {
			bump();
			final hint = readTypeHintText(() -> stop() || cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TRBrace)
				|| cur.kind.match(TSemicolon) || cur.kind.match(TEof));
			e = ECast(e, hint);
		}
		return e;
	}

	/** Preserve authored branches, including a missing else and each original value group. */
	function parseIfExpr(stop:() -> Bool):HxExpr {
		final position = cur.getPos();
		bump();
		expect(TLParen, "'(' after if");
		final condition = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
		expect(TRParen, "')' after if condition");
		if (stop()
			|| cur.kind.match(TKeyword(KElse))
			|| cur.kind.match(TSemicolon)
			|| cur.kind.match(TRBrace)
			|| cur.kind.match(TEof))
			fail("Expected expression after if condition");
		final whenTrue = parseExpr(() -> stop() || cur.kind.match(TKeyword(KElse)) || cur.kind.match(TSemicolon) || cur.kind.match(TRBrace)
			|| cur.kind.match(TEof));
		if (cur.kind.match(TSemicolon) && peekKind().match(TKeyword(KElse)))
			bump();
		var whenFalse:Null<HxExpr> = null;
		if (acceptKeyword(KElse)) {
			if (stop() || cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof))
				fail("Expected expression after else");
			whenFalse = parseExpr(stop);
		}
		return ESourceIf(condition, whenTrue, whenFalse, position);
	}

	/** Keep the thrown operand inside its surrounding branch or argument boundary. */
	function parseThrowExpr(stop:() -> Bool):HxExpr {
		final position = cur.getPos();
		bump();
		if (stop()
			|| cur.kind.match(TSemicolon)
			|| cur.kind.match(TRBrace)
			|| cur.kind.match(TEof)
			|| cur.kind.match(TKeyword(KElse)))
			fail("Expected thrown expression");
		final value = parseExpr(() -> stop()
			|| cur.kind.match(TSemicolon)
			|| cur.kind.match(TRBrace)
			|| cur.kind.match(TEof)
			|| cur.kind.match(TKeyword(KElse | KCase | KDefault))
			|| cur.kind.match(TComma)
			|| cur.kind.match(TRParen));
		return EThrow(value, position);
	}

	/** Both function spellings retain the same written parameters and ordered defaults. */
	function parseSourceFunctionParameters():{
		arguments:Array<String>,
		parameters:Array<HxLambdaSignature.HxLambdaParameter>,
		defaults:Array<HxExpr>
	} {
		expect(TLParen, "'('");
		final args = new Array<String>();
		final parameters = new Array<HxLambdaSignature.HxLambdaParameter>();
		final defaults = new Array<HxExpr>();
		if (!cur.kind.match(TRParen)) {
			while (true) {
				final isRest = cur.kind.match(TDot) && peekKind().match(TDot) && peekKind2().match(TDot);
				if (isRest) {
					bump();
					bump();
					bump();
				}
				final isOptional = acceptOtherChar("?");
				args.push(readIdent("argument name"));
				var typeHint = "";
				if (cur.kind.match(TColon)) {
					bump();
					typeHint = readTypeHintText(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof) || isOtherChar("="));
				}
				final hasDefault = acceptOtherChar("=");
				if (hasDefault)
					defaults.push(parseExpr(() -> cur.kind.match(TComma) || cur.kind.match(TRParen) || cur.kind.match(TEof)));
				parameters.push({
					typeHint: typeHint.length == 0 ? null : typeHint,
					isOptional: isOptional,
					isRest: isRest,
					hasDefault: hasDefault
				});
				if (!cur.kind.match(TComma))
					break;
				bump();
			}
		}
		expect(TRParen, "')'");
		return {arguments: args, parameters: parameters, defaults: defaults};
	}

	/** Authored arrows own a function scope; transport lambdas are created only by lowering. */
	function tryReadArrowLambdaExpr(stop:() -> Bool):Null<HxExpr> {
		if (stop())
			return null;
		final position = cur.getPos();
		var inputs:{arguments:Array<String>, parameters:Array<HxLambdaSignature.HxLambdaParameter>, defaults:Array<HxExpr>};
		switch (cur.kind) {
			case TLParen if (parenthesizedArrowAhead()):
				inputs = parseSourceFunctionParameters();
			case TIdent(name) if (peekKind().match(TOther("-".code)) && peekKind2().match(TOther(">".code))):
				bump();
				inputs = {
					arguments: [name],
					parameters: [
						{
							typeHint: null,
							isOptional: false,
							isRest: false,
							hasDefault: false
						}
					],
					defaults: []
				};
			case _:
				return null;
		}
		for (parameter in inputs.parameters)
			if (parameter.isRest)
				fail("Arrow rest parameters require a haxe.Rest<T> annotation");
		if (!acceptOtherChar("-") || !acceptOtherChar(">"))
			fail("Expected '->' after arrow parameters");
		final bodyLine = cur.getPos().getLine();
		final body = parseAuthoredControl(() -> parseExpr(stop));
		final facts = new HxSourceFunction({
			kind: Arrow,
			placement: Value,
			arguments: inputs.arguments,
			signature: new HxLambdaSignature(inputs.parameters, null)
		});
		return ESourceFunction(facts, markTraceExpressionLine(body, bodyLine), inputs.defaults, position);
	}

	/** Inspect balanced tokens without consuming parser state or splitting parameter text. */
	function parenthesizedArrowAhead():Bool {
		final pending = [cur];
		for (token in [peeked1, peeked2, peeked3])
			if (token != null)
				pending.push(token);
		final lookahead = lex.fork();
		var index = 0;
		function next():HxTokenKind {
			return index < pending.length ? pending[index++].kind : lookahead.next().kind;
		}
		var depth = 0;
		while (true) {
			switch next() {
				case TLParen:
					depth++;
				case TRParen:
					depth--;
					if (depth == 0)
						return next().match(TOther("-".code)) && next().match(TOther(">".code));
				case TEof:
					return false;
				case _:
			}
		}
	}

	static function markTraceExpressionLine(expr:HxExpr, line:Int):HxExpr {
		return switch (expr) {
			case ECall(EIdent("trace"), args) if (line > 0):
				ECall(EIdent("__hxhx_trace_at_" + Std.string(line)), args);
			case _:
				expr;
		};
	}

	/** Preserve switch arms as authored expression blocks, without adding return or loop helper functions. */
	function parseSwitchExpr(stop:() -> Bool):HxExpr {
		if (!cur.kind.match(TKeyword(KSwitch)))
			return EUnsupported("switch");

		bump(); // `switch`

		// Parentheses belong to the operand expression and may have a field, call,
		// or index suffix. Use the same complete grammar as statement switches.
		final scrutinee = parseExpr(() -> cur.kind.match(TLBrace) || cur.kind.match(TEof));

		// `{ <cases> }`
		expect(TLBrace, "'{' before switch arms");

		final patterns = new Array<HxSwitchPattern>();
		final exprs = new Array<HxExpr>();
		while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
			final pat:HxSwitchPattern = if (acceptKeyword(KCase)) {
				parseSwitchPattern();
			} else if (acceptKeyword(KDefault)) {
				// Haxe: `default:` (no pattern). Bring-up: treat as wildcard.
				PWildcard;
			} else {
				fail("Expected switch case or default");
				PWildcard;
			}
			expect(TColon, "':'");
			final armPosition = cur.getPos();
			final armExpressions = new Array<HxExpr>();
			while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof) && !cur.kind.match(TKeyword(KCase)) && !cur.kind.match(TKeyword(KDefault))) {
				if (cur.kind.match(TSemicolon)) {
					bump();
					continue;
				}
				final start = currentIndex();
				final expression = parseAuthoredControl(() -> parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof)
					|| cur.kind.match(TKeyword(KCase)) || cur.kind.match(TKeyword(KDefault))));
				if (currentIndex() == start)
					fail("Expected switch arm expression");
				armExpressions.push(expression);
				if (cur.kind.match(TSemicolon))
					bump();
				else if (!cur.kind.match(TRBrace) && !cur.kind.match(TKeyword(KCase)) && !cur.kind.match(TKeyword(KDefault))
					&& !endsWithSourceBrace(expression))
					fail("Expected ';' after switch arm expression");
			}
			patterns.push(pat);
			exprs.push(ESourceGroup(armExpressions, armPosition));
		}
		expect(TRBrace, "'}' after switch arms");
		return ESwitch(scrutinee, patterns, exprs);
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
				case SSwitch(scrutinee, patterns, bodies, pos, exhaustive):
					final rewrittenBodies = new Array<HxStmt>();
					for (body in bodies)
						rewrittenBodies.push(markTailValue(body));
					SSwitch(scrutinee, patterns, rewrittenBodies, pos, exhaustive);
				case other:
					other;
			}
		}

		final rewritten = stmts.copy();
		final lastIndex = rewritten.length - 1;
		rewritten[lastIndex] = markTailValue(rewritten[lastIndex]);
		return lambdaBodyExprFromStmts(rewritten);
	}

	/** Preserve handler order and lexical bodies without introducing helper functions. */
	function parseSourceTryExpr(stop:() -> Bool):HxExpr {
		final position = cur.getPos();
		expect(TKeyword(KTry), "'try'");
		if (stop() || cur.kind.match(TEof) || cur.kind.match(TKeyword(KCatch)))
			fail("Expected try body");
		final bodies = [
			parseAuthoredControl(() -> parseExpr(() -> cur.kind.match(TKeyword(KCatch)) || stop()))
		];
		final catches = new Array<HxSourceCatch>();
		while (cur.kind.match(TKeyword(KCatch))) {
			final catchPosition = cur.getPos();
			bump();
			expect(TLParen, "'(' after catch");
			final name = readIdent("catch variable");
			var hint = "";
			if (cur.kind.match(TColon)) {
				bump();
				hint = readTypeHintText(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
				if (StringTools.trim(hint).length == 0)
					fail("Expected catch type after ':'");
			}
			expect(TRParen, "')' after catch variable");
			if (stop() || cur.kind.match(TEof) || cur.kind.match(TKeyword(KCatch)))
				fail("Expected catch body");
			catches.push(new HxSourceCatch(name, hint, catchPosition));
			bodies.push(parseAuthoredControl(() -> parseExpr(() -> cur.kind.match(TKeyword(KCatch)) || stop())));
		}
		if (catches.length == 0)
			fail("Expected at least one catch after try");
		return ESourceTry(catches, bodies, position);
	}

	/** Retain the authored binding, iterable, and body without changing return ownership. */
	function parseSourceForExpr(stop:() -> Bool):HxExpr {
		final position = cur.getPos();
		expect(TKeyword(KFor), "'for'");
		expect(TLParen, "'(' after for");
		final first = readIdent("for binding");
		final binding:HxForBinding = if (cur.kind.match(TOther("=".code)) && peekKind().match(TOther(">".code))) {
			bump();
			bump();
			HxForBinding.KeyValue(first, readIdent("for value binding"));
		} else HxForBinding.Value(first);
		expect(TKeyword(KIn), "'in' after for binding");
		final iterable = parseExpr(() -> cur.kind.match(TRParen) || cur.kind.match(TEof));
		expect(TRParen, "')' after for iterable");
		if (stop() || cur.kind.match(TEof))
			fail("Expected for body");
		final body = parseAuthoredControl(() -> parseExpr(stop));
		return ESourceFor(binding, iterable, body, position);
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
					case SReturn(_, _) | SReturnVoid(_) | SThrow(_, _):
						s;
					case SExpr(e, p):
						SReturn(e, p);
					case SIf(cond, thenBranch, elseBranch, p):
						// Keep nullable enum coercion in assignment form. Inlining the mixed null/enum
						// branch can emit an unboxed HxStmt in no-prepass OCaml source builds.
						var rewrittenElse:Null<HxStmt> = null;
						if (elseBranch == null)
							rewrittenElse = SReturnVoid(p);
						else
							rewrittenElse = ensureBranchReturns(elseBranch);
						SIf(cond, ensureBranchReturns(thenBranch), rewrittenElse, p);
					case SBlock(stmts, p):
						if (stmts.length == 0) {
							SBlock([SReturnVoid(p)], p);
						} else {
							final last = stmts[stmts.length - 1];
							switch (last) {
								case SReturn(_, _) | SReturnVoid(_) | SThrow(_, _):
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
				case TString(s, _):
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
			if (isSemicolonlessStatementBoundary())
				return;
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

	function isSemicolonlessStatementBoundary():Bool {
		final start = currentIndex();
		if (start <= 0)
			return false;

		var i = start - 1;
		var sawNewline = false;
		while (i >= 0) {
			final ch = source.charCodeAt(i);
			switch (ch) {
				case " ".code | "\t".code | "\r".code:
					i--;
				case "\n".code:
					sawNewline = true;
					i--;
				case "}".code:
					return sawNewline && tokenCanStartStatement(cur.kind);
				case _:
					return false;
			}
		}
		return false;
	}

	static function tokenCanStartStatement(kind:HxTokenKind):Bool {
		if (kind.match(TIdent(_)) || kind.match(TLBrace) || kind.match(TLParen))
			return true;
		return switch (kind) {
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
			case TOther(c): c == "@".code || c == "#".code;
			case _:
				false;
		}
	}

	function syncToStmtEnd():Void {
		syncToStmtEndUntil(() -> false);
	}

	function parseVarDecls(pos:HxPos):Array<HxStmt> {
		// `var [@:meta] a[:T] [= expr], [@:meta] b[:U] [= expr];`
		//
		// Why
		// - Upstream Haxe tests use grouped declarators heavily, e.g. `var a:Int64, b:Int64;`.
		// - Dropping tail declarators makes later assignments unbound in Stage3 emission.
		//
		// How
		// - Parse each declarator here.
		// - Metadata belongs to the declarator immediately following it. This is
		//   distinct from metadata written before the whole `var` statement.
		// - In statement-list contexts, callers flatten grouped declarators into the surrounding list.
		// - In single-statement contexts (e.g. `if (...) var a, b;`), we keep them wrapped in
		//   a local block so branch-local scope remains correct.
		function parseSingleVarDecl():HxStmt {
			final metadata = new Array<String>();
			while (isOtherChar("@"))
				metadata.push(parseMetadataText());
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
			return SVar(name, typeHint, init, pos, metadata);
		}

		final decls = new Array<HxStmt>();
		decls.push(parseSingleVarDecl());
		while (cur.kind.match(TComma)) {
			bump();
			decls.push(parseSingleVarDecl());
		}
		final nextStartsStatement = switch (cur.kind) {
			case TIdent(_):
				declsCanEndBeforeIdentifier(decls);
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

	static function declsCanEndBeforeIdentifier(decls:Array<HxStmt>):Bool {
		if (decls == null || decls.length == 0)
			return false;
		final last = decls[decls.length - 1];
		return switch (last) {
			case SVar(_, _, EAnon(_, _), _):
				true;
			case _:
				false;
		}
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
		final isVarDecl = cur.kind.match(TKeyword(KVar)) || cur.kind.match(TKeyword(KFinal)) || isLocalStaticVarDecl();
		if (isVarDecl) {
			final pos = cur.pos;
			if (cur.kind.match(TKeyword(KStatic)))
				bump();
			bump();
			final decls = parseVarDecls(pos);
			for (stmt in decls)
				out.push(stmt);
			return;
		}
		out.push(parseStmt(stop));
	}

	function isLocalStaticVarDecl():Bool {
		if (!cur.kind.match(TKeyword(KStatic)))
			return false;
		return peekKind().match(TKeyword(KVar)) || peekKind().match(TKeyword(KFinal));
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
		final inlineNekoElseThrow = tryParseInlineNekoElseThrowStmt(pos);
		if (inlineNekoElseThrow != null)
			return inlineNekoElseThrow;
		if (cur.kind.match(TKeyword(KCase)) || cur.kind.match(TKeyword(KDefault)))
			return parseRecoveredCaseFragmentStmt(pos);

		return switch (cur.kind) {
			case TLBrace:
				if (braceStartsAnonLiteral()) {
					final expr = parseExpr(() -> stop() || cur.kind.match(TSemicolon) || cur.kind.match(TKeyword(KElse)));
					if (cur.kind.match(TSemicolon))
						bump();
					SExpr(expr, pos);
				} else {
					bump();
					final ss = new Array<HxStmt>();
					while (!cur.kind.match(TRBrace) && !cur.kind.match(TEof)) {
						parseStmtInto(ss, () -> cur.kind.match(TRBrace) || cur.kind.match(TEof));
					}
					expect(TRBrace, "'}'");
					SBlock(ss, pos);
				}
			case TOther("@".code) if (peekKind().match(TColon) && peekKind2().match(TIdent("privateAccess"))):
				// Use the expression grammar so annotated declarations retain their
				// surrounding scope and assignment permission includes its RHS.
				final expr = parseExpr(() -> stop() || cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
				if (cur.kind.match(TSemicolon))
					bump();
				SExpr(expr, pos);
			case TKeyword(KUntyped):
				// A wrapped block can end a function without a semicolon. Recovery
				// scanning here would consume the next declaration or statement.
				final expr = parseExpr(() -> stop() || cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
				if (cur.kind.match(TSemicolon))
					bump();
				SExpr(expr, pos);
			case TKeyword(KReturn):
				bump();
				parseReturnStmt(pos);
			case TKeyword(KInline):
				// Keep the written inline flag on the authored named function.
				bump();
				if (cur.kind.match(TKeyword(KFunction))) {
					parseLocalFunctionStmt(pos, true);
				} else {
					SExpr(EUnsupported("inline"), pos);
				}
			case TKeyword(KFunction):
				if (peekKind().match(TLParen)) {
					final expr = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
					syncToStmtEnd();
					SExpr(expr, pos);
				} else {
					parseLocalFunctionStmt(pos);
				}
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
				// Direct parser fixtures can retain conditional-compilation lines around
				// an `else if` chain. The directive itself is not a statement in the
				// chain, so step over it before deciding whether this `if` owns an else.
				while (cur.kind.match(TOther("#".code)))
					consumePreprocessorLine();
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
				// Use the complete expression grammar: a parenthesized receiver can have
				// a field/call suffix before the switch's opening brace.
				final scrutinee = parseExpr(() -> cur.kind.match(TLBrace) || cur.kind.match(TEof));

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
				if (cur.kind.match(TOther("@".code))) {
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

	function parseRecoveredCaseFragmentStmt(pos:HxPos):HxStmt {
		// Best-effort declaration scanning can retain a method-body slice that starts
		// inside a switch case list. At top level this is not a real Haxe statement,
		// so consume one case/default fragment as neutral recovery instead of emitting
		// an EUnsupported(case...) that blocks backend burn-down.
		bump(); // `case` / `default`
		while (!cur.kind.match(TColon) && !cur.kind.match(TEof) && !cur.kind.match(TRBrace) && !cur.kind.match(TKeyword(KCase))
			&& !cur.kind.match(TKeyword(KDefault))) {
			bump();
		}
		if (cur.kind.match(TColon))
			bump();
		while (!cur.kind.match(TSemicolon) && !cur.kind.match(TEof) && !cur.kind.match(TRBrace) && !cur.kind.match(TKeyword(KCase))
			&& !cur.kind.match(TKeyword(KDefault))) {
			bump();
		}
		if (cur.kind.match(TSemicolon))
			bump();
		return SExpr(ENull, pos);
	}

	function tryParseInlineNekoElseThrowStmt(pos:HxPos):Null<HxStmt> {
		if (!cur.kind.match(TOther("#".code)))
			return null;
		final idxIf = currentIndex();
		if (source.substr(idxIf, 8) != "#if neko")
			return null;
		final idxElse = source.indexOf("#else", idxIf + 8);
		final idxEnd = source.indexOf("#end", idxIf + 8);
		if (idxElse < 0 || idxEnd < 0 || idxElse > idxEnd)
			return null;
		final lineEnd = source.indexOf("\n", idxIf);
		if (lineEnd >= 0 && idxEnd > lineEnd)
			return null;
		final elsePayload = StringTools.trim(source.substr(idxElse + 5, idxEnd - (idxElse + 5)));
		if (elsePayload != "throw")
			return null;
		final afterEnd = idxEnd + 4;
		while (!cur.kind.match(TEof) && currentIndex() < afterEnd)
			bump();
		final thrown = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TRBrace) || cur.kind.match(TEof));
		syncToStmtEnd();
		return SThrow(thrown, pos);
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

	/**
		Recover statements and leave their closing brace as the current token.

		Expression-block callers need that token's position before advancing past
		comments. Standalone body recovery discards the parser after this call.
	**/
	function parseFunctionBodyStatementsBestEffort(wrapperCloseOnly:Bool = true):Array<HxStmt> {
		// Like `parseFunctionBodyStatements`, but never throws.
		//
		// Why
		// - Best-effort recovery may parse method bodies from raw source slices.
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
				case TString(_, _): "string";
				case TInt(_): "int";
				case TFloat(_): "float";
				case TRegex(_, _): "regex";
				case TKeyword(k): "kw(" + keywordText(k) + ")";
				case TOther(c): "other(" + String.fromCharCode(c) + ")";
			};
		}
		inline function isWrapperCloseBrace():Bool {
			return cur.kind.match(TRBrace) && (!wrapperCloseOnly || peekKind().match(TEof));
		}
		inline function oneLine(text:String):String {
			if (text == null)
				return "";
			return StringTools.replace(StringTools.replace(text, "\n", " "), "\r", " ");
		}
		inline function bodyParseErrorDetail(errorText:String):String {
			return "body_parse_error fn=<unknown> tok=" + oneLine(curTokLabel()) + " err=" + oneLine(errorText);
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
					//
					// Nested block expressions are parsed from the real source stream, not a synthetic
					// wrapper, so their close brace is always a valid boundary for this helper.
					if (isWrapperCloseBrace()) {
						return out;
					}
					// Stray brace: consume it and continue so we don't silently truncate the body.
					bump();
					out.push(SExpr(ENull, HxPos.unknown()));
				case _:
					try {
						parseStmtInto(out, () -> cur.kind.match(TRBrace) || cur.kind.match(TEof));
						0; // ensure try/catch has a concrete, consistent expression type across targets
					} catch (e:HxParseError) {
						if (Sys.getEnv("HXHX_TRACE_BODY_STMT_PARSE_ERROR") == "1") {
							try {
								Sys.println("body_stmt_parse_error fn=<unknown> tok=" + curTokLabel() + " err=" + e.message);
							} catch (_:haxe.io.Error) {} catch (_:String) {}
						}
						// Surface that we hit a parse hole so later stages can diagnose why a body is partial.
						out.push(SExpr(EUnsupported(bodyParseErrorDetail(e.message)), HxPos.unknown()));

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
					} catch (e:String) {
						if (Sys.getEnv("HXHX_TRACE_BODY_STMT_PARSE_ERROR") == "1") {
							try {
								Sys.println("body_stmt_parse_error fn=<unknown> tok=" + curTokLabel() + " err=" + e);
							} catch (_:haxe.io.Error) {} catch (_:String) {}
						}
						// Surface that we hit a parse hole so later stages can diagnose why a body is partial.
						out.push(SExpr(EUnsupported(bodyParseErrorDetail(e)), HxPos.unknown()));

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
		final functionTypeMetadata = HxFunctionTypeParamMetadata.fromParameters(new HxTypedefParser(this).parameters(), source);
		final args = new Array<HxFunctionArg>();
		for (argument in new HxFunctionSyntaxParser(this).readParenthesizedArguments())
			args.push(HxFunctionSyntaxParser.methodArgument(argument.declaration));

		var returnType = "";
		if (cur.kind.match(TColon)) {
			bump();
			returnType = readFunctionReturnTypeHint(() -> cur.kind.match(TLBrace) || cur.kind.match(TSemicolon) || cur.kind.match(TEof)
				|| cur.kind.match(TKeyword(KReturn)) || cur.kind.match(TKeyword(KThrow)));
		}

		final body = new Array<HxStmt>();
		var bodyText = "";
		var hasBody = false;
		switch (cur.kind) {
			case TSemicolon:
				bump();
			case TLBrace:
				hasBody = true;
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
				hasBody = true;
				// Expression-bodied function: `function f() return expr;`
				final statementPosition = cur.getPos();
				if (acceptKeyword(KReturn)) {
					final bodyStart = currentIndex();
					body.push(parseReturnStmt(statementPosition));
					bodyText = "return " + StringTools.trim(sliceSource(bodyStart, currentIndex()));
				} else {
					final bodyStart = currentIndex();
					body.push(parseStmt(() -> cur.kind.match(TEof)));
					if (cur.kind.match(TSemicolon))
						bump();
					bodyText = StringTools.trim(sliceSource(bodyStart, currentIndex()));
				}
		}

		return new HxFunctionDecl(name, visibility, isStatic, args, returnType, body, capturedReturnStringLiteral, metadata.concat(functionTypeMetadata),
			startPos, cur.getPos(), bodyText, hasBody);
	}

	/**
		Skip a conditional modifier placed after an unconditional `static` marker.

		Standard-library declarations can spell a target-specific modifier as
		`static #if target inline #end function`. Some bootstrap input reaches this
		parser before conditional filtering. The conditional clause must not split
		the declaration and erase the already observed `static` fact.
	**/
	function skipConditionalStaticModifier():Void {
		var depth = 0;
		while (!cur.kind.match(TEof)) {
			if (isOtherChar("#")) {
				bump();
				switch (cur.kind) {
					case TKeyword(KIf):
						depth += 1;
						bump();
					case TIdent("end"):
						depth -= 1;
						bump();
						if (depth <= 0)
							return;
					case _:
						bump();
				}
			} else {
				bump();
			}
		}
	}

	/** Extern members default to public; authored modifiers still override the owning class default. */
	function parseClassMembers(defaultVisibility:HxVisibility):{functions:Array<HxFunctionDecl>, fields:Array<HxFieldDecl>} {
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
					var visibility:HxVisibility = defaultVisibility;
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
						} else if (isStatic && isOtherChar("#") && peekKind().match(TKeyword(KIf))) {
							skipConditionalStaticModifier();
							keep = true;
						} else if (acceptKeyword(KInline)) {
							// Keep the declaration fact available to semantic indexing. Inlining is
							// still a later typer/lowering decision; the parser does not apply it.
							metadata.push("inline");
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
								case TIdent(name) if (name == "dynamic"):
									metadata.push("dynamic");
									bump();
									keep = true;
								case TIdent(name) if (name == "extern" || name == "override"):
									// These context-sensitive modifiers are accepted at class-member scope but
									// are not modeled in the current bring-up AST.
									bump();
									keep = true;
								case TIdent(name) if (name == "overload"):
									// Preserve overload declarations so the Stage3 typer can reject ambiguous
									// call sites instead of silently treating overloaded externs as unknown.
									metadata.push("overload");
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
		final directives = new Array<HxModuleDirective>();
		var hasToplevelMain = false;
		final moduleFields = new Array<HxFieldDecl>();

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

		while (true) {
			final isImport = if (acceptKeyword(KImport)) true else if (acceptKeyword(KUsing)) false else break;
			final path = readImportPath();
			if (isImport) {
				if (acceptKeyword(KAs) || acceptKeyword(KIn))
					directives.push(HxModuleDirective.aliasImport(path, readIdent("import alias")))
				else if (StringTools.endsWith(path, ".*"))
					directives.push(HxModuleDirective.wildcardImport(path.substr(0, path.length - 2)))
				else
					directives.push(HxModuleDirective.normalImport(path));
			} else {
				directives.push(HxModuleDirective.usingDirective(path));
			}
			expect(TSemicolon, "';'");
		}

		// Bootstrap: scan the whole file looking for class declarations.
		//
		// Notes
		// - We still recognize module-level `function main(...)` for upstream unit tests.
		// - Typedefs retain structured syntax in their own declaration catalog.
		final classes = new Array<HxClassDecl>();
		final typedefs = new Array<HxTypedefDecl>();
		final moduleFunctions = new Array<HxFunctionDecl>();
		var pendingTypeMetadata = new Array<String>();
		/**
			Skip one non-class type declaration that `ParserStage` rebuilds through
			its focused Haxe scanners.

			`parseModule` still delegates enum and abstract declaration
			details to those scanners. It must nevertheless consume the complete
			declaration here. Otherwise enum fields or abstract methods can be
			merged into the following ordinary class. Typedefs have their own
			structured parser and do not enter this scanner boundary.
		**/
		function skipScannedTypeDeclaration():Void {
			bump(); // `enum` or `abstract`
			var bodyDepth = 0;
			var parenDepth = 0;
			var bracketDepth = 0;
			var angleDepth = 0;
			// A generic type can contain an anonymous structure, such as `Array<{ value:Int }>`. Its
			// field semicolons must not end the surrounding enum or abstract header.
			var nestedTypeBraceDepth = 0;
			while (!cur.kind.match(TEof)) {
				if (bodyDepth > 0) {
					switch (cur.kind) {
						case TLBrace:
							bodyDepth++;
							bump();
						case TRBrace:
							bodyDepth--;
							bump();
							if (bodyDepth == 0)
								return;
						case _:
							bump();
					}
					continue;
				}

				switch (cur.kind) {
					case TLParen:
						parenDepth++;
						bump();
					case TRParen:
						if (parenDepth > 0)
							parenDepth--;
						bump();
					case TOther(code) if (code == "[".code):
						bracketDepth++;
						bump();
					case TOther(code) if (code == "]".code):
						if (bracketDepth > 0)
							bracketDepth--;
						bump();
					case TOther(code) if (code == "<".code):
						angleDepth++;
						bump();
					case TOther(code) if (code == ">".code):
						if (angleDepth > 0)
							angleDepth--;
						bump();
					case TLBrace:
						if (parenDepth == 0 && bracketDepth == 0 && angleDepth == 0 && nestedTypeBraceDepth == 0) {
							bodyDepth = 1;
						} else {
							nestedTypeBraceDepth++;
						}
						bump();
					case TRBrace:
						if (nestedTypeBraceDepth > 0)
							nestedTypeBraceDepth--;
						bump();
					case TSemicolon:
						bump();
						if (nestedTypeBraceDepth == 0)
							return;
					case _:
						bump();
				}
			}
		}
		function parseModuleField(isFinal:Bool):Void {
			final fieldStart = cur.getPos();
			bump();
			final name = readIdent("top-level field name");
			var typeHint = "";
			if (cur.kind.match(TColon)) {
				bump();
				typeHint = readTypeHintText(() -> cur.kind.match(TOther("=".code)) || cur.kind.match(TSemicolon) || cur.kind.match(TEof));
			}
			var init:Null<HxExpr> = null;
			var initText = "";
			if (acceptOtherChar("=")) {
				final initStart = currentIndex();
				init = parseExpr(() -> cur.kind.match(TSemicolon) || cur.kind.match(TEof));
				initText = sliceSource(initStart, currentIndex());
			}
			if (cur.kind.match(TSemicolon))
				bump();
			else
				syncToStmtEnd();
			moduleFields.push(new HxFieldDecl(name, Public, true, typeHint, init, [], fieldStart, cur.getPos(), isFinal, "", "", initText));
		}
		while (!cur.kind.match(TEof)) {
			if (isOtherChar("@")) {
				pendingTypeMetadata.push(parseMetadataText());
				continue;
			}
			var moduleMemberVisibility:HxVisibility = Public;
			var typeIsExtern = false;
			final moduleFunctionMetadata = pendingTypeMetadata.copy();
			var keepModuleModifiers = true;
			while (keepModuleModifiers) {
				keepModuleModifiers = false;
				if (acceptKeyword(KPublic)) {
					moduleMemberVisibility = Public;
					keepModuleModifiers = true;
				} else if (acceptKeyword(KPrivate)) {
					moduleMemberVisibility = Private;
					keepModuleModifiers = true;
				} else if (acceptKeyword(KStatic)) {
					keepModuleModifiers = true;
				} else if (acceptKeyword(KInline)) {
					moduleFunctionMetadata.push("inline");
					keepModuleModifiers = true;
				} else if (cur.kind.match(TKeyword(KFinal))
					&& (peekKind().match(TKeyword(KClass))
						|| peekKind().match(TKeyword(KPrivate))
						|| peekKind().match(TIdent("extern")))) {
					// A class modifier precedes class or another class modifier. A module final precedes its field name.
					pendingTypeMetadata.push("final");
					bump();
					keepModuleModifiers = true;
				} else {
					switch (cur.kind) {
						case TIdent(name) if (name == "overload"):
							moduleFunctionMetadata.push("overload");
							bump();
							keepModuleModifiers = true;
						case TIdent(name) if (name == "extern" || name == "override"):
							if (name == "extern")
								typeIsExtern = true;
							bump();
							keepModuleModifiers = true;
						case _:
					}
				}
			}
			switch (cur.kind) {
				case TKeyword(KFinal):
					pendingTypeMetadata = [];
					parseModuleField(true);
					continue;
				case TKeyword(KVar):
					pendingTypeMetadata = [];
					parseModuleField(false);
					continue;
				case _:
			}
			switch (cur.kind) {
				case TKeyword(KClass) | TIdent("interface"):
					final classMetadata = pendingTypeMetadata.copy();
					pendingTypeMetadata = [];
					final isInterface = cur.kind.match(TIdent("interface"));
					bump(); // 'class' / 'interface'
					final className = readIdent("class name");
					final classTypeParameters = new HxTypedefParser(this).parameters();
					if (classTypeParameters.length > 0)
						classMetadata.push("__hxhx_type_params=" + classTypeParameters.map(parameter -> parameter.name).join(","));
					var extendsPath = "";
					final interfaceExtendsPaths = new Array<String>();
					final implementsPaths = new Array<String>();
					var readingImplements = false;
					while (!cur.kind.match(TLBrace) && !cur.kind.match(TEof)) {
						switch (cur.kind) {
							case TIdent(name) if (name == "extends"):
								bump();
								final parentPath = readHeaderTypePath();
								if (isInterface)
									interfaceExtendsPaths.push(parentPath);
								else
									extendsPath = parentPath;
								readingImplements = false;
							case TIdent(name) if (name == "implements"):
								bump();
								readingImplements = true;
							case TIdent(_) if (readingImplements):
								implementsPaths.push(readHeaderTypePath());
								if (cur.kind.match(TComma)) {
									bump();
									readingImplements = true;
								} else {
									readingImplements = false;
								}
							case _:
								bump();
						}
					}
					if (cur.kind.match(TEof))
						break;
					expect(TLBrace, "'{'");

					final members = parseClassMembers(typeIsExtern ? Public : Private);
					final functions = members.functions == null ? [] : members.functions;
					final fields = members.fields == null ? [] : members.fields;
					var hasStaticMain = false;
					for (fn in functions) {
						if (HxFunctionDecl.getIsStatic(fn) && HxFunctionDecl.getName(fn) == "main") {
							hasStaticMain = true;
							break;
						}
					}

					classes.push(new HxClassDecl(className, hasStaticMain, functions, fields, extendsPath, classMetadata, isInterface, implementsPaths,
						moduleMemberVisibility, interfaceExtendsPaths, typeIsExtern, null, classTypeParameters));
				// `parseClassMembers` consumes the closing `}`.
				case TIdent("typedef"):
					typedefs.push(new HxTypedefParser(this).declaration(moduleMemberVisibility, pendingTypeMetadata, typeIsExtern));
					pendingTypeMetadata = [];
				case TIdent("enum") | TIdent("abstract"):
					pendingTypeMetadata = [];
					skipScannedTypeDeclaration();
				case TKeyword(KFunction):
					pendingTypeMetadata = [];
					// Detect module-level `function main(...)` entrypoint.
					final fnStart = cur.getPos();
					bump();
					final parsedFn = parseFunctionDecl(moduleMemberVisibility, true, moduleFunctionMetadata, fnStart);
					final fn = new HxFunctionDecl(HxFunctionDecl.getName(parsedFn), HxFunctionDecl.getVisibility(parsedFn),
						HxFunctionDecl.getIsStatic(parsedFn), HxFunctionDecl.getArgs(parsedFn), HxFunctionDecl.getReturnTypeHint(parsedFn),
						offsetFunctionBodyColumns(HxFunctionDecl.getBody(parsedFn), 1), HxFunctionDecl.getReturnStringLiteral(parsedFn),
						HxFunctionDecl.getMetadata(parsedFn), HxFunctionDecl.getPos(parsedFn), HxFunctionDecl.getEndPos(parsedFn),
						HxFunctionDecl.getBodyText(parsedFn), HxFunctionDecl.getHasBody(parsedFn));
					if (HxFunctionDecl.getName(fn) == "main")
						hasToplevelMain = true;
					moduleFunctions.push(fn);
				default:
					pendingTypeMetadata = [];
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
		if (moduleFunctions.length > 0 || moduleFields.length > 0) {
			final base = chosen == null ? new HxClassDecl(expected.length > 0 ? expected : "Unknown", false, [], []) : chosen;
			final mergedFunctions = moduleFunctions.concat(HxClassDecl.getFunctions(base));
			final mergedFields = moduleFields.concat(HxClassDecl.getFields(base));
			chosen = new HxClassDecl(HxClassDecl.getName(base), HxClassDecl.getHasStaticMain(base) || hasToplevelMain, mergedFunctions, mergedFields,
				HxClassDecl.getExtendsPath(base), HxClassDecl.getMetadata(base), HxClassDecl.getIsInterface(base), HxClassDecl.getImplementsPaths(base),
				HxClassDecl.getVisibility(base), HxClassDecl.getInterfaceExtendsPaths(base), HxClassDecl.getIsExtern(base),
				HxClassDecl.getEnumDeclaration(base), HxClassDecl.getTypeParameters(base));
			var replaced = false;
			for (i in 0...classes.length) {
				if (HxClassDecl.getName(classes[i]) == HxClassDecl.getName(chosen)) {
					classes[i] = chosen;
					replaced = true;
					break;
				}
			}
			if (!replaced)
				classes.push(chosen);
		}
		final mainClass = chosen == null ? new HxClassDecl("Unknown", false, [], []) : chosen;
		return new HxModuleDecl(packagePath, directives, mainClass, classes, false, hasToplevelMain, typedefs);
	}

	static function isRestTypeHintText(typeHint:String):Bool {
		final hint = StringTools.trim(typeHint == null ? "" : typeHint);
		return hint == "Rest"
			|| StringTools.startsWith(hint, "Rest<")
			|| StringTools.startsWith(hint, "haxe.Rest<")
			|| StringTools.startsWith(hint, "haxe.extern.Rest<");
	}
}
