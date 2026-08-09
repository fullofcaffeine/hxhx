package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralEvaluationKind;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerContract;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;

/**
	The completed literal and its exact compiler-runtime calls.

	`runtimeOperations` contains the same create and push expression values that
	were placed in `expression`. The caller checks these small subtrees because an
	element expression can contain separate compiler work with its own owner.
**/
typedef OcamlArrayLiteralMaterialization = {
	final expression:OcamlExpr;
	final runtimeOperations:Array<OcamlExpr>;
}

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
			freshTemporary:String->String, runtimeAuthority:OcamlRuntimeUseAuthority):OcamlArrayLiteralMaterialization {
		OcamlArrayLiteralProducerContract.requireDecision(decision);
		if (runtimeAuthority == null)
			throw 'reflaxe.ocaml [ocaml-array-literal:missing-runtime-authority]: producer "${decision.id}" cannot construct private HxArray identifiers';
		if (items.length != decision.elements.length)
			throw 'reflaxe.ocaml [ocaml-array-literal:typed-element-count-mismatch]: producer "${decision.id}" seals ${decision.elements.length} elements, but syntax received ${items.length}';

		final arrayTemporary = freshTemporary("represented_array");
		final elementTemporaries:Map<Int, String> = [];
		final runtimeOperations:Array<OcamlExpr> = [];

		function runtimeReference(useIndex:Int, exactSymbol:String, role:String):OcamlRuntimeReference {
			if (useIndex < 0 || useIndex >= decision.runtimeUseOccurrences.length)
				throw 'reflaxe.ocaml [ocaml-array-literal:missing-runtime-use]: producer "${decision.id}" has no runtime use at index $useIndex';
			final occurrence = decision.runtimeUseOccurrences[useIndex];
			if (occurrence.exactSymbol != exactSymbol || occurrence.role != role)
				throw 'reflaxe.ocaml [ocaml-array-literal:wrong-runtime-use]: producer "${decision.id}" expected $role/$exactSymbol at runtime-use index $useIndex';
			return runtimeAuthority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		}

		function materialize(stepIndex:Int):OcamlExpr {
			if (stepIndex >= decision.evaluationSchedule.length)
				throw 'reflaxe.ocaml [ocaml-array-literal:missing-result-step]: producer "${decision.id}" ended without returning its array';
			final step = decision.evaluationSchedule[stepIndex];
			return switch (step.kind) {
				case CreateArray:
					final createReference = runtimeReference(0, "HxArray.create", "create-array");
					final create = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(createReference), [OcamlExpr.EConst(OcamlConst.CUnit)]);
					runtimeOperations.push(create);
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
					final pushReference = runtimeReference(elementIndex + 1, "HxArray.push", 'store-element:$elementIndex');
					final pushOperation = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(pushReference),
						[OcamlExpr.EIdent(arrayTemporary), OcamlExpr.EIdent(temporary)]);
					runtimeOperations.push(pushOperation);
					final push = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [pushOperation]);
					OcamlExpr.ESeq([push, materialize(stepIndex + 1)]);
				case ResultArray:
					if (stepIndex != decision.evaluationSchedule.length - 1)
						throw 'reflaxe.ocaml [ocaml-array-literal:early-result-step]: producer "${decision.id}" returns its array before the schedule ends';
					OcamlExpr.EIdent(arrayTemporary);
			};
		}

		return {
			expression: materialize(0),
			runtimeOperations: runtimeOperations
		};
	}

	static function requiredElementIndex(decision:OcamlArrayLiteralProducerDecision, stepIndex:Int, value:Null<Int>):Int {
		if (value == null || value < 0 || value >= decision.elements.length)
			throw 'reflaxe.ocaml [ocaml-array-literal:invalid-step-element]: producer "${decision.id}" has no valid element for construction step $stepIndex';
		return value;
	}
}
#end
