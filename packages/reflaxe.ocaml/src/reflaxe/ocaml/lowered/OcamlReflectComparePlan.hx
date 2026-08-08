package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.ds.StringMap;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** The concrete Haxe value family selected for one `Reflect.compare` value. */
enum abstract OcamlReflectCompareDomain(String) from String to String {
	final Int = "int";
	final Float = "float";
	final String = "string";
}

/**
	One resolved standard comparator whose behavior is fixed before OCaml syntax.

	The decision records a concrete domain because Haxe declares
	`Reflect.compare` generically. Contextual typing turns a use such as
	`names.sort(Reflect.compare)` into `(String, String) -> Int`; this plan keeps
	that final fact so target syntax never guesses from the printed field name or
	widens the operands to `Obj.t`.
**/
typedef OcamlReflectCompareDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final domain:OcamlReflectCompareDomain;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/**
	Request-local lookup for every admitted `Reflect.compare` function value.

	The lookup uses the active compiler request's exact typed expression only to
	connect syntax with its already-selected decision. The copied decisions use
	stable source and revision identities; this plan must not be cached across
	requests.
**/
class OcamlReflectComparePlan {
	public static inline final MODEL_REVISION = "typed-ocaml-reflect-compare-intrinsic-v1";
	public static inline final PROOF_ID_PREFIX = "ocaml-reflect-compare-intrinsic-v1:";

	final byExpression:ObjectMap<TypedExpr, OcamlReflectCompareDecision>;
	final bySource:StringMap<Array<OcamlReflectCompareDecision>>;
	final ordered:Array<OcamlReflectCompareDecision>;

	public function new(entries:Array<{expression:TypedExpr, decision:OcamlReflectCompareDecision}>) {
		byExpression = new ObjectMap();
		bySource = new StringMap();
		ordered = [];
		for (entry in entries) {
			requireDecision(entry.decision);
			if (byExpression.exists(entry.expression))
				throw 'reflaxe.ocaml [ocaml-reflect-compare:duplicate-occurrence]: one typed Reflect.compare value was planned more than once';
			byExpression.set(entry.expression, copyDecision(entry.decision));
			final sourceKey = key(entry.decision.source);
			final candidates = bySource.get(sourceKey) ?? [];
			candidates.push(copyDecision(entry.decision));
			bySource.set(sourceKey, candidates);
			ordered.push(copyDecision(entry.decision));
		}
		ordered.sort((left, right) -> Reflect.compare(left.id, right.id));
	}

	/** Returns the decision for one resolved comparator used as a value. */
	public function decisionForValue(expression:TypedExpr):Null<OcamlReflectCompareDecision> {
		if (!isResolvedStandardCompare(expression))
			return null;
		return lookup(expression);
	}

	/** Returns the decision for one direct invocation of the standard comparator. */
	public function decisionForCall(expression:TypedExpr):Null<OcamlReflectCompareDecision> {
		return switch (expression.expr) {
			case TCall(callee, _) if (isResolvedStandardCompare(callee)): lookup(expression);
			case _: null;
		}
	}

	function lookup(expression:TypedExpr):Null<OcamlReflectCompareDecision> {
		final decision = byExpression.get(expression);
		if (decision != null)
			return copyDecision(decision);
		final candidates = bySource.get(key(OcamlLoweredOrigin.sourceSpan(expression.pos))) ?? [];
		if (candidates.length == 0)
			return null;
		if (candidates.length == 1)
			return copyDecision(candidates[0]);
		throw 'reflaxe.ocaml [ocaml-reflect-compare:ambiguous-occurrence]: ${candidates.length} sealed comparator decisions share one typed source occurrence';
	}

	/** Returns report-safe copies in deterministic identity order. */
	public function decisions():Array<OcamlReflectCompareDecision>
		return ordered.map(copyDecision);

	/** Proves that every decision belongs to the function or standalone root. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered) {
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-reflect-compare:stale-plan]: comparator "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
		}
	}

	/**
		Identifies only the resolved root standard-library `Reflect.compare`.

		Reflaxe turns an extern function stored in a variable into a small lambda.
		Its `:wrappedInLambda` marker surrounds the original field and deliberately
		erases that field's function type. Unwrapping that one framework-owned marker
		lets the plan and syntax consumer recognize the same standard function; no
		other metadata or printed field name is accepted.
	**/
	public static function isResolvedStandardCompare(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TMeta(metadata, inner) if (metadata.name == ":wrappedInLambda"):
				isResolvedStandardCompare(inner);
			case TField({expr: TTypeExpr(TClassDecl(ownerRef))}, FStatic(classRef, fieldRef)):
				final owner = ownerRef.get();
				final fieldOwner = classRef.get();
				final field = fieldRef.get();
				owner.pack.length == 0
				&& owner.name == "Reflect"
				&& owner.module == "Reflect"
				&& fieldOwner.module == owner.module
				&& fieldOwner.name == owner.name
				&& field.name == "compare";
			case _:
				false;
		}
	}

	/** True only for the exact Reflaxe lambda wrapper around `Reflect.compare`. */
	public static function isWrappedStandardCompare(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TMeta(metadata, inner) if (metadata.name == ":wrappedInLambda"):
				isResolvedStandardCompare(inner);
			case _:
				false;
		}
	}

	public static function requireDecision(decision:OcamlReflectCompareDecision):Void {
		if (decision.id.length == 0
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0
			|| decision.proofId != PROOF_ID_PREFIX + (decision.domain : String)) {
			throw "reflaxe.ocaml [ocaml-reflect-compare:invalid-plan]: a comparator decision is incomplete or has an unknown proof";
		}
	}

	static function copyDecision(decision:OcamlReflectCompareDecision):OcamlReflectCompareDecision {
		return {
			id: decision.id,
			source: {
				file: decision.source.file,
				min: decision.source.min,
				max: decision.source.max
			},
			domain: decision.domain,
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static inline function key(source:OcamlLoweredSourceSpan):String
		return source.file + ":" + source.min + ":" + source.max;
}

/** Selects the exact comparison domain from the final typed Haxe function. */
class OcamlReflectComparePlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	/**
		Plans every resolved comparator in one root, including nested expressions.

		Unsupported resolved uses fail here, before the builder can emit a plausible
		but incorrect generic comparison. Unrelated fields named `compare` are never
		considered.
	**/
	public function plan(expression:TypedExpr):OcamlReflectComparePlan {
		final entries:Array<{expression:TypedExpr, decision:OcamlReflectCompareDecision}> = [];
		final planned:ObjectMap<TypedExpr, Bool> = new ObjectMap();
		function add(current:TypedExpr, domain:OcamlReflectCompareDomain):Void {
			if (planned.exists(current))
				return;
			planned.set(current, true);
			final source = OcamlLoweredOrigin.sourceSpan(current.pos);
			final proofId = OcamlReflectComparePlan.PROOF_ID_PREFIX + (domain : String);
			entries.push({
				expression: current,
				decision: {
					id: "reflect-compare:" + Sha256.encode([
						binding.functionId,
						binding.programRevision,
						binding.bodyRevision,
						binding.pipelineRevision,
						Std.string(entries.length),
						source.file,
						Std.string(source.min),
						Std.string(source.max),
						(domain : String)
					].join("\u001f")).substr(0, 24),
					source: source,
					domain: domain,
					proofId: proofId,
					proofClaim: proofClaim(domain),
					functionId: binding.functionId,
					programRevision: binding.programRevision,
					bodyRevision: binding.bodyRevision,
					pipelineRevision: binding.pipelineRevision
				}
			});
		}
		function visit(current:TypedExpr):Void {
			switch (current.expr) {
				case TCall(callee, arguments) if (OcamlReflectComparePlan.isResolvedStandardCompare(callee)):
					final domain = domainForCall(callee, arguments, current.t);
					if (domain == null)
						unsupported('${TypeTools.toString(callee.t)} called with (${arguments.map(argument -> TypeTools.toString(argument.t)).join(", ")})');
					add(current, domain);
					// The call decision owns its callee. Mark the nested field as consumed so
					// traversal does not publish a second function-value decision that syntax
					// can never reach independently.
					planned.set(callee, true);
				case TCall(callee, arguments):
					final parameters = switch (TypeTools.follow(callee.t)) {
						case TFun(expected, _): expected;
						case _: [];
					}
					for (index in 0...arguments.length) {
						final argument = arguments[index];
						if (!OcamlReflectComparePlan.isResolvedStandardCompare(argument))
							continue;
						if (index >= parameters.length)
							unsupported('missing callable parameter for argument $index');
						final domain = domainFor(parameters[index].t);
						if (domain == null)
							unsupported(TypeTools.toString(parameters[index].t));
						add(argument, domain);
					}
				case _ if (OcamlReflectComparePlan.isResolvedStandardCompare(current)):
					final functionType = switch (TypeTools.follow(current.t)) {
						case TFun(_, _): true;
						case _: false;
					}
					if (functionType) {
						final domain = domainFor(current.t);
						if (domain == null)
							unsupported(TypeTools.toString(current.t));
						add(current, domain);
					}
				case _:
			}
			TypedExprTools.iter(current, visit);
		}
		visit(expression);
		final plan = new OcamlReflectComparePlan(entries);
		plan.requirePlanBinding(binding);
		return plan;
	}

	static function unsupported(typeDescription:String):Dynamic {
		throw 'reflaxe.ocaml [ocaml-reflect-compare:unsupported-domain]: resolved Reflect.compare has unsupported contextual type $typeDescription; the first native contract accepts only exact (Int, Int), (Float, Float), or (String, String) operands';
	}

	static function domainFor(type:Type):Null<OcamlReflectCompareDomain> {
		return switch (TypeTools.follow(type)) {
			case TFun(arguments, result) if (arguments.length == 2 && OcamlRepresentationRegistry.isExactInt(result)):
				final left = arguments[0].t;
				final right = arguments[1].t;
				if (OcamlRepresentationRegistry.isExactInt(left) && OcamlRepresentationRegistry.isExactInt(right)) {
					OcamlReflectCompareDomain.Int;
				} else if (OcamlRepresentationRegistry.isExactFloat(left) && OcamlRepresentationRegistry.isExactFloat(right)) {
					OcamlReflectCompareDomain.Float;
				} else if (OcamlRepresentationRegistry.isExactString(left) && OcamlRepresentationRegistry.isExactString(right)) {
					OcamlReflectCompareDomain.String;
				} else {
					null;
				}
			case _:
				null;
		}
	}

	static function domainForCall(callee:TypedExpr, arguments:Array<TypedExpr>, result:Type):Null<OcamlReflectCompareDomain> {
		if (arguments.length != 2)
			return null;
		final validResult = if (OcamlReflectComparePlan.isWrappedStandardCompare(callee)) {
			OcamlCallPlanner.isExactVoid(result);
		} else {
			OcamlRepresentationRegistry.isExactInt(result);
		};
		if (!validResult)
			return null;
		final left = arguments[0].t;
		final right = arguments[1].t;
		if (OcamlRepresentationRegistry.isExactInt(left) && OcamlRepresentationRegistry.isExactInt(right))
			return OcamlReflectCompareDomain.Int;
		if (OcamlRepresentationRegistry.isExactFloat(left) && OcamlRepresentationRegistry.isExactFloat(right))
			return OcamlReflectCompareDomain.Float;
		if (OcamlRepresentationRegistry.isExactString(left) && OcamlRepresentationRegistry.isExactString(right))
			return OcamlReflectCompareDomain.String;
		return null;
	}

	static function proofClaim(domain:OcamlReflectCompareDomain):String {
		return switch (domain) {
			case Int:
				"The resolved standard comparator has exact Int operands and returns only their numeric ordering sign; no Dynamic or OCaml structural comparison participates.";
			case Float:
				"The resolved standard comparator has exact Float operands. It rejects NaN deterministically, treats signed zero as equal, and orders all remaining finite or infinite values numerically.";
			case String:
				"The resolved standard comparator has exact String operands. It treats two Haxe null sentinels as equal, rejects a one-null pair, and otherwise compares non-null strings lexicographically.";
		}
	}
}
#end
