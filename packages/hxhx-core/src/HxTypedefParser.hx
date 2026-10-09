import HxTypeSyntax.HxTypeSyntaxArgument;
import HxTypeSyntax.HxTypeSyntaxField;
import HxTypeSyntax.HxTypeSyntaxFieldKind;
import HxTypeSyntax.HxTypeSyntaxParameter;

/**
	Parse type syntax, generic parameters, and typedef declarations on HxParser's token stream.

	This owner retains grammar and positions only. It does not resolve imports,
	expand aliases, validate cycles, or manufacture runtime classes. Keeping the
	stream shared avoids a second scanner disagreeing about comments or braces.
**/
@:access(HxParser)
class HxTypedefParser {
	final parser:HxParser;
	var end:HxPos;

	public function new(parser:HxParser) {
		this.parser = parser;
		end = parser.cur.getPos();
	}

	/** Type grammar consumes identifiers and single-character punctuation, never multiline literals. */
	function advance():Void {
		final start = parser.cur.getPos();
		final width = switch (parser.cur.kind) {
			case TIdent(name): name.length;
			case TKeyword(keyword): HxParser.keywordText(keyword).length;
			case _: 1;
		};
		end = new HxPos(start.getIndex() + width, start.getLine(), start.getColumn() + width);
		parser.bump();
	}

	function take(kind:HxTokenKind):Bool {
		final matches = switch [parser.cur.kind, kind] {
			case [TLBrace, TLBrace] | [TRBrace, TRBrace] | [TLParen, TLParen] | [TRParen, TRParen] | [TSemicolon, TSemicolon] | [TColon, TColon] |
				[TDot, TDot] | [TComma, TComma]: true;
			case [TIdent(left), TIdent(right)]: left == right;
			case [TKeyword(left), TKeyword(right)]: left == right;
			case [TOther(left), TOther(right)]: left == right;
			case _: false;
		};
		if (!matches)
			return false;
		advance();
		return true;
	}

	function require(kind:HxTokenKind, label:String):Void {
		if (!take(kind))
			parser.fail("Expected " + label + " in typedef declaration");
	}

	function other(value:String):Bool
		return take(TOther(value.charCodeAt(0)));

	function name():String {
		return switch (parser.cur.kind) {
			case TIdent(value):
				advance();
				value;
			case _: parser.fail("Expected type or member name in typedef declaration");
		};
	}

	function metadata():Array<String> {
		final values = new Array<String>();
		while (parser.isOtherChar("@"))
			values.push(parser.parseMetadataText());
		return values;
	}

	function arrow():Bool {
		if (!parser.isOtherChar("-") || !parser.peekKind().match(TOther(">".code)))
			return false;
		advance();
		advance();
		return true;
	}

	/** Parse an isolated generic declaration using the same grammar as a full source declaration. */
	public static function parseParameters(source:String):Array<HxTypeSyntaxParameter> {
		final parser = new HxParser(source);
		final parameters = new HxTypedefParser(parser).parameters();
		if (!parser.cur.kind.match(TEof))
			parser.fail("Unexpected token after generic parameters");
		return parameters;
	}

	/** Parse a recovered header slice while retaining positions in the original source. */
	public static function parseParametersAt(source:String, start:Int, end:Int):Array<HxTypeSyntaxParameter> {
		final positioned = new StringBuf();
		// Whitespace preserves offsets and line breaks without parsing preceding declarations.
		for (index in 0...start) {
			final code = source.charCodeAt(index);
			positioned.addChar(code == 10 || code == 13 ? code : 32);
		}
		positioned.add(source.substring(start, end));
		return parseParameters(positioned.toString());
	}

	/** Preserve binders, constraints, and defaults; semantic arity checks belong to typing. */
	public function parameters():Array<HxTypeSyntaxParameter> {
		final values = new Array<HxTypeSyntaxParameter>();
		if (!other("<"))
			return values;
		do {
			final pos = parser.cur.getPos();
			final annotations = metadata();
			final parameterName = name();
			final constraints = new Array<HxTypeSyntax>();
			if (take(TColon))
				constraints.push(type());
			final defaultType = other("=") ? type() : null;
			values.push({
				name: parameterName,
				constraints: constraints,
				defaultType: defaultType,
				metadata: annotations,
				pos: pos,
				endPos: end
			});
		} while (take(TComma));
		require(TOther(">".code), "'>'");
		return values;
	}

	function arguments():Array<HxTypeSyntaxArgument> {
		final values = new Array<HxTypeSyntaxArgument>();
		if (parser.cur.kind.match(TRParen))
			return values;
		do {
			final pos = parser.cur.getPos();
			final annotations = metadata();
			final optional = other("?");
			final rest = !optional && parser.cur.kind.match(TDot) && parser.peekKind().match(TDot) && parser.peekKind2().match(TDot);
			if (rest) {
				advance();
				advance();
				advance();
			}
			var argumentName:Null<String> = null;
			if (parser.cur.kind.match(TIdent(_)) && parser.peekKind().match(TColon)) {
				argumentName = name();
				require(TColon, "':'");
			}
			final value = type();
			values.push({
				name: argumentName,
				type: value,
				isOptional: optional,
				isRest: rest,
				metadata: annotations,
				pos: pos,
				endPos: end
			});
		} while (take(TComma));
		return values;
	}

	function accessor():String {
		return switch (parser.cur.kind) {
			case TKeyword(keyword):
				advance();
				HxParser.keywordText(keyword);
			case TIdent(_): name();
			case _: parser.fail("Expected property accessor in typedef declaration");
		};
	}

	function anonymous(pos:HxPos):HxTypeSyntax {
		final fields = new Array<HxTypeSyntaxField>();
		final extensions = new Array<HxTypeSyntax>();
		while (!parser.cur.kind.match(TRBrace)) {
			if (parser.cur.kind.match(TEof))
				parser.fail("Unclosed anonymous typedef structure");
			if (other(">")) {
				extensions.push(type());
				if (take(TComma))
					continue;
				if (!parser.cur.kind.match(TRBrace))
					parser.fail("Expected ',' after structural extension");
				continue;
			}
			final fieldPos = parser.cur.getPos();
			final annotations = metadata();
			final privateWritten = take(TKeyword(KPrivate));
			final publicWritten = take(TKeyword(KPublic));
			final visibility:HxVisibility = privateWritten ? Private : Public;
			var optional = other("?");
			final method = take(TKeyword(KFunction));
			final isFinal = !method && take(TKeyword(KFinal));
			if (!method && !isFinal)
				take(TKeyword(KVar));
			optional = other("?") || optional;
			final fieldName = name();
			final kind:HxTypeSyntaxFieldKind = if (method) {
				final binders = parameters();
				require(TLParen, "'('");
				final args = arguments();
				require(TRParen, "')'");
				require(TColon, "':'");
				Method(binders, args, type());
			} else {
				var get = "";
				var set = "";
				if (take(TLParen)) {
					get = accessor();
					require(TComma, "','");
					set = accessor();
					require(TRParen, "')'");
				}
				require(TColon, "':'");
				Variable(type(), isFinal, get, set);
			};
			fields.push({
				name: fieldName,
				kind: kind,
				isOptional: optional,
				visibility: visibility,
				isVisibilityExplicit: privateWritten || publicWritten,
				metadata: annotations,
				pos: fieldPos,
				endPos: end
			});
			if (!take(TSemicolon) && !take(TComma) && !parser.cur.kind.match(TRBrace))
				parser.fail("Expected anonymous typedef field separator");
		}
		require(TRBrace, "'}'");
		return new HxTypeSyntax(AnonymousType(fields, extensions), pos, end);
	}

	/** Parse nested type syntax without flattening arrow or grouping information. */
	function type():HxTypeSyntax {
		final pos = parser.cur.getPos();
		final value = if (take(TLBrace)) {
			anonymous(pos);
		} else if (take(TLParen)) {
			final args = arguments();
			require(TRParen, "')'");
			if (args.length == 1 && args[0].name == null && !args[0].isOptional && !args[0].isRest && args[0].metadata.length == 0) {
				// One unnamed type is grouping in the legacy arrow grammar.
				new HxTypeSyntax(GroupedType(args[0].type), pos, end);
			} else if (arrow()) {
				final result = type();
				if (result.getKind().match(ArrowType(_, _)))
					parser.fail("A returned function type must be parenthesized");
				new HxTypeSyntax(FunctionType(args, result), pos, end);
			} else {
				parser.fail("Expected '->' after function type arguments");
			}
		} else {
			final segments = [name()];
			while (take(TDot))
				segments.push(name());
			final args = new Array<HxTypeSyntax>();
			if (other("<")) {
				do {
					args.push(type());
				} while (take(TComma));
				require(TOther(">".code), "'>'");
			}
			new HxTypeSyntax(TypePath(segments, args), pos, end);
		};
		if (arrow()) {
			final result = type();
			return new HxTypeSyntax(ArrowType(value, result), pos, end);
		}
		if (other("&")) {
			final result = type();
			final members = switch result.getKind() {
				case IntersectionType(members): [value].concat(members);
				case _: [value, result];
			};
			return new HxTypeSyntax(IntersectionType(members), pos, end);
		}
		return value;
	}

	public function declaration(visibility:HxVisibility, annotations:Array<String>, isExtern:Bool):HxTypedefDecl {
		final pos = parser.cur.getPos();
		require(TIdent("typedef"), "'typedef'");
		final declarationName = name();
		final binders = parameters();
		require(TOther("=".code), "'='");
		final target = type();
		take(TSemicolon);
		return new HxTypedefDecl({
			name: declarationName,
			visibility: visibility,
			isExtern: isExtern,
			metadata: annotations,
			parameters: binders,
			target: target,
			pos: pos,
			endPos: end
		});
	}
}
