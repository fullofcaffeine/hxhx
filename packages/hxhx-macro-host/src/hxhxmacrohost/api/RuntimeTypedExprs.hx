package hxhxmacrohost.api;

import haxe.macro.Expr;
import haxe.macro.Type;
import hxhxmacrohost.HostToCompilerRpc;
import hxhxmacrohost.Protocol;

/**
	Minimal runtime `TypedExpr` model for external-host macro bring-up.

	Why
	- `Context.typeExpr()` and `TypedExprTools.*` are exercised by the macro bucket fixtures, but the
	  external host does not have upstream's full typer available at runtime.
	- We still need a deterministic, testable rung for a tiny typed-expression subset.

	What
	- Builds synthetic `TypedExpr` values for:
	  - type-path expressions that can be resolved through the existing compiler-backed
		`Context.getType(...)` rung
	  - literal constants
	  - generic identifiers
	  - dynamic field and call chains
	  - object and array literals
	  - array access
	  - unary/cast/meta wrappers
	  - parenthesized expressions
	  - simple `+` binary expressions
	  - simple block/return wrappers
	  - single-variable `var` declarations
	  - `check-type` wrappers
	- Renders that subset back to deterministic Haxe-like text.

	Gotchas
	- This is intentionally not a general typed AST builder.
	- Newly supported non-constant expression bodies still use conservative `Dynamic`
	  result types unless a more specific runtime type is justified locally.
	- Unsupported expression shapes still fail fast so future slices stay explicit.
**/
class RuntimeTypedExprs {
	public static function typeExpr(e:Expr):TypedExpr {
		if (e == null)
			throw "runtime macro typeExpr: null expr";
		final typePath = extractTypePathCandidate(e);
		if (typePath != null) {
			final typedTypeExpr = tryTypeExprFromPath(typePath, e.pos);
			if (typedTypeExpr != null)
				return typedTypeExpr;
		}
		return switch (e.expr) {
			case EConst(CInt(raw, suffix)):
				if (suffix != null) {}
				makeTyped(e.pos, TConst(TInt(Std.parseInt(raw))), RuntimeMacroTypes.typeofExpr(e));
			case EConst(CFloat(raw)):
				makeTyped(e.pos, TConst(TFloat(raw)), RuntimeMacroTypes.typeofExpr(e));
			case EConst(CString(text, kind)):
				if (kind != null) {}
				makeTyped(e.pos, TConst(TString(text)), RuntimeMacroTypes.typeofExpr(e));
			case EConst(CIdent("true")):
				makeTyped(e.pos, TConst(TBool(true)), RuntimeMacroTypes.typeofExpr(e));
			case EConst(CIdent("false")):
				makeTyped(e.pos, TConst(TBool(false)), RuntimeMacroTypes.typeofExpr(e));
			case EConst(CIdent("null")):
				makeTyped(e.pos, TConst(TNull), RuntimeMacroTypes.typeofExpr(e));
			case EConst(CIdent(name)):
				makeTyped(e.pos, TIdent(name), dynamicType());
			case EParenthesis(inner):
				final typedInner = typeExpr(inner);
				makeTyped(e.pos, TParenthesis(typedInner), typedInner.t);
			case EField(owner, field, _):
				makeTyped(e.pos, TField(typeExpr(owner), FDynamic(field)), dynamicType());
			case ECall(callee, args):
				makeTyped(e.pos, TCall(typeExpr(callee), [for (arg in args) typeExpr(arg)]), dynamicType());
			case EObjectDecl(fields):
				makeTyped(e.pos, TObjectDecl([for (field in fields) {name: field.field, expr: typeExpr(field.expr)}]), dynamicType());
			case EArrayDecl(items):
				makeTyped(e.pos, TArrayDecl([for (item in items) typeExpr(item)]), dynamicType());
			case EArray(arrayExpr, indexExpr):
				makeTyped(e.pos, TArray(typeExpr(arrayExpr), typeExpr(indexExpr)), dynamicType());
			case EMeta(meta, inner):
				final typedInner = typeExpr(inner);
				makeTyped(e.pos, TMeta(meta, typedInner), typedInner.t);
			case ECast(inner, ct):
				final typedInner = typeExpr(inner);
				makeTyped(e.pos, TCast(typedInner, null), ct == null ? typedInner.t : RuntimeMacroTypes.resolveComplexType(ct));
			case EUnop(op, postFix, inner):
				makeTyped(e.pos, TUnop(op, postFix, typeExpr(inner)), dynamicType());
			case EBlock(items):
				typeBlockExpr(e.pos, items);
			case EReturn(value):
				makeTyped(e.pos, TReturn(value == null ? null : typeExpr(value)), RuntimeMacroTypes.getTypeByName("Void"));
			case EVars(vars):
				typeVarsExpr(e.pos, vars);
			case ECheckType(inner, ct):
				final typedInner = typeExpr(inner);
				makeTyped(e.pos, TParenthesis(typedInner), RuntimeMacroTypes.resolveComplexType(ct));
			case EBinop(op, e1, e2):
				final left = typeExpr(e1);
				final right = typeExpr(e2);
				makeTyped(e.pos, TBinop(op, left, right), RuntimeMacroTypes.typeofExpr(e));
			case _:
				throw "runtime macro typeExpr: unsupported expr shape";
		}
	}

	public static function toString(e:TypedExpr):String {
		if (e == null)
			throw "runtime typed expr -> string: null typed expr";
		return switch (e.expr) {
			case TConst(TInt(i)):
				Std.string(i);
			case TConst(TFloat(s)):
				s;
			case TConst(TString(s)):
				quoteString(s);
			case TConst(TBool(true)):
				"true";
			case TConst(TBool(false)):
				"false";
			case TConst(TNull):
				"null";
			case TIdent(name):
				name;
			case TTypeExpr(moduleType):
				RuntimeMacroTypes.moduleTypePath(moduleType);
			case TParenthesis(inner):
				"(" + toString(inner) + ")";
			case TField(owner, FDynamic(field)):
				toString(owner) + "." + field;
			case TField(_, _):
				throw "runtime typed expr -> string: unsupported non-dynamic field access";
			case TCall(callee, args):
				toString(callee) + "(" + [for (arg in args) toString(arg)].join(", ") + ")";
			case TObjectDecl(fields):
				"{" + [for (field in fields) field.name + ": " + toString(field.expr)].join(", ") + "}";
			case TArrayDecl(items):
				"[" + [for (item in items) toString(item)].join(", ") + "]";
			case TArray(arrayExpr, indexExpr):
				toString(arrayExpr) + "[" + toString(indexExpr) + "]";
			case TCast(inner, _):
				"cast " + toString(inner);
			case TMeta(meta, inner):
				renderMetadata(meta) + " " + toString(inner);
			case TUnop(op, postFix, inner):
				renderUnop(op, postFix, inner);
			case TVar(v, expr):
				final prefix = v.isStatic ? "static var " : "var ";
				prefix + v.name + (expr == null ? "" : " = " + toString(expr));
			case TBlock(items):
				"{ " + [for (item in items) toString(item)].join("; ") + " }";
			case TReturn(expr):
				expr == null ? "return" : ("return " + toString(expr));
			case TBinop(op, e1, e2):
				toString(e1) + " " + renderBinop(op) + " " + toString(e2);
			case _:
				throw "runtime typed expr -> string: unsupported typed expr shape";
		};
	}

	public static function toExpr(e:TypedExpr):Expr {
		if (e == null)
			throw "runtime typed expr -> expr: null typed expr";
		return switch (e.expr) {
			case TConst(TInt(i)):
				makeExpr(e.pos, EConst(CInt(Std.string(i), null)));
			case TConst(TFloat(s)):
				makeExpr(e.pos, EConst(CFloat(s)));
			case TConst(TString(s)):
				makeExpr(e.pos, EConst(CString(s, DoubleQuotes)));
			case TConst(TBool(true)):
				makeExpr(e.pos, EConst(CIdent("true")));
			case TConst(TBool(false)):
				makeExpr(e.pos, EConst(CIdent("false")));
			case TConst(TNull):
				makeExpr(e.pos, EConst(CIdent("null")));
			case TIdent(name):
				makeExpr(e.pos, EConst(CIdent(name)));
			case TTypeExpr(moduleType):
				RuntimeMacroTypes.moduleTypeExpr(moduleType, e.pos);
			case TParenthesis(inner):
				makeExpr(e.pos, EParenthesis(toExpr(inner)));
			case TField(owner, FDynamic(field)):
				makeExpr(e.pos, EField(toExpr(owner), field));
			case TField(_, _):
				throw "runtime typed expr -> expr: unsupported non-dynamic field access";
			case TCall(callee, args):
				makeExpr(e.pos, ECall(toExpr(callee), [for (arg in args) toExpr(arg)]));
			case TObjectDecl(fields):
				makeExpr(e.pos, EObjectDecl([
					for (field in fields)
						{field: field.name, expr: toExpr(field.expr), quotes: null}
				]));
			case TArrayDecl(items):
				makeExpr(e.pos, EArrayDecl([for (item in items) toExpr(item)]));
			case TArray(arrayExpr, indexExpr):
				makeExpr(e.pos, EArray(toExpr(arrayExpr), toExpr(indexExpr)));
			case TCast(inner, _):
				makeExpr(e.pos, ECast(toExpr(inner), null));
			case TMeta(meta, inner):
				makeExpr(e.pos, EMeta(meta, toExpr(inner)));
			case TUnop(op, postFix, inner):
				makeExpr(e.pos, EUnop(op, postFix, toExpr(inner)));
			case TVar(v, expr):
				makeExpr(e.pos, EVars([
					{
						name: v.name,
						type: RuntimeMacroTypes.toComplexType(v.t),
						expr: expr == null ? null : toExpr(expr),
						isFinal: false,
						isStatic: v.isStatic,
						meta: []
					}
				]));
			case TBlock(items):
				makeExpr(e.pos, EBlock([for (item in items) toExpr(item)]));
			case TReturn(expr):
				makeExpr(e.pos, EReturn(expr == null ? null : toExpr(expr)));
			case TBinop(op, e1, e2):
				makeExpr(e.pos, EBinop(op, toExpr(e1), toExpr(e2)));
			case _:
				throw "runtime typed expr -> expr: unsupported typed expr shape";
		};
	}

	static function makeTyped(pos:Position, expr:TypedExprDef, t:Type):TypedExpr {
		return {
			expr: expr,
			pos: pos == null ? defaultPosition() : pos,
			t: t
		};
	}

	static function defaultPosition():Position {
		return cast {
			file: "<macro>",
			min: 0,
			max: 0
		};
	}

	static inline function dynamicType():Type {
		return RuntimeMacroTypes.getTypeByName("Dynamic");
	}

	static function tryTypeExprFromPath(path:String, pos:Position):Null<TypedExpr> {
		return try {
			final resolved = resolveTypePathFromCompiler(path);
			final moduleType = RuntimeMacroTypes.moduleTypeOfType(resolved);
			if (moduleType == null)
				null;
			else
				makeTyped(pos, TTypeExpr(moduleType), resolved);
		} catch (_:Dynamic) {
			null;
		}
	}

	static function extractTypePathCandidate(e:Expr):Null<String> {
		final stripped = stripTypePathWrappers(e);
		if (stripped == null)
			return null;
		final parts = new Array<String>();
		if (!collectTypePathParts(stripped, parts))
			return null;
		if (parts.length == 0)
			return null;
		final tail = parts[parts.length - 1];
		if (!looksLikeTypeName(tail))
			return null;
		return parts.join(".");
	}

	static function stripTypePathWrappers(e:Expr):Expr {
		if (e == null)
			return null;
		return switch (e.expr) {
			case EParenthesis(inner):
				stripTypePathWrappers(inner);
			case ECheckType(inner, _):
				stripTypePathWrappers(inner);
			case EMeta(_, inner):
				stripTypePathWrappers(inner);
			case ECast(inner, _):
				stripTypePathWrappers(inner);
			case _:
				e;
		}
	}

	static function collectTypePathParts(e:Expr, out:Array<String>):Bool {
		if (e == null)
			return false;
		return switch (e.expr) {
			case EConst(CIdent(name)):
				if (!isSimpleTypePathSegment(name)) false; else {
					out.push(name);
					true;
				}
			case EField(owner, field, _):
				if (!collectTypePathParts(owner, out) || !isSimpleTypePathSegment(field)) false; else {
					out.push(field);
					true;
				}
			case _:
				false;
		}
	}

	static function isSimpleTypePathSegment(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		return ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(name);
	}

	static function looksLikeTypeName(name:String):Bool {
		if (!isSimpleTypePathSegment(name))
			return false;
		final first = name.charCodeAt(0);
		return first >= "A".code && first <= "Z".code;
	}

	static function resolveTypePathFromCompiler(name:String):Type {
		try {
			return RuntimeMacroTypes.getTypeByName(name);
		} catch (_:Dynamic) {}
		final payload = HostToCompilerRpc.call("context.getType", Protocol.encodeLen("n", name));
		if (payload == null || payload.length == 0)
			throw "runtime macro typeExpr: unresolved type path " + name;
		final parts = Protocol.kvParse(payload);
		if (!parts.exists("ok") || parts.get("ok") != "1")
			throw "runtime macro typeExpr: unresolved type path " + name;
		final metadata = new Array<String>();
		final count = parseNonNegativeInt(parts.exists("c") ? parts.get("c") : "", 0);
		for (i in 0...count) {
			final key = "md" + i;
			if (parts.exists(key))
				metadata.push(parts.get(key));
		}
		final staticFields = new Array<{
			name:String,
			kind:String,
			metadata:Array<String>,
			initExpr:Null<String>,
			args:Array<{
				name:String,
				opt:Bool,
				typeText:String
			}>,
			returnTypeText:Null<String>,
			file:String,
			min:Int,
			max:Int
		}>();
		final staticCount = parseNonNegativeInt(parts.exists("sc") ? parts.get("sc") : "", 0);
		for (i in 0...staticCount) {
			final nameKey = "sn" + i;
			if (!parts.exists(nameKey))
				continue;
			final fieldMetadata = new Array<String>();
			final fieldMetadataCount = parseNonNegativeInt(parts.exists("smc" + i) ? parts.get("smc" + i) : "", 0);
			for (j in 0...fieldMetadataCount) {
				final key = "smd" + i + "_" + j;
				if (parts.exists(key))
					fieldMetadata.push(parts.get(key));
			}
			final args = new Array<{
				name:String,
				opt:Bool,
				typeText:String
			}>();
			final argCount = parseNonNegativeInt(parts.exists("sac" + i) ? parts.get("sac" + i) : "", 0);
			for (j in 0...argCount) {
				final argNameKey = "san" + i + "_" + j;
				if (!parts.exists(argNameKey))
					continue;
				args.push({
					name: parts.get(argNameKey),
					opt: parts.exists("sao" + i + "_" + j) && parts.get("sao" + i + "_" + j) == "1",
					typeText: parts.exists("sat" + i + "_" + j) ? parts.get("sat" + i + "_" + j) : "Dynamic"
				});
			}
			staticFields.push({
				name: parts.get(nameKey),
				kind: parts.exists("sk" + i) ? parts.get("sk" + i) : "var",
				metadata: fieldMetadata,
				initExpr: parts.exists("se" + i) ? parts.get("se" + i) : null,
				args: args,
				returnTypeText: parts.exists("sr" + i) ? parts.get("sr" + i) : null,
				file: parts.exists("sf" + i) ? parts.get("sf" + i) : "<macro>",
				min: parseNonNegativeInt(parts.exists("smin" + i) ? parts.get("smin" + i) : "", 0),
				max: parseNonNegativeInt(parts.exists("smax" + i) ? parts.get("smax" + i) : "", 0)
			});
		}
		final typePath = parts.exists("t") ? parts.get("t") : name;
		final moduleName = parts.exists("m") ? parts.get("m") : null;
		final kind = parts.exists("k") ? parts.get("k") : "class";
		return RuntimeMacroTypes.typeForResolvedDecl(typePath, kind, metadata, moduleName, parts.exists("f") ? parts.get("f") : "<macro>",
			parseNonNegativeInt(parts.exists("min") ? parts.get("min") : "", 0), parseNonNegativeInt(parts.exists("max") ? parts.get("max") : "", 0),
			staticFields);
	}

	static function parseNonNegativeInt(raw:String, fallback:Int):Int {
		final parsed = Std.parseInt(raw);
		return parsed == null || parsed < 0 ? fallback : parsed;
	}

	static function makeExpr(pos:Position, expr:ExprDef):Expr {
		return {
			expr: expr,
			pos: pos == null ? defaultPosition() : pos
		};
	}

	/**
		Build the narrow runtime `TVar` rung used by real Reflaxe consumers.

		Why
		- Vendored sibling code currently calls `Context.typeExpr(macro var name:T = ...)` and then
		  switches directly on `typedExpr.expr` being `TVar(...)`.
		- Returning "unsupported expr shape" there would keep the runtime macro API technically wide
		  but behaviorally dishonest for a real consumer seam.

		What
		- Supports exactly one declared variable at a time.
		- Preserves the variable type from the explicit hint when present, otherwise from the typed
		  initializer, otherwise falls back to `Dynamic`.
		- Uses `Void` as the outer typed-expression type, matching upstream typed var declarations.

		How
		- The initializer is typed through the existing narrow runtime `typeExpr(...)` bridge.
		- The variable record is synthetic and compiler-agnostic; we only claim the TVar shape and the
		  observable type information, not full upstream local-var identity semantics.
	**/
	static function typeVarsExpr(pos:Position, vars:Array<Var>):TypedExpr {
		if (vars == null || vars.length != 1)
			throw "runtime macro typeExpr: only single-variable declarations are supported";
		final v = vars[0];
		final typedInit = v.expr == null ? null : typeExpr(v.expr);
		final varType = if (v.type != null) RuntimeMacroTypes.resolveComplexType(v.type); else if (typedInit != null) typedInit.t; else
			RuntimeMacroTypes.getTypeByName("Dynamic");
		final tvar:TVar = {
			id: 1,
			name: v.name == null ? "" : v.name,
			t: varType,
			capture: false,
			extra: null,
			meta: null,
			isStatic: v.isStatic == true
		};
		return makeTyped(pos, TVar(tvar, typedInit), RuntimeMacroTypes.getTypeByName("Void"));
	}

	static function typeBlockExpr(pos:Position, items:Array<Expr>):TypedExpr {
		final typedItems = items == null ? [] : [for (item in items) typeExpr(item)];
		final resultType = typedItems.length == 0 ? RuntimeMacroTypes.getTypeByName("Void") : typedItems[typedItems.length - 1].t;
		return makeTyped(pos, TBlock(typedItems), resultType);
	}

	static function renderBinop(op:Binop):String {
		return switch (op) {
			case OpAdd:
				"+";
			case OpSub:
				"-";
			case OpMult:
				"*";
			case OpDiv:
				"/";
			case OpMod:
				"%";
			case OpAssign:
				"=";
			case OpEq:
				"==";
			case OpNotEq:
				"!=";
			case OpGt:
				">";
			case OpGte:
				">=";
			case OpLt:
				"<";
			case OpLte:
				"<=";
			case OpAnd:
				"&";
			case OpOr:
				"|";
			case OpXor:
				"^";
			case OpBoolAnd:
				"&&";
			case OpBoolOr:
				"||";
			case OpShl:
				"<<";
			case OpShr:
				">>";
			case OpUShr:
				">>>";
			case OpInterval:
				"...";
			case OpArrow:
				"=>";
			case OpAssignOp(inner):
				renderBinop(inner) + "=";
			case OpIn:
				"in";
			case OpNullCoal:
				"??";
		};
	}

	static function renderUnop(op:Unop, postFix:Bool, inner:TypedExpr):String {
		final renderedInner = toString(inner);
		final renderedOp = switch (op) {
			case OpIncrement: "++";
			case OpDecrement: "--";
			case OpNot: "!";
			case OpNeg: "-";
			case OpNegBits: "~";
			case OpSpread: "...";
		};
		return postFix ? (renderedInner + renderedOp) : (renderedOp + renderedInner);
	}

	static function renderMetadata(meta:MetadataEntry):String {
		final params = meta == null
			|| meta.params == null
			|| meta.params.length == 0 ? "" : ("(" + [for (param in meta.params) renderRawExpr(param)].join(", ") + ")");
		return (meta == null ? "@:unknown" : meta.name) + params;
	}

	static function renderRawExpr(e:Expr):String {
		if (e == null)
			return "null";
		return switch (e.expr) {
			case EConst(CInt(raw, suffix)):
				suffix == null ? raw : (raw + suffix);
			case EConst(CFloat(raw)):
				raw;
			case EConst(CString(text, _)):
				quoteString(text);
			case EConst(CIdent(name)):
				name;
			case EParenthesis(inner):
				"(" + renderRawExpr(inner) + ")";
			case EField(owner, field, _):
				renderRawExpr(owner) + "." + field;
			case ECall(callee, args):
				renderRawExpr(callee) + "(" + [for (arg in args) renderRawExpr(arg)].join(", ") + ")";
			case EObjectDecl(fields):
				"{" + [for (field in fields) field.field + ": " + renderRawExpr(field.expr)].join(", ") + "}";
			case EArrayDecl(items):
				"[" + [for (item in items) renderRawExpr(item)].join(", ") + "]";
			case EArray(arrayExpr, indexExpr):
				renderRawExpr(arrayExpr) + "[" + renderRawExpr(indexExpr) + "]";
			case EMeta(meta, inner):
				renderMetadata(meta) + " " + renderRawExpr(inner);
			case ECast(inner, ct):
				ct == null ? ("cast " + renderRawExpr(inner)) : ("cast(" + renderRawExpr(inner) + ", " + renderComplexType(ct) + ")");
			case EUnop(op, postFix, inner):
				renderRawUnop(op, postFix, inner);
			case EBinop(op, left, right):
				renderRawExpr(left) + " " + renderBinop(op) + " " + renderRawExpr(right);
			case EBlock(items):
				"{ " + [for (item in items) renderRawExpr(item)].join("; ") + " }";
			case EReturn(value):
				value == null ? "return" : ("return " + renderRawExpr(value));
			case EVars(vars):
				final pieces = [
					for (v in vars) {
						final typeText = v.type == null ? "" : (":" + renderComplexType(v.type));
						final exprText = v.expr == null ? "" : (" = " + renderRawExpr(v.expr));
						v.name + typeText + exprText;
					}
				];
				"var " + pieces.join(", ");
			case _:
				"<expr>";
		};
	}

	static function renderRawUnop(op:Unop, postFix:Bool, inner:Expr):String {
		final renderedInner = renderRawExpr(inner);
		final renderedOp = switch (op) {
			case OpIncrement: "++";
			case OpDecrement: "--";
			case OpNot: "!";
			case OpNeg: "-";
			case OpNegBits: "~";
			case OpSpread: "...";
		};
		return postFix ? (renderedInner + renderedOp) : (renderedOp + renderedInner);
	}

	static function renderComplexType(ct:ComplexType):String {
		return switch (ct) {
			case null:
				"Dynamic";
			case TPath(tp):
				renderTypePath(tp);
			case TParent(inner):
				"(" + renderComplexType(inner) + ")";
			case TOptional(inner):
				"?" + renderComplexType(inner);
			case TNamed(name, inner):
				name + ":" + renderComplexType(inner);
			case TFunction(args, ret):
				[for (arg in args) renderComplexType(arg)].join(" -> ") + " -> " + renderComplexType(ret);
			case TAnonymous(_):
				"{...}";
			case TExtend(_, _):
				"{...}";
			case TIntersection(_):
				"Dynamic";
		};
	}

	static function renderTypePath(tp:TypePath):String {
		if (tp == null)
			return "Dynamic";
		final fullName = ((tp.pack == null || tp.pack.length == 0) ? [] : tp.pack).concat([tp.name]).join(".");
		final subName = tp.sub == null ? "" : ("." + tp.sub);
		final params = tp.params == null
			|| tp.params.length == 0 ? "" : ("<" + [for (param in tp.params) renderTypeParam(param)].join(", ") + ">");
		return fullName + subName + params;
	}

	static function renderTypeParam(param:TypeParam):String {
		return switch (param) {
			case TPType(inner):
				renderComplexType(inner);
			case TPExpr(expr):
				renderRawExpr(expr);
		};
	}

	static function quoteString(value:String):String {
		final escapedBackslashes = StringTools.replace(value, "\\", "\\\\");
		final escapedQuotes = StringTools.replace(escapedBackslashes, "\"", "\\\"");
		return "\"" + escapedQuotes + "\"";
	}
}
