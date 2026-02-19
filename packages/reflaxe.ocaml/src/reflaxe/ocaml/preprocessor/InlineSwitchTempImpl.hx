package reflaxe.ocaml.preprocessor;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TypedExprDef;
import haxe.macro.Type.TVar;
import haxe.macro.TypedExprTools;
import reflaxe.preprocessors.BasePreprocessor;
import reflaxe.data.ClassFuncData;
import reflaxe.BaseCompiler;

/**
 * Collapses common Haxe desugaring shapes into expressions that map better to OCaml.
 *
 * Current focus (M2): `var _g = expr; switch(_g) ...` -> `switch(expr) ...`
 */
class InlineSwitchTempImpl extends BasePreprocessor {
	public function new() {}

	public function process(data:ClassFuncData, compiler:BaseCompiler):Void {
		if (data.expr == null)
			return;
		data.setExpr(transform(data.expr));
	}

	static inline function withExpr(e:TypedExpr, expr:TypedExprDef):TypedExpr {
		return {expr: expr, pos: e.pos, t: e.t};
	}

	function transform(e:TypedExpr):TypedExpr {
		final updated:TypedExpr = switch (e.expr) {
			case TBlock(el):
				final next = inlineSwitchTemps(el);
				withExpr(e, TBlock(next));
			case _:
				e;
		}

		return TypedExprTools.map(updated, transform);
	}

	function inlineSwitchTemps(el:Array<TypedExpr>):Array<TypedExpr> {
		if (el.length < 2)
			return el;

		final out:Array<TypedExpr> = [];
		var i = 0;
		while (i < el.length) {
			if (i + 1 < el.length) {
				switch [el[i].expr, el[i + 1].expr] {
					case [TVar(v, init), TSwitch(switchExpr, cases, edef)] if (init != null && isLocalVar(switchExpr, v)):
						{
							// Ensure the temp isn't used later in the block.
							if (!isVarUsedInExprs(el, i + 2, v.id)) {
								out.push(withExpr(el[i + 1], TSwitch(init, cases, edef)));
								i += 2;
								continue;
							}
						}
					case _:
				}
			}

			out.push(el[i]);
			i += 1;
		}

		return out;
	}

	static function isLocalVar(e:TypedExpr, v:TVar):Bool {
		return switch (e.expr) {
			case TLocal(v2): v2.id == v.id;
			case _: false;
		}
	}

	static function isVarUsedInExprs(exprs:Array<TypedExpr>, startIndex:Int, varId:Int):Bool {
		for (i in startIndex...exprs.length) {
			if (isVarUsed(exprs[i], varId))
				return true;
		}
		return false;
	}

	static function isVarUsed(e:TypedExpr, varId:Int):Bool {
		var used = false;
		function visit(e:TypedExpr):TypedExpr {
			switch (e.expr) {
				case TLocal(v) if (v.id == varId):
					used = true;
				case _:
			}
			return TypedExprTools.map(e, visit);
		}
		visit(e);
		return used;
	}
}
#end
