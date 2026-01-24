package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)

import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TConstant;

import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlAssignOp;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.ast.OcamlExpr.OcamlUnop;
import reflaxe.ocaml.ast.OcamlMatchCase;
import reflaxe.ocaml.ast.OcamlPat;

/**
 * Milestone 2: minimal TypedExpr -> OcamlExpr lowering for expressions and function bodies.
 *
 * Notes:
 * - This pass is intentionally conservative: unsupported constructs emit `()` with a comment where possible.
 * - Local vars declared with `TVar` are treated as `ref` (mutable-by-default) for now; M3 will infer mutability.
 */
class OcamlBuilder {
	public final ctx:CompilationContext;

	// Track locals introduced by TVar that we currently represent as `ref`.
	final refLocals:Map<Int, Bool> = [];

	public function new(ctx:CompilationContext) {
		this.ctx = ctx;
	}

	public function buildExpr(e:TypedExpr):OcamlExpr {
		return switch (e.expr) {
			case TConst(c):
				OcamlExpr.EConst(buildConst(c));
			case TLocal(v):
				buildLocal(v);
			case TIdent(s):
				OcamlExpr.EIdent(s);
			case TParenthesis(inner):
				buildExpr(inner);
			case TBinop(op, e1, e2):
				buildBinop(op, e1, e2);
			case TUnop(op, postFix, inner):
				buildUnop(op, postFix, inner);
			case TFunction(tfunc):
				final params = tfunc.args.length == 0
					? [OcamlPat.PConst(OcamlConst.CUnit)]
					: tfunc.args.map(a -> OcamlPat.PVar(a.v.name));
				OcamlExpr.EFun(params, buildExpr(tfunc.expr));
			case TIf(cond, eif, eelse):
				OcamlExpr.EIf(buildExpr(cond), buildExpr(eif), eelse != null ? buildExpr(eelse) : OcamlExpr.EConst(OcamlConst.CUnit));
			case TBlock(el):
				buildBlock(el);
			case TVar(v, init):
				// Variable declarations should generally be handled by `buildBlock`
				// so that scope covers the remainder of the block.
				OcamlExpr.EConst(OcamlConst.CUnit);
			case TCall(fn, args):
				OcamlExpr.EApp(buildExpr(fn), args.map(buildExpr));
			case TField(obj, fa):
				buildField(obj, fa);
			case TMeta(_, e1):
				buildExpr(e1);
			case TCast(e1, _):
				buildExpr(e1);
			case TWhile(cond, body, normalWhile):
				// do {body} while(cond) not supported yet; lower as while for now
				if (!normalWhile) {
					OcamlExpr.ESeq([buildExpr(body), OcamlExpr.EWhile(buildExpr(cond), buildExpr(body))]);
				} else {
					OcamlExpr.EWhile(buildExpr(cond), buildExpr(body));
				}
			case TSwitch(scrutinee, cases, edef):
				buildSwitch(scrutinee, cases, edef);
			case TArrayDecl(items):
				// Placeholder: represent Haxe Array literals as OCaml lists for now.
				OcamlExpr.EList(items.map(buildExpr));
			case TObjectDecl(_):
				// Placeholder until class/anon-struct strategy lands.
				OcamlExpr.EConst(OcamlConst.CUnit);
			case TReturn(ret):
				ret != null ? buildExpr(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	function buildConst(c:TConstant):OcamlConst {
		return switch (c) {
			case TInt(v): OcamlConst.CInt(v);
			case TFloat(v): OcamlConst.CFloat(v);
			case TString(v): OcamlConst.CString(v);
			case TBool(v): OcamlConst.CBool(v);
			case TNull: OcamlConst.CUnit;
			case TThis, TSuper:
				OcamlConst.CUnit;
		}
	}

	function buildLocal(v:TVar):OcamlExpr {
		final name = renameVar(v.name);
		final isRef = refLocals.exists(v.id) && refLocals.get(v.id) == true;
		return isRef ? OcamlExpr.EUnop(OcamlUnop.Deref, OcamlExpr.EIdent(name)) : OcamlExpr.EIdent(name);
	}

	function renameVar(name:String):String {
		final existing = ctx.variableRenameMap.get(name);
		if (existing != null) return existing;

		// reserved words are handled by Reflaxe reservedVarNames; keep deterministic suffix as backup.
		final renamed = name;
		ctx.variableRenameMap.set(name, renamed);
		return renamed;
	}

	function buildVarDecl(v:TVar, init:Null<TypedExpr>):OcamlExpr {
		// Kept for compatibility when TVar occurs outside of a block (rare in typed output).
		// Prefer `buildBlock` handling for correct scoping.
		refLocals.set(v.id, true);
		final initExpr = init != null ? buildExpr(init) : OcamlExpr.EConst(OcamlConst.CUnit);
		return OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [initExpr]);
	}

	function buildBinop(op:Binop, e1:TypedExpr, e2:TypedExpr):OcamlExpr {
		return switch (op) {
			case OpAssign:
				// Handle local ref assignment: x = v  ->  x := v
				switch (e1.expr) {
					case TLocal(v) if (refLocals.exists(v.id)):
						OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), buildExpr(e2));
					case _:
						OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case OpAdd: OcamlExpr.EBinop(OcamlBinop.Add, buildExpr(e1), buildExpr(e2));
			case OpSub: OcamlExpr.EBinop(OcamlBinop.Sub, buildExpr(e1), buildExpr(e2));
			case OpMult: OcamlExpr.EBinop(OcamlBinop.Mul, buildExpr(e1), buildExpr(e2));
			case OpDiv: OcamlExpr.EBinop(OcamlBinop.Div, buildExpr(e1), buildExpr(e2));
			case OpMod: OcamlExpr.EBinop(OcamlBinop.Mod, buildExpr(e1), buildExpr(e2));
			case OpEq: OcamlExpr.EBinop(OcamlBinop.Eq, buildExpr(e1), buildExpr(e2));
			case OpNotEq: OcamlExpr.EBinop(OcamlBinop.Neq, buildExpr(e1), buildExpr(e2));
			case OpLt: OcamlExpr.EBinop(OcamlBinop.Lt, buildExpr(e1), buildExpr(e2));
			case OpLte: OcamlExpr.EBinop(OcamlBinop.Lte, buildExpr(e1), buildExpr(e2));
			case OpGt: OcamlExpr.EBinop(OcamlBinop.Gt, buildExpr(e1), buildExpr(e2));
			case OpGte: OcamlExpr.EBinop(OcamlBinop.Gte, buildExpr(e1), buildExpr(e2));
			case OpBoolAnd: OcamlExpr.EBinop(OcamlBinop.And, buildExpr(e1), buildExpr(e2));
			case OpBoolOr: OcamlExpr.EBinop(OcamlBinop.Or, buildExpr(e1), buildExpr(e2));
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	function buildUnop(op:Unop, postFix:Bool, e:TypedExpr):OcamlExpr {
		return switch (op) {
			case OpNot:
				OcamlExpr.EUnop(OcamlUnop.Not, buildExpr(e));
			case OpNeg:
				OcamlExpr.EUnop(OcamlUnop.Neg, buildExpr(e));
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	function buildBlock(exprs:Array<TypedExpr>):OcamlExpr {
		return buildBlockFromIndex(exprs, 0);
	}

	function buildBlockFromIndex(exprs:Array<TypedExpr>, index:Int):OcamlExpr {
		if (index >= exprs.length) return OcamlExpr.EConst(OcamlConst.CUnit);

		final e = exprs[index];
		return switch (e.expr) {
			case TVar(v, init):
				// Default for M2: locals are refs so we can compile assignments and while counters.
				refLocals.set(v.id, true);
				final initExpr = init != null ? buildExpr(init) : OcamlExpr.EConst(OcamlConst.CUnit);
				final rhs = OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [initExpr]);
				OcamlExpr.ELet(renameVar(v.name), rhs, buildBlockFromIndex(exprs, index + 1), false);
			case TReturn(ret):
				ret != null ? buildExpr(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
			case _:
				final current = buildExpr(e);
				if (index == exprs.length - 1) {
					current;
				} else {
					final rest = buildBlockFromIndex(exprs, index + 1);
					switch (rest) {
						case ESeq(items):
							OcamlExpr.ESeq([current].concat(items));
						case _:
							OcamlExpr.ESeq([current, rest]);
					}
				}
		}
	}

	function buildSwitch(
		scrutinee:TypedExpr,
		cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>,
		edef:Null<TypedExpr>
	):OcamlExpr {
		final arms:Array<OcamlMatchCase> = [];
		for (c in cases) {
			final pats = c.values.map(buildSwitchValuePat);
			final pat = pats.length == 1 ? pats[0] : OcamlPat.POr(pats);
			arms.push({ pat: pat, guard: null, expr: buildExpr(c.expr) });
		}
		arms.push({
			pat: OcamlPat.PAny,
			guard: null,
			expr: edef != null ? buildExpr(edef) : OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Non-exhaustive switch"))])
		});
		return OcamlExpr.EMatch(buildExpr(scrutinee), arms);
	}

	function buildSwitchValuePat(v:TypedExpr):OcamlPat {
		return switch (v.expr) {
			case TConst(c):
				OcamlPat.PConst(buildConst(c));
			case _:
				OcamlPat.PAny;
		}
	}

	function buildField(obj:TypedExpr, fa:FieldAccess):OcamlExpr {
		return switch (fa) {
			case FStatic(clsRef, cfRef):
				final cls = clsRef.get();
				final modName = moduleIdToOcamlModuleName(cls.module);
				OcamlExpr.EField(OcamlExpr.EIdent(modName), cfRef.get().name);
			case _:
				// For now, treat unknown field access as unit.
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	static function moduleIdToOcamlModuleName(moduleId:String):String {
		if (moduleId == null || moduleId.length == 0) return "Main";
		final flat = moduleId.split(".").join("_");
		return flat.substr(0, 1).toUpperCase() + flat.substr(1);
	}
}

#end
