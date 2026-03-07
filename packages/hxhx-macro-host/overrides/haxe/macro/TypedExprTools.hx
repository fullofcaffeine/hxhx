package haxe.macro;

import haxe.macro.Type;
import hxhxmacrohost.api.RuntimeTypedExprs;

/**
	Macro-host override for `haxe.macro.TypedExprTools`.

	Why
	- Runtime macro modules executed through `hxhx-macro-host` can now construct a narrow synthetic
	  `TypedExpr` subset via `Context.typeExpr()`.
	- The same runtime code and the macro-host build itself already rely on `TypedExprTools.map`,
	  `iter`, and `toString`, so the override has to be coherent rather than a one-method stub.

	What
	- Provides a small typed-expression utility layer that works in both personalities:
	  - macro/eval contexts keep a normal macro-quality `toString(...)` surface,
	  - runtime contexts use the synthetic typed-expression model from `RuntimeTypedExprs`.
	- `map` / `iter` / `mapWithType` handle the standard typed-expression tree shape without
	  pretending to expose more runtime typing semantics than we actually have.

	Gotchas
	- This is a bring-up utility layer, not a claim of full upstream typed-expression parity.
	- Runtime `toString(...)` only supports the synthetic subset currently produced by
	  `RuntimeTypedExprs.typeExpr(...)`.
**/
class TypedExprTools {
	static inline function withExpr(e:TypedExpr, ?expr:TypedExprDef, ?t:Type):TypedExpr {
		return {
			expr: expr == null ? e.expr : expr,
			pos: e.pos,
			t: t == null ? e.t : t
		};
	}

	#if macro
	public static function map(e:TypedExpr, f:TypedExpr->TypedExpr):TypedExpr {
		return switch (e.expr) {
			case TConst(_) | TLocal(_) | TBreak | TContinue | TTypeExpr(_) | TIdent(_):
				e;
			case TArray(e1, e2):
				withExpr(e, TArray(f(e1), f(e2)));
			case TBinop(op, e1, e2):
				withExpr(e, TBinop(op, f(e1), f(e2)));
			case TField(e1, fa):
				withExpr(e, TField(f(e1), fa));
			case TParenthesis(e1):
				withExpr(e, TParenthesis(f(e1)));
			case TObjectDecl(fields):
				withExpr(e, TObjectDecl([for (field in fields) {name: field.name, expr: f(field.expr)}]));
			case TArrayDecl(items):
				withExpr(e, TArrayDecl([for (item in items) f(item)]));
			case TCall(e1, args):
				withExpr(e, TCall(f(e1), [for (arg in args) f(arg)]));
			case TNew(c, params, args):
				withExpr(e, TNew(c, params, [for (arg in args) f(arg)]));
			case TUnop(op, postFix, e1):
				withExpr(e, TUnop(op, postFix, f(e1)));
			case TFunction(fun):
				withExpr(e, TFunction({
					args: [for (arg in fun.args) {v: arg.v, value: arg.value == null ? null : f(arg.value)}],
					t: fun.t,
					expr: f(fun.expr)
				}));
			case TVar(v, expr):
				withExpr(e, TVar(v, expr == null ? null : f(expr)));
			case TBlock(items):
				withExpr(e, TBlock([for (item in items) f(item)]));
			case TFor(v, e1, e2):
				withExpr(e, TFor(v, f(e1), f(e2)));
			case TIf(econd, eif, eelse):
				withExpr(e, TIf(f(econd), f(eif), eelse == null ? null : f(eelse)));
			case TWhile(econd, body, normalWhile):
				withExpr(e, TWhile(f(econd), f(body), normalWhile));
			case TSwitch(subject, cases, defaultExpr):
				withExpr(e,
					TSwitch(f(subject), [for (c in cases) {values: [for (value in c.values) f(value)], expr: f(c.expr)}],
						defaultExpr == null ? null : f(defaultExpr)));
			case TTry(body, catches):
				withExpr(e, TTry(f(body), [for (c in catches) {v: c.v, expr: f(c.expr)}]));
			case TReturn(expr):
				withExpr(e, TReturn(expr == null ? null : f(expr)));
			case TThrow(e1):
				withExpr(e, TThrow(f(e1)));
			case TCast(e1, moduleType):
				withExpr(e, TCast(f(e1), moduleType));
			case TMeta(meta, e1):
				withExpr(e, TMeta(meta, f(e1)));
			case TEnumParameter(e1, enumField, index):
				withExpr(e, TEnumParameter(f(e1), enumField, index));
			case TEnumIndex(e1):
				withExpr(e, TEnumIndex(f(e1)));
		};
	}

	public static function iter(e:TypedExpr, f:TypedExpr->Void):Void {
		switch (e.expr) {
			case TConst(_) | TLocal(_) | TBreak | TContinue | TTypeExpr(_) | TIdent(_):
			case TArray(e1, e2) | TBinop(_, e1, e2) | TFor(_, e1, e2) | TWhile(e1, e2, _):
				f(e1);
				f(e2);
			case TThrow(e1) | TEnumParameter(e1, _, _) | TEnumIndex(e1) | TField(e1, _) | TParenthesis(e1) | TUnop(_, _, e1) | TCast(e1, _) | TMeta(_, e1):
				f(e1);
			case TArrayDecl(items) | TNew(_, _, items) | TBlock(items):
				for (item in items)
					f(item);
			case TObjectDecl(fields):
				for (field in fields)
					f(field.expr);
			case TCall(e1, args):
				f(e1);
				for (arg in args)
					f(arg);
			case TVar(_, expr) | TReturn(expr):
				if (expr != null)
					f(expr);
			case TFunction(fun):
				for (arg in fun.args)
					if (arg.value != null)
						f(arg.value);
				f(fun.expr);
			case TIf(econd, eif, eelse):
				f(econd);
				f(eif);
				if (eelse != null)
					f(eelse);
			case TSwitch(subject, cases, defaultExpr):
				f(subject);
				for (c in cases) {
					for (value in c.values)
						f(value);
					f(c.expr);
				}
				if (defaultExpr != null)
					f(defaultExpr);
			case TTry(body, catches):
				f(body);
				for (c in catches)
					f(c.expr);
		}
	}

	public static function mapWithType(e:TypedExpr, f:TypedExpr->TypedExpr, ft:Type->Type, fv:TVar->TVar):TypedExpr {
		return switch (e.expr) {
			case TConst(_) | TBreak | TContinue | TTypeExpr(_) | TIdent(_):
				withExpr(e, null, ft(e.t));
			case TLocal(v):
				withExpr(e, TLocal(fv(v)), ft(e.t));
			case TArray(e1, e2):
				withExpr(e, TArray(f(e1), f(e2)), ft(e.t));
			case TBinop(op, e1, e2):
				withExpr(e, TBinop(op, f(e1), f(e2)), ft(e.t));
			case TField(e1, fa):
				withExpr(e, TField(f(e1), fa), ft(e.t));
			case TParenthesis(e1):
				withExpr(e, TParenthesis(f(e1)), ft(e.t));
			case TObjectDecl(fields):
				withExpr(e, TObjectDecl([for (field in fields) {name: field.name, expr: f(field.expr)}]), ft(e.t));
			case TArrayDecl(items):
				withExpr(e, TArrayDecl([for (item in items) f(item)]), ft(e.t));
			case TCall(e1, args):
				withExpr(e, TCall(f(e1), [for (arg in args) f(arg)]), ft(e.t));
			case TNew(c, params, args):
				withExpr(e, TNew(c, [for (param in params) ft(param)], [for (arg in args) f(arg)]), ft(e.t));
			case TUnop(op, postFix, e1):
				withExpr(e, TUnop(op, postFix, f(e1)), ft(e.t));
			case TFunction(fun):
				withExpr(e, TFunction({
					args: [
						for (arg in fun.args)
							{v: fv(arg.v), value: arg.value == null ? null : f(arg.value)}
					],
					t: ft(fun.t),
					expr: f(fun.expr)
				}), ft(e.t));
			case TVar(v, expr):
				withExpr(e, TVar(fv(v), expr == null ? null : f(expr)), ft(e.t));
			case TBlock(items):
				withExpr(e, TBlock([for (item in items) f(item)]), ft(e.t));
			case TFor(v, e1, e2):
				withExpr(e, TFor(fv(v), f(e1), f(e2)), ft(e.t));
			case TIf(econd, eif, eelse):
				withExpr(e, TIf(f(econd), f(eif), eelse == null ? null : f(eelse)), ft(e.t));
			case TWhile(econd, body, normalWhile):
				withExpr(e, TWhile(f(econd), f(body), normalWhile), ft(e.t));
			case TSwitch(subject, cases, defaultExpr):
				withExpr(e,
					TSwitch(f(subject), [for (c in cases) {values: [for (value in c.values) f(value)], expr: f(c.expr)}],
						defaultExpr == null ? null : f(defaultExpr)),
					ft(e.t));
			case TTry(body, catches):
				withExpr(e, TTry(f(body), [for (c in catches) {v: fv(c.v), expr: f(c.expr)}]), ft(e.t));
			case TReturn(expr):
				withExpr(e, TReturn(expr == null ? null : f(expr)), ft(e.t));
			case TThrow(e1):
				withExpr(e, TThrow(f(e1)), ft(e.t));
			case TCast(e1, moduleType):
				withExpr(e, TCast(f(e1), moduleType), ft(e.t));
			case TMeta(meta, e1):
				withExpr(e, TMeta(meta, f(e1)), ft(e.t));
			case TEnumParameter(e1, enumField, index):
				withExpr(e, TEnumParameter(f(e1), enumField, index), ft(e.t));
			case TEnumIndex(e1):
				withExpr(e, TEnumIndex(f(e1)), ft(e.t));
		};
	}

	public static function toString(t:TypedExpr, ?pretty:Bool = false):String {
		return @:privateAccess haxe.macro.Context.sExpr(t, pretty);
	}
	#else
	public static function map(e:TypedExpr, f:TypedExpr->TypedExpr):TypedExpr {
		return switch (e.expr) {
			case TArray(e1, e2):
				withExpr(e, TArray(f(e1), f(e2)));
			case TBinop(op, e1, e2):
				withExpr(e, TBinop(op, f(e1), f(e2)));
			case TField(e1, fa):
				withExpr(e, TField(f(e1), fa));
			case TParenthesis(e1):
				withExpr(e, TParenthesis(f(e1)));
			case TObjectDecl(fields):
				withExpr(e, TObjectDecl([for (field in fields) {name: field.name, expr: f(field.expr)}]));
			case TArrayDecl(items):
				withExpr(e, TArrayDecl([for (item in items) f(item)]));
			case TCall(e1, args):
				withExpr(e, TCall(f(e1), [for (arg in args) f(arg)]));
			case TNew(c, params, args):
				withExpr(e, TNew(c, params, [for (arg in args) f(arg)]));
			case TUnop(op, postFix, e1):
				withExpr(e, TUnop(op, postFix, f(e1)));
			case TFunction(fun):
				withExpr(e, TFunction({
					args: [for (arg in fun.args) {v: arg.v, value: arg.value == null ? null : f(arg.value)}],
					t: fun.t,
					expr: f(fun.expr)
				}));
			case TVar(v, expr):
				withExpr(e, TVar(v, expr == null ? null : f(expr)));
			case TBlock(items):
				withExpr(e, TBlock([for (item in items) f(item)]));
			case TFor(v, e1, e2):
				withExpr(e, TFor(v, f(e1), f(e2)));
			case TIf(econd, eif, eelse):
				withExpr(e, TIf(f(econd), f(eif), eelse == null ? null : f(eelse)));
			case TWhile(econd, body, normalWhile):
				withExpr(e, TWhile(f(econd), f(body), normalWhile));
			case TSwitch(subject, cases, defaultExpr):
				withExpr(e,
					TSwitch(f(subject), [for (c in cases) {values: [for (value in c.values) f(value)], expr: f(c.expr)}],
						defaultExpr == null ? null : f(defaultExpr)));
			case TTry(body, catches):
				withExpr(e, TTry(f(body), [for (c in catches) {v: c.v, expr: f(c.expr)}]));
			case TReturn(expr):
				withExpr(e, TReturn(expr == null ? null : f(expr)));
			case _:
				e;
		};
	}

	public static function iter(e:TypedExpr, f:TypedExpr->Void):Void {
		switch (e.expr) {
			case TArray(e1, e2) | TBinop(_, e1, e2) | TFor(_, e1, e2) | TWhile(e1, e2, _):
				f(e1);
				f(e2);
			case TField(e1, _) | TParenthesis(e1) | TUnop(_, _, e1):
				f(e1);
			case TArrayDecl(items) | TNew(_, _, items) | TBlock(items):
				for (item in items)
					f(item);
			case TObjectDecl(fields):
				for (field in fields)
					f(field.expr);
			case TCall(e1, args):
				f(e1);
				for (arg in args)
					f(arg);
			case TVar(_, expr) | TReturn(expr):
				if (expr != null)
					f(expr);
			case TFunction(fun):
				for (arg in fun.args)
					if (arg.value != null)
						f(arg.value);
				f(fun.expr);
			case TIf(econd, eif, eelse):
				f(econd);
				f(eif);
				if (eelse != null)
					f(eelse);
			case TSwitch(subject, cases, defaultExpr):
				f(subject);
				for (c in cases) {
					for (value in c.values)
						f(value);
					f(c.expr);
				}
				if (defaultExpr != null)
					f(defaultExpr);
			case TTry(body, catches):
				f(body);
				for (c in catches)
					f(c.expr);
			case _:
		}
	}

	public static function mapWithType(e:TypedExpr, f:TypedExpr->TypedExpr, ft:Type->Type, fv:TVar->TVar):TypedExpr {
		return switch (e.expr) {
			case TLocal(v):
				withExpr(e, TLocal(fv(v)), ft(e.t));
			case TVar(v, expr):
				withExpr(e, TVar(fv(v), expr == null ? null : f(expr)), ft(e.t));
			case TFor(v, e1, e2):
				withExpr(e, TFor(fv(v), f(e1), f(e2)), ft(e.t));
			case TFunction(fun):
				withExpr(e, TFunction({
					args: [
						for (arg in fun.args)
							{v: fv(arg.v), value: arg.value == null ? null : f(arg.value)}
					],
					t: ft(fun.t),
					expr: f(fun.expr)
				}), ft(e.t));
			case TNew(c, params, args):
				withExpr(e, TNew(c, [for (param in params) ft(param)], [for (arg in args) f(arg)]), ft(e.t));
			case _:
				withExpr(map(e, f), null, ft(e.t));
		};
	}

	public static function toString(t:TypedExpr, ?pretty:Bool = false):String {
		if (pretty != false) {}
		return RuntimeTypedExprs.toString(t);
	}
	#end
}
