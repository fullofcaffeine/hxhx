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
	  - zero or more 'import <path>;'
	  - a single 'class <Name> { ... }'
	  - detects 'static function main(...)' (we only care about name + 'static')

	How:
	- We intentionally do not fully parse expressions or types yet.
	- For class bodies, we do lightweight scanning:
	  - when we see 'static function <ident>', record it
	  - then skip the parameter list and function body by balancing braces/parens
**/
class HxParser {
	final lex:HxLexer;
	var cur:HxToken;

	public function new(source:String) {
		lex = new HxLexer(source);
		cur = lex.next();
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

	public function parseModule():HxModuleDecl {
		var packagePath = "";
		final imports = new Array<String>();

		if (acceptKeyword(KPackage)) {
			packagePath = readDottedPath();
			expect(TSemicolon, "';'");
		}

		while (acceptKeyword(KImport)) {
			final path = readDottedPath();
			imports.push(path);
			expect(TSemicolon, "';'");
		}

		// Bootstrap: scan forward until we find the first `class` declaration.
		// This lets us tolerate (for now):
		// - metadata like `@:build(...)`
		// - multiple type declarations per module
		// - top-level functions (ignored in this phase)
		while (true) {
			switch (cur.kind) {
				case TKeyword(KClass):
					break;
				case TEof:
					fail("No class declaration found");
				default:
					bump();
			}
		}

		expect(TKeyword(KClass), "'class'");
		final className = readIdent("class name");

		expect(TLBrace, "'{'");

		var hasStaticMain = false;
		while (true) {
			switch (cur.kind) {
				case TRBrace:
					bump();
					break;
				case TEof:
					fail("Unexpected end of input in class body");
				case _:
					if (acceptKeyword(KStatic)) {
						if (acceptKeyword(KFunction)) {
							final fn = readIdent("function name");
							// Skip params
							expect(TLParen, "'('");
							skipBalancedParens();

							// Skip optional ': <type...>' (we don't parse types yet)
							if (cur.kind.match(TColon)) {
								bump();
								// consume a type-ish token sequence until '{' or ';' or end
								while (true) {
									switch (cur.kind) {
										case TLBrace:
											break;
										case TSemicolon:
											break;
										case TEof:
											break;
										default:
											bump();
									}
								}
							}

							// Skip body or declaration terminator
							switch (cur.kind) {
								case TLBrace:
									bump();
									skipBalancedBraces();
								case TSemicolon:
									bump();
								case _:
									// best-effort: consume until ';' or '{' or end
									while (true) {
										switch (cur.kind) {
											case TLBrace:
												bump();
												skipBalancedBraces();
												break;
											case TSemicolon:
												bump();
												break;
											case TEof:
												break;
											case _:
												bump();
										}
									}
							}

							if (fn == "main") hasStaticMain = true;
						} else {
							// `static` without `function` isn't supported yet; continue scanning.
						}
					} else {
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
		return new HxModuleDecl(packagePath, imports, new HxClassDecl(className, hasStaticMain));
	}
}
