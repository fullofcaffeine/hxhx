package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlExpr.OcamlRawPart;
import reflaxe.ocaml.ast.OcamlRawInterpolationPlan.OcamlRawInterpolationPlanPart;
import reflaxe.ocaml.ast.OcamlRawInterpolationPlan.OcamlRawInterpolationPlanResult;

/** The checked raw-template plan or the source-facing reason it was rejected. */
enum OcamlRawInjectionPlanResult {
	PlanReady(plan:OcamlRawInjectionPlan);
	PlanInvalid(message:String);
}

/** The completed raw injection or a compiler-invariant failure. */
enum OcamlRawInjectionMaterializationResult {
	InjectionReady(injection:OcamlRawInjection);
	InjectionInvalid(message:String);
}

/**
	A validated raw template whose typed expression positions are fixed.

	Planning happens before the typed arguments are compiled. This matters because
	an invalid raw template must not create runtime-use records or other target
	syntax as a side effect. The private constructor prevents callers from
	inventing a plan that skipped namespace and placeholder checks.
**/
class OcamlRawInjectionPlan {
	public final argumentCount:Int;

	final plannedParts:Array<OcamlRawInterpolationPlanPart>;

	private function new(argumentCount:Int, plannedParts:Array<OcamlRawInterpolationPlanPart>) {
		this.argumentCount = argumentCount;
		this.plannedParts = plannedParts.copy();
	}

	/** Validates authored text and fixes every typed argument's exact position. */
	public static function create(template:String, argumentCount:Int):OcamlRawInjectionPlanResult {
		if (template == null)
			template = "";
		final privateNames = OcamlCodeIdentifierScanner.scan(template).filter(OcamlCodeIdentifierScanner.isPrivateRuntimeIdentifier);
		if (privateNames.length > 0) {
			return PlanInvalid("raw __ocaml__ text cannot name compiler-private runtime identifier "
				+ privateNames[0]
				+ "; use a typed Haxe expression or supported extern instead");
		}

		return switch (OcamlRawInterpolationPlan.create(template, argumentCount)) {
			case Planned(parts): PlanReady(new OcamlRawInjectionPlan(argumentCount, parts));
			case Invalid(message): PlanInvalid(message);
		};
	}

	/** Returns a defensive copy so a validated plan cannot be changed by its caller. */
	public function parts():Array<OcamlRawInterpolationPlanPart> {
		return plannedParts.copy();
	}
}

/**
	Validated authored OCaml text with structurally visible typed expressions.

	The OCaml target supports `__ocaml__` as an explicit escape hatch. Authored
	text stays opaque after this boundary, so this value proves the text cannot
	name compiler-private `Hx...` runtime modules and every typed argument appears
	exactly once. The target AST carries this value instead of exposing an
	unchecked raw-expression constructor.
**/
class OcamlRawInjection {
	final storedSegments:Array<OcamlRawPart>;

	private function new(segments:Array<OcamlRawPart>) {
		storedSegments = segments.copy();
	}

	/** Validates a template without compiling any typed argument expression. */
	public static function plan(template:String, argumentCount:Int):OcamlRawInjectionPlanResult {
		return OcamlRawInjectionPlan.create(template, argumentCount);
	}

	/**
		Binds one compiled expression to each position in a validated plan.

		The cardinality checks are repeated here so a corrupted or stale plan cannot
		drop, duplicate, or reorder a typed child before it reaches the target AST.
	**/
	public static function materialize(plan:OcamlRawInjectionPlan, typedArguments:Array<OcamlExpr>):OcamlRawInjectionMaterializationResult {
		if (plan == null)
			return InjectionInvalid("raw __ocaml__ injection has no validated template plan");
		if (typedArguments == null)
			typedArguments = [];
		if (typedArguments.length != plan.argumentCount) {
			return InjectionInvalid('raw __ocaml__ injection expected ${plan.argumentCount} typed arguments but received ${typedArguments.length}');
		}

		final seen = [for (_ in 0...typedArguments.length) 0];
		final segments:Array<OcamlRawPart> = [];
		for (part in plan.parts()) {
			switch (part) {
				case AuthoredText(value):
					segments.push(RawText(value));
				case TypedArgument(index):
					if (index < 0 || index >= typedArguments.length)
						return InjectionInvalid('raw __ocaml__ plan refers to missing typed argument $index');
					seen[index]++;
					segments.push(RawExpression(typedArguments[index]));
			}
		}
		for (index in 0...seen.length) {
			if (seen[index] != 1)
				return InjectionInvalid('raw __ocaml__ typed argument $index must appear exactly once; found ${seen[index]} planned positions');
		}
		return InjectionReady(new OcamlRawInjection(segments));
	}

	/** Returns a defensive copy for mechanical printing and read-only inspection. */
	public function segments():Array<OcamlRawPart> {
		return storedSegments.copy();
	}

	/** Rebuilds only typed children and preserves this wrapper when none changed. */
	public function mapExpressions(mapExpression:OcamlExpr->OcamlExpr):OcamlRawInjection {
		var changed = false;
		final mapped:Array<OcamlRawPart> = [];
		for (segment in storedSegments) {
			switch (segment) {
				case RawText(_):
					mapped.push(segment);
				case RawExpression(expression):
					final mappedExpression = mapExpression(expression);
					if (mappedExpression != expression)
						changed = true;
					mapped.push(RawExpression(mappedExpression));
			}
		}
		return changed ? new OcamlRawInjection(mapped) : this;
	}
}
