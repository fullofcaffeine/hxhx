package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Position;
import haxe.macro.Type;
import haxe.macro.Type.TVar;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import reflaxe.lifecycle.FunctionBodyRevision;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan.OcamlArrayLiteralProducerPlanner;
import reflaxe.ocaml.lowered.OcamlArrayReadPlan;
import reflaxe.ocaml.lowered.OcamlArrayReadPlan.OcamlArrayReadPlanner;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan.OcamlArrayIteratorPlanner;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicEqualityPlanner;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan.OcamlDynamicStringPlanner;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan.OcamlContainerElementPlanner;
import reflaxe.ocaml.lowered.OcamlBytesAccessPlan;
import reflaxe.ocaml.lowered.OcamlBytesAccessPlan.OcamlBytesAccessPlanner;
import reflaxe.ocaml.lowered.OcamlBytesMutationPlan;
import reflaxe.ocaml.lowered.OcamlBytesMutationPlan.OcamlBytesMutationPlanner;
import reflaxe.ocaml.lowered.OcamlBytesProducerPlan;
import reflaxe.ocaml.lowered.OcamlBytesProducerPlan.OcamlBytesProducerPlanner;
import reflaxe.ocaml.lowered.OcamlBytesReadPlan;
import reflaxe.ocaml.lowered.OcamlBytesReadPlan.OcamlBytesReadPlanner;
import reflaxe.ocaml.lowered.OcamlAnonymousStructurePlan;
import reflaxe.ocaml.lowered.OcamlAnonymousStructurePlan.OcamlAnonymousStructurePlanner;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldPlanner;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPlanner;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionStatus;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.OcamlNestedFunctionIdentity;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.OcamlSealedNestedFunctionPlan;
import reflaxe.ocaml.lowered.OcamlFunctionResultBoundary;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalCarrierConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlanner;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlanner;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan.OcamlIMapInterfacePlanner;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceOperation;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectComparePlanner;

private typedef OcamlPlaceRuntimeFacts = {
	final decisionId:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final requirementIds:Array<String>;
}

/**
	Builds every admitted lowered plan from the final preprocessed function body.

	This is the last source-semantic step for admitted place operations and local
	storage. It plans both from the same body revision, rejects an admitted
	operation that lost early protection, and seals one function record before
	syntax construction begins.
**/
class OcamlFunctionPlanSealer {
	final context:CompilationContext;
	final registry:OcamlFunctionPlanRegistry;
	final representations:OcamlRepresentationRegistry;
	final staticStorage:OcamlStaticStoragePlan;

	public function new(context:CompilationContext, registry:OcamlFunctionPlanRegistry, representations:OcamlRepresentationRegistry,
			staticStorage:OcamlStaticStoragePlan) {
		this.context = context;
		this.registry = registry;
		this.representations = representations;
		this.staticStorage = staticStorage;
	}

	static function fail(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-lowering:plan-seal]: " + message;
		#if macro
		haxe.macro.Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	static function runtimeFacts(operation:OcamlLoweredPlaceOperation):OcamlPlaceRuntimeFacts {
		return switch (operation) {
			case Simple(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case StaticSimple(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case ArraySimple(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case Compound(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case StaticCompound(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case ArrayCompound(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case Update(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case StaticUpdate(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case ArrayUpdate(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
		}
	}

	static function factsFromPlan(decisionId:String, originId:String, source:OcamlLoweredSourceSpan, semanticTypeId:String,
			requirementIds:Array<String>):OcamlPlaceRuntimeFacts {
		return {
			decisionId: decisionId,
			originId: originId,
			source: source,
			semanticTypeId: semanticTypeId,
			requirementIds: requirementIds
		};
	}

	/** Plans, validates, and seals one exact function-body revision. */
	public function seal(data:ClassFuncData):Void {
		final binding = registry.planningBindingFor(data);
		final externalLocals = data.tfunc == null ? [] : data.tfunc.args.map(argument -> argument.v);
		final localIdentities = LexicalLocalIdentityPlan.build(binding.functionId, data.expr, externalLocals);
		registry.registerRootIdentityPlan(binding, localIdentities);
		final callPlanner = new OcamlCallPlanner(representations, binding);
		final callableBoundary = callPlanner.boundaryFor(data);
		final constructionBoundary = callPlanner.constructionBoundaryFor(data);
		final functionResultType = switch (TypeTools.follow(data.field.type)) {
			case TFun(_, result): result;
			case _: null;
		};
		if (data.expr == null) {
			final anonymousStructures = new OcamlAnonymousStructurePlan([], []);
			final functionResultBoundary = OcamlFunctionResultBoundary.select(data, callableBoundary, representations, binding, anonymousStructures);
			final controls = OcamlControlPlan.notAdmitted(binding);
			final imapInterfaces = new OcamlIMapInterfacePlan(binding, new haxe.ds.ObjectMap(), new haxe.ds.ObjectMap());
			registry.sealFunction(binding, localIdentities, OcamlLocalStoragePlanner.planExpressions([], localIdentities),
				new OcamlLocalRepresentationPlan([]), new OcamlContainerElementPlan([]), new OcamlBytesAccessPlan([]), new OcamlBytesMutationPlan([]),
				new OcamlBytesProducerPlan([]), new OcamlBytesReadPlan([]), imapInterfaces, new OcamlCallPlan([]), controls, callableBoundary,
				functionResultBoundary, constructionBoundary, anonymousStructures, new OcamlStructuralFieldPlan([]), new OcamlArrayLiteralProducerPlan([]),
				new OcamlReflectComparePlan([]));
			return;
		}
		final localStorage = OcamlLocalStoragePlanner.planExpression(data.expr, localIdentities);
		final preliminaryCalls = callPlanner.plan(data.expr);
		final localRepresentations = OcamlLocalRepresentationPlanner.planExpression(data.expr, localIdentities, localStorage, representations, binding,
			preliminaryCalls.preservesNullableBoolArgument, preliminaryCalls.producesNullableBool, preliminaryCalls.producesExactString);
		localRepresentations.requirePlanBinding(binding);
		final containerElements = OcamlContainerElementPlanner.planExpression(data.expr, binding);
		containerElements.requirePlanBinding(binding);
		OcamlContainerElementPlanner.requireCompleteness(data.expr, binding, containerElements);
		final arrayLiteralProducers = new OcamlArrayLiteralProducerPlanner(binding, representations).plan(data.expr);
		arrayLiteralProducers.requirePlanBinding(binding);
		arrayLiteralProducers.requireRepresentations(representations);
		for (decision in arrayLiteralProducers.decisions())
			context.recordArrayLiteralRuntimeRequirements(decision);
		final arrayReads = new OcamlArrayReadPlanner(binding).plan(data.expr);
		arrayReads.requirePlanBinding(binding);
		for (decision in arrayReads.decisions())
			context.recordArrayReadRuntimeRequirements(decision);
		for (decision in arrayReads.dynamicDecisions())
			context.recordDynamicBracketReadRuntimeRequirements(decision);
		final arrayIterators = new OcamlArrayIteratorPlanner(binding).plan(data.expr);
		arrayIterators.requirePlanBinding(binding);
		for (decision in arrayIterators.decisions())
			context.recordArrayIteratorRuntimeRequirements(decision);
		final dynamicEquality = new OcamlDynamicEqualityPlanner(binding).plan(data.expr);
		dynamicEquality.requirePlanBinding(binding);
		for (decision in dynamicEquality.decisions())
			context.recordDynamicEqualityRuntimeRequirement(decision);
		final dynamicString = new OcamlDynamicStringPlanner(binding).plan(data.expr);
		dynamicString.requirePlanBinding(binding);
		for (decision in dynamicString.decisions())
			context.recordDynamicStringRuntimeRequirement(decision);
		final imapInterfaces = new OcamlIMapInterfacePlanner(context, binding, staticStorage, localIdentities).plan(data.expr, functionResultType);
		for (conversion in imapInterfaces.conversions())
			context.recordIMapInterfaceRuntimeRequirements(conversion);
		for (alias in imapInterfaces.storageAliases())
			context.recordIMapStorageAliasRuntimeRequirements(alias);
		final calls = new OcamlCallPlanner(representations, binding, localRepresentations, localIdentities).plan(data.expr);
		final reflectCompare = new OcamlReflectComparePlanner(binding).plan(data.expr);
		for (decision in reflectCompare.decisions())
			context.recordReflectCompareRuntimeRequirements(decision);
		final anonymousStructures = new OcamlAnonymousStructurePlanner(binding, representations).plan(data.expr);
		var functionResultBoundary = OcamlFunctionResultBoundary.select(data, callableBoundary, representations, binding, anonymousStructures);
		final structuralFields = new OcamlStructuralFieldPlanner(binding, calls, imapInterfaces, anonymousStructures, representations,
			localIdentities).plan(data.expr);
		final bytesAccesses = new OcamlBytesAccessPlanner(binding, representations).plan(data.expr);
		final bytesMutations = new OcamlBytesMutationPlanner(binding, representations).plan(data.expr);
		final bytesProducers = new OcamlBytesProducerPlanner(binding, representations).plan(data.expr);
		final bytesReads = new OcamlBytesReadPlanner(binding, representations).plan(data.expr);
		final controls = new OcamlControlPlanner(representations, localRepresentations, binding, localIdentities,
			arrayLiteralProducers).plan(data.expr, functionResultBoundary);
		requireCompleteCatchCoverage(controls, data.expr.pos);
		for (chain in controls.catchChains())
			context.recordCatchChainRuntimeRequirements(chain);
		for (target in controls.loopTargets()) {
			final transfers = controls.decisionsForTarget(target.id);
			if (transfers.length > 0)
				context.recordLoopRuntimeRequirements(target, transfers);
		}
		for (decision in controls.decisions())
			if (decision.kind == OcamlControlTransferKind.Return)
				context.recordReturnRuntimeRequirement(decision);
		functionResultBoundary = OcamlFunctionResultBoundary.retainAfterControlPlanning(functionResultBoundary,
			Lambda.exists(controls.decisions(), decision -> decision.kind == OcamlControlTransferKind.Return));
		sealNestedFunctions(data.expr, binding, localIdentities, localRepresentations);

		final moduleId = data.classType.module;
		final typeName = data.classType.name;
		final planner = new OcamlPlaceAssignmentPlanner(context, moduleId, typeName, representations, localRepresentations, localIdentities, staticStorage,
			binding);
		final seen:Map<String, Bool> = [];
		final markerOriginIds:Array<String> = [];

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TMeta(metadata, child) if (metadata.name == OcamlLoweredOrigin.PLACE_META):
					final originId = OcamlLoweredOrigin.readPlaceId(metadata);
					if (originId == null)
						fail("a final place marker has no valid stable identity", expression.pos);
					if (seen.exists(originId))
						fail('place origin "$originId" occurs more than once in function "${data.id}"', expression.pos);
					seen.set(originId, true);
					final operation = planner.plan(metadata, child);
					if (operation == null)
						fail('place origin "$originId" no longer wraps an operation admitted by the final typed planner', child.pos);
					final errors = OcamlPlaceAssignmentValidator.validate(operation);
					if (errors.length > 0)
						fail(errors.join("; ") + ' (origin "$originId")', child.pos);
					validateRepresentationReferences(operation, binding.programRevision, child.pos);
					final runtime = runtimeFacts(operation);
					context.recordPlaceRuntimeRequirements(runtime.decisionId, runtime.originId, runtime.source, runtime.semanticTypeId,
						runtime.requirementIds);
					registry.register(binding, operation);
					markerOriginIds.push(originId);
					// The wrapper owns this operation. Continue with its children so a
					// nested origin receives its own independently sealed plan.
					TypedExprTools.iter(child, visit);
				case _:
					if (OcamlPlaceInputPolicy.admitsExpression(expression, moduleId, typeName, staticStorage)) {
						fail("an admitted assignment or update reached final planning without its early protection marker", expression.pos);
					}
					TypedExprTools.iter(expression, visit);
			}
		}

		visit(data.expr);
		validateLocalRepresentationReferences(localStorage, localRepresentations, binding.programRevision, data.expr.pos);
		for (conversion in localRepresentations.conversions()) {
			if (conversion.conversion == OcamlLocalCarrierConversion.BoxExactEnumToDynamic)
				context.recordEnumDynamicLocalRuntimeRequirement(conversion);
		}
		for (conversion in containerElements.decisions())
			context.recordEnumDynamicContainerRuntimeRequirement(conversion);
		validateCallRepresentationReferences(calls, callableBoundary, constructionBoundary, binding.programRevision, data.expr.pos);
		for (call in calls.decisions()) {
			final runtimeUsePlan = calls.runtimeUsePlanFor(call.id);
			if (runtimeUsePlan != null)
				context.recordCallRuntimeRequirements(call, runtimeUsePlan);
			if (call.standardIMapTarget != null)
				context.recordStandardIMapRuntimeRequirements(call);
			if (call.structuralIteratorTarget != null)
				context.recordStructuralIteratorRuntimeRequirements(call);
		}
		validateControlRepresentationReferences(controls, binding.programRevision, data.expr.pos);
		for (control in controls.decisions()) {
			final payload = control.payload;
			if (payload != null && OcamlControlPlan.isAdmittedEnumThrowPayload(payload))
				context.recordEnumThrowRuntimeRequirement(control);
		}
		anonymousStructures.requirePlanBinding(binding);
		anonymousStructures.requireRepresentations(representations);
		validateFunctionResultRepresentationReferences(functionResultBoundary, anonymousStructures, binding.programRevision, data.expr.pos);
		for (decision in anonymousStructures.operations())
			context.recordAnonymousStructureRuntimeRequirement(decision);
		for (decision in structuralFields.decisions())
			context.recordStructuralFieldRuntimeRequirement(decision);
		bytesAccesses.requireRepresentations(representations);
		for (decision in bytesAccesses.decisions())
			context.recordBytesAccessRuntimeRequirements(decision);
		bytesMutations.requireRepresentations(representations);
		for (decision in bytesMutations.decisions())
			context.recordBytesMutationRuntimeRequirements(decision);
		bytesProducers.requireRepresentations(representations);
		for (decision in bytesProducers.decisions())
			context.recordBytesProducerRuntimeRequirements(decision);
		bytesReads.requireRepresentations(representations);
		for (decision in bytesReads.decisions())
			context.recordBytesReadRuntimeRequirements(decision);
		registry.sealFunction(binding, localIdentities, localStorage, localRepresentations, containerElements, bytesAccesses, bytesMutations, bytesProducers,
			bytesReads, imapInterfaces, calls, controls, callableBoundary, functionResultBoundary, constructionBoundary, anonymousStructures,
			structuralFields, arrayLiteralProducers, reflectCompare, arrayReads, arrayIterators, dynamicEquality, dynamicString);
		final finalError = registry.validateBinding(binding, markerOriginIds);
		if (finalError != null)
			fail(finalError, data.expr.pos);
	}

	/**
		Seals completely represented nested control using the generic function occurrence.

		A function occurrence is the literal's deterministic structural position in
		the enclosing typed body. Generic Reflaxe records it during the same traversal
		that names lexical locals, so zero-argument and argument-taking functions share
		one identity model. The typed expression remains only a request-local lookup
		key; target plans retain the stable identity and never retain another host
		object for cross-request reuse. A nested function gets a complete behavior
		plan only when the planner represented every return, loop transfer, and throw.
		A blocked non-empty catch is never deferred: sealing fails before syntax so a
		nested function cannot reintroduce the removed catch compiler.
	**/
	function sealNestedFunctions(body:TypedExpr, parentBinding:OcamlFunctionPlanBinding, localIdentities:LexicalLocalIdentityPlan,
			localRepresentations:OcamlLocalRepresentationPlan):Void {
		function visit(expression:TypedExpr, lexicalParentBinding:OcamlFunctionPlanBinding):Void {
			switch (expression.expr) {
				case TFunction(tfunc):
					final bodyExternalLocals = nestedBodyExternalLocals(tfunc, localIdentities);
					final observedBodyRevision = FunctionBodyRevision.initial(tfunc.expr, bodyExternalLocals).id;
					final occurrence = try {
						localIdentities.requireFunctionOccurrence(expression);
					} catch (error:Dynamic) {
						fail(Std.string(error), expression.pos);
					}
					if (occurrence.ownerId != localIdentities.ownerId
						|| !LexicalLocalIdentityPlan.isReusableFunctionOccurrenceId(occurrence.id)) {
						fail("the generic function occurrence is malformed or belongs to another lexical plan", expression.pos);
					}
					final occurrenceId = occurrence.id;
					final nestedFunctionId = OcamlFunctionPlanRegistry.nestedFunctionId(lexicalParentBinding.functionId, occurrenceId);
					final nestedBinding:OcamlFunctionPlanBinding = {
						functionId: nestedFunctionId,
						programRevision: lexicalParentBinding.programRevision,
						bodyRevision: observedBodyRevision,
						pipelineRevision: OcamlFunctionPlanRegistry.NESTED_FUNCTION_PIPELINE_REVISION
					};
					final nestedIdentity:OcamlNestedFunctionIdentity = {
						occurrenceId: occurrenceId,
						parentBinding: lexicalParentBinding,
						binding: nestedBinding
					};
					final nestedResultType:Type = switch (TypeTools.follow(tfunc.t)) {
						case TFun(_, result): result;
						case result: result;
					};
					// IMap conversion and dispatch are independent of whether the nested
					// function's return/control behavior has moved to its typed plan. Plan
					// this exact body now so syntax never reuses the enclosing function's
					// conversions or guesses an adapter from a type name.
					final imapInterfaces = new OcamlIMapInterfacePlanner(context, nestedBinding, staticStorage,
						localIdentities).plan(tfunc.expr, nestedResultType);
					imapInterfaces.requirePlanBinding(nestedBinding);
					for (conversion in imapInterfaces.conversions())
						context.recordIMapInterfaceRuntimeRequirements(conversion);
					for (alias in imapInterfaces.storageAliases())
						context.recordIMapStorageAliasRuntimeRequirements(alias);
					// Array reads belong to the nested body even when its return and catch
					// behavior still uses the older path. Seal them independently so a simple
					// iterator closure cannot inherit its parent's decisions or reach syntax
					// without an exact HxArray.get owner.
					final arrayReads = new OcamlArrayReadPlanner(nestedBinding).plan(tfunc.expr);
					arrayReads.requirePlanBinding(nestedBinding);
					for (decision in arrayReads.decisions())
						context.recordArrayReadRuntimeRequirements(decision);
					for (decision in arrayReads.dynamicDecisions())
						context.recordDynamicBracketReadRuntimeRequirements(decision);
					final arrayIterators = new OcamlArrayIteratorPlanner(nestedBinding).plan(tfunc.expr);
					arrayIterators.requirePlanBinding(nestedBinding);
					for (decision in arrayIterators.decisions())
						context.recordArrayIteratorRuntimeRequirements(decision);
					final dynamicEquality = new OcamlDynamicEqualityPlanner(nestedBinding).plan(tfunc.expr);
					dynamicEquality.requirePlanBinding(nestedBinding);
					for (decision in dynamicEquality.decisions())
						context.recordDynamicEqualityRuntimeRequirement(decision);
					final dynamicString = new OcamlDynamicStringPlanner(nestedBinding).plan(tfunc.expr);
					dynamicString.requirePlanBinding(nestedBinding);
					for (decision in dynamicString.decisions())
						context.recordDynamicStringRuntimeRequirement(decision);
					// Every nested body becomes the parent of its own children, even when
					// this function still uses the older result or control syntax. The
					// optional behavior plan does not own the lexical parent relationship.
					final childParentBinding = nestedBinding;
					final boundary = new OcamlCallPlanner(representations, nestedBinding).boundaryForNestedRepresentedResult(tfunc);
					if (boundary == null) {
						registry.deferNestedFunction(expression, nestedIdentity, bodyExternalLocals, observedBodyRevision, localIdentities, imapInterfaces,
							arrayReads, arrayIterators, dynamicEquality,
							"The typed function literal is outside the existing represented-result callable boundary.", dynamicString);
					} else {
						final functionResultBoundary = OcamlFunctionResultBoundary.fromCallable(boundary);
						// A nested function can read a local declared by its enclosing function.
						// Reuse the enclosing function's sealed representation choices so an exact
						// captured value, such as a monomorphic class record, crosses an early
						// return with the same carrier. The nested planner still sees only locals
						// present in its typed body and validates every selected representation
						// against the current complete-program revision.
						final arrayLiteralProducers = new OcamlArrayLiteralProducerPlanner(nestedBinding, representations).plan(tfunc.expr);
						arrayLiteralProducers.requirePlanBinding(nestedBinding);
						arrayLiteralProducers.requireRepresentations(representations);
						final controls = new OcamlControlPlanner(representations, localRepresentations, nestedBinding, localIdentities,
							arrayLiteralProducers).plan(tfunc.expr, functionResultBoundary);
						requireCompleteCatchCoverage(controls, expression.pos);
						// An unsupported transfer or catch is omitted from the admitted lists.
						// Compare both the family flags and the observed catch count so one valid
						// return cannot make a partly represented closure look complete.
						final allControlFamiliesAdmitted = controls.returnFamilyAdmitted && controls.loopFamilyAdmitted && controls.throwFamilyAdmitted;
						final allCatchOccurrencesAdmitted = controls.catchChains().length == controls.catchOccurrenceCount();
						if (!allControlFamiliesAdmitted || !allCatchOccurrencesAdmitted || !controls.hasReturnTransfers()) {
							registry.deferNestedFunction(expression, nestedIdentity, bodyExternalLocals, observedBodyRevision, localIdentities,
								imapInterfaces, arrayReads, arrayIterators, dynamicEquality,
								"The typed function literal has a represented result, but at least one return, loop, throw, or catch occurrence is not represented by its nested control plan.",
								dynamicString);
						} else {
							validateBoundaryRepresentationReferences(boundary, lexicalParentBinding.programRevision, expression.pos);
							validateControlRepresentationReferences(controls, lexicalParentBinding.programRevision, expression.pos);
							final plan:OcamlSealedNestedFunctionPlan = {
								occurrenceId: occurrenceId,
								parentBinding: lexicalParentBinding,
								binding: nestedBinding,
								callableBoundary: boundary,
								functionResultBoundary: functionResultBoundary,
								controls: controls,
								arrayLiteralProducers: arrayLiteralProducers,
								arrayReads: arrayReads,
								arrayIterators: arrayIterators,
								dynamicEquality: dynamicEquality,
								dynamicString: dynamicString,
								imapInterfaces: imapInterfaces
							};
							for (decision in arrayLiteralProducers.decisions())
								context.recordArrayLiteralRuntimeRequirements(decision);
							for (chain in controls.catchChains())
								context.recordCatchChainRuntimeRequirements(chain);
							for (target in controls.loopTargets()) {
								final transfers = controls.decisionsForTarget(target.id);
								if (transfers.length > 0)
									context.recordLoopRuntimeRequirements(target, transfers);
							}
							for (decision in controls.decisions())
								if (decision.kind == OcamlControlTransferKind.Return)
									context.recordReturnRuntimeRequirement(decision);
							registry.sealNestedFunction(expression, bodyExternalLocals, observedBodyRevision, plan, localIdentities);
						}
					}
					TypedExprTools.iter(tfunc.expr, child -> visit(child, childParentBinding));
				case _:
					TypedExprTools.iter(expression, child -> visit(child, lexicalParentBinding));
			}
		}
		visit(body, parentBinding);
	}

	/**
		Returns the parameters and captured outer locals needed to fingerprint one
		nested body without using process-local Haxe variable numbers.

		The function's own parameters come first in signature order. Captures then
		use the enclosing lexical plan's stable source path, so compiling unrelated
		code first cannot change the body revision. Locals declared inside this
		function or a deeper literal are not captures.
	**/
	static function nestedBodyExternalLocals(tfunc:haxe.macro.Type.TFunc, localIdentities:LexicalLocalIdentityPlan):Array<TVar> {
		final declared:Map<Int, Bool> = [];
		final referenced:Map<Int, TVar> = [];
		for (argument in tfunc.args)
			declared.set(argument.v.id, true);
		function collect(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TLocal(local):
					referenced.set(local.id, local);
				case TVar(local, _):
					declared.set(local.id, true);
				case TFunction(nested):
					for (argument in nested.args)
						declared.set(argument.v.id, true);
				case TFor(local, _, _):
					declared.set(local.id, true);
				case TTry(_, catches):
					for (caught in catches)
						declared.set(caught.v.id, true);
				case _:
			}
			TypedExprTools.iter(expression, collect);
		}
		collect(tfunc.expr);
		final captures:Array<TVar> = [];
		for (hostId => local in referenced)
			if (!declared.exists(hostId))
				captures.push(local);
		captures.sort((left, right) -> Reflect.compare(localIdentities.require(left).path, localIdentities.require(right).path));
		return tfunc.args.map(argument -> argument.v).concat(captures);
	}

	/**
		Rejects a non-empty source catch before OCaml syntax when no sealed chain exists.

		A sealed chain fixes source order, runtime tags, payload recovery, private
		control propagation, and unmatched rethrow behavior. Letting syntax rebuild
		any of those decisions would restore the duplicate catch compiler removed by
		the hard cut. An empty typed `try` has no source clause and needs no chain.
	**/
	static function requireCompleteCatchCoverage(controls:OcamlControlPlan, position:Position):Void {
		final admission = controls.admission;
		if (admission == null)
			fail("the control plan has no complete admission snapshot", position);
		for (catchAdmission in admission.catches) {
			if (catchAdmission.status != OcamlControlAdmissionStatus.Blocked)
				continue;
			final onlyEmpty = catchAdmission.blockers.length == 1 && catchAdmission.blockers[0].code == "catch-chain-empty";
			if (!onlyEmpty) {
				final blocker = catchAdmission.blockers.length == 0 ? "no blocker was recorded" : catchAdmission.blockers[0].message;
				fail('non-empty catch "${catchAdmission.occurrenceId}" reached the hard-cut boundary without a sealed chain: $blocker', position);
			}
		}
	}

	function validateControlRepresentationReferences(controls:OcamlControlPlan, programRevision:String, position:Position):Void {
		for (control in controls.decisions()) {
			final payload = control.payload;
			if (payload == null)
				continue;
			if (payload.inputSemanticTypeId == "Dynamic") {
				final validDynamic = switch (control.kind) {
					case Return: OcamlControlPlan.isAdmittedDynamicReturnPayload(payload);
					case Throw: OcamlControlPlan.isAdmittedDynamicThrowPayload(payload);
					case _: false;
				}
				if (!validDynamic) {
					fail('control "${control.id}" has an invalid Dynamic carrier for ${control.kind}', position);
				}
				continue;
			}
			if (OcamlControlPlan.isAdmittedHaxeExceptionThrowPayload(payload))
				continue;
			if (OcamlControlPlan.isAdmittedEnumThrowPayload(payload))
				continue;
			if (OcamlControlPlan.isAdmittedRuntimeClassThrowPayload(payload))
				continue;
			validateCallValueSide(payload.inputRepresentationId, payload.inputSemanticTypeId, payload.inputCarrierTypeId, programRevision,
				'control "${control.id}" input', position);
			validateCallValueSide(payload.outputRepresentationId, payload.outputSemanticTypeId, payload.outputCarrierTypeId, programRevision,
				'control "${control.id}" output', position);
			final nominal = payload.nominalRepresentation;
			if (nominal == null)
				continue;
			final representation = try {
				representations.require(payload.inputRepresentationId, programRevision);
			} catch (error:Dynamic) {
				fail(Std.string(error), position);
			}
			if (representation.nominalTargetModuleName != nominal.targetModuleName
				|| representation.nominalTargetTypeName != nominal.targetTypeName
				|| representation.nominalLayoutRevision != nominal.layoutRevision
				|| representation.proof.id != nominal.representationProofId) {
				fail('control "${control.id}" does not match its sealed nominal representation proof', position);
			}
		}
		for (chain in controls.catchChains()) {
			for (clause in chain.clauses) {
				if (clause.semanticTypeId == "Dynamic"
					|| OcamlControlPlan.isAdmittedHaxeExceptionCatchClause(clause)
					|| OcamlControlPlan.isAdmittedEnumCatchClause(clause)
					|| OcamlControlPlan.isAdmittedRuntimeClassCatchClause(clause))
					continue;
				validateCallValueSide(clause.outputRepresentationId, clause.semanticTypeId, clause.outputCarrierTypeId, programRevision,
					'control catch clause "${clause.id}" output', position);
				final nominal = clause.nominalRepresentation;
				if (nominal == null)
					continue;
				final representation = try {
					representations.require(clause.outputRepresentationId, programRevision);
				} catch (error:Dynamic) {
					fail(Std.string(error), position);
				}
				if (representation.nominalTargetModuleName != nominal.targetModuleName
					|| representation.nominalTargetTypeName != nominal.targetTypeName
					|| representation.nominalLayoutRevision != nominal.layoutRevision
					|| representation.proof.id != nominal.representationProofId) {
					fail('control catch clause "${clause.id}" does not match its sealed nominal representation proof', position);
				}
			}
		}
	}

	function validateCallRepresentationReferences(calls:OcamlCallPlan, callableBoundary:Null<OcamlCallableBoundaryPlan>,
			constructionBoundary:Null<OcamlCallableBoundaryPlan>, programRevision:String, position:Position):Void {
		for (call in calls.decisions()) {
			if (call.receiver != null)
				validateCallValue(call.receiver, programRevision, 'call "${call.id}" receiver', position);
			for (index in 0...call.arguments.length)
				validateCallValue(call.arguments[index], programRevision, 'call "${call.id}" argument $index', position);
			if (call.result != null)
				validateCallValue(call.result, programRevision, 'call "${call.id}" result', position);
		}
		if (callableBoundary != null) {
			validateBoundaryRepresentationReferences(callableBoundary, programRevision, position);
		}
		if (constructionBoundary != null)
			validateBoundaryRepresentationReferences(constructionBoundary, programRevision, position);
	}

	function validateBoundaryRepresentationReferences(boundary:OcamlCallableBoundaryPlan, programRevision:String, position:Position):Void {
		if (boundary.receiver != null)
			validateCallValue(boundary.receiver, programRevision, 'callable boundary "${boundary.id}" receiver', position);
		for (index in 0...boundary.arguments.length)
			validateCallValue(boundary.arguments[index], programRevision, 'callable boundary "${boundary.id}" argument $index', position);
		if (boundary.result != null)
			validateCallValue(boundary.result, programRevision, 'callable boundary "${boundary.id}" result', position);
	}

	/** Rechecks a result-only carrier and its exact anonymous-structure owner before sealing. */
	function validateFunctionResultRepresentationReferences(boundary:Null<OcamlFunctionResultBoundaryPlan>, anonymousStructures:OcamlAnonymousStructurePlan,
			programRevision:String, position:Position):Void {
		if (boundary == null)
			return;
		try {
			OcamlFunctionResultBoundary.require(boundary);
		} catch (error:Dynamic) {
			fail(Std.string(error), position);
		}
		if (boundary.result != null)
			validateCallValue(boundary.result, programRevision, 'function result boundary "${boundary.id}"', position);
		final proof = boundary.anonymousStructure;
		if (proof == null)
			return;
		final structure = Lambda.find(anonymousStructures.structures(), candidate -> candidate.id == proof.structureId);
		if (structure == null
			|| structure.semanticTypeId != proof.semanticTypeId
			|| structure.revision != proof.structureRevision
			|| structure.proofId != proof.structureProofId
			|| structure.representationId != proof.representationId
			|| structure.representationRevision != proof.representationRevision
			|| structure.programRevision != programRevision) {
			fail('function result boundary "${boundary.id}" does not match its sealed anonymous-object structure and representation revisions', position);
		}
	}

	function validateCallValue(value:OcamlCallValuePlan, programRevision:String, owner:String, position:Position):Void {
		validateCallValueSide(value.inputRepresentationId, value.inputSemanticTypeId, value.inputCarrierTypeId, programRevision, owner + " input", position);
		validateCallValueSide(value.outputRepresentationId, value.outputSemanticTypeId, value.outputCarrierTypeId, programRevision, owner + " output",
			position);
	}

	function validateCallValueSide(representationId:String, semanticTypeId:String, carrierTypeId:String, programRevision:String, owner:String,
			position:Position):Void {
		final decision = try {
			representations.require(representationId, programRevision);
		} catch (error:Dynamic) {
			fail(Std.string(error), position);
		}
		if (decision.semanticTypeId != semanticTypeId
			|| decision.carrierTypeId != carrierTypeId
			|| decision.domain != OcamlRepresentationDomain.InternalValue) {
			fail('$owner expects $semanticTypeId -> $carrierTypeId in ${OcamlRepresentationDomain.InternalValue}, but ${decision.id} selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} in ${decision.domain}',
				position);
		}
	}

	function validateLocalRepresentationReferences(storage:OcamlLocalStoragePlan, plan:OcamlLocalRepresentationPlan, programRevision:String,
			position:Position):Void {
		for (reference in plan.references()) {
			final decision = try {
				representations.require(reference.representationId, programRevision);
			} catch (error:Dynamic) {
				fail(Std.string(error), position);
			}
			if (decision.semanticTypeId != reference.semanticTypeId || decision.domain != reference.domain) {
				fail('local ${reference.localId} expects ${reference.semanticTypeId} in representation domain ${reference.domain}, but ${decision.id} selects ${decision.semanticTypeId} in ${decision.domain}',
					position);
			}
			if (OcamlMonomorphicClassMaterializer.isNominalClass(decision)) {
				final storageDecision = storage.decisionFor(reference.localId);
				if (storageDecision == null) {
					if (decision.domain != OcamlRepresentationDomain.InternalValue) {
						fail('immutable nominal local ${reference.localId} must consume an internal-value representation, but ${decision.id} selects ${decision.domain}',
							position);
					}
				} else if (!storage.isCaptured(reference.localId)) {
					fail('mutable nominal local ${reference.localId} is not captured, so its ${storageDecision.storage} storage remains outside the admitted class carrier slice',
						position);
				} else if (!storage.requiresRef(reference.localId) || decision.domain != OcamlRepresentationDomain.CapturedLocalStorage) {
					fail('captured-and-reassigned nominal local ${reference.localId} must consume one captured-local-storage representation backed by a shared ref cell',
						position);
				}
			}
		}
	}

	function validateRepresentationReferences(operation:OcamlLoweredPlaceOperation, programRevision:String, position:Position):Void {
		switch (operation) {
			case Simple(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.InstanceField, programRevision, position);
				validateAdmittedInstanceReceiver(plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					programRevision, position);
			case StaticSimple(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.StaticField, programRevision, position);
			case ArraySimple(plan):
				validateArrayRepresentationReferences(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					plan.place.indexRepresentationId, plan.place.indexSemanticTypeId, plan.place.indexCarrierTypeId, programRevision, position);
			case Compound(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.InstanceField, programRevision, position);
				validateAdmittedInstanceReceiver(plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					programRevision, position);
			case StaticCompound(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.StaticField, programRevision, position);
			case ArrayCompound(plan):
				validateArrayRepresentationReferences(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					plan.place.indexRepresentationId, plan.place.indexSemanticTypeId, plan.place.indexCarrierTypeId, programRevision, position);
			case Update(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.InstanceField, programRevision, position);
				validateAdmittedInstanceReceiver(plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					programRevision, position);
			case StaticUpdate(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.StaticField, programRevision, position);
			case ArrayUpdate(plan):
				validateArrayRepresentationReferences(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					plan.place.indexRepresentationId, plan.place.indexSemanticTypeId, plan.place.indexCarrierTypeId, programRevision, position);
		}
	}

	function validateAdmittedInstanceReceiver(representationId:String, semanticTypeId:String, carrierTypeId:String, programRevision:String,
			position:Position):Void {
		if (!StringTools.startsWith(representationId, "representation:"))
			return;
		validateRepresentationReference(representationId, semanticTypeId, carrierTypeId, OcamlRepresentationDomain.InternalValue, programRevision, position);
	}

	function validateArrayRepresentationReferences(representationId:String, semanticTypeId:String, carrierTypeId:String, receiverRepresentationId:String,
			receiverSemanticTypeId:String, receiverCarrierTypeId:String, indexRepresentationId:String, indexSemanticTypeId:String, indexCarrierTypeId:String,
			programRevision:String, position:Position):Void {
		validateRepresentationReference(representationId, semanticTypeId, carrierTypeId, OcamlRepresentationDomain.ArrayElement, programRevision, position);
		validateRepresentationReference(receiverRepresentationId, receiverSemanticTypeId, receiverCarrierTypeId, OcamlRepresentationDomain.InternalValue,
			programRevision, position);
		validateRepresentationReference(indexRepresentationId, indexSemanticTypeId, indexCarrierTypeId, OcamlRepresentationDomain.InternalValue,
			programRevision, position);
	}

	function validateRepresentationReference(representationId:String, semanticTypeId:String, carrierTypeId:String, domain:OcamlRepresentationDomain,
			programRevision:String, position:Position):Void {
		final decision = try {
			representations.require(representationId, programRevision);
		} catch (error:Dynamic) {
			fail(Std.string(error), position);
		}
		if (decision.semanticTypeId != semanticTypeId || decision.carrierTypeId != carrierTypeId || decision.domain != domain) {
			fail('representation ${decision.id} selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} in ${decision.domain}, but the place plan expects $semanticTypeId -> $carrierTypeId in $domain',
				position);
		}
	}
}
#end
