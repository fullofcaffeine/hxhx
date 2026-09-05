package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlRawInterpolationPlan.OcamlRawInterpolationPlanPart;

using StringTools;

/**
	One authored-text or typed-value segment inside raw OCaml interpolation.

	The value type is generic so template validation does not depend on the target
	AST module. This one-way dependency keeps the model compilable by native OCaml
	while callers still choose the exact expression type carried by each segment.
**/
enum OcamlRawPart<T> {
	RawText(value:String);
	RawExpression(expression:T);
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
	public static function validate(template:String, argumentCount:Int):OcamlRawInjectionPlanResult<OcamlRawInjectionPlan> {
		if (template == null)
			template = "";
		final privateNames = OcamlCodeIdentifierScanner.scan(template).filter(OcamlCodeIdentifierScanner.isPrivateRuntimeIdentifier);
		if (privateNames.length > 0) {
			return PlanInvalid("raw __ocaml__ text cannot name compiler-private runtime identifier "
				+ privateNames[0]
				+ "; use a typed Haxe expression or supported extern instead");
		}

		if (argumentCount < 0)
			return PlanInvalid("raw __ocaml__ interpolation received a negative typed-argument count");

		final referencedArguments:Array<Int> = [];
		final parts:Array<OcamlRawInterpolationPlanPart> = [];
		var lastPosition = 0;
		var invalidReason:Null<String> = null;
		~/{(\d+)}/g.map(template, function(ereg) {
			final matchPosition = ereg.matchedPos();
			if (matchPosition.pos > lastPosition)
				parts.push(AuthoredText(template.substring(lastPosition, matchPosition.pos)));

			final beforeIsIdentifier = matchPosition.pos > 0
				&& OcamlCodeIdentifierScanner.isIdentifierPartCode(template.fastCodeAt(matchPosition.pos - 1));
			final afterPosition = matchPosition.pos + matchPosition.len;
			final afterIsIdentifier = afterPosition < template.length
				&& OcamlCodeIdentifierScanner.isIdentifierPartCode(template.fastCodeAt(afterPosition));
			final argumentIndex = Std.parseInt(ereg.matched(1));
			if (beforeIsIdentifier || afterIsIdentifier) {
				if (invalidReason == null)
					invalidReason = 'raw __ocaml__ interpolation placeholder ${ereg.matched(0)} must be separated from authored identifier text';
			} else if (argumentIndex == null || argumentIndex < 0 || argumentIndex >= argumentCount) {
				if (invalidReason == null)
					invalidReason = 'raw __ocaml__ interpolation placeholder ${ereg.matched(0)} has no matching typed argument';
			} else {
				referencedArguments.push(argumentIndex);
				parts.push(TypedArgument(argumentIndex));
			}
			lastPosition = matchPosition.pos + matchPosition.len;
			return "";
		});
		if (lastPosition < template.length)
			parts.push(AuthoredText(template.substring(lastPosition)));

		if (invalidReason != null)
			return PlanInvalid(invalidReason);
		for (index in 0...argumentCount) {
			var count = 0;
			for (referencedArgument in referencedArguments) {
				if (referencedArgument == index)
					count++;
			}
			if (count != 1)
				return PlanInvalid('raw __ocaml__ typed argument $index must appear exactly once; found $count placeholders');
		}
		return PlanReady(new OcamlRawInjectionPlan(argumentCount, parts));
	}

	/** Returns a defensive copy so a validated plan cannot be changed by its caller. */
	public function parts():Array<OcamlRawInterpolationPlanPart> {
		return plannedParts.copy();
	}
}

/** The checked raw-template plan or the source-facing reason it was rejected. */
enum OcamlRawInjectionPlanResult<T> {
	PlanReady(plan:T);
	PlanInvalid(message:String);
}

/**
	Validated authored OCaml text with structurally visible typed expressions.

	The OCaml target supports `__ocaml__` as an explicit escape hatch. Authored
	text stays opaque after this boundary, so this value proves the text cannot
	name compiler-private `Hx...` runtime modules and every typed argument appears
	exactly once. The target AST carries this value instead of exposing an
	unchecked raw-expression constructor.
**/
class OcamlRawInjection<T> {
	final storedSegments:Array<OcamlRawPart<T>>;

	private function new(segments:Array<OcamlRawPart<T>>) {
		storedSegments = segments.copy();
	}

	/** Validates a template without compiling any typed argument expression. */
	public static function plan(template:String, argumentCount:Int):OcamlRawInjectionPlanResult<OcamlRawInjectionPlan> {
		return OcamlRawInjectionPlan.validate(template, argumentCount);
	}

	/**
		Binds one compiled expression to each position in a validated plan.

		The cardinality checks are repeated here so a corrupted or stale plan cannot
		drop, duplicate, or reorder a typed child before it reaches the target AST.
	**/
	public static function materialize<T>(plan:OcamlRawInjectionPlan, typedArguments:Array<T>):OcamlRawInjectionMaterializationResult<OcamlRawInjection<T>> {
		if (plan == null)
			return InjectionInvalid("raw __ocaml__ injection has no validated template plan");
		if (typedArguments == null)
			typedArguments = [];
		if (typedArguments.length != plan.argumentCount) {
			return InjectionInvalid('raw __ocaml__ injection expected ${plan.argumentCount} typed arguments but received ${typedArguments.length}');
		}

		final seen = [for (_ in 0...typedArguments.length) 0];
		final segments:Array<OcamlRawPart<T>> = [];
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
	public function segments():Array<OcamlRawPart<T>> {
		return storedSegments.copy();
	}

	/** Rebuilds only typed children and preserves this wrapper when none changed. */
	public function mapExpressions(mapExpression:T->T):OcamlRawInjection<T> {
		var changed = false;
		final mapped:Array<OcamlRawPart<T>> = [];
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

/** The completed raw injection or a compiler-invariant failure. */
enum OcamlRawInjectionMaterializationResult<T> {
	InjectionReady(injection:T);
	InjectionInvalid(message:String);
}
