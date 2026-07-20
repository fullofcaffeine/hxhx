package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type.TFunc;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageDecision;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageKind;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageReason;

/**
	Selects the OCaml storage shape needed by mutated Haxe locals.

	A straight-line assignment can become a newer immutable `let` binding. A
	write that must remain visible across a loop, nested block, nested function,
	or expression boundary needs one shared `ref` cell. Captured-and-mutated
	locals also need a cell so every closure observes the same storage.

	This planner intentionally preserves the legacy builder's conservative
	classification. It changes ownership and makes reasons inspectable; it does
	not change generated code or attempt broader representation optimization.
**/
class OcamlLocalStoragePlanner {
	/** Plans storage for a block whose expressions are top-level statements. */
	public static function planExpressions(expressions:Array<TypedExpr>):OcamlLocalStoragePlan {
		final mutatedAny:Map<Int, Bool> = [];
		final needsRef:Map<Int, Bool> = [];
		final captured:Map<Int, Bool> = [];
		final declaredScopeByLocal:Map<Int, Int> = [];
		final reasonsByLocal:Map<Int, Array<OcamlLocalStorageReason>> = [];

		function addReason(localId:Int, reason:OcamlLocalStorageReason):Void {
			final reasons = reasonsByLocal.get(localId);
			if (reasons == null) {
				reasonsByLocal.set(localId, [reason]);
				return;
			}
			final reasonId:String = reason;
			for (existing in reasons) {
				final existingId:String = existing;
				if (existingId == reasonId)
					return;
			}
			reasons.push(reason);
		}

		function collectDeclaredLocalIdsShallow(expression:TypedExpr, declared:Map<Int, Bool>):Void {
			switch (expression.expr) {
				case TVar(local, initializer):
					declared.set(local.id, true);
					if (initializer != null)
						collectDeclaredLocalIdsShallow(initializer, declared);
				case TFunction(_):
					// A nested function defines its own scope.
				case _:
					TypedExprTools.iter(expression, child -> collectDeclaredLocalIdsShallow(child, declared));
			}
		}

		function collectUsedLocalIdsShallow(expression:TypedExpr, used:Map<Int, Bool>):Void {
			switch (expression.expr) {
				case TLocal(local):
					used.set(local.id, true);
				case TFunction(_):
					// A deeper function reports its own captured locals when visited.
				case _:
					TypedExprTools.iter(expression, child -> collectUsedLocalIdsShallow(child, used));
			}
		}

		function declaredLocalsForFunction(functionExpression:TFunc):Map<Int, Bool> {
			final declared:Map<Int, Bool> = [];
			for (argument in functionExpression.args)
				declared.set(argument.v.id, true);
			collectDeclaredLocalIdsShallow(functionExpression.expr, declared);
			return declared;
		}

		function capturedOuterLocalsForFunction(functionExpression:TFunc):Map<Int, Bool> {
			final declared = declaredLocalsForFunction(functionExpression);
			final used:Map<Int, Bool> = [];
			collectUsedLocalIdsShallow(functionExpression.expr, used);

			final outer:Map<Int, Bool> = [];
			for (localId in used.keys()) {
				if (!declared.exists(localId))
					outer.set(localId, true);
			}
			return outer;
		}

		function addContextReasons(localId:Int, crossesDeclaringScope:Bool, inLoop:Bool, inFunction:Bool, isStatement:Bool):Void {
			if (inLoop)
				addReason(localId, OcamlLocalStorageReason.LoopMutation);
			if (inFunction)
				addReason(localId, OcamlLocalStorageReason.NestedFunctionMutation);
			if (isStatement && crossesDeclaringScope)
				addReason(localId, OcamlLocalStorageReason.NestedBlockMutation);
			if (!isStatement)
				addReason(localId, OcamlLocalStorageReason.ExpressionPositionMutation);
		}

		function markSimpleAssignment(localId:Int, scopeDepth:Int, inLoop:Bool, inFunction:Bool, isStatement:Bool):Void {
			mutatedAny.set(localId, true);
			final declarationScope = declaredScopeByLocal.get(localId) ?? 0;
			final crossesDeclaringScope = declarationScope != scopeDepth;
			final canUseImmutableRebinding = isStatement && !crossesDeclaringScope && !inLoop && !inFunction;
			if (canUseImmutableRebinding) {
				addReason(localId, OcamlLocalStorageReason.StraightLineAssignment);
				return;
			}
			needsRef.set(localId, true);
			addContextReasons(localId, crossesDeclaringScope, inLoop, inFunction, isStatement);
		}

		function markCellMutation(localId:Int, reason:OcamlLocalStorageReason, scopeDepth:Int, inLoop:Bool, inFunction:Bool, isStatement:Bool):Void {
			mutatedAny.set(localId, true);
			needsRef.set(localId, true);
			addReason(localId, reason);
			final declarationScope = declaredScopeByLocal.get(localId) ?? 0;
			addContextReasons(localId, declarationScope != scopeDepth, inLoop, inFunction, isStatement);
		}

		function visit(expression:TypedExpr, scopeDepth:Int, inLoop:Bool, ownedLocals:Null<Map<Int, Bool>>, isStatement:Bool):Void {
			switch (expression.expr) {
				case TVar(local, _):
					declaredScopeByLocal.set(local.id, scopeDepth);
				case TFunction(functionExpression):
					final functionCaptures = capturedOuterLocalsForFunction(functionExpression);
					for (localId in functionCaptures.keys())
						captured.set(localId, true);
					// The sealed plan covers the complete function tree, but each nested
					// function still has its own straight-line block. Reset the lexical
					// scope and loop context so its own locals retain the storage choice they
					// received when the legacy builder rescanned that function alone.
					final functionLocals = declaredLocalsForFunction(functionExpression);
					for (argument in functionExpression.args)
						declaredScopeByLocal.set(argument.v.id, 0);
					switch (functionExpression.expr.expr) {
						case TBlock(items):
							for (item in items)
								visit(item, 0, false, functionLocals, true);
						case _:
							visit(functionExpression.expr, 0, false, functionLocals, true);
					}
					return;
				case TWhile(condition, body, _):
					visit(condition, scopeDepth, true, ownedLocals, false);
					visit(body, scopeDepth, true, ownedLocals, false);
					return;
				case TBlock(items):
					for (item in items)
						visit(item, scopeDepth + 1, inLoop, ownedLocals, true);
					return;
				case _:
			}

			switch (expression.expr) {
				case TBinop(OpAssign, left, _):
					switch (left.expr) {
						case TLocal(local):
							final mutatesCapturedOuter = ownedLocals != null && !ownedLocals.exists(local.id);
							markSimpleAssignment(local.id, scopeDepth, inLoop, mutatesCapturedOuter, isStatement);
						case _:
					}
				case TBinop(OpAssignOp(_), left, _):
					switch (left.expr) {
						case TLocal(local):
							final mutatesCapturedOuter = ownedLocals != null && !ownedLocals.exists(local.id);
							markCellMutation(local.id, OcamlLocalStorageReason.CompoundAssignment, scopeDepth, inLoop, mutatesCapturedOuter, isStatement);
						case _:
					}
				case TUnop(OpIncrement, _, operand) | TUnop(OpDecrement, _, operand):
					switch (operand.expr) {
						case TLocal(local):
							final mutatesCapturedOuter = ownedLocals != null && !ownedLocals.exists(local.id);
							markCellMutation(local.id, OcamlLocalStorageReason.IncrementOrDecrement, scopeDepth, inLoop, mutatesCapturedOuter, isStatement);
						case _:
					}
				case _:
			}

			TypedExprTools.iter(expression, child -> visit(child, scopeDepth, inLoop, ownedLocals, false));
		}

		for (expression in expressions)
			visit(expression, 0, false, null, true);

		for (localId in captured.keys()) {
			if (mutatedAny.exists(localId) && mutatedAny.get(localId) == true) {
				needsRef.set(localId, true);
				addReason(localId, OcamlLocalStorageReason.CapturedAndMutated);
			}
		}

		final decisions:Array<OcamlLocalStorageDecision> = [];
		for (localId in mutatedAny.keys()) {
			final reasons = reasonsByLocal.get(localId) ?? [];
			reasons.sort((left, right) -> {
				final leftId:String = left;
				final rightId:String = right;
				return leftId < rightId ? -1 : (leftId > rightId ? 1 : 0);
			});
			decisions.push({
				localId: localId,
				storage: needsRef.exists(localId)
				&& needsRef.get(localId) == true ? OcamlLocalStorageKind.RefCell : OcamlLocalStorageKind.ImmutableRebinding,
				reasons: reasons
			});
		}
		return new OcamlLocalStoragePlan(decisions);
	}

	/** Plans storage for one expression, treating a root block as statements. */
	public static function planExpression(expression:TypedExpr):OcamlLocalStoragePlan {
		return switch (expression.expr) {
			case TBlock(expressions): planExpressions(expressions);
			case _: planExpressions([expression]);
		}
	}
}
#end
