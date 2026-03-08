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
	- Structured switch/try/lambda/comprehension/range nodes remain unsupported at runtime.
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
		return parse(expr, pos);
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
			case EUnop(op, inner):
				EUnop(parseUnop(op), false, convert(inner, pos));
			case EBinop(op, left, right):
				EBinop(parseBinop(op), convert(left, pos), convert(right, pos));
			case ETryCatchRaw(_) | ESwitchRaw(_) | ESwitch(_, _, _) | ELambda(_, _) | EArrayComprehension(_, _, _) | ERange(_, _) | EUnsupported(_):
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
