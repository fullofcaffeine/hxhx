package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralEvaluationKind;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerContract;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;

/**
	Materializes one already-sealed direct array literal as OCaml syntax.

	The producer decision, not this module, owns source evaluation order. This
	module follows its create/evaluate/store/result steps and introduces a local
	temporary for every element. As a result, an element expression is built once,
	then the already-built value is appended once to the same `HxArray` object.
**/
class OcamlArrayLiteralSyntax {
	/** Turns the producer's exact construction schedule into nested OCaml lets. */
	public static function build(decision:OcamlArrayLiteralProducerDecision, items:Array<TypedExpr>, buildElement:TypedExpr->OcamlExpr,
			freshTemporary:String->String):OcamlExpr {
		OcamlArrayLiteralProducerContract.requireDecision(decision);
		if (items.length != decision.elements.length)
			throw 'reflaxe.ocaml [ocaml-array-literal:typed-element-count-mismatch]: producer "${decision.id}" seals ${decision.elements.length} elements, but syntax received ${items.length}';

		final arrayTemporary = freshTemporary("represented_array");
		final elementTemporaries:Map<Int, String> = [];

		function materialize(stepIndex:Int):OcamlExpr {
			if (stepIndex >= decision.evaluationSchedule.length)
				throw 'reflaxe.ocaml [ocaml-array-literal:missing-result-step]: producer "${decision.id}" ended without returning its array';
			final step = decision.evaluationSchedule[stepIndex];
			return switch (step.kind) {
				case CreateArray:
					final create = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
					OcamlExpr.ELet(arrayTemporary, create, materialize(stepIndex + 1), false);
				case EvaluateElement:
					final elementIndex = requiredElementIndex(decision, stepIndex, step.elementIndex);
					final temporary = freshTemporary("represented_array_element_" + elementIndex);
					elementTemporaries.set(elementIndex, temporary);
					OcamlExpr.ELet(temporary, buildElement(items[elementIndex]), materialize(stepIndex + 1), false);
				case StoreElement:
					final elementIndex = requiredElementIndex(decision, stepIndex, step.elementIndex);
					final temporary = elementTemporaries.get(elementIndex);
					if (temporary == null)
						throw 'reflaxe.ocaml [ocaml-array-literal:store-before-evaluation]: producer "${decision.id}" stores element $elementIndex before its value is evaluated';
					final push = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "push"), [OcamlExpr.EIdent(arrayTemporary), OcamlExpr.EIdent(temporary)])
					]);
					OcamlExpr.ESeq([push, materialize(stepIndex + 1)]);
				case ResultArray:
					if (stepIndex != decision.evaluationSchedule.length - 1)
						throw 'reflaxe.ocaml [ocaml-array-literal:early-result-step]: producer "${decision.id}" returns its array before the schedule ends';
					OcamlExpr.EIdent(arrayTemporary);
			};
		}

		return materialize(0);
	}

	static function requiredElementIndex(decision:OcamlArrayLiteralProducerDecision, stepIndex:Int, value:Null<Int>):Int {
		if (value == null || value < 0 || value >= decision.elements.length)
			throw 'reflaxe.ocaml [ocaml-array-literal:invalid-step-element]: producer "${decision.id}" has no valid element for construction step $stepIndex';
		return value;
	}
}
#end
