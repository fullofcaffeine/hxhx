package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;

/**
	Retains a producer through a single-write local introduced by expression lowering.

	A declaration and its write must precede the read in the same statement block.
	The whole function, including nested functions, must contain exactly one write.
	Captured locals are excluded. The returned exact read-to-producer links prove
	only provenance; the caller must still validate the producer's carrier contract.
	No variable names, source positions, or generated-name conventions are trusted.
**/
function localInitializerSources(body:TypedExpr):ObjectMap<TypedExpr, TypedExpr> {
	final writes:Map<Int, Int> = [];
	final captured:Map<Int, Bool> = [];
	function write(local:TVar):Void {
		writes.set(local.id, (writes.get(local.id) ?? 0) + 1);
	}
	function scan(current:TypedExpr, nested:Bool):Void {
		switch (current.expr) {
			case TFunction(func):
				scan(func.expr, true);
				return;
			case TVar(local, initializer) if (initializer != null):
				write(local);
			case TBinop(OpAssign | OpAssignOp(_), left, _):
				switch (transparent(left).expr) {
					case TLocal(local): write(local);
					case _:
				}
			case TUnop(OpIncrement | OpDecrement, _, operand):
				switch (transparent(operand).expr) {
					case TLocal(local): write(local);
					case _:
				}
			case TLocal(local) if (nested):
				captured.set(local.id, true);
			case _:
		}
		TypedExprTools.iter(current, child -> scan(child, nested));
	}
	scan(body, false);
	final result:ObjectMap<TypedExpr, TypedExpr> = new ObjectMap();
	function visit(current:TypedExpr):Void {
		switch (current.expr) {
			case TFunction(_):
				return;
			case TBlock(statements):
				final declared:Map<Int, Bool> = [];
				final sources:Map<Int, TypedExpr> = [];
				for (statement in statements) {
					switch (transparent(statement).expr) {
						case TVar(local, initializer):
							if (initializer != null) {
								switch (transparent(initializer).expr) {
									case TLocal(sourceLocal):
										final source = sources.get(sourceLocal.id);
										if (source != null && sameType(source.t, initializer.t)) result.set(initializer, source);
									case _:
								}
							}
							declared.set(local.id, true);
							if (initializer != null && writes.get(local.id) == 1 && !captured.exists(local.id) && sameType(local.t,
								initializer.t)) sources.set(local.id, initializer);
						case TBinop(OpAssign, left, value):
							switch (transparent(left).expr) {
								case TLocal(local)
									if (declared.exists(local.id) && writes.get(local.id) == 1 && !captured.exists(local.id) && sameType(local.t, value.t)):
									sources.set(local.id, value);
								case _:
							}
						case _:
					}
				}
			case _:
		}
		TypedExprTools.iter(current, visit);
	}
	visit(body);
	return result;
}

private function sameType(left:Type, right:Type):Bool {
	return TypeTools.toString(left) == TypeTools.toString(right);
}

private function transparent(expression:TypedExpr):TypedExpr {
	return switch (expression.expr) {
		case TParenthesis(child), TMeta(_, child): transparent(child);
		case _: expression;
	};
}
#end
