package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
#if macro
import haxe.macro.Context;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The two source forms that can select the native character encoder. */
enum abstract OcamlStringFromCharCodeForm(String) from String to String {
	final DirectCall = "direct-call";
	final FunctionValue = "function-value";
}

/** The argument conversion used by a direct encoder call. */
enum abstract OcamlStringFromCharCodeArgumentCarrier(String) from String to String {
	final ExactInt = "exact-int";
	final NullableInt = "nullable-int";
}

/** One source-bound use of `String.fromCharCode`. */
typedef OcamlStringFromCharCodeDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final form:OcamlStringFromCharCodeForm;
	final argumentCarrier:Null<OcamlStringFromCharCodeArgumentCarrier>;
	final argumentSemanticTypeId:Null<String>;
	final resultSemanticTypeId:String;
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
	Owns the native helper used by `String.fromCharCode` syntax.

	A direct call owns the encoder and, for `Null<Int>`, the null sentinel used by
	the existing null-to-zero conversion. Taking the method as a value owns only
	the encoder identifier. Calling that stored value later remains ordinary
	function-call work.

	The typed-expression lookup is valid only for the current compiler request.
**/
class OcamlStringFromCharCodePlan {
	public static inline final MODEL_REVISION = "typed-ocaml-string-from-char-code-v1";
	public static inline final PROOF_ID = "string-from-char-code-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed expression is the root String.fromCharCode intrinsic. Its call or function-value form and exact argument carrier select every private runtime identifier before target syntax.";
	public static inline final RUNTIME_CAPABILITY = "haxe-string-from-char-code";

	final ordered:Array<OcamlStringFromCharCodeDecision>;
	final byId:Map<String, OcamlStringFromCharCodeDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlStringFromCharCodeDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-string-from-char-code:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Returns the decision for this exact request-local typed expression. */
	public function requireFor(expression:TypedExpr):OcamlStringFromCharCodeDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-string-from-char-code:missing-decision]: String.fromCharCode syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-string-from-char-code:missing-decision]: the typed expression names no sealed decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	/** Returns report-safe decisions in source order. */
	public function decisions():Array<OcamlStringFromCharCodeDecision>
		return ordered.map(copyDecision);

	/** Rejects decisions from another function, body, program, or pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision)
				throw 'reflaxe.ocaml [ocaml-string-from-char-code:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
	}

	/** Rejects changed form, carrier, identity, requirement, or helper facts. */
	public static function requireDecision(decision:OcamlStringFromCharCodeDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.resultSemanticTypeId != "String"
			|| decision.order < 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-string-from-char-code:invalid-plan]: decision has incomplete facts";

		final validShape = switch (decision.form) {
			case DirectCall: (decision.argumentCarrier == ExactInt
					&& decision.argumentSemanticTypeId == "Int") || (decision.argumentCarrier == NullableInt
					&& decision.argumentSemanticTypeId == "Null<Int>");
			case FunctionValue: decision.argumentCarrier == null && decision.argumentSemanticTypeId == null;
			case _:
				false;
		};
		if (!validShape)
			throw 'reflaxe.ocaml [ocaml-string-from-char-code:invalid-form]: decision "${decision.id}" has incompatible form and argument facts';

		final symbols = exactSymbolsFor(decision.form, decision.argumentCarrier);
		final roles = rolesFor(decision.form, decision.argumentCarrier);
		final requirementIds = [decision.id + ":runtime:" + RUNTIME_CAPABILITY];
		final expectedRevision = sealRevision(decision.id, decision.source, decision.form, decision.argumentCarrier, decision.argumentSemanticTypeId,
			decision.resultSemanticTypeId, decision.order, bindingFor(decision), requirementIds, symbols, roles);
		if (decision.revision != expectedRevision
			|| decision.runtimeRequirementIds.join(",") != requirementIds.join(",")
			|| decision.runtimeUseOccurrences.length != symbols.length)
			throw 'reflaxe.ocaml [ocaml-string-from-char-code:invalid-runtime-use]: decision "${decision.id}" has stale or conflicting runtime facts';

		for (index in 0...symbols.length) {
			final occurrence = decision.runtimeUseOccurrences[index];
			if (occurrence.id != decision.id + ":runtime-use:" + roles[index]
				|| occurrence.planRevision != decision.revision
				|| occurrence.ownerId != decision.id
				|| occurrence.requirementId != requirementIds[0]
				|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
				|| occurrence.exactSymbol != symbols[index]
				|| occurrence.role != roles[index]
				|| occurrence.order != index
				|| occurrence.source.file != decision.source.file
				|| occurrence.source.min != decision.source.min
				|| occurrence.source.max != decision.source.max
				|| occurrence.profileEligibility.join(",") != "metal,portable"
				|| occurrence.cardinality != 1)
				throw 'reflaxe.ocaml [ocaml-string-from-char-code:invalid-runtime-use]: decision "${decision.id}" has a conflicting helper at order $index';
		}
	}

	/** Returns the complete private helper sequence in target-tree order. */
	public static function exactSymbolsFor(form:OcamlStringFromCharCodeForm, argumentCarrier:Null<OcamlStringFromCharCodeArgumentCarrier>):Array<String> {
		return form == DirectCall
			&& argumentCarrier == NullableInt ? ["HxString.fromCharCode", "HxRuntime.hx_null"] : ["HxString.fromCharCode"];
	}

	/** Returns stable roles for the selected helper sequence. */
	public static function rolesFor(form:OcamlStringFromCharCodeForm, argumentCarrier:Null<OcamlStringFromCharCodeArgumentCarrier>):Array<String> {
		return form == DirectCall
			&& argumentCarrier == NullableInt ? ["encode-character", "nullable-null-sentinel"] : ["encode-character"];
	}

	/** Returns the direct runtime modules required by the decision. */
	public static function rootModules(decision:OcamlStringFromCharCodeDecision):Array<String> {
		requireDecision(decision);
		final roots:Map<String, Bool> = [];
		for (occurrence in decision.runtimeUseOccurrences) {
			final separator = occurrence.exactSymbol.indexOf(".");
			roots.set(separator < 0 ? occurrence.exactSymbol : occurrence.exactSymbol.substr(0, separator), true);
		}
		final out = [for (root in roots.keys()) root];
		out.sort(Reflect.compare);
		return out;
	}

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, form:OcamlStringFromCharCodeForm,
			argumentCarrier:Null<OcamlStringFromCharCodeArgumentCarrier>, argumentSemanticTypeId:Null<String>, resultSemanticTypeId:String, order:Int,
			binding:OcamlFunctionPlanBinding, requirementIds:Array<String>, symbols:Array<String>, roles:Array<String>):String {
		return "sha256:" + Sha256.encode([
			MODEL_REVISION,
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			(form : String),
			argumentCarrier == null ? "" : (argumentCarrier : String),
			argumentSemanticTypeId ?? "",
			resultSemanticTypeId,
			Std.string(order),
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			requirementIds.join("\u001e"),
			symbols.join("\u001e"),
			roles.join("\u001e")
		].map(value -> value.length + ":" + value).join("|"));
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (_ => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-string-from-char-code:duplicate-lookup]: decision "$decisionId" is bound more than once';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-string-from-char-code:missing-decision]: typed expression "$decisionId" has no decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-string-from-char-code:unreachable-decision]: decision "${decision.id}" has no typed expression';
	}

	static function bindingFor(decision:OcamlStringFromCharCodeDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyDecision(decision:OcamlStringFromCharCodeDecision):OcamlStringFromCharCodeDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			form: decision.form,
			argumentCarrier: decision.argumentCarrier,
			argumentSemanticTypeId: decision.argumentSemanticTypeId,
			resultSemanticTypeId: decision.resultSemanticTypeId,
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
/** Selects exact encoder calls and method values before target syntax. */
class OcamlStringFromCharCodePlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlStringFromCharCodePlan {
		final decisions:Array<OcamlStringFromCharCodeDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function add(expression:TypedExpr, form:OcamlStringFromCharCodeForm, argumentCarrier:Null<OcamlStringFromCharCodeArgumentCarrier>,
				argumentSemanticTypeId:Null<String>):Void {
			final order = decisions.length;
			final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
			final id = "string-from-char-code:" + Sha256.encode([
				binding.functionId,
				binding.programRevision,
				binding.bodyRevision,
				binding.pipelineRevision,
				Std.string(order),
				source.file,
				Std.string(source.min),
				Std.string(source.max),
				(form : String),
				argumentCarrier == null ? "" : (argumentCarrier : String),
				argumentSemanticTypeId ?? ""
			].join("\u001f")).substr(0, 24);
			final symbols = OcamlStringFromCharCodePlan.exactSymbolsFor(form, argumentCarrier);
			final roles = OcamlStringFromCharCodePlan.rolesFor(form, argumentCarrier);
			final requirementIds = [id + ":runtime:" + OcamlStringFromCharCodePlan.RUNTIME_CAPABILITY];
			final revision = OcamlStringFromCharCodePlan.sealRevision(id, source, form, argumentCarrier, argumentSemanticTypeId, "String", order, binding,
				requirementIds, symbols, roles);
			final occurrences:Array<OcamlRuntimeUseOccurrence> = [];
			for (index in 0...symbols.length)
				occurrences.push({
					id: id + ":runtime-use:" + roles[index],
					planRevision: revision,
					ownerId: id,
					requirementId: requirementIds[0],
					domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
					exactSymbol: symbols[index],
					role: roles[index],
					order: index,
					source: copySource(source),
					profileEligibility: ["metal", "portable"],
					cardinality: 1
				});
			final decision:OcamlStringFromCharCodeDecision = {
				id: id,
				revision: revision,
				source: copySource(source),
				form: form,
				argumentCarrier: argumentCarrier,
				argumentSemanticTypeId: argumentSemanticTypeId,
				resultSemanticTypeId: "String",
				order: order,
				profileEligibility: ["metal", "portable"],
				runtimeRequirementIds: requirementIds,
				runtimeUseOccurrences: occurrences,
				proofId: OcamlStringFromCharCodePlan.PROOF_ID,
				proofClaim: OcamlStringFromCharCodePlan.PROOF_CLAIM,
				functionId: binding.functionId,
				programRevision: binding.programRevision,
				bodyRevision: binding.bodyRevision,
				pipelineRevision: binding.pipelineRevision
			};
			decisions.push(decision);
			lookup.set(expression, decision.id);
		}

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TCall(callee, [argument]) if (isWrappedIntrinsic(callee)):
					if (!OcamlRepresentationRegistry.isExactInt(argument.t) || TypeTools.toString(expression.t) != "Void")
						unsupported('stored-method wrapper argument ${TypeTools.toString(argument.t)}', expression.pos);
					add(expression, OcamlStringFromCharCodeForm.FunctionValue, null, null);
					visit(argument);
					return;
				case TCall(callee, [argument]) if (isResolvedIntrinsic(callee)):
					final carrier = if (OcamlRepresentationRegistry.isExactInt(argument.t)) {
						OcamlStringFromCharCodeArgumentCarrier.ExactInt;
					} else if (OcamlRepresentationRegistry.isExactNullInt(argument.t)) {
						OcamlStringFromCharCodeArgumentCarrier.NullableInt;
					} else {
						unsupported(TypeTools.toString(argument.t), expression.pos);
					}
					if (!OcamlRepresentationRegistry.isExactString(expression.t))
						unsupported('result ${TypeTools.toString(expression.t)}', expression.pos);
					add(expression, OcamlStringFromCharCodeForm.DirectCall, carrier, TypeTools.toString(argument.t));
					visit(argument);
					return;
				case _ if (isResolvedIntrinsic(expression)):
					if (!isExactFunctionValueType(expression.t))
						unsupported('function value ${TypeTools.toString(expression.t)}', expression.pos);
					add(expression, OcamlStringFromCharCodeForm.FunctionValue, null, null);
					return;
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}

		visit(root);
		final plan = new OcamlStringFromCharCodePlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
	}

	/** Identifies only the root built-in `String.fromCharCode` field. */
	public static function isResolvedIntrinsic(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TMeta(metadata, inner) if (metadata.name == ":wrappedInLambda"):
				isResolvedIntrinsic(inner);
			case TField({expr: TTypeExpr(TClassDecl(ownerRef))}, FStatic(classRef, fieldRef)):
				final owner = ownerRef.get();
				final fieldOwner = classRef.get();
				final field = fieldRef.get();
				owner.pack.length == 0
				&& owner.name == "String"
				&& owner.module == "String"
				&& fieldOwner.module == owner.module
				&& fieldOwner.name == owner.name
				&& field.name == "fromCharCode";
			case _:
				false;
		};
	}

	/** Reports whether Reflaxe created the marked adapter for a stored method value. */
	public static function isWrappedIntrinsic(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TMeta(metadata, inner) if (metadata.name == ":wrappedInLambda"):
				isResolvedIntrinsic(inner);
			case _:
				false;
		};
	}

	/** Accepts only the public `(Int) -> String` type of the stored method. */
	static function isExactFunctionValueType(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TFun(arguments, result):
				arguments.length == 1
				&& !arguments[0].opt
				&& OcamlRepresentationRegistry.isExactInt(arguments[0].t)
				&& OcamlRepresentationRegistry.isExactString(result);
			case _:
				false;
		};
	}

	static function unsupported(typeDescription:String, position:haxe.macro.Expr.Position):Dynamic {
		Context.error('reflaxe.ocaml [ocaml-string-from-char-code:unsupported-type]: String.fromCharCode requires exact Int or Null<Int> input and String output, received $typeDescription',
			position);
		return null;
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}
#end

#end
