package hxhxmacrohost.api;

import haxe.macro.Expr;
import haxe.macro.Type;

/**
	Minimal runtime `TypedExpr` model for external-host macro bring-up.

	Why
	- `Context.typeExpr()` and `TypedExprTools.*` are exercised by the macro bucket fixtures, but the
	  external host does not have upstream's full typer available at runtime.
	- We still need a deterministic, testable rung for a tiny typed-expression subset.

	What
	- Builds synthetic `TypedExpr` values for:
	  - literal constants
	  - parenthesized expressions
	  - simple `+` binary expressions
	  - single-variable `var` declarations
	  - `check-type` wrappers
	- Renders that subset back to deterministic Haxe-like text.

	Gotchas
	- This is intentionally not a general typed AST builder.
	- Unsupported expression shapes fail fast so future slices stay explicit.
**/
class RuntimeTypedExprs {
	public static function typeExpr(e:Expr):TypedExpr {
		if (e == null)
			throw "runtime macro typeExpr: null expr";
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
			case EParenthesis(inner):
				final typedInner = typeExpr(inner);
				makeTyped(e.pos, TParenthesis(typedInner), typedInner.t);
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
			case TParenthesis(inner):
				"(" + toString(inner) + ")";
			case TVar(v, expr):
				final prefix = v.isStatic ? "static var " : "var ";
				prefix + v.name + (expr == null ? "" : " = " + toString(expr));
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
			case TParenthesis(inner):
				makeExpr(e.pos, EParenthesis(toExpr(inner)));
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

	static function quoteString(value:String):String {
		final escapedBackslashes = StringTools.replace(value, "\\", "\\\\");
		final escapedQuotes = StringTools.replace(escapedBackslashes, "\"", "\\\"");
		return "\"" + escapedQuotes + "\"";
	}
}
