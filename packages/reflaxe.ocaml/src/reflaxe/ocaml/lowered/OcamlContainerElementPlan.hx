package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalCarrierConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlUnsafeOperationKind;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlUnsafeOperationRecord;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** The typed container boundary that owns one element conversion. */
enum abstract OcamlContainerElementRole(String) from String to String {
	/** One source value enters an `Array<Dynamic>` literal slot. */
	final ArrayLiteralDynamicElement = "array-literal-dynamic-element";
}

/**
	Describes how syntax should treat one exact typed array element.

	`Unknown` means the typed expression is not part of the body that was
	planned and must stop compilation. `Excluded` means the planner deliberately
	left the element on the ordinary expression path. `Required` carries the
	stable occurrence identity and its sealed conversion.
**/
enum OcamlContainerElementLookup {
	Unknown;
	Excluded;
	Required(id:String, conversion:Null<OcamlContainerElementDecision>);
}

/** One immutable enum-to-Dynamic conversion selected for an array literal element. */
typedef OcamlContainerElementDecision = {
	final id:String;
	final role:OcamlContainerElementRole;
	final containerSource:OcamlLoweredSourceSpan;
	final source:OcamlLoweredSourceSpan;
	final containerOrdinal:Int;
	final elementIndex:Int;
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final conversion:OcamlLocalCarrierConversion;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final profileEligibility:Array<String>;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
	final unsafeOperation:OcamlUnsafeOperationRecord;
}

/**
	Owns exact carrier conversions for typed container elements in one function.

	The first admitted boundary is deliberately small: a directly written Haxe
	enum constructor entering an `Array<Dynamic>` literal. The plan retains the
	enum identity and the exact source occurrence before OCaml syntax exists.
	Array syntax may then apply the recorded `HxEnum.box_if_needed` operation,
	but it may not infer an enum name from target text or native variant tags.
**/
class OcamlContainerElementPlan {
	final orderedDecisions:Array<OcamlContainerElementDecision>;
	final orderedRequiredConversionIds:Array<String>;
	final decisionsById:Map<String, OcamlContainerElementDecision> = [];
	final requiredConversionById:Map<String, Bool> = [];
	final requiredIdByContainer:ObjectMap<TypedExpr, Array<Null<String>>>;
	final syntaxLookupPrepared:Bool;

	public final count:Int;
	public final requiredConversionCount:Int;
	public final requiredConversionRevision:String;
	public final unsafeOperationCount:Int;
	public final revision:String;

	/**
		Seals both the required occurrence inventory and its conversion decisions.

		`requiredConversionIds` comes from a separate typed-body observation. Its
		presence prevents an accidentally omitted conversion from becoming an
		unrecorded legacy case. Tests that construct a plan directly may omit the
		argument, in which case their supplied decisions define the inventory.
	**/
	public function new(decisions:Array<OcamlContainerElementDecision>, ?requiredConversionIds:Array<String>,
			?requiredIdByContainer:ObjectMap<TypedExpr, Array<Null<String>>>) {
		orderedDecisions = decisions.map(copyDecision);
		orderedDecisions.sort((left, right) -> Reflect.compare(left.id, right.id));
		this.requiredIdByContainer = requiredIdByContainer == null ? new ObjectMap() : requiredIdByContainer;
		syntaxLookupPrepared = requiredIdByContainer != null;
		orderedRequiredConversionIds = requiredConversionIds == null ? orderedDecisions.map(decision -> decision.id) : requiredConversionIds.copy();
		orderedRequiredConversionIds.sort(Reflect.compare);
		for (id in orderedRequiredConversionIds) {
			if (id.length == 0)
				throw "reflaxe.ocaml [ocaml-container-element:invalid-required-conversion]: a required occurrence identity is empty";
			if (requiredConversionById.exists(id))
				throw 'reflaxe.ocaml [ocaml-container-element:duplicate-required-conversion]: occurrence "$id" is required more than once';
			requiredConversionById.set(id, true);
		}
		for (decision in orderedDecisions) {
			requireDecision(decision);
			if (decisionsById.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-container-element:duplicate-conversion]: occurrence "${decision.id}" is sealed more than once';
			if (!requiredConversionById.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-container-element:unexpected-conversion]: occurrence "${decision.id}" has a decision but is not in the independently observed required inventory';
			decisionsById.set(decision.id, decision);
		}
		requireStructuralOrdinalConsistency();
		for (id in orderedRequiredConversionIds) {
			if (!decisionsById.exists(id))
				throw 'reflaxe.ocaml [ocaml-container-element:missing-required-conversion]: required occurrence "$id" has no sealed conversion decision';
		}
		if (syntaxLookupPrepared)
			requireSyntaxLookupCompleteness();
		count = orderedDecisions.length;
		requiredConversionCount = orderedRequiredConversionIds.length;
		requiredConversionRevision = "sha256:" + Sha256.encode(haxe.Json.stringify(orderedRequiredConversionIds));
		unsafeOperationCount = orderedDecisions.length;
		revision = "sha256:" + Sha256.encode([
			"required",
			orderedRequiredConversionIds.join("\n"),
			"decisions",
			orderedDecisions.map(fingerprint).join("\n")
		].join("\n"));
	}

	/**
		Builds the deterministic identity shared by typed planning and syntax.

		`containerOrdinal` is the zero-based pre-order position of the array
		literal in the final typed function body. It distinguishes macro-generated
		arrays even when they share source positions. The source spans remain useful
		provenance, while function, program, body, and pipeline revisions prevent
		reuse after any owning input changes.
	**/
	public static function occurrenceId(binding:OcamlFunctionPlanBinding, role:OcamlContainerElementRole, containerSource:OcamlLoweredSourceSpan,
			source:OcamlLoweredSourceSpan, containerOrdinal:Int, elementIndex:Int):String {
		return "container-element-conversion:" + Sha256.encode([
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			(role : String),
			containerSource.file,
			Std.string(containerSource.min),
			Std.string(containerSource.max),
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			Std.string(containerOrdinal),
			Std.string(elementIndex)
		].join("\n")).substr(0, 32);
	}

	/** Rejects a plan retained from another function body or target pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in orderedDecisions) {
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-container-element:stale-binding]: occurrence "${decision.id}" belongs to ${decision.functionId}/${decision.bodyRevision}/${decision.pipelineRevision}, expected ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
			requireCanonicalIdentity(decision);
		}
	}

	/**
		Resolves one exact request-local array element for syntax generation.

		The object-keyed lookup is deliberately request-local and is never part of
		a cache payload. The returned identity is the stable ordinal-based value
		used by reports and revisions.
	**/
	public function syntaxLookup(container:TypedExpr, elementIndex:Int):OcamlContainerElementLookup {
		if (!syntaxLookupPrepared || !requiredIdByContainer.exists(container))
			return Unknown;
		final entries = requiredIdByContainer.get(container);
		if (entries == null || elementIndex < 0 || elementIndex >= entries.length)
			return Unknown;
		final id = entries[elementIndex];
		if (id == null)
			return Excluded;
		final decision = decisionsById.get(id);
		return Required(id, decision == null ? null : copyDecision(decision));
	}

	/** Returns the independent required occurrence inventory in stable order. */
	public function requiredConversionIds():Array<String> {
		return orderedRequiredConversionIds.copy();
	}

	/** Checks one stable occurrence without copying the decision payload. */
	public function hasDecision(id:String):Bool {
		return decisionsById.exists(id);
	}

	/** Returns defensive copies in deterministic identity order. */
	public function decisions():Array<OcamlContainerElementDecision> {
		return orderedDecisions.map(copyDecision);
	}

	/** Returns the unsafe operations that own the admitted target boxing calls. */
	public function unsafeOperations():Array<OcamlUnsafeOperationRecord> {
		return orderedDecisions.map(decision -> copyUnsafeOperation(decision.unsafeOperation));
	}

	function requireSyntaxLookupCompleteness():Void {
		final lookupIds:Array<String> = [];
		final seen:Map<String, Bool> = [];
		for (container in requiredIdByContainer.keys()) {
			final entries = requiredIdByContainer.get(container);
			if (entries == null)
				throw "reflaxe.ocaml [ocaml-container-element:invalid-syntax-lookup]: a typed array has no element disposition list";
			for (id in entries) {
				if (id == null)
					continue;
				if (seen.exists(id))
					throw 'reflaxe.ocaml [ocaml-container-element:duplicate-syntax-lookup]: required occurrence "$id" is assigned to more than one typed array element';
				seen.set(id, true);
				lookupIds.push(id);
			}
		}
		lookupIds.sort(Reflect.compare);
		if (lookupIds.join("\n") != orderedRequiredConversionIds.join("\n"))
			throw 'reflaxe.ocaml [ocaml-container-element:syntax-lookup-mismatch]: typed array lookup [${lookupIds.join(",")}] does not match required inventory [${orderedRequiredConversionIds.join(",")}]';
	}

	function requireStructuralOrdinalConsistency():Void {
		final containerSourceByOrdinal:Map<Int, String> = [];
		final occupiedSlots:Map<String, Bool> = [];
		for (decision in orderedDecisions) {
			final containerSource = '${decision.containerSource.file}:${decision.containerSource.min}:${decision.containerSource.max}';
			final previousSource = containerSourceByOrdinal.get(decision.containerOrdinal);
			if (previousSource != null && previousSource != containerSource)
				throw 'reflaxe.ocaml [ocaml-container-element:ordinal-source-conflict]: structural array ordinal ${decision.containerOrdinal} names both "$previousSource" and "$containerSource"';
			containerSourceByOrdinal.set(decision.containerOrdinal, containerSource);
			final slot = '${decision.containerOrdinal}:${decision.elementIndex}';
			if (occupiedSlots.exists(slot))
				throw 'reflaxe.ocaml [ocaml-container-element:duplicate-structural-slot]: array element slot "$slot" has more than one conversion';
			occupiedSlots.set(slot, true);
		}
	}

	static function requireDecision(decision:OcamlContainerElementDecision):Void {
		if (decision.role != OcamlContainerElementRole.ArrayLiteralDynamicElement
			|| decision.containerOrdinal < 0
			|| decision.elementIndex < 0
			|| decision.reason.length == 0
			|| decision.proofId.length == 0
			|| decision.proofClaim.length == 0
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-container-element:invalid-conversion]: occurrence "${decision.id}" has incomplete role, index, proof, or revision facts';
		}
		requireSource(decision.containerSource, "container", decision.id);
		requireSource(decision.source, "element", decision.id);
		if (decision.containerSource.file != decision.source.file)
			throw 'reflaxe.ocaml [ocaml-container-element:source-mismatch]: occurrence "${decision.id}" crosses source files';
		if (decision.conversion != OcamlLocalCarrierConversion.BoxExactEnumToDynamic)
			throw 'reflaxe.ocaml [ocaml-container-element:unsupported-conversion]: occurrence "${decision.id}" selects ${decision.conversion}';
		OcamlEnumDynamicCarrier.requireIdentity(decision.inputSemanticTypeId, decision.inputCarrierTypeId);
		if (decision.outputSemanticTypeId != "Dynamic" || decision.outputCarrierTypeId != OcamlEnumDynamicCarrier.DYNAMIC_CARRIER) {
			throw 'reflaxe.ocaml [ocaml-container-element:wrong-output-carrier]: occurrence "${decision.id}" must produce Dynamic/${OcamlEnumDynamicCarrier.DYNAMIC_CARRIER}';
		}
		if (decision.profileEligibility.length == 0)
			throw 'reflaxe.ocaml [ocaml-container-element:missing-profile]: occurrence "${decision.id}" has no eligible profile';
		final seenProfiles:Map<String, Bool> = [];
		for (profile in decision.profileEligibility) {
			if (profile.length == 0 || seenProfiles.exists(profile))
				throw 'reflaxe.ocaml [ocaml-container-element:invalid-profile]: occurrence "${decision.id}" has an empty or duplicate profile';
			seenProfiles.set(profile, true);
		}
		requireCanonicalIdentity(decision);
		requireUnsafeOperation(decision);
	}

	static function requireCanonicalIdentity(decision:OcamlContainerElementDecision):Void {
		final expected = occurrenceId({
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		}, decision.role, decision.containerSource,
			decision.source, decision.containerOrdinal, decision.elementIndex);
		if (decision.id != expected)
			throw 'reflaxe.ocaml [ocaml-container-element:noncanonical-identity]: occurrence "${decision.id}" does not match its retained function, revisions, role, sources, array ordinal, and element index; expected "$expected"';
	}

	static function requireUnsafeOperation(decision:OcamlContainerElementDecision):Void {
		final operation = decision.unsafeOperation;
		final expectedId = decision.id + ":unsafe:" + (OcamlUnsafeOperationKind.BoxExactEnumToDynamic : String);
		if (operation.id != expectedId
			|| operation.conversionId != decision.id
			|| operation.operation != OcamlUnsafeOperationKind.BoxExactEnumToDynamic
			|| !sameSource(operation.source, decision.source)
			|| operation.inputSemanticTypeId != decision.inputSemanticTypeId
			|| operation.inputCarrierTypeId != decision.inputCarrierTypeId
			|| operation.outputSemanticTypeId != decision.outputSemanticTypeId
			|| operation.outputCarrierTypeId != decision.outputCarrierTypeId
			|| operation.reason != decision.reason
			|| operation.proofId != decision.proofId
			|| operation.proofClaim != decision.proofClaim
			|| operation.profileEligibility.join(",") != decision.profileEligibility.join(",")
			|| operation.functionId != decision.functionId
			|| operation.programRevision != decision.programRevision
			|| operation.bodyRevision != decision.bodyRevision
			|| operation.pipelineRevision != decision.pipelineRevision) {
			throw 'reflaxe.ocaml [ocaml-container-element:unsafe-proof-mismatch]: unsafe operation "${operation.id}" does not match occurrence "${decision.id}"';
		}
	}

	static function requireSource(source:OcamlLoweredSourceSpan, label:String, id:String):Void {
		if (source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'reflaxe.ocaml [ocaml-container-element:invalid-source]: $label source for occurrence "$id" is invalid';
	}

	static function sameSource(left:OcamlLoweredSourceSpan, right:OcamlLoweredSourceSpan):Bool {
		return left.file == right.file && left.min == right.min && left.max == right.max;
	}

	static function fingerprint(decision:OcamlContainerElementDecision):String {
		return [
			decision.id,
			(decision.role : String),
			decision.containerSource.file,
			Std.string(decision.containerSource.min),
			Std.string(decision.containerSource.max),
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			Std.string(decision.containerOrdinal),
			Std.string(decision.elementIndex),
			decision.inputSemanticTypeId,
			decision.inputCarrierTypeId,
			decision.outputSemanticTypeId,
			decision.outputCarrierTypeId,
			(decision.conversion : String),
			decision.reason,
			decision.proofId,
			decision.proofClaim,
			decision.profileEligibility.join(","),
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision,
			decision.unsafeOperation.id
		].join("|");
	}

	static function copyDecision(decision:OcamlContainerElementDecision):OcamlContainerElementDecision {
		return {
			id: decision.id,
			role: decision.role,
			containerSource: copySource(decision.containerSource),
			source: copySource(decision.source),
			containerOrdinal: decision.containerOrdinal,
			elementIndex: decision.elementIndex,
			inputSemanticTypeId: decision.inputSemanticTypeId,
			inputCarrierTypeId: decision.inputCarrierTypeId,
			outputSemanticTypeId: decision.outputSemanticTypeId,
			outputCarrierTypeId: decision.outputCarrierTypeId,
			conversion: decision.conversion,
			reason: decision.reason,
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			profileEligibility: decision.profileEligibility.copy(),
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision,
			unsafeOperation: copyUnsafeOperation(decision.unsafeOperation)
		};
	}

	static function copyUnsafeOperation(operation:OcamlUnsafeOperationRecord):OcamlUnsafeOperationRecord {
		return {
			id: operation.id,
			conversionId: operation.conversionId,
			operation: operation.operation,
			source: copySource(operation.source),
			inputSemanticTypeId: operation.inputSemanticTypeId,
			inputCarrierTypeId: operation.inputCarrierTypeId,
			outputSemanticTypeId: operation.outputSemanticTypeId,
			outputCarrierTypeId: operation.outputCarrierTypeId,
			reason: operation.reason,
			proofId: operation.proofId,
			proofClaim: operation.proofClaim,
			profileEligibility: operation.profileEligibility.copy(),
			functionId: operation.functionId,
			programRevision: operation.programRevision,
			bodyRevision: operation.bodyRevision,
			pipelineRevision: operation.pipelineRevision
		};
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {
			file: source.file,
			min: source.min,
			max: source.max
		};
	}
}

/**
	Finds direct enum constructors entering exact `Array<Dynamic>` literals.

	The planner reads the final typed array element type and each exact source
	constructor once. Other arrays and indirect enum expressions remain outside
	this first slice and therefore produce no conversion decision.
**/
class OcamlContainerElementPlanner {
	public static function planExpression(expression:TypedExpr, binding:OcamlFunctionPlanBinding):OcamlContainerElementPlan {
		final decisions:Array<OcamlContainerElementDecision> = [];
		var arrayOrdinal = 0;

		function visit(current:TypedExpr):Void {
			switch (current.expr) {
				case TArrayDecl(items):
					final currentArrayOrdinal = arrayOrdinal++;
					if (isExactDynamicArray(current.t)) {
						final containerSource = OcamlLoweredOrigin.sourceSpan(current.pos);
						for (elementIndex in 0...items.length) {
							final item = items[elementIndex];
							final identity = OcamlEnumDynamicCarrier.fromDirectValue(item);
							if (identity == null)
								continue;
							final source = OcamlLoweredOrigin.sourceSpan(item.pos);
							final role = OcamlContainerElementRole.ArrayLiteralDynamicElement;
							final id = OcamlContainerElementPlan.occurrenceId(binding, role, containerSource, source, currentArrayOrdinal, elementIndex);
							final reason = "One exact Haxe enum constructor enters an Array<Dynamic> literal slot and must retain its enum identity.";
							final proofId = "dynamic-array-element-box-exact-enum-v1";
							final proofClaim = "The typed array element is one directly written ordinary Haxe enum constructor. HxEnum.box_if_needed records its fully qualified enum name before the native OCaml variant enters the Dynamic Obj.t element carrier.";
							final profiles = ["metal", "portable"];
							final unsafeOperation:OcamlUnsafeOperationRecord = {
								id: id + ":unsafe:" + (OcamlUnsafeOperationKind.BoxExactEnumToDynamic : String),
								conversionId: id,
								operation: OcamlUnsafeOperationKind.BoxExactEnumToDynamic,
								source: source,
								inputSemanticTypeId: identity.semanticTypeId,
								inputCarrierTypeId: identity.carrierTypeId,
								outputSemanticTypeId: "Dynamic",
								outputCarrierTypeId: OcamlEnumDynamicCarrier.DYNAMIC_CARRIER,
								reason: reason,
								proofId: proofId,
								proofClaim: proofClaim,
								profileEligibility: profiles,
								functionId: binding.functionId,
								programRevision: binding.programRevision,
								bodyRevision: binding.bodyRevision,
								pipelineRevision: binding.pipelineRevision
							};
							decisions.push({
								id: id,
								role: role,
								containerSource: containerSource,
								source: source,
								containerOrdinal: currentArrayOrdinal,
								elementIndex: elementIndex,
								inputSemanticTypeId: identity.semanticTypeId,
								inputCarrierTypeId: identity.carrierTypeId,
								outputSemanticTypeId: "Dynamic",
								outputCarrierTypeId: OcamlEnumDynamicCarrier.DYNAMIC_CARRIER,
								conversion: OcamlLocalCarrierConversion.BoxExactEnumToDynamic,
								reason: reason,
								proofId: proofId,
								proofClaim: proofClaim,
								profileEligibility: profiles,
								functionId: binding.functionId,
								programRevision: binding.programRevision,
								bodyRevision: binding.bodyRevision,
								pipelineRevision: binding.pipelineRevision,
								unsafeOperation: unsafeOperation
							});
						}
					}
					TypedExprTools.iter(current, visit);
				case _:
					TypedExprTools.iter(current, visit);
			}
		}

		visit(expression);
		final observation = requiredConversionObservation(expression, binding);
		return new OcamlContainerElementPlan(decisions, observation.ids, observation.requiredIdByContainer);
	}

	/**
		Checks a sealed plan against a fresh observation of the final typed body.

		This pass does not trust the decision list or the inventory stored beside
		it. It walks the typed Haxe expression again and requires exact agreement,
		so a planner omission becomes an internal compiler error before syntax.
	**/
	public static function requireCompleteness(expression:TypedExpr, binding:OcamlFunctionPlanBinding, plan:OcamlContainerElementPlan):Void {
		final observation = requiredConversionObservation(expression, binding);
		final observed = observation.ids;
		final sealed = plan.requiredConversionIds();
		if (observed.join("\n") != sealed.join("\n")) {
			throw 'reflaxe.ocaml [ocaml-container-element:required-inventory-mismatch]: fresh typed-body observation found [${observed.join(",")}], but the sealed plan requires [${sealed.join(",")}]';
		}
		for (id in observed) {
			if (!plan.hasDecision(id))
				throw 'reflaxe.ocaml [ocaml-container-element:missing-required-conversion]: required occurrence "$id" has no sealed conversion decision';
		}
		for (container in observation.requiredIdByContainer.keys()) {
			final entries = observation.requiredIdByContainer.get(container);
			if (entries == null)
				throw "reflaxe.ocaml [ocaml-container-element:invalid-required-observation]: a typed array has no element disposition list";
			for (elementIndex in 0...entries.length) {
				final expected = entries[elementIndex];
				switch (plan.syntaxLookup(container, elementIndex)) {
					case Excluded if (expected == null):
					case Required(actual, conversion) if (expected != null && actual == expected && conversion != null):
					case Unknown:
						throw 'reflaxe.ocaml [ocaml-container-element:missing-syntax-lookup]: typed array element $elementIndex has no request-local plan lookup';
					case _:
						throw 'reflaxe.ocaml [ocaml-container-element:syntax-lookup-mismatch]: typed array element $elementIndex does not match required occurrence "$expected"';
				}
			}
		}
	}

	static function requiredConversionObservation(expression:TypedExpr, binding:OcamlFunctionPlanBinding):{
		ids:Array<String>,
		requiredIdByContainer:ObjectMap<TypedExpr, Array<Null<String>>>
	} {
		final ids:Array<String> = [];
		final requiredIdByContainer:ObjectMap<TypedExpr, Array<Null<String>>> = new ObjectMap();
		var arrayOrdinal = 0;

		function visit(current:TypedExpr):Void {
			switch (current.expr) {
				case TArrayDecl(items):
					final currentArrayOrdinal = arrayOrdinal++;
					final requiredIds:Array<Null<String>> = [];
					final exactDynamicArray = isExactDynamicArray(current.t);
					final containerSource = exactDynamicArray ? OcamlLoweredOrigin.sourceSpan(current.pos) : null;
					for (elementIndex in 0...items.length) {
						final item = items[elementIndex];
						final identity = exactDynamicArray ? OcamlEnumDynamicCarrier.fromDirectValue(item) : null;
						if (identity == null || containerSource == null) {
							requiredIds.push(null);
							continue;
						}
						final source = OcamlLoweredOrigin.sourceSpan(item.pos);
						final id = OcamlContainerElementPlan.occurrenceId(binding, OcamlContainerElementRole.ArrayLiteralDynamicElement, containerSource,
							source, currentArrayOrdinal, elementIndex);
						requiredIds.push(id);
						ids.push(id);
					}
					requiredIdByContainer.set(current, requiredIds);
					TypedExprTools.iter(current, visit);
				case _:
					TypedExprTools.iter(current, visit);
			}
		}

		visit(expression);
		ids.sort(Reflect.compare);
		return {
			ids: ids,
			requiredIdByContainer: requiredIdByContainer
		};
	}

	static function isExactDynamicArray(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TInst(classRef, [elementType]):
				final cls = classRef.get();
				(cls.pack ?? []).length == 0 && cls.name == "Array" && OcamlRepresentationRegistry.isExactDynamic(elementType);
			case _:
				false;
		}
	}
}
#end
