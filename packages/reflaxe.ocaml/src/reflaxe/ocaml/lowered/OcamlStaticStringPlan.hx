package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Expr.Binop;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
#if macro
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The Haxe operation that requests one static String conversion. */
enum abstract OcamlStaticStringSourceKind(String) from String to String {
	final StdString = "std-string";
	final StringConcat = "string-concat";
	final StringCompoundLeft = "string-compound-left";
	final StringCompoundRight = "string-compound-right";
	final ReflectFieldName = "reflect-field-name";
}

/** One immutable decision for one generated `HxString.toStdString` call. */
typedef OcamlStaticStringDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final ownerSource:OcamlLoweredSourceSpan;
	final sourceKind:OcamlStaticStringSourceKind;
	final semanticTypeId:String;
	final inputCarrierTypeId:String;
	final order:Int;
	final profileEligibility:Array<String>;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/**
	Validates the static String conversions selected from one final typed root.

	Static String values use the OCaml `string` carrier. This plan keeps those
	uses separate from Dynamic string conversion, which uses an `Obj.t` carrier
	and `HxDynamic.toStdString`.
**/
class OcamlStaticStringPlan {
	public static inline final MODEL_REVISION = "ocaml-static-string-runtime-use-v1";
	public static inline final PROOF_ID = "static-string-runtime-use-v1";
	public static inline final PROOF_CLAIM = "One final typed String or Null<String> occurrence authorizes exactly one HxString.toStdString identifier. String literals, null literals, completed concatenations, and Dynamic values do not receive this authority.";
	public static inline final RUNTIME_CAPABILITY = "haxe-static-string-conversion";
	public static inline final EXACT_SYMBOL = "HxString.toStdString";
	public static inline final INPUT_CARRIER_TYPE = "string";

	final ordered:Array<OcamlStaticStringDecision>;
	final byId:Map<String, OcamlStaticStringDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlStaticStringDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-static-string:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Requires the decision for this exact request-local typed expression. */
	public function requireFor(expression:TypedExpr):OcamlStaticStringDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-static-string:missing-decision]: static String syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-static-string:missing-decision]: the typed occurrence names no sealed static String decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	public function decisions():Array<OcamlStaticStringDecision>
		return ordered.map(copyDecision);

	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision)
				throw 'reflaxe.ocaml [ocaml-static-string:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
	}

	/** Rejects changed source, type, requirement, or occurrence facts. */
	public static function requireDecision(decision:OcamlStaticStringDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.ownerSource.file.length == 0
			|| decision.ownerSource.min < 0
			|| decision.ownerSource.max < decision.ownerSource.min
			|| (decision.semanticTypeId != "String" && decision.semanticTypeId != "Null<String>")
			|| decision.inputCarrierTypeId != INPUT_CARRIER_TYPE
			|| decision.order < 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeUseOccurrences.length != 1
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-static-string:invalid-plan]: static String decision has incomplete or incompatible facts";

		final requirementId = runtimeRequirementId(decision.id);
		final role = roleFor(decision.sourceKind);
		final expectedRevision = sealRevision(decision.id, decision.source, decision.ownerSource, decision.sourceKind, decision.semanticTypeId,
			decision.inputCarrierTypeId, decision.order, bindingFor(decision), requirementId, role);
		final occurrence = decision.runtimeUseOccurrences[0];
		if (decision.revision != expectedRevision
			|| decision.runtimeRequirementIds[0] != requirementId
			|| occurrence.id != runtimeUseId(decision.id, role)
			|| occurrence.planRevision != decision.revision
			|| occurrence.ownerId != decision.id
			|| occurrence.requirementId != requirementId
			|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
			|| occurrence.exactSymbol != EXACT_SYMBOL
			|| occurrence.role != role
			|| occurrence.order != 0
			|| occurrence.source.file != decision.source.file
			|| occurrence.source.min != decision.source.min
			|| occurrence.source.max != decision.source.max
			|| occurrence.profileEligibility.join(",") != "metal,portable"
			|| occurrence.cardinality != 1)
			throw 'reflaxe.ocaml [ocaml-static-string:invalid-runtime-use]: decision "${decision.id}" has stale or conflicting runtime facts';
	}

	public static function roleFor(sourceKind:OcamlStaticStringSourceKind):String {
		return switch (sourceKind) {
			case StdString: "std-string";
			case StringConcat: "string-concat";
			case StringCompoundLeft: "string-compound-left";
			case StringCompoundRight: "string-compound-right";
			case ReflectFieldName: "reflect-field-name";
		};
	}

	public static function runtimeRequirementId(decisionId:String):String
		return decisionId + ":runtime:" + RUNTIME_CAPABILITY;

	public static function runtimeUseId(decisionId:String, role:String):String
		return decisionId + ":runtime-use:" + role;

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, ownerSource:OcamlLoweredSourceSpan, sourceKind:OcamlStaticStringSourceKind,
			semanticTypeId:String, inputCarrierTypeId:String, order:Int, binding:OcamlFunctionPlanBinding, requirementId:String, role:String):String {
		return "sha256:" + Sha256.encode([
			MODEL_REVISION,
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			ownerSource.file,
			Std.string(ownerSource.min),
			Std.string(ownerSource.max),
			(sourceKind : String),
			semanticTypeId,
			inputCarrierTypeId,
			Std.string(order),
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			requirementId,
			role,
			EXACT_SYMBOL
		].map(value -> value.length + ":" + value).join("|"));
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (_ => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-static-string:duplicate-lookup]: decision "$decisionId" is bound more than once';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-static-string:missing-decision]: typed occurrence "$decisionId" has no decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-static-string:unreachable-decision]: decision "${decision.id}" has no typed occurrence';
	}

	static function bindingFor(decision:OcamlStaticStringDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyDecision(decision:OcamlStaticStringDecision):OcamlStaticStringDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			ownerSource: copySource(decision.ownerSource),
			sourceKind: decision.sourceKind,
			semanticTypeId: decision.semanticTypeId,
			inputCarrierTypeId: decision.inputCarrierTypeId,
			order: decision.order,
			profileEligibility: decision.profileEligibility.copy(),
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: decision.runtimeUseOccurrences.map(copyOccurrence),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: source.ownerId,
			requirementId: source.requirementId,
			domain: source.domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: source.order,
			source: copySource(source.source),
			profileEligibility: source.profileEligibility.copy(),
			cardinality: source.cardinality
		};
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}

#if macro
/** Finds static String conversions before target syntax starts. */
class OcamlStaticStringPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlStaticStringPlan {
		final decisions:Array<OcamlStaticStringDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function add(expression:TypedExpr, owner:TypedExpr, sourceKind:OcamlStaticStringSourceKind):Void {
			if (!selectsStaticStringConversion(expression))
				return;
			if (lookup.exists(expression))
				throw "reflaxe.ocaml [ocaml-static-string:duplicate-source]: one typed expression requested static String conversion more than once";
			final order = decisions.length;
			final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
			final ownerSource = OcamlLoweredOrigin.sourceSpan(owner.pos);
			final semanticTypeId = TypeTools.toString(expression.t);
			final id = "static-string:" + Sha256.encode([
				binding.functionId,
				binding.programRevision,
				binding.bodyRevision,
				binding.pipelineRevision,
				Std.string(order),
				source.file,
				Std.string(source.min),
				Std.string(source.max),
				ownerSource.file,
				Std.string(ownerSource.min),
				Std.string(ownerSource.max),
				(sourceKind : String),
				semanticTypeId
			].join("\u001f")).substr(0, 24);
			final requirementId = OcamlStaticStringPlan.runtimeRequirementId(id);
			final role = OcamlStaticStringPlan.roleFor(sourceKind);
			final revision = OcamlStaticStringPlan.sealRevision(id, source, ownerSource, sourceKind, semanticTypeId, OcamlStaticStringPlan.INPUT_CARRIER_TYPE,
				order, binding, requirementId, role);
			final decision:OcamlStaticStringDecision = {
				id: id,
				revision: revision,
				source: copySource(source),
				ownerSource: copySource(ownerSource),
				sourceKind: sourceKind,
				semanticTypeId: semanticTypeId,
				inputCarrierTypeId: OcamlStaticStringPlan.INPUT_CARRIER_TYPE,
				order: order,
				profileEligibility: ["metal", "portable"],
				runtimeRequirementIds: [requirementId],
				runtimeUseOccurrences: [
					{
						id: OcamlStaticStringPlan.runtimeUseId(id, role),
						planRevision: revision,
						ownerId: id,
						requirementId: requirementId,
						domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
						exactSymbol: OcamlStaticStringPlan.EXACT_SYMBOL,
						role: role,
						order: 0,
						source: copySource(source),
						profileEligibility: ["metal", "portable"],
						cardinality: 1
					}
				],
				proofId: OcamlStaticStringPlan.PROOF_ID,
				proofClaim: OcamlStaticStringPlan.PROOF_CLAIM,
				functionId: binding.functionId,
				programRevision: binding.programRevision,
				bodyRevision: binding.bodyRevision,
				pipelineRevision: binding.pipelineRevision
			};
			OcamlStaticStringPlan.requireDecision(decision);
			decisions.push(decision);
			lookup.set(expression, id);
		}

		function collectConcatParts(expression:TypedExpr, output:Array<TypedExpr>):Void {
			final unwrapped = unwrap(expression);
			switch (unwrapped.expr) {
				case TBinop(OpAdd, left, right) if (isStringType(unwrapped.t) || isStringType(left.t) || isStringType(right.t)):
					collectConcatParts(left, output);
					collectConcatParts(right, output);
				case _:
					output.push(expression);
			}
		}

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TBinop(OpAdd, left, right) if (isStringType(expression.t) || isStringType(left.t) || isStringType(right.t)):
					final parts:Array<TypedExpr> = [];
					collectConcatParts(left, parts);
					collectConcatParts(right, parts);
					for (part in parts) {
						add(part, expression, OcamlStaticStringSourceKind.StringConcat);
						visit(part);
					}
					return;
				case TBinop(OpAssignOp(OpAdd), left, right) if (isStringType(left.t) || isStringType(right.t)):
					add(left, expression, OcamlStaticStringSourceKind.StringCompoundLeft);
					add(right, expression, OcamlStaticStringSourceKind.StringCompoundRight);
					visit(left);
					visit(right);
					return;
				case TCall(functionExpression, arguments):
					switch (unwrap(functionExpression).expr) {
						case TField(_, FStatic(classRef, fieldRef)):
							final classType = classRef.get();
							final field = fieldRef.get();
							if (classType.pack.length == 0 && classType.name == "Std" && field.name == "string" && arguments.length == 1) {
								add(arguments[0], expression, OcamlStaticStringSourceKind.StdString);
							} else if (classType.pack.length == 0
								&& classType.name == "Reflect"
								&& arguments.length >= 2
								&& Lambda.has(["field", "getProperty", "setField", "hasField", "deleteField"], field.name)) {
								add(arguments[1], expression, OcamlStaticStringSourceKind.ReflectFieldName);
							}
						case _:
					}
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}

		visit(root);
		final plan = new OcamlStaticStringPlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
	}

	static function selectsStaticStringConversion(expression:TypedExpr):Bool {
		final unwrapped = unwrap(expression);
		if (!isStringType(unwrapped.t))
			return false;
		return switch (unwrapped.expr) {
			case TConst(TNull) | TConst(TString(_)): false;
			case TBinop(OpAdd, left, right) if (isStringType(unwrapped.t) || isStringType(left.t) || isStringType(right.t)): false;
			case _: true;
		};
	}

	static function isStringType(type:Type):Bool {
		return switch (followNoAbstracts(type)) {
			case TAbstract(abstractRef, [inner]): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Null" && isStringType(inner);
			case TInst(classRef, _): final classType = classRef.get(); classType.pack.length == 0 && classType.name == "String";
			case _: false;
		};
	}

	static function followNoAbstracts(type:Type):Type {
		var current = type;
		while (true) {
			final next = switch (current) {
				case TLazy(resolve): resolve();
				case TMono(reference):
					final inner = reference.get();
					inner == null ? current : inner;
				case TType(typeRef, parameters):
					final definition = typeRef.get();
					TypeTools.applyTypeParameters(definition.type, definition.params, parameters);
				case _: return current;
			};
			if (next == current)
				return current;
			current = next;
		}
	}

	static function unwrap(expression:TypedExpr):TypedExpr {
		var current = expression;
		while (true) {
			switch (current.expr) {
				case TParenthesis(inner) | TMeta(_, inner):
					current = inner;
				case _:
					return current;
			}
		}
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}
#end

#end
