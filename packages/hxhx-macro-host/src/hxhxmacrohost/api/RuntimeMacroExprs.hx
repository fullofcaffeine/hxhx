package hxhxmacrohost.api;

import HxExpr;
import HxStmt;
import HxParser;
import StringTools;
import haxe.macro.Expr;

/**
	Minimal runtime parser-backed `Expr` bridge for external-host macro bring-up.

	Why
	- Real macro code often calls `Context.parse(...)` / `Context.parseInlineString(...)` to turn a
	  small Haxe expression snippet into `haxe.macro.Expr` values.
	- The external host does not have upstream's parser or typer available directly, but the repo
	  already has a local expression parser (`HxParser.parseExprText(...)`).

	What
	- Parses text through `HxParser` and converts a deliberately narrow `HxExpr` subset into real
	  `haxe.macro.Expr` values.
	- Supported today:
	  - literals (`null`, booleans, strings, ints, floats)
	  - identifiers / bare enum-like values / `this` / `super`
	  - field access and call chains
	  - narrow arrow lambdas (`(arg0, arg1) -> expr`)
	  - unary / binary / ternary expressions
	  - `new TypePath(...)`
	  - array literals and array access
	  - anonymous-structure literals
	  - `cast expr`, `cast(expr, Type)`, and `untyped expr`

	How
	- `HxParser` performs the text parsing.
	- This bridge converts the resulting `HxExpr` tree into the corresponding macro AST nodes.
	- Unsupported parser nodes fail fast so later parity slices stay explicit instead of quietly
	  fabricating semantics.

	Gotchas
	- This is not a full Haxe parser bridge.
	- Structured switch/try/comprehension/range nodes remain unsupported at runtime.
	- Type-hint parsing for `cast(..., T)` is intentionally narrow and only supports simple path-like
	  forms plus `Null<T>` / `Dynamic<T>` wrappers.
**/
class RuntimeMacroExprs {
	public static function parse(expr:String, pos:Position):Expr {
		if (expr == null)
			throw "runtime macro parse: null source";
		final parsed = HxParser.parseExprText(expr);
		return convert(parsed, pos == null ? defaultPos() : pos);
	}

	public static function parseInlineString(expr:String, pos:Position):Expr {
		if (expr == null)
			throw "runtime macro parse: null source";
		final usePos = pos == null ? defaultPos() : pos;
		final trimmed = StringTools.trim(expr);
		final special = tryParseInlineExpr(trimmed, usePos);
		return special != null ? special : parse(trimmed, usePos);
	}

	public static function parseOptionalComplexTypeText(typeHint:String):Null<ComplexType> {
		return parseOptionalComplexType(typeHint);
	}

	public static function parseFunctionBodyText(bodySource:String, pos:Position):Expr {
		final statements = HxParser.parseFunctionBodyText(bodySource);
		return {
			expr: EBlock([for (stmt in statements) convertStmt(stmt, pos == null ? defaultPos() : pos)]),
			pos: pos == null ? defaultPos() : pos
		};
	}

	/**
		Build a narrow runtime `Expr` value from a macro-runtime value.

		Why
		- Real macro helpers use `Context.makeExpr(...)` to turn plain runtime values into AST.
		- The external-host runtime does not have upstream's full dynamic-to-AST bridge, but it can
		  still support the conservative subset that appears in bring-up probes and common helpers.

		What
		- Supports:
		  - `null`
		  - `Bool`
		  - `String`
		  - `Int`
		  - `Float`
		  - `Array<Dynamic>` recursively
		  - anonymous structures recursively

		Gotchas
		- Enums and richer object graphs are intentionally not implemented yet.
		- Unsupported values fail fast so later parity work stays explicit.
	**/
	public static function makeExpr(value:Dynamic, pos:Position):Expr {
		return convertValue(value, pos == null ? defaultPos() : pos);
	}

	public static function signature(value:Dynamic):String {
		return haxe.crypto.Md5.encode(haxe.Serializer.run(value));
	}

	/**
		Narrow upstream-compatible inline-string parser prepass.

		Why
		- Upstream Haxe 4.3.7 accepts inline-markup payloads in `Context.parseInlineString(...)`
		  that are not representable through the current `HxParser` subset.
		- We only need a bounded subset here:
		  - root `@:markup` literals
		  - `if (...) <markup> else <markup-or-expr>`
		  - call expressions whose arguments recursively use the same subset
		  - arrow lambdas whose bodies recursively use the same subset

		What
		- Recognizes only the upstream-proven shapes above and constructs macro AST directly.
		- Everything else falls back to the ordinary parser-backed path.

		Gotchas
		- This is not a general markup grammar.
		- The supported forms are intentionally small because this path exists to close a concrete
		  Haxe-compat seam, not to become a second parser.
	**/
	static function tryParseInlineExpr(expr:String, pos:Position):Null<Expr> {
		if (expr == null)
			return null;
		final trimmed = StringTools.trim(expr);
		if (trimmed.length == 0)
			return null;

		final markupEnd = scanMarkupLiteral(trimmed, 0);
		if (markupEnd == trimmed.length)
			return makeMarkupExpr(trimmed.substr(0, markupEnd), pos);

		final ifExpr = tryParseInlineIfExpr(trimmed, pos);
		if (ifExpr != null)
			return ifExpr;

		final lambdaExpr = tryParseInlineLambdaExpr(trimmed, pos);
		if (lambdaExpr != null)
			return lambdaExpr;

		return tryParseInlineCallExpr(trimmed, pos);
	}

	static function tryParseInlineIfExpr(expr:String, pos:Position):Null<Expr> {
		if (!StringTools.startsWith(expr, "if"))
			return null;
		var index = skipWhitespace(expr, 2);
		if (index >= expr.length || expr.charCodeAt(index) != "(".code)
			return null;
		final condEnd = scanBalanced(expr, index, "(".code, ")".code);
		if (condEnd < 0)
			return null;
		final condText = expr.substr(index + 1, condEnd - index - 2);
		final thenStart = skipWhitespace(expr, condEnd);
		if (thenStart >= expr.length)
			return null;
		final thenEnd = scanMarkupLiteral(expr, thenStart);
		if (thenEnd < 0)
			return null;
		final elseStart = skipWhitespace(expr, thenEnd);
		if (!hasKeywordAt(expr, elseStart, "else"))
			return null;
		final elseExprStart = skipWhitespace(expr, elseStart + 4);
		if (elseExprStart >= expr.length)
			return null;
		final elseText = expr.substr(elseExprStart);
		return {
			expr: EIf(parse(condText, pos), parseInlineString(expr.substr(thenStart, thenEnd - thenStart), pos), parseInlineString(elseText, pos)),
			pos: pos
		};
	}

	static function tryParseInlineLambdaExpr(expr:String, pos:Position):Null<Expr> {
		final arrow = findTopLevelArrow(expr);
		if (arrow < 0)
			return null;
		final lhs = StringTools.trim(expr.substr(0, arrow));
		final rhs = StringTools.trim(expr.substr(arrow + 2));
		if (lhs.length == 0 || rhs.length == 0)
			return null;

		final args = parseLambdaArgs(lhs);
		if (args == null)
			return null;
		return {
			expr: EFunction(FArrow, {
				args: [
					for (arg in args)
						{
							name: arg,
							type: null,
							opt: false,
							value: null,
							meta: null
						}
				],
				ret: null,
				expr: parseInlineString(rhs, pos),
				params: []
			}),
			pos: pos
		};
	}

	static function tryParseInlineCallExpr(expr:String, pos:Position):Null<Expr> {
		final open = findTopLevelCallOpen(expr);
		if (open <= 0)
			return null;
		final close = scanBalanced(expr, open, "(".code, ")".code);
		if (close != expr.length)
			return null;
		final calleeText = StringTools.trim(expr.substr(0, open));
		if (calleeText.length == 0)
			return null;
		final argTexts = splitTopLevelArgs(expr.substr(open + 1, close - open - 2));
		return {
			expr: ECall(parse(calleeText, pos), [for (arg in argTexts) parseInlineString(arg, pos)]),
			pos: pos
		};
	}

	static function parseLambdaArgs(lhs:String):Null<Array<String>> {
		if (lhs.length == 0)
			return null;
		if (lhs.charCodeAt(0) != "(".code) {
			return isValidLambdaArg(lhs) ? [lhs] : null;
		}
		if (lhs.charCodeAt(lhs.length - 1) != ")".code)
			return null;
		final inner = StringTools.trim(lhs.substr(1, lhs.length - 2));
		if (inner.length == 0)
			return [];
		final raw = splitTopLevelArgs(inner);
		final args = new Array<String>();
		for (part in raw) {
			final arg = StringTools.trim(part);
			if (!isValidLambdaArg(arg))
				return null;
			args.push(arg);
		}
		return args;
	}

	static function isValidLambdaArg(arg:String):Bool {
		if (arg == null || arg.length == 0)
			return false;
		final first = arg.charCodeAt(0);
		if (!(first == "_".code || (first >= "A".code && first <= "Z".code) || (first >= "a".code && first <= "z".code)))
			return false;
		for (i in 1...arg.length) {
			final c = arg.charCodeAt(i);
			if (!(c == "_".code || (c >= "A".code && c <= "Z".code) || (c >= "a".code && c <= "z".code) || (c >= "0".code && c <= "9".code)))
				return false;
		}
		return true;
	}

	static function makeMarkupExpr(payload:String, pos:Position):Expr {
		final inner = {
			expr: EConst(CString(payload, DoubleQuotes)),
			pos: pos
		};
		return {
			expr: EMeta({
				name: ":markup",
				params: [],
				pos: pos
			}, inner),
			pos: pos
		};
	}

	static function hasKeywordAt(source:String, index:Int, keyword:String):Bool {
		if (index < 0 || index + keyword.length > source.length)
			return false;
		final candidate = source.substr(index, keyword.length);
		if (candidate != keyword)
			return false;
		final beforeOk = index == 0 || !isIdentChar(source.charCodeAt(index - 1));
		final afterIndex = index + keyword.length;
		final afterOk = afterIndex >= source.length || !isIdentChar(source.charCodeAt(afterIndex));
		return beforeOk && afterOk;
	}

	static function isIdentChar(c:Int):Bool {
		return c == "_".code
			|| (c >= "A".code && c <= "Z".code)
			|| (c >= "a".code && c <= "z".code)
			|| (c >= "0".code && c <= "9".code);
	}

	static function skipWhitespace(source:String, index:Int):Int {
		var i = index;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code)
				i++;
			else
				break;
		}
		return i;
	}

	static function scanBalanced(source:String, start:Int, open:Int, close:Int):Int {
		if (start < 0 || start >= source.length || source.charCodeAt(start) != open)
			return -1;
		var depth = 0;
		var i = start;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuoted(source, i);
				continue;
			}
			if (c == open)
				depth++;
			else if (c == close) {
				depth--;
				if (depth == 0)
					return i + 1;
			}
			i++;
		}
		return -1;
	}

	static function skipQuoted(source:String, start:Int):Int {
		final quote = source.charCodeAt(start);
		var i = start + 1;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\\".code) {
				i += 2;
				continue;
			}
			if (c == quote)
				return i + 1;
			i++;
		}
		return source.length;
	}

	static function skipInterpolation(source:String, start:Int):Int {
		if (start + 1 >= source.length || source.charCodeAt(start) != "$".code || source.charCodeAt(start + 1) != "{".code)
			return start + 1;
		var depth = 1;
		var i = start + 2;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuoted(source, i);
				continue;
			}
			if (c == "{".code)
				depth++;
			else if (c == "}".code) {
				depth--;
				if (depth == 0)
					return i + 1;
			}
			i++;
		}
		return source.length;
	}

	static function findTopLevelArrow(source:String):Int {
		var paren = 0;
		var bracket = 0;
		var brace = 0;
		var i = 0;
		while (i < source.length - 1) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuoted(source, i);
				continue;
			}
			switch (c) {
				case "(".code:
					paren++;
				case ")".code:
					paren--;
				case "[".code:
					bracket++;
				case "]".code:
					bracket--;
				case "{".code:
					brace++;
				case "}".code:
					brace--;
				case "-".code:
					if (paren == 0 && bracket == 0 && brace == 0 && source.charCodeAt(i + 1) == ">".code)
						return i;
				case _:
			}
			i++;
		}
		return -1;
	}

	static function findTopLevelCallOpen(source:String):Int {
		var paren = 0;
		var bracket = 0;
		var brace = 0;
		var i = 0;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuoted(source, i);
				continue;
			}
			switch (c) {
				case "(".code:
					if (paren == 0 && bracket == 0 && brace == 0)
						return i;
					paren++;
				case ")".code:
					paren--;
				case "[".code:
					bracket++;
				case "]".code:
					bracket--;
				case "{".code:
					brace++;
				case "}".code:
					brace--;
				case _:
			}
			i++;
		}
		return -1;
	}

	static function splitTopLevelArgs(source:String):Array<String> {
		final out = new Array<String>();
		final trimmed = StringTools.trim(source);
		if (trimmed.length == 0)
			return out;
		var start = 0;
		var paren = 0;
		var bracket = 0;
		var brace = 0;
		var i = 0;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuoted(source, i);
				continue;
			}
			switch (c) {
				case "(".code:
					paren++;
				case ")".code:
					paren--;
				case "[".code:
					bracket++;
				case "]".code:
					bracket--;
				case "{".code:
					brace++;
				case "}".code:
					brace--;
				case ",".code:
					if (paren == 0 && bracket == 0 && brace == 0) {
						out.push(StringTools.trim(source.substr(start, i - start)));
						start = i + 1;
					}
				case _:
			}
			i++;
		}
		out.push(StringTools.trim(source.substr(start)));
		return out;
	}

	static function scanMarkupLiteral(source:String, start:Int):Int {
		final begin = skipWhitespace(source, start);
		if (begin >= source.length || source.charCodeAt(begin) != "<".code)
			return -1;
		if (begin + 1 < source.length && source.charCodeAt(begin + 1) == "/".code)
			return -1;

		final stack = new Array<String>();
		var i = begin;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuoted(source, i);
				continue;
			}
			if (c == "$".code && i + 1 < source.length && source.charCodeAt(i + 1) == "{".code) {
				i = skipInterpolation(source, i);
				continue;
			}
			if (c != "<".code) {
				i++;
				continue;
			}

			final isClosing = i + 1 < source.length && source.charCodeAt(i + 1) == "/".code;
			final nameStart = isClosing ? i + 2 : i + 1;
			final name = readMarkupTagName(source, nameStart);
			if (name == null)
				return -1;
			var j = nameStart + name.length;
			var inQuote = -1;
			while (j < source.length) {
				final cj = source.charCodeAt(j);
				if (inQuote >= 0) {
					if (cj == "\\".code)
						j += 2;
					else {
						if (cj == inQuote)
							inQuote = -1;
						j++;
					}
					continue;
				}
				if (cj == "\"".code || cj == "'".code) {
					inQuote = cj;
					j++;
					continue;
				}
				if (cj == "$".code && j + 1 < source.length && source.charCodeAt(j + 1) == "{".code) {
					j = skipInterpolation(source, j);
					continue;
				}
				if (cj == ">".code)
					break;
				j++;
			}
			if (j >= source.length)
				return -1;

			final selfClosing = !isClosing && endsWithSelfClose(source, i, j);
			if (isClosing) {
				if (stack.length == 0)
					return -1;
				stack.pop();
				if (stack.length == 0)
					return j + 1;
			} else if (!selfClosing) {
				stack.push(name);
			} else if (stack.length == 0) {
				return j + 1;
			}
			i = j + 1;
		}
		return -1;
	}

	static function readMarkupTagName(source:String, start:Int):Null<String> {
		if (start >= source.length)
			return null;
		var i = start;
		final first = source.charCodeAt(i);
		final firstOk = first == "_".code
			|| first == ":".code
			|| (first >= "A".code && first <= "Z".code)
			|| (first >= "a".code && first <= "z".code);
		if (!firstOk)
			return null;
		i++;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			final ok = isIdentChar(c) || c == ":".code || c == "-".code || c == ".".code;
			if (!ok)
				break;
			i++;
		}
		return source.substr(start, i - start);
	}

	static function endsWithSelfClose(source:String, tagStart:Int, tagEnd:Int):Bool {
		var i = tagEnd - 1;
		while (i > tagStart) {
			final c = source.charCodeAt(i);
			if (c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code) {
				i--;
				continue;
			}
			return c == "/".code;
		}
		return false;
	}

	static function convert(expr:HxExpr, pos:Position):Expr {
		return {
			expr: convertDef(expr, pos),
			pos: pos == null ? defaultPos() : pos
		};
	}

	static function convertDef(expr:HxExpr, pos:Position):ExprDef {
		return switch (expr) {
			case ENull:
				EConst(CIdent("null"));
			case EBool(value):
				EConst(CIdent(value ? "true" : "false"));
			case EString(value):
				EConst(CString(value, DoubleQuotes));
			case EInt(value):
				EConst(CInt(Std.string(value), null));
			case EFloat(value):
				EConst(CFloat(Std.string(value)));
			case EEnumValue(name):
				EConst(CIdent(name));
			case EThis:
				EConst(CIdent("this"));
			case ESuper:
				EConst(CIdent("super"));
			case EIdent(name):
				EConst(CIdent(name));
			case EField(obj, field):
				EField(convert(obj, pos), field);
			case ECall(callee, args):
				ECall(convert(callee, pos), [for (arg in args) convert(arg, pos)]);
			case ETernary(cond, thenExpr, elseExpr):
				ETernary(convert(cond, pos), convert(thenExpr, pos), convert(elseExpr, pos));
			case EAnon(fieldNames, fieldValues):
				final fields = new Array<ObjectField>();
				final count = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
				for (i in 0...count) {
					fields.push({
						field: fieldNames[i],
						expr: convert(fieldValues[i], pos),
						quotes: null
					});
				}
				EObjectDecl(fields);
			case EArrayDecl(values):
				EArrayDecl([for (value in values) convert(value, pos)]);
			case EArrayAccess(array, index):
				EArray(convert(array, pos), convert(index, pos));
			case ENew(typePath, args):
				ENew(parseTypePath(typePath), [for (arg in args) convert(arg, pos)]);
			case ECast(inner, typeHint):
				ECast(convert(inner, pos), parseOptionalComplexType(typeHint));
			case EUntyped(inner):
				EUntyped(convert(inner, pos));
			case ELambda(args, body):
				EFunction(FArrow, {
					args: [
						for (arg in args)
							{
								name: arg,
								type: null,
								opt: false,
								value: null,
								meta: null
							}
					],
					ret: null,
					expr: convert(body, pos),
					params: []
				});
			case EUnop(op, inner):
				EUnop(parseUnop(op), false, convert(inner, pos));
			case EBinop(op, left, right):
				EBinop(parseBinop(op), convert(left, pos), convert(right, pos));
			case EMacroExpr(_, _) | EMacroType(_) | ETryCatchRaw(_) | ESwitchRaw(_) | ESwitch(_, _, _) | EArrayComprehension(_, _, _) | ERange(_, _) |
				EUnsupported(_):
				throw "runtime macro parse: unsupported parsed expression shape";
		};
	}

	static function parseOptionalComplexType(typeHint:String):Null<ComplexType> {
		final trimmed = StringTools.trim(typeHint == null ? "" : typeHint);
		return trimmed.length == 0 ? null : parseComplexType(trimmed);
	}

	static function parseComplexType(typeHint:String):ComplexType {
		final trimmed = StringTools.trim(typeHint == null ? "" : typeHint);
		if (trimmed.length == 0)
			throw "runtime macro parse: empty cast type hint";
		if (StringTools.startsWith(trimmed, "Null<") && StringTools.endsWith(trimmed, ">"))
			return TPath({
				pack: [],
				name: "Null",
				sub: null,
				params: [TPType(parseComplexType(innerType(trimmed, "Null")))]
			});
		if (StringTools.startsWith(trimmed, "Dynamic<") && StringTools.endsWith(trimmed, ">"))
			return TPath({
				pack: [],
				name: "Dynamic",
				sub: null,
				params: [TPType(parseComplexType(innerType(trimmed, "Dynamic")))]
			});
		return TPath(parseTypePath(trimmed));
	}

	static function innerType(raw:String, prefix:String):String {
		return raw.substr(prefix.length + 1, raw.length - prefix.length - 2);
	}

	static function parseTypePath(typePath:String):TypePath {
		final trimmed = StringTools.trim(typePath == null ? "" : typePath);
		if (trimmed.length == 0)
			throw "runtime macro parse: missing type path";
		final parts = [for (part in trimmed.split(".")) StringTools.trim(part)];
		final filtered = [for (part in parts) if (part.length > 0) part];
		if (filtered.length == 0)
			throw "runtime macro parse: invalid type path " + typePath;
		final name = filtered.pop();
		return {
			pack: filtered,
			name: name,
			sub: null,
			params: []
		};
	}

	static function parseUnop(op:String):Unop {
		return switch (op) {
			case "!": OpNot;
			case "-": OpNeg;
			case "~": OpNegBits;
			case "++": OpIncrement;
			case "--": OpDecrement;
			case _: throw "runtime macro parse: unsupported unary operator " + op;
		};
	}

	static function parseBinop(op:String):Binop {
		if (op != null && op.length > 1 && StringTools.endsWith(op, "="))
			return OpAssignOp(parseBinop(op.substr(0, op.length - 1)));
		return switch (op) {
			case "+": OpAdd;
			case "-": OpSub;
			case "*": OpMult;
			case "/": OpDiv;
			case "%": OpMod;
			case "=": OpAssign;
			case "==": OpEq;
			case "!=": OpNotEq;
			case ">": OpGt;
			case ">=": OpGte;
			case "<": OpLt;
			case "<=": OpLte;
			case "&&": OpBoolAnd;
			case "||": OpBoolOr;
			case "&": OpAnd;
			case "|": OpOr;
			case "^": OpXor;
			case "<<": OpShl;
			case ">>": OpShr;
			case ">>>": OpUShr;
			case "in": OpIn;
			case "...": OpInterval;
			case "??": OpNullCoal;
			case _:
				throw "runtime macro parse: unsupported binary operator " + op;
		};
	}

	static function defaultPos():Position {
		return cast {
			file: "<macro>",
			min: 0,
			max: 0
		};
	}

	static function convertValue(value:Dynamic, pos:Position):Expr {
		if (value == null)
			return makeConstExpr(CIdent("null"), pos);
		if (Std.isOfType(value, Bool))
			return makeConstExpr(CIdent(value ? "true" : "false"), pos);
		if (Std.isOfType(value, String))
			return makeConstExpr(CString(cast value, DoubleQuotes), pos);
		if (Std.isOfType(value, Int))
			return makeConstExpr(CInt(Std.string(value), null), pos);
		if (Std.isOfType(value, Float))
			return makeConstExpr(CFloat(Std.string(value)), pos);
		if (Std.isOfType(value, Array)) {
			final items:Array<Dynamic> = cast value;
			return {
				expr: EArrayDecl([for (item in items) convertValue(item, pos)]),
				pos: pos
			};
		}

		return switch (Type.typeof(value)) {
			case TObject:
				final fields = Reflect.fields(value);
				fields.sort(function(a:String, b:String):Int {
					return Reflect.compare(a, b);
				});
				{
					expr: EObjectDecl([
						for (field in fields)
							{
								field: field,
								expr: convertValue(Reflect.field(value, field), pos),
								quotes: null
							}
					]),
					pos: pos
				};
			case _:
				throw "runtime macro makeExpr: unsupported value";
		};
	}

	static function makeConstExpr(c:Constant, pos:Position):Expr {
		return {
			expr: EConst(c),
			pos: pos
		};
	}

	static function convertStmt(stmt:HxStmt, pos:Position):Expr {
		final usePos = pos == null ? defaultPos() : pos;
		return switch (stmt) {
			case SBlock(stmts, _):
				{expr: EBlock([for (inner in stmts) convertStmt(inner, usePos)]), pos: usePos};
			case SExpr(expr, _):
				convert(expr, usePos);
			case SReturn(expr, _):
				{expr: EReturn(convert(expr, usePos)), pos: usePos};
			case SReturnVoid(_):
				{expr: EReturn(null), pos: usePos};
			case SVar(name, typeHint, init, _):
				{
					expr: EVars([
						{
							name: name == null ? "" : name,
							type: parseOptionalComplexType(typeHint),
							expr: init == null ? null : convert(init, usePos),
							isFinal: false,
							meta: []
						}
					]),
					pos: usePos
				};
			case _:
				throw "runtime macro parse: unsupported function body statement shape";
		};
	}
}
