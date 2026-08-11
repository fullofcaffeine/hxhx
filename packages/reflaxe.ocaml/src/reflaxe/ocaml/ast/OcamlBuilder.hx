package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Binop;
import haxe.macro.Expr;
import haxe.macro.Expr.Unop;
import haxe.macro.Expr.Position;
#if macro
import haxe.macro.Context;
#end
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TConstant;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.OcamlBuildContext;
import reflaxe.ocaml.OcamlProfileContract;
import reflaxe.ocaml.ast.OcamlAssignOp;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.ast.OcamlExpr.OcamlUnop;
import reflaxe.ocaml.ast.OcamlApplyArg;
import reflaxe.ocaml.ast.OcamlAnonymousStructureSyntax;
import reflaxe.ocaml.ast.OcamlAnonymousStructureSyntax.OcamlAnonymousStructureMaterialization;
import reflaxe.ocaml.ast.OcamlArrayLiteralSyntax;
import reflaxe.ocaml.ast.OcamlBytesAccessSyntax;
import reflaxe.ocaml.ast.OcamlBytesMutationSyntax;
import reflaxe.ocaml.ast.OcamlBytesProducerSyntax;
import reflaxe.ocaml.ast.OcamlBytesReadSyntax;
import reflaxe.ocaml.ast.OcamlIMapInterfaceSyntax;
import reflaxe.ocaml.ast.OcamlIMapInterfaceSyntax.OcamlIMapInterfaceSyntaxServices;
import reflaxe.ocaml.ast.OcamlMatchCase;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlRawInjection.OcamlRawInjectionMaterializationResult;
import reflaxe.ocaml.ast.OcamlRawInjection.OcamlRawInjectionPlanResult;
import reflaxe.ocaml.ast.OcamlSourcePositionMapper;
import reflaxe.ocaml.ast.OcamlStructuralFieldSyntax;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallEvaluationStepKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallRuntimeUseModel.OcamlCallRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlCatchRuntimeUseModel.OcamlCatchRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlCatchRuntimeUseModel.OcamlCatchRuntimeTagUseRole;
import reflaxe.ocaml.lowered.OcamlLoopRuntimeUseModel.OcamlLoopRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlLoopRuntimeUseModel.OcamlLoopTargetRuntimeUsePlan;
import reflaxe.ocaml.lowered.OcamlReturnRuntimeUseModel.OcamlReturnRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlThrowRuntimeUseModel.OcamlThrowRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlThrowRuntimeUseModel.OcamlThrowRuntimeUseRole;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationKind;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationDecision;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan.OcamlArrayLiteralProducerLookup;
import reflaxe.ocaml.lowered.OcamlArrayReadPlan;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan.OcamlArrayIteratorDecision;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan.OcamlArrayIteratorUseKind;
import reflaxe.ocaml.lowered.OcamlArrayReadModel.OcamlArrayReadDecision;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicCarrierModel;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicEqualityKind;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan.OcamlDynamicStringModel;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan.OcamlDynamicStringStrategy;
import reflaxe.ocaml.lowered.OcamlDynamicBracketReadModel.OcamlDynamicBracketReadDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructurePlan;
import reflaxe.ocaml.lowered.OcamlBytesAccessPlan;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessDecision;
import reflaxe.ocaml.lowered.OcamlBytesMutationPlan;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationDecision;
import reflaxe.ocaml.lowered.OcamlBytesProducerPlan;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerDecision;
import reflaxe.ocaml.lowered.OcamlBytesReadPlan;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchBranchResultPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchChainDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchClauseDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchPrivateControlPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchMatchPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchPayloadConversion;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchUnmatchedPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopTarget;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPayloadConversion;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlStatementResultPolicy;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.OcamlSealedFunctionPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.OcamlSealedNestedFunctionPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.OcamlSealedStandaloneExpressionPlan;
import reflaxe.ocaml.lowered.OcamlEnumDynamicCarrier;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan.OcamlIMapInterfacePlanner;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceCallDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapStorageAliasDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapStorageAliasNullPolicy;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan.OcamlIMapInterfaceConversionMaterialization;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan.OcamlIMapInterfaceMethodMaterialization;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan.OcamlContainerElementLookup;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalCarrierConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionRole;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationChoice;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan;
import reflaxe.ocaml.lowered.OcamlMonomorphicClassMaterializer;
import reflaxe.ocaml.lowered.OcamlPlaceAssignmentLowerer;
import reflaxe.ocaml.lowered.OcamlPlaceAssignmentLowerer.OcamlPlaceAssignmentLoweringResult;
import reflaxe.ocaml.lowered.OcamlPlaceInputPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectCompareDecision;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectCompareDomain;
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan;
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan.OcamlReflectRuntimeUseKind;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan.OcamlStaticStorageDeclarationSite;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan.OcamlStaticStorageEntry;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldDecision;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldPlanner;
import reflaxe.ocaml.lowered.OcamlStandardArrayCallModel.OcamlStandardArrayCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallContract;
import reflaxe.ocaml.lowered.OcamlStringDefaultPlan;
import reflaxe.ocaml.lowered.OcamlStringRepresentationMaterializer;
import reflaxe.ocaml.runtimegen.OcamlNativeRuntimeBoundary;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

private typedef OcamlLoopControlCases = {
	final breakCase:Null<OcamlMatchCase>;
	final continueCase:Null<OcamlMatchCase>;
}

/**
	Converts Haxe's final typed expressions into OCaml syntax.

	Some source expressions need more than a direct syntax translation. For
	example, an anonymous object must preserve field types, aliasing, mutation,
	and evaluation order even though OCaml has no matching built-in value. A
	focused lowering module decides those behaviors first and records them in a
	validated function plan; this builder only turns that decision into syntax.

	Place operations, local mutable storage, typed calls, anonymous structures,
	early returns, and loop control already use that boundary. New decisions
	about representation, evaluation order, mutation, control, runtime support,
	or plugin interfaces belong in their focused lowering owner rather than this
	already-large traversal. Older `unit` fallbacks remain migration debt and
	must not define a newly supported language family.
**/
class OcamlBuilder {
	public final ctx:CompilationContext;
	public final typeExprFromHaxeType:Type->OcamlTypeExpr;
	public final emitSourceMap:Bool;

	final placeAssignmentLowerer:OcamlPlaceAssignmentLowerer;
	final functionPlanRegistry:OcamlFunctionPlanRegistry;
	final representationRegistry:OcamlRepresentationRegistry;
	final staticStoragePlan:OcamlStaticStoragePlan;
	var currentFunctionPlanBinding:Null<OcamlFunctionPlanBinding> = null;
	var currentAnonymousStructurePlan:Null<OcamlAnonymousStructurePlan> = null;
	var currentStructuralFieldPlan:Null<OcamlStructuralFieldPlan> = null;
	var currentBytesAccessPlan:Null<OcamlBytesAccessPlan> = null;
	var currentBytesMutationPlan:Null<OcamlBytesMutationPlan> = null;
	var currentBytesProducerPlan:Null<OcamlBytesProducerPlan> = null;
	var currentBytesReadPlan:Null<OcamlBytesReadPlan> = null;
	var currentIMapInterfacePlan:Null<OcamlIMapInterfacePlan> = null;
	var currentCallPlan:Null<OcamlCallPlan> = null;
	var currentReflectComparePlan:Null<OcamlReflectComparePlan> = null;
	var currentReflectRuntimeUsePlan:Null<OcamlReflectRuntimeUsePlan> = null;
	var currentControlPlan:Null<OcamlControlPlan> = null;
	var currentArrayLiteralProducerPlan:Null<OcamlArrayLiteralProducerPlan> = null;
	var currentArrayReadPlan:Null<OcamlArrayReadPlan> = null;
	var currentArrayIteratorPlan:Null<OcamlArrayIteratorPlan> = null;
	var currentDynamicEqualityPlan:Null<OcamlDynamicEqualityPlan> = null;
	var currentDynamicStringPlan:Null<OcamlDynamicStringPlan> = null;

	/**
		Identifies the root function that sealed the active local plans.

		One root local plan covers its complete tree of nested functions so captured
		and nested locals share one storage and carrier decision. A nested function
		still installs its own behavior binding for calls and control flow. Keeping
		this second binding prevents local conversion lookup from accidentally using
		that nested behavior identity.
	**/
	var currentLocalPlanBinding:Null<OcamlFunctionPlanBinding> = null;

	/**
		Identifies the root function that sealed the active assignment plans.

		One root planning pass records every supported assignment and update in its
		complete tree of nested functions. A nested function still installs its own
		behavior binding for calls and control flow. Keeping this second binding lets
		syntax request the exact root-owned assignment without pretending that a
		nested behavior plan created it.
	**/
	var currentPlacePlanBinding:Null<OcamlFunctionPlanBinding> = null;

	// Track locals introduced by TVar that we currently represent as `ref`.
	final refLocals:Map<Int, Bool> = [];
	// `ref` locals whose initializer is `null` (or omitted and null-defaulted).
	// Assignments to these refs may need a local `Obj.magic` cast to avoid OCaml
	// weak-polymorphism lock-in when branches assign heterogeneous closure values.
	final weakRefLocals:Map<Int, Bool> = [];
	// Ref locals whose declared OCaml slot type is `Obj.t`.
	final objRefLocals:Map<Int, Bool> = [];

	var tmpId:Int = 0;

	// Tracks the exact lexical loop targets active while syntax builds one sealed
	// expression owner. A break or continue must name the final target in this list.
	var currentLoopTargetIds:Array<String> = [];

	// Set while compiling a function body so declarations consume the selected
	// shared-cell versus immutable-rebinding decision.
	var currentLocalStoragePlan:Null<OcamlLocalStoragePlan> = null;
	var currentLocalRepresentationPlan:Null<OcamlLocalRepresentationPlan> = null;
	var currentContainerElementPlan:Null<OcamlContainerElementPlan> = null;
	// The current request's host-ID adapter is separate because it maps host
	// variables to stable lexical identities. Other sealed plans may also retain
	// exact typed nodes, but every such lookup is cleared with the request.
	var currentLocalIdentities:Null<LexicalLocalIdentityPlan> = null;
	// Current function return type while lowering a function body.
	var currentFunctionReturnType:Null<Type> = null;
	// The sealed callable boundary, when the complete signature is admitted.
	var currentCallableBoundary:Null<OcamlCallableBoundaryPlan> = null;

	// Used for pruning unused `let` bindings inside blocks (keeps dune warn-error happy).
	var currentUsedLocalIds:Null<Map<Int, Bool>> = null;

	// Set while compiling a switch arm to resolve TEnumParameter -> bound pattern variables.
	//
	// Correctness note:
	// `TEnumParameter(enumValueExpr, ef, index)` does not carry a unique "pattern binding id".
	// The Haxe typer may emit multiple `TEnumParameter` nodes with the same `(ef,index)` inside
	// nested lambdas/conditions that *also* use enum-index tests. If we key only by `(ef,index)`,
	// we can accidentally capture an outer pattern binding for a different scrutinee value.
	//
	// To avoid that, we only resolve via this map when the `enumValueExpr` is the same compiler-
	// introduced `TLocal` scrutinee for the current switch arm.
	var currentEnumParamNames:Null<Map<String, String>> = null;
	var currentEnumParamScrutineeLocalId:Null<Int> = null;

	static inline function enumParamScrutineeLocalId(e:TypedExpr):Null<Int> {
		return switch (unwrap(e).expr) {
			case TLocal(v): v.id;
			case _: null;
		}
	}

	public function new(ctx:CompilationContext, typeExprFromHaxeType:Type->OcamlTypeExpr, functionPlanRegistry:OcamlFunctionPlanRegistry,
			representationRegistry:OcamlRepresentationRegistry, staticStoragePlan:OcamlStaticStoragePlan, emitSourceMap:Bool = false) {
		this.ctx = ctx;
		this.typeExprFromHaxeType = typeExprFromHaxeType;
		this.functionPlanRegistry = functionPlanRegistry;
		this.representationRegistry = representationRegistry;
		this.staticStoragePlan = staticStoragePlan;
		this.emitSourceMap = emitSourceMap;
		this.placeAssignmentLowerer = new OcamlPlaceAssignmentLowerer(ctx, functionPlanRegistry);
	}

	inline function freshTmp(prefix:String):String {
		tmpId += 1;
		return "__" + prefix + "_" + tmpId;
	}

	function placeLoweringInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-lowering:place-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	function localStorageInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-lowering:local-storage-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	function containerElementInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-lowering:container-element-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	function arrayLiteralProducerInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-array-literal:plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/** Resolves one request-local Haxe binding to the identity used by sealed plans. */
	function stableLocalId(hostLocalId:Int, position:Position):String {
		final identities = currentLocalIdentities;
		if (identities == null)
			return localStorageInvariant("syntax construction has no request-local lexical identity lookup", position);
		return try {
			identities.requireHostId(hostLocalId).id;
		} catch (error:Dynamic) {
			localStorageInvariant(Std.string(error), position);
		}
	}

	/** Returns the sealed storage decision for one active request-local binding. */
	function localStorageDecision(hostLocalId:Int, position:Position):Null<reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageDecision> {
		final plan = currentLocalStoragePlan;
		return plan == null ? null : plan.decisionFor(stableLocalId(hostLocalId, position));
	}

	/** Returns whether one active request-local binding uses a shared `ref`. */
	function localRequiresRef(hostLocalId:Int, position:Position):Bool {
		final plan = currentLocalStoragePlan;
		return plan != null && plan.requiresRef(stableLocalId(hostLocalId, position));
	}

	function callPlanInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-call:plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/**
		Stops code generation when an admitted anonymous-object operation has no
		matching validated decision.

		Continuing would let this syntax traversal guess field representation or
		evaluation order, which can produce plausible OCaml with the wrong Haxe
		behavior. The compiler therefore reports the missing boundary before
		writing target code.
	**/
	function anonymousStructureInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-anonymous:plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/** Creates one request-local checker for an anonymous-object source operation. */
	function anonymousRuntimeAuthority(operation:OcamlAnonymousStructureOperationDecision):OcamlRuntimeUseAuthority {
		final binding:OcamlFunctionPlanBinding = {
			functionId: operation.functionId,
			programRevision: operation.programRevision,
			bodyRevision: operation.bodyRevision,
			pipelineRevision: operation.pipelineRevision
		};
		final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
		final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
		return new OcamlRuntimeUseAuthority(runtimePlanRevision, activeProfile, ctx.runtimeRequirementsByIds(operation.runtimeRequirementIds),
			operation.runtimeUseOccurrences, ctx.finalRuntimeUses);
	}

	/**
		Checks each anonymous operation's own private-runtime helper calls.

		A literal has separate create and field-initializer operations. Keeping one
		authority per operation prevents an initializer from consuming another
		field's permission while still returning one complete Haxe expression. A
		field value is evaluated before the initializer's helper call, so the exact
		call checked here does not include compiler work owned by that field value.
	**/
	function reconcileAnonymousMaterialization(materialization:OcamlAnonymousStructureMaterialization, authorities:Map<String, OcamlRuntimeUseAuthority>,
			position:Position):OcamlExpr {
		return try {
			final reconciled:Map<String, Bool> = [];
			for (runtimeOperation in materialization.runtimeOperations) {
				if (reconciled.exists(runtimeOperation.operationId))
					throw 'operation "${runtimeOperation.operationId}" returned more than one runtime subtree';
				final authority = authorities.get(runtimeOperation.operationId);
				if (authority == null)
					throw 'operation "${runtimeOperation.operationId}" returned syntax without its runtime authority';
				authority.reconcileExpression(runtimeOperation.expression);
				reconciled.set(runtimeOperation.operationId, true);
			}
			for (operationId in authorities.keys())
				if (!reconciled.exists(operationId))
					throw 'operation "$operationId" created runtime identifiers without returning its checked subtree';
			materialization.expression;
		} catch (error:Dynamic) {
			anonymousStructureInvariant(Std.string(error), position);
		}
	}

	/** Builds one literal and reconciles create and initializer permissions separately. */
	function buildAnonymousLiteral(plan:OcamlAnonymousStructureLiteralPlan, fields:Array<{name:String, expr:TypedExpr}>, position:Position):OcamlExpr {
		final authorities:Map<String, OcamlRuntimeUseAuthority> = [];
		final materialization = try {
			OcamlAnonymousStructureSyntax.buildLiteral(plan, fields, buildExpr, freshTmp, operation -> {
				if (authorities.exists(operation.id))
					throw 'operation "${operation.id}" requested more than one runtime authority';
				final authority = anonymousRuntimeAuthority(operation);
				authorities.set(operation.id, authority);
				authority;
			});
		} catch (error:Dynamic) {
			return anonymousStructureInvariant(Std.string(error), position);
		}
		return reconcileAnonymousMaterialization(materialization, authorities, position);
	}

	/** Builds one read and checks only the runtime subtree inserted for that read. */
	function buildAnonymousRead(operation:OcamlAnonymousStructureOperationDecision, receiver:TypedExpr, position:Position):OcamlExpr {
		final authority = anonymousRuntimeAuthority(operation);
		final materialization = OcamlAnonymousStructureSyntax.buildRead(operation, receiver, buildExpr, freshTmp, authority);
		final authorities:Map<String, OcamlRuntimeUseAuthority> = [];
		authorities.set(operation.id, authority);
		return reconcileAnonymousMaterialization(materialization, authorities, position);
	}

	/** Builds one write and checks only the runtime subtree inserted for that write. */
	function buildAnonymousWrite(operation:OcamlAnonymousStructureOperationDecision, receiver:TypedExpr, value:TypedExpr, position:Position):OcamlExpr {
		final authority = anonymousRuntimeAuthority(operation);
		final materialization = OcamlAnonymousStructureSyntax.buildWrite(operation, receiver, value, buildExpr, freshTmp, authority);
		final authorities:Map<String, OcamlRuntimeUseAuthority> = [];
		authorities.set(operation.id, authority);
		return reconcileAnonymousMaterialization(materialization, authorities, position);
	}

	/** Builds one `Int +=` write and checks its read, addition, and write helpers. */
	function buildAnonymousCompoundWrite(operation:OcamlAnonymousStructureOperationDecision, receiver:TypedExpr, value:TypedExpr, position:Position):OcamlExpr {
		final authority = anonymousRuntimeAuthority(operation);
		final materialization = OcamlAnonymousStructureSyntax.buildCompoundWrite(operation, receiver, value, buildExpr, freshTmp, authority);
		final authorities:Map<String, OcamlRuntimeUseAuthority> = [];
		authorities.set(operation.id, authority);
		return reconcileAnonymousMaterialization(materialization, authorities, position);
	}

	/**
		Stops syntax from deciding what an overlapping structural field means.

		The final typed planner must first classify the occurrence as an ordinary
		stored field, a captured Iterator method, or a proven Map-pair projection.
		Reaching this boundary without that decision is an internal compiler error:
		choosing from `next`, `hasNext`, `key`, or `value` alone can silently change
		valid object or iteration behavior.
	**/
	function structuralFieldInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-structural-field:plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/** Builds and reconciles only the runtime subtree owned by one structural field. */
	function buildStructuralField(decision:OcamlStructuralFieldDecision, receiver:TypedExpr, value:Null<TypedExpr>, position:Position):OcamlExpr {
		return try {
			// The structural-field planner currently owns nested expressions as part
			// of their enclosing typed body. Use that sealed owner here instead of
			// the nested function's separate control-flow binding.
			final binding:OcamlFunctionPlanBinding = {
				functionId: decision.functionId,
				programRevision: decision.programRevision,
				bodyRevision: decision.bodyRevision,
				pipelineRevision: decision.pipelineRevision
			};
			final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimePlanRevision, activeProfile,
				ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final materialization = OcamlStructuralFieldSyntax.build(decision, receiver, value, buildExpr, freshTmp, runtimeAuthority);
			// The receiver and assigned value can contain separately planned work.
			// Reconcile only the completed call subtree created for this field.
			runtimeAuthority.reconcileExpression(materialization.runtimeOperation);
			materialization.expression;
		} catch (error:Dynamic) {
			structuralFieldInvariant(Std.string(error), position);
		}
	}

	function bytesProducerInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-bytes:plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/**
		Builds one Bytes-producing call from the compiler's completed decision.

		The decision names both the runtime arguments and the one private `HxBytes`
		function the call may use. Syntax binds runtime arguments in Haxe order, then
		the request-local authority checks the private identifier before printing.
	**/
	function buildBytesProducer(decision:OcamlBytesProducerDecision, arguments:Array<TypedExpr>, position:Position):OcamlExpr {
		return try {
			final binding:OcamlFunctionPlanBinding = {
				functionId: decision.functionId,
				programRevision: decision.programRevision,
				bodyRevision: decision.bodyRevision,
				pipelineRevision: decision.pipelineRevision
			};
			final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimePlanRevision, activeProfile,
				ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final materialization = OcamlBytesProducerSyntax.build(decision, arguments, buildExpr, freshTmp, runtimeAuthority);
			// Argument expressions can contain helper calls owned by other decisions.
			// Check only the one private identifier this producer inserted.
			runtimeAuthority.reconcileExpression(OcamlExpr.ESeq(materialization.runtimeReferences));
			materialization.expression;
		} catch (error:Dynamic) {
			bytesProducerInvariant(Std.string(error), position);
		}
	}

	function bytesMutationInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-bytes:mutation-plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/**
		Builds one Bytes mutation from the compiler's completed decision.

		The decision lists each private runtime helper the generated expression may
		call. Syntax must consume those exact entries, in order, before printing;
		otherwise compilation fails instead of silently introducing an unplanned
		`HxBytes` or `HxRuntime` dependency.
	**/
	function buildBytesMutation(decision:OcamlBytesMutationDecision, receiver:TypedExpr, arguments:Array<TypedExpr>, position:Position):OcamlExpr {
		return try {
			final binding:OcamlFunctionPlanBinding = {
				functionId: decision.functionId,
				programRevision: decision.programRevision,
				bodyRevision: decision.bodyRevision,
				pipelineRevision: decision.pipelineRevision
			};
			final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimePlanRevision, activeProfile,
				ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final materialization = OcamlBytesMutationSyntax.build(decision, receiver, arguments, buildExpr, freshTmp, runtimeAuthority);
			// Receiver and argument expressions can contain helper calls owned by
			// other compiler decisions. Check only the identifiers inserted for this
			// mutation so each decision remains responsible for its own calls.
			runtimeAuthority.reconcileExpression(OcamlExpr.ESeq(materialization.runtimeReferences));
			materialization.expression;
		} catch (error:Dynamic) {
			bytesMutationInvariant(Std.string(error), position);
		}
	}

	function bytesAccessInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-bytes:access-plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/**
		Builds one Bytes access from its completed compiler decision.

		The decision names each conversion helper and final `HxBytes` operation that
		target syntax may use. The completed identifiers are checked in order before
		printing, so syntax cannot introduce a plausible but unplanned runtime call.
	**/
	function buildBytesAccess(decision:OcamlBytesAccessDecision, receiver:Null<TypedExpr>, arguments:Array<TypedExpr>, position:Position):OcamlExpr {
		return try {
			final binding:OcamlFunctionPlanBinding = {
				functionId: decision.functionId,
				programRevision: decision.programRevision,
				bodyRevision: decision.bodyRevision,
				pipelineRevision: decision.pipelineRevision
			};
			final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimePlanRevision, activeProfile,
				ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final materialization = OcamlBytesAccessSyntax.build(decision, receiver, arguments, buildExpr, freshTmp, runtimeAuthority);
			// Receiver and argument expressions can contain helper calls owned by
			// other decisions. Check only the identifiers this access inserted.
			runtimeAuthority.reconcileExpression(OcamlExpr.ESeq(materialization.runtimeReferences));
			materialization.expression;
		} catch (error:Dynamic) {
			bytesAccessInvariant(Std.string(error), position);
		}
	}

	function bytesReadInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-bytes:read-plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	function arrayReadInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-array-read:plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/**
		Builds one standard Array bracket read from its typed decision.

		For `makeArray()[makeIndex()]`, Haxe evaluates `makeArray()` first and
		`makeIndex()` second. The temporary bindings preserve that order and prevent
		either expression from running twice. The runtime authority supplies only the
		private `HxArray.get` name; nested expressions keep their own decisions.
	**/
	function buildArrayRead(decision:OcamlArrayReadDecision, receiver:TypedExpr, index:TypedExpr, position:Position):OcamlExpr {
		return try {
			final binding:OcamlFunctionPlanBinding = {
				functionId: decision.functionId,
				programRevision: decision.programRevision,
				bodyRevision: decision.bodyRevision,
				pipelineRevision: decision.pipelineRevision
			};
			final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimePlanRevision, activeProfile,
				ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final occurrence = decision.runtimeUseOccurrences[0];
			final runtimeFunction = OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(occurrence.id, occurrence.planRevision,
				occurrence.exactSymbol));
			// The receiver and index can contain private calls from other plans. Check
			// only the HxArray.get identifier inserted by this read decision.
			runtimeAuthority.reconcileExpression(runtimeFunction);
			final receiverName = freshTmp("array_read_receiver");
			final indexName = freshTmp("array_read_index");
			OcamlExpr.ELet(receiverName, buildExpr(receiver), OcamlExpr.ELet(indexName, buildExpr(index), OcamlExpr.EApp(runtimeFunction, [
				coerceArrayReceiver(OcamlExpr.EIdent(receiverName), receiver),
				OcamlExpr.EIdent(indexName)
			]), false), false);
		} catch (error:Dynamic) {
			arrayReadInvariant(Std.string(error), position);
		}
	}

	/**
		Builds one numeric-style bracket read whose receiver is not a standard Array.

		This is a compatibility rule for values typed as `Dynamic` or another
		non-Array type. Its separate decision keeps the strict `Array<T>` proof
		unchanged while still checking the one private `HxArray.get` name used here.
	**/
	function buildDynamicBracketRead(decision:OcamlDynamicBracketReadDecision, receiver:TypedExpr, index:TypedExpr, position:Position):OcamlExpr {
		return try {
			final binding:OcamlFunctionPlanBinding = {
				functionId: decision.functionId,
				programRevision: decision.programRevision,
				bodyRevision: decision.bodyRevision,
				pipelineRevision: decision.pipelineRevision
			};
			final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimePlanRevision, activeProfile,
				ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final occurrence = decision.runtimeUseOccurrences[0];
			final runtimeFunction = OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(occurrence.id, occurrence.planRevision,
				occurrence.exactSymbol));
			runtimeAuthority.reconcileExpression(runtimeFunction);
			final receiverName = freshTmp("dynamic_bracket_receiver");
			final indexName = freshTmp("dynamic_bracket_index");
			OcamlExpr.ELet(receiverName, buildExpr(receiver), OcamlExpr.ELet(indexName, buildExpr(index), OcamlExpr.EApp(runtimeFunction, [
				coerceArrayReceiver(OcamlExpr.EIdent(receiverName), receiver),
				OcamlExpr.EIdent(indexName)
			]), false), false);
		} catch (error:Dynamic) {
			arrayReadInvariant(Std.string(error), position);
		}
	}

	/**
		Builds one read-only Bytes call from its completed compiler decision.

		The decision names the nullable-receiver checks, when needed, and the final
		`HxBytes` call. Only those identifiers are reconciled here because nested
		receiver and argument expressions remain owned by their own decisions.
	**/
	function buildBytesRead(decision:OcamlBytesReadDecision, receiver:TypedExpr, arguments:Array<TypedExpr>, position:Position):OcamlExpr {
		return try {
			final binding:OcamlFunctionPlanBinding = {
				functionId: decision.functionId,
				programRevision: decision.programRevision,
				bodyRevision: decision.bodyRevision,
				pipelineRevision: decision.pipelineRevision
			};
			final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimePlanRevision, activeProfile,
				ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final materialization = OcamlBytesReadSyntax.build(decision, receiver, arguments, buildExpr, freshTmp, runtimeAuthority);
			runtimeAuthority.reconcileExpression(OcamlExpr.ESeq(materialization.runtimeReferences));
			materialization.expression;
		} catch (error:Dynamic) {
			bytesReadInvariant(Std.string(error), position);
		}
	}

	function controlPlanInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-control:plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	function requireCallValue(value:OcamlCallValuePlan, expectedIndex:Int, owner:String, position:Position):Void {
		try {
			OcamlCallPlan.requireCallValue(value, expectedIndex, owner);
		} catch (error:Dynamic) {
			callPlanInvariant(Std.string(error), position);
		}
	}

	/**
		Resolves the target type selected for one callable-side represented value.

		Most carriers are complete OCaml type names such as `int` or `Obj.t`.
		A monomorphic class deliberately stores `t` plus its owning module as
		separate representation facts, so this helper qualifies that carrier when
		the callable is emitted from another module.
	**/
	function callableOutputType(value:OcamlCallValuePlan, position:Position):OcamlTypeExpr {
		final binding = currentFunctionPlanBinding;
		if (binding == null)
			return callPlanInvariant("a callable carrier reached syntax without a sealed function binding", position);
		final representation = try {
			representationRegistry.require(value.outputRepresentationId, binding.programRevision);
		} catch (error:Dynamic) {
			return callPlanInvariant(Std.string(error), position);
		}
		if (representation.semanticTypeId != value.outputSemanticTypeId || representation.carrierTypeId != value.outputCarrierTypeId) {
			return
				callPlanInvariant('callable carrier ${value.outputSemanticTypeId}/${value.outputCarrierTypeId} does not match representation "${value.outputRepresentationId}"',
				position);
		}
		if (OcamlMonomorphicClassMaterializer.isNominalClass(representation)) {
			if (ctx.currentModuleId == null)
				return callPlanInvariant("a nominal callable carrier reached syntax outside an OCaml module", position);
			return OcamlMonomorphicClassMaterializer.typeExpr(representation, moduleIdToOcamlModuleName(ctx.currentModuleId));
		}
		return OcamlTypeExpr.TIdent(value.outputCarrierTypeId);
	}

	/** Mechanically applies one conversion already selected by the call plan. */
	function buildPlannedCallArgument(call:OcamlCallDecision, value:OcamlCallValuePlan, expression:TypedExpr):OcamlExpr {
		requireCallValue(value, value.index, 'call argument ${value.index}', expression.pos);
		return switch (value.conversion) {
			case Identity, PreserveNullableIntCarrier, PreserveNullableBoolCarrier, PreserveDynamicCarrier:
				buildExpr(expression);
			case BoxExactIntToNullableInt, BoxExactBoolToNullableBool:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(expression)]);
			case BoxConcreteToDynamic:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(expression)]);
			case BoxExactBoolToDynamic:
				final callPlan = currentCallPlan;
				if (callPlan == null)
					return callPlanInvariant('call "${call.id}" reached Bool-to-Dynamic boxing without its sealed call inventory', expression.pos);
				final runtimeUsePlan = callPlan.runtimeUsePlanFor(call.id);
				if (runtimeUsePlan == null)
					return callPlanInvariant('call "${call.id}" argument ${value.index} has no exact Boolean runtime-use plan', expression.pos);
				try {
					OcamlCallRuntimeUseContract.requireForCall(call, runtimeUsePlan);
					final occurrence = OcamlCallRuntimeUseContract.occurrenceForArgument(runtimeUsePlan, value.index);
					final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
					final authority = new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile,
						ctx.runtimeRequirementsByIds([occurrence.requirementId]), [occurrence], ctx.finalRuntimeUses);
					final runtimeFunction = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(occurrence.id, occurrence.planRevision,
						occurrence.exactSymbol));
					// The argument expression can contain private runtime calls owned by
					// other plans. Check only this call slot's helper identifier before
					// placing the independently built argument beneath it.
					authority.reconcileExpression(runtimeFunction);
					OcamlExpr.EApp(runtimeFunction, [buildExpr(expression)]);
				} catch (error:Dynamic) {
					callPlanInvariant(Std.string(error), expression.pos);
				}
			case CheckedUnboxNullableInt:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_unwrap"), [buildExpr(expression)]);
			case MaterializeOmittedNullableInt, MaterializeOmittedNullableBool, MaterializeOmittedString, MaterializeOmittedDynamic:
				callPlanInvariant('call argument ${value.index} claims an omitted conversion but received a source expression', expression.pos);
			case MaterializeExplicitNullString:
				if (!OcamlCallPlan.isExplicitNullExpression(expression))
					callPlanInvariant('call argument ${value.index} claims an explicit null String conversion for a non-null source expression',
						expression.pos);
				exactStringNullValue(OcamlRepresentationDomain.InternalValue, 'call:${call.id}:explicit-null:${value.index}', expression.pos);
			case MaterializeExplicitNullDynamic:
				if (!OcamlCallPlan.isExplicitNullExpression(expression))
					callPlanInvariant('call argument ${value.index} claims an explicit null Dynamic conversion for a non-null source expression',
						expression.pos);
				OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
		}
	}

	/** Materializes the selected null carrier for one omitted optional parameter. */
	function buildPlannedOmittedArgument(callId:String, value:OcamlCallValuePlan, position:Position):OcamlExpr {
		requireCallValue(value, value.index, 'omitted call argument ${value.index}', position);
		return switch (value.conversion) {
			case MaterializeOmittedNullableInt, MaterializeOmittedNullableBool, MaterializeOmittedDynamic:
				OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
			case MaterializeOmittedString:
				exactStringNullValue(OcamlRepresentationDomain.InternalValue, 'call:$callId:omitted:${value.index}', position);
			case _:
				callPlanInvariant('call argument ${value.index} has no sealed omitted-argument conversion', position);
		}
	}

	/** Mechanically applies the sealed final-body crossing at a callable boundary. */
	function buildPlannedFunctionResult(value:OcamlCallValuePlan, body:OcamlExpr, position:Position):OcamlExpr {
		requireCallValue(value, -1, "callable definition result", position);
		return switch (value.conversion) {
			case Identity, PreserveNullableIntCarrier, PreserveNullableBoolCarrier, PreserveDynamicCarrier:
				body;
			case BoxExactIntToNullableInt, BoxExactBoolToNullableBool:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [body]);
			case CheckedUnboxNullableInt:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_unwrap"), [body]);
			case BoxConcreteToDynamic, BoxExactBoolToDynamic, MaterializeOmittedNullableInt, MaterializeOmittedNullableBool, MaterializeOmittedString,
				MaterializeOmittedDynamic, MaterializeExplicitNullString, MaterializeExplicitNullDynamic:
				callPlanInvariant("a callable result cannot use a call-argument-only conversion", position);
		}
	}

	/** Raises one early return using only its sealed value or effect-only mechanism. */
	function buildPlannedReturn(decision:OcamlControlDecision, value:Null<TypedExpr>, position:Position):OcamlExpr {
		try {
			OcamlControlPlan.requireDecision(decision);
		} catch (error:Dynamic) {
			return controlPlanInvariant(Std.string(error), position);
		}
		final binding = currentFunctionPlanBinding;
		if (binding == null)
			return controlPlanInvariant('control decision "${decision.id}" reached syntax without a sealed function binding', position);
		if (decision.kind != OcamlControlTransferKind.Return
			|| decision.targetKind != OcamlControlTargetKind.Function
			|| decision.targetId != binding.functionId) {
			return
				controlPlanInvariant('control decision "${decision.id}" targets ${decision.targetKind} "${decision.targetId}" while return syntax is building "${binding.functionId}"',
				position);
		}
		return switch (decision.mechanism) {
			case RuntimeVoidReturnSignal:
				if (value != null || decision.payload != null)
					controlPlanInvariant('control decision "${decision.id}" selected an effect-only Void return for a value-bearing typed return',
					position); else buildAuthorizedReturnSignal(decision, null, position);
			case RuntimeReturnSignal:
				if (value == null)
					controlPlanInvariant('control decision "${decision.id}" expects an exact represented return value, but the typed return is empty',
						position); else {
					final selectedPayload = decision.payload;
					if (selectedPayload == null)
						controlPlanInvariant('return decision "${decision.id}" reached syntax without its sealed value payload', position);
					else {
						final payload = switch (selectedPayload.conversion) {
							case BoxAndRecoverExactValue, BoxAndRecoverNominalValue, BoxAndRecoverTypedFunctionResult:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(value)]);
							case BoxBoolAndRecoverDynamicTypedFunctionResult:
								buildAuthorizedDynamicBoolReturnPayload(decision, buildExpr(value), position);
							case PreserveNullableCarrier, PreserveDynamicReturnCarrier:
								buildExpr(value);
							case PreserveAnonymousCarrier:
								OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
							case BoxExactIntToNullableCarrier, BoxExactBoolToNullableCarrier:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(value)]);
							case _:
								return
									controlPlanInvariant('control decision "${decision.id}" selected unsupported payload conversion ${selectedPayload.conversion}',
										position);
						}
						buildAuthorizedReturnSignal(decision, payload, position);
					}
				}
			case _:
				controlPlanInvariant('control decision "${decision.id}" selected unsupported target mechanism ${decision.mechanism}', position);
		}
	}

	/** Boxes one planned Bool return into the target's distinct Dynamic carrier. */
	function buildAuthorizedDynamicBoolReturnPayload(decision:OcamlControlDecision, value:OcamlExpr, position:Position):OcamlExpr {
		return try {
			final runtimeUsePlan = OcamlReturnRuntimeUseContract.forBoolPayloadDecision(decision);
			OcamlReturnRuntimeUseContract.requireForBoolPayloadDecision(decision, runtimeUsePlan);
			final occurrence = OcamlReturnRuntimeUseContract.boolPayloadOccurrence(runtimeUsePlan);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile,
				ctx.runtimeRequirementsByIds(runtimeUsePlan.runtimeRequirementIds), runtimeUsePlan.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final helper = OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(occurrence.id, runtimeUsePlan.planRevision, occurrence.exactSymbol));
			final expression = OcamlExpr.EApp(helper, [value]);
			runtimeAuthority.reconcileExpression(OcamlExpr.EApp(helper, [OcamlExpr.EIdent("return_bool_payload_owned_elsewhere")]));
			expression;
		} catch (error:Dynamic) {
			controlPlanInvariant(Std.string(error), position);
		}
	}

	/**
		Raises one planned private return signal after checking its exact owner.

		The control plan has already decided whether this return carries a value. This
		helper only converts that decision's one runtime-use occurrence into a hidden
		AST reference and proves the resulting signal expression used it exactly once.
	**/
	function buildAuthorizedReturnSignal(decision:OcamlControlDecision, payload:Null<OcamlExpr>, position:Position):OcamlExpr {
		return try {
			final runtimeUsePlan = OcamlReturnRuntimeUseContract.forDecision(decision);
			OcamlReturnRuntimeUseContract.requireForDecision(decision, runtimeUsePlan);
			final occurrence = OcamlReturnRuntimeUseContract.signalOccurrence(runtimeUsePlan);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile,
				ctx.runtimeRequirementsByIds(runtimeUsePlan.runtimeRequirementIds), runtimeUsePlan.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final signal = OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(occurrence.id, runtimeUsePlan.planRevision, occurrence.exactSymbol));
			final expression = switch (decision.mechanism) {
				case RuntimeReturnSignal:
					if (payload == null)
						return controlPlanInvariant('return decision "${decision.id}" lost its sealed payload before signal construction', position);
					OcamlExpr.ERaise(OcamlExpr.EApp(signal, [payload]));
				case RuntimeVoidReturnSignal:
					if (payload != null)
						return controlPlanInvariant('payloadless return decision "${decision.id}" received a target value', position);
					OcamlExpr.ERaise(signal);
				case _:
					return controlPlanInvariant('return decision "${decision.id}" selected unsupported signal mechanism ${decision.mechanism}', position);
			};
			// The returned value can contain private helpers owned by other sealed
			// plans. Check only the signal node introduced here; the request-wide final
			// authority still walks the complete expression before publication.
			final signalProof = switch (decision.mechanism) {
				case RuntimeReturnSignal: OcamlExpr.EApp(signal, [OcamlExpr.EIdent("return_payload_owned_elsewhere")]);
				case RuntimeVoidReturnSignal: signal;
				case _: throw "unreachable return-signal proof mechanism";
			};
			runtimeAuthority.reconcileExpression(signalProof);
			expression;
		} catch (error:Dynamic) {
			controlPlanInvariant(Std.string(error), position);
		}
	}

	/**
		Builds the checked pattern that catches one planned function return.

		The sealed return decision already selects the value-bearing or payloadless
		signal. This helper authorizes only the matching pattern constructor. The
		branch result remains owned by the function-result plan.
	**/
	function buildAuthorizedReturnBoundaryPattern(decision:OcamlControlDecision, arguments:Array<OcamlPat>, position:Position):OcamlPat {
		return try {
			final runtimeUsePlan = OcamlReturnRuntimeUseContract.forBoundaryDecision(decision);
			OcamlReturnRuntimeUseContract.requireForBoundaryDecision(decision, runtimeUsePlan);
			final occurrence = OcamlReturnRuntimeUseContract.boundaryPatternOccurrence(runtimeUsePlan);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile,
				ctx.runtimeRequirementsByIds(runtimeUsePlan.runtimeRequirementIds), runtimeUsePlan.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final pattern = OcamlPat.PRuntimeConstructor(runtimeAuthority.patternIdentifier(occurrence.id, runtimeUsePlan.planRevision,
				occurrence.exactSymbol), arguments);
			// The real branch can contain target names owned by other plans. Reconcile a
			// small tree that contains only the constructor introduced by this helper.
			runtimeAuthority.reconcileExpression(OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit),
				[{pat: pattern, guard: null, expr: OcamlExpr.EConst(OcamlConst.CUnit)}]));
			pattern;
		} catch (error:Dynamic) {
			controlPlanInvariant(Std.string(error), position);
		}
	}

	/** Recovers the sealed early-return payload at its exact function boundary. */
	function buildPlannedReturnBoundary(decision:OcamlControlDecision, returnVarName:String, position:Position):OcamlExpr {
		try {
			OcamlControlPlan.requireDecision(decision);
		} catch (error:Dynamic) {
			return controlPlanInvariant(Std.string(error), position);
		}
		final payload = decision.payload;
		if (payload == null)
			return controlPlanInvariant('return decision "${decision.id}" reached its function boundary without a sealed value payload', position);
		return switch (payload.conversion) {
			case BoxAndRecoverExactValue, BoxAndRecoverNominalValue:
				OcamlExpr.EAnnot(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(returnVarName)]),
					OcamlTypeExpr.TIdent(payload.outputCarrierTypeId));
			case BoxAndRecoverTypedFunctionResult, BoxBoolAndRecoverDynamicTypedFunctionResult:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(returnVarName)]);
			case PreserveNullableCarrier, PreserveAnonymousCarrier, PreserveDynamicReturnCarrier:
				OcamlExpr.EAnnot(OcamlExpr.EIdent(returnVarName), OcamlTypeExpr.TIdent(payload.outputCarrierTypeId));
			case BoxExactIntToNullableCarrier, BoxExactBoolToNullableCarrier:
				OcamlExpr.EAnnot(OcamlExpr.EIdent(returnVarName), OcamlTypeExpr.TIdent(payload.outputCarrierTypeId));
			case _:
				controlPlanInvariant('control decision "${decision.id}" selected unsupported boundary conversion ${payload.conversion}', position);
		}
	}

	/** Raises one exact Haxe value through its sealed private exception channel. */
	function buildPlannedThrow(decision:OcamlControlDecision, value:TypedExpr, position:Position):OcamlExpr {
		try {
			OcamlControlPlan.requireDecision(decision);
		} catch (error:Dynamic) {
			return controlPlanInvariant(Std.string(error), position);
		}
		if (decision.kind != OcamlControlTransferKind.Throw
			|| decision.targetKind != OcamlControlTargetKind.HaxeExceptionChannel
			|| decision.targetId != OcamlControlPlan.HAXE_EXCEPTION_CHANNEL_ID) {
			return
				controlPlanInvariant('control decision "${decision.id}" targets ${decision.targetKind} "${decision.targetId}" while Haxe throw syntax is building',
					position);
		}
		final selectedPayload = decision.payload;
		if (selectedPayload == null)
			return controlPlanInvariant('throw decision "${decision.id}" reached syntax without its sealed value payload', position);
		final built = buildExpr(value);
		final payload = switch (selectedPayload.conversion) {
			case ReprAndRecoverExactValue:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
			case BoxBoolAndRecoverExactValue:
				buildAuthorizedThrowPayloadHelper(decision, OcamlThrowRuntimeUseRole.BoxExactBoolPayload, [built], position);
			case PreserveNullableIntThrowCarrier:
				built;
			case NormalizeNullableBoolThrowCarrier:
				final carrierName = freshTmp("throw_nullable_bool");
				final carrier = OcamlExpr.EIdent(carrierName);
				final isNull = buildAuthorizedThrowPayloadHelper(decision, OcamlThrowRuntimeUseRole.TestNullableBoolPayload, [carrier], position);
				final recovered = buildAuthorizedThrowPayloadHelper(decision, OcamlThrowRuntimeUseRole.RecoverNullableBoolPayload, [carrier], position);
				final normalized = buildAuthorizedThrowPayloadHelper(decision, OcamlThrowRuntimeUseRole.BoxNullableBoolPayload, [recovered], position);
				OcamlExpr.ELet(carrierName, built, OcamlExpr.EIf(isNull, carrier, normalized), false);
			case BoxRepresentedArrayThrowCarrier:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
			case BoxNominalThrowCarrier:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
			case PreserveDynamicThrowCarrier:
				built;
			case BoxHaxeExceptionWrapperThrowCarrier:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
			case BoxEnumThrowCarrier:
				final represented = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
				buildAuthorizedThrowPayloadHelper(decision, OcamlThrowRuntimeUseRole.BoxEnumPayload, [
					OcamlExpr.EConst(OcamlConst.CString(selectedPayload.inputSemanticTypeId)),
					represented
				], position);
			case BoxRuntimeClassThrowCarrier:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
			case _:
				return controlPlanInvariant('throw decision "${decision.id}" selected unsupported payload conversion ${selectedPayload.conversion}', position);
		}
		final tags = OcamlExpr.EList(decision.runtimeTags.map(tag -> OcamlExpr.EConst(OcamlConst.CString(tag))));
		return switch (decision.mechanism) {
			case RuntimeTypedHaxeExceptionSignal:
				buildAuthorizedThrowSignal(decision, payload, tags, position);
			case _:
				controlPlanInvariant('throw decision "${decision.id}" selected unsupported target mechanism ${decision.mechanism}', position);
		}
	}

	/**
		Builds one planned throw call after checking its exact private-runtime owner.

		The payload can contain calls owned by other plans. This helper checks only
		the `HxType` name introduced for this throw. The request-wide final check then
		verifies that the completed target tree contains the same occurrence once.
	**/
	function buildAuthorizedThrowSignal(decision:OcamlControlDecision, payload:OcamlExpr, tags:OcamlExpr, position:Position):OcamlExpr {
		return try {
			final runtimeUsePlan = OcamlThrowRuntimeUseContract.forDecision(decision);
			OcamlThrowRuntimeUseContract.requireForDecision(decision, runtimeUsePlan);
			final occurrence = OcamlThrowRuntimeUseContract.signalOccurrence(runtimeUsePlan);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final authority = new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile,
				ctx.runtimeRequirementsByIds(runtimeUsePlan.runtimeRequirementIds), [occurrence], ctx.finalRuntimeUses);
			final signal = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
			final expression = OcamlExpr.EApp(signal, [payload, tags]);
			authority.reconcileExpression(OcamlExpr.EApp(signal, [
				OcamlExpr.EIdent("throw_payload_owned_elsewhere"),
				OcamlExpr.EIdent("throw_tags_owned_by_control_plan")
			]));
			expression;
		} catch (error:Dynamic) {
			controlPlanInvariant(Std.string(error), position);
		}
	}

	/**
		Builds one payload conversion call selected by the sealed throw decision.

		The source expression passed as an argument has a different owner. The proof
		expression therefore uses placeholders for arguments and checks only the
		private runtime name introduced at this boundary.
	**/
	function buildAuthorizedThrowPayloadHelper(decision:OcamlControlDecision, role:OcamlThrowRuntimeUseRole, arguments:Array<OcamlExpr>,
			position:Position):OcamlExpr {
		return try {
			final runtimeUsePlan = OcamlThrowRuntimeUseContract.forDecision(decision);
			OcamlThrowRuntimeUseContract.requireForDecision(decision, runtimeUsePlan);
			final occurrence = OcamlThrowRuntimeUseContract.payloadOccurrence(runtimeUsePlan, role);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final authority = new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile,
				ctx.runtimeRequirementsByIds(runtimeUsePlan.runtimeRequirementIds), [occurrence], ctx.finalRuntimeUses);
			final helper = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
			final expression = OcamlExpr.EApp(helper, arguments);
			final proofArguments = [
				for (index in 0...arguments.length)
					OcamlExpr.EIdent('throw_payload_argument_${index}_owned_elsewhere')
			];
			authority.reconcileExpression(OcamlExpr.EApp(helper, proofArguments));
			expression;
		} catch (error:Dynamic) {
			controlPlanInvariant(Std.string(error), position);
		}
	}

	/**
		Materializes one source-ordered catch chain from its sealed typed record.

		The clause tag, payload conversion, incoming channels, unmatched behavior,
		and compiler-private control policy are already fixed. This function only
		constructs the corresponding OCaml expressions.
	**/
	function buildPlannedCatchChain(chain:OcamlCatchChainDecision, tryExpression:TypedExpr, catches:Array<{v:TVar, expr:TypedExpr}>,
			position:Position):OcamlExpr {
		try {
			OcamlControlPlan.requireCatchChain(chain);
		} catch (error:Dynamic) {
			return controlPlanInvariant(Std.string(error), position);
		}
		final binding = currentFunctionPlanBinding;
		if (binding == null
			|| chain.functionId != binding.functionId
			|| chain.programRevision != binding.programRevision
			|| chain.bodyRevision != binding.bodyRevision
			|| chain.pipelineRevision != binding.pipelineRevision) {
			return controlPlanInvariant('catch chain "${chain.id}" does not belong to the function currently building syntax', position);
		}
		if (chain.clauses.length != catches.length)
			return controlPlanInvariant('catch chain "${chain.id}" has ${chain.clauses.length} clauses, but the typed try has ${catches.length}', position);
		final runtimeUsePlan = try {
			final selected = OcamlCatchRuntimeUseContract.forChain(chain);
			OcamlCatchRuntimeUseContract.requireForChain(chain, selected);
			selected;
		} catch (error:Dynamic) {
			return controlPlanInvariant(Std.string(error), position);
		}
		final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
		final runtimeAuthority = try {
			new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile, ctx.runtimeRequirementsByIds(runtimeUsePlan.runtimeRequirementIds),
				runtimeUsePlan.runtimeUseOccurrences, ctx.finalRuntimeUses);
		} catch (error:Dynamic) {
			return controlPlanInvariant(Std.string(error), position);
		}
		final originalTagFunctions:Map<String, OcamlExpr> = [];
		final tagProofsByClause:Array<Array<OcamlExpr>> = [for (_ in chain.clauses) []];

		final syntax:Array<{variableName:String, variableType:OcamlTypeExpr, body:OcamlExpr}> = [];
		for (index in 0...catches.length) {
			final entry = catches[index];
			final clause = chain.clauses[index];
			if (clause.order != index || clause.variableName != entry.v.name)
				return controlPlanInvariant('catch chain "${chain.id}" clause $index no longer matches typed variable "${entry.v.name}"', position);
			final variableName = renameVar(entry.v.name);
			syntax.push({
				variableName: variableName,
				variableType: typeExprFromHaxeType(entry.v.t),
				body: applyCatchBranchResultPolicy(clause.bodyResultPolicy, buildExpr(entry.expr), clause.id, position)
			});
		}

		function runtimeTagTest(clause:OcamlCatchClauseDecision, clauseIndex:Int, role:OcamlCatchRuntimeTagUseRole, tagsExpression:OcamlExpr,
				runtimeTag:String, copyForNativeChannel:Bool):OcamlExpr {
			final occurrence = OcamlCatchRuntimeUseContract.runtimeTagOccurrence(runtimeUsePlan, clause.id, role);
			final key = occurrence.id;
			final runtimeFunction = if (copyForNativeChannel) {
				final original = originalTagFunctions.get(key);
				if (original == null)
					return controlPlanInvariant('catch clause "${clause.id}" has no original runtime-tag use for role "$role"', position);
				original;
			} else {
				final selected = OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(occurrence.id, runtimeUsePlan.planRevision,
					occurrence.exactSymbol));
				originalTagFunctions.set(key, selected);
				tagProofsByClause[clauseIndex].push(selected);
				selected;
			}
			return OcamlExpr.EApp(runtimeFunction, [tagsExpression, OcamlExpr.EConst(OcamlConst.CString(runtimeTag))]);
		}

		function buildChain(valueExpression:OcamlExpr, tagsExpression:OcamlExpr, fallback:OcamlExpr, copyForNativeChannel:Bool):OcamlExpr {
			var current = fallback;
			for (offset in 0...chain.clauses.length) {
				final index = chain.clauses.length - 1 - offset;
				final clause = chain.clauses[index];
				final entry = syntax[index];
				final condition = switch (clause.matchPolicy) {
					case ExactRuntimeTag:
						final runtimeTag = clause.runtimeTag;
						if (runtimeTag == null)
							return controlPlanInvariant('exact catch clause "${clause.id}" has no sealed runtime tag', position);
						runtimeTagTest(clause, index, OcamlCatchRuntimeTagUseRole.MatchExactRuntimeTag, tagsExpression, runtimeTag, copyForNativeChannel);
					case MatchAll:
						OcamlExpr.EConst(OcamlConst.CBool(true));
					case MatchHaxeException:
						OcamlExpr.EConst(OcamlConst.CBool(true));
					case MatchHaxeValueException:
						final isValueException = runtimeTagTest(clause, index, OcamlCatchRuntimeTagUseRole.MatchValueException, tagsExpression,
							"haxe.ValueException", copyForNativeChannel);
						final isAnyException = runtimeTagTest(clause, index, OcamlCatchRuntimeTagUseRole.MatchAnyException, tagsExpression, "haxe.Exception",
							copyForNativeChannel);
						OcamlExpr.EBinop(OcamlBinop.Or, isValueException, OcamlExpr.EUnop(OcamlUnop.Not, isAnyException));
				};
				final boundValue = switch (clause.conversion) {
					case RecoverExactValue:
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [valueExpression]);
					case RecoverCheckedBool:
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [valueExpression]);
					case RecoverNominalValue:
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [valueExpression]);
					case RecoverEnumValue:
						final runtimeTag = clause.runtimeTag;
						if (runtimeTag == null)
							return controlPlanInvariant('enum catch clause "${clause.id}" has no sealed runtime tag', position);
						final unboxed = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "unbox_or_obj"),
							[OcamlExpr.EConst(OcamlConst.CString(runtimeTag)), valueExpression]);
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [unboxed]);
					case RecoverRuntimeClassValue:
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [valueExpression]);
					case PreserveDynamicCarrier:
						valueExpression;
					case PreserveOrWrapHaxeException:
						final isAnyException = runtimeTagTest(clause, index, OcamlCatchRuntimeTagUseRole.ConvertAnyException, tagsExpression,
							"haxe.Exception", copyForNativeChannel);
						final asException = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [valueExpression]);
						final nullPrevious = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "magic"),
							[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);
						final wrapped = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "magic"), [
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Haxe_ValueException"), "create"),
								[valueExpression, nullPrevious, valueExpression])
						]);
						OcamlExpr.EIf(isAnyException, asException, wrapped);
					case PreserveOrWrapHaxeValueException:
						final isValueException = runtimeTagTest(clause, index, OcamlCatchRuntimeTagUseRole.ConvertValueException, tagsExpression,
							"haxe.ValueException", copyForNativeChannel);
						final asValueException = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [valueExpression]);
						final nullPrevious = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "magic"),
							[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);
						final wrapped = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Haxe_ValueException"), "create"),
							[valueExpression, nullPrevious, valueExpression]);
						OcamlExpr.EIf(isValueException, asValueException, wrapped);
				};
				final annotated = OcamlExpr.EAnnot(boundValue, entry.variableType);
				final body = OcamlExpr.ELet(entry.variableName, annotated, OcamlExpr.ESeq([
					OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.EIdent(entry.variableName)]),
					entry.body
				]), false);
				current = OcamlExpr.EIf(condition, body, current);
			}
			return current;
		}

		final privateControlCases:Array<OcamlMatchCase> = switch (chain.privateControlPolicy) {
			case PropagatePrivateControlSignals:
				final returnVariable = freshTmp("ret");
				final breakPattern = OcamlCatchRuntimeUseContract.privateControlOccurrence(runtimeUsePlan,
					OcamlCatchRuntimeUseContract.PRIVATE_BREAK_PATTERN_ROLE);
				final breakReraise = OcamlCatchRuntimeUseContract.privateControlOccurrence(runtimeUsePlan,
					OcamlCatchRuntimeUseContract.PRIVATE_BREAK_RERAISE_ROLE);
				final continuePattern = OcamlCatchRuntimeUseContract.privateControlOccurrence(runtimeUsePlan,
					OcamlCatchRuntimeUseContract.PRIVATE_CONTINUE_PATTERN_ROLE);
				final continueReraise = OcamlCatchRuntimeUseContract.privateControlOccurrence(runtimeUsePlan,
					OcamlCatchRuntimeUseContract.PRIVATE_CONTINUE_RERAISE_ROLE);
				final returnPattern = OcamlCatchRuntimeUseContract.privateControlOccurrence(runtimeUsePlan,
					OcamlCatchRuntimeUseContract.PRIVATE_RETURN_PATTERN_ROLE);
				final returnReraise = OcamlCatchRuntimeUseContract.privateControlOccurrence(runtimeUsePlan,
					OcamlCatchRuntimeUseContract.PRIVATE_RETURN_RERAISE_ROLE);
				final voidReturnPattern = OcamlCatchRuntimeUseContract.privateControlOccurrence(runtimeUsePlan,
					OcamlCatchRuntimeUseContract.PRIVATE_VOID_RETURN_PATTERN_ROLE);
				final voidReturnReraise = OcamlCatchRuntimeUseContract.privateControlOccurrence(runtimeUsePlan,
					OcamlCatchRuntimeUseContract.PRIVATE_VOID_RETURN_RERAISE_ROLE);
				[
					{
						pat: OcamlPat.PRuntimeConstructor(runtimeAuthority.patternIdentifier(breakPattern.id, runtimeUsePlan.planRevision,
							breakPattern.exactSymbol), []),
						guard: null,
						expr: OcamlExpr.ERaise(OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(breakReraise.id, runtimeUsePlan.planRevision,
							breakReraise.exactSymbol)))
					},
					{
						pat: OcamlPat.PRuntimeConstructor(runtimeAuthority.patternIdentifier(continuePattern.id, runtimeUsePlan.planRevision,
							continuePattern.exactSymbol), []),
						guard: null,
						expr: OcamlExpr.ERaise(OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(continueReraise.id, runtimeUsePlan.planRevision,
							continueReraise.exactSymbol)))
					},
					{
						pat: OcamlPat.PRuntimeConstructor(runtimeAuthority.patternIdentifier(returnPattern.id, runtimeUsePlan.planRevision,
							returnPattern.exactSymbol),
							[OcamlPat.PVar(returnVariable)]),
						guard: null,
						expr: OcamlExpr.ERaise(OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(returnReraise.id,
							runtimeUsePlan.planRevision, returnReraise.exactSymbol)),
							[OcamlExpr.EIdent(returnVariable)]))
					},
					{
						pat: OcamlPat.PRuntimeConstructor(runtimeAuthority.patternIdentifier(voidReturnPattern.id, runtimeUsePlan.planRevision,
							voidReturnPattern.exactSymbol), []),
						guard: null,
						expr: OcamlExpr.ERaise(OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(voidReturnReraise.id,
							runtimeUsePlan.planRevision, voidReturnReraise.exactSymbol)))
					}
				];
		};

		final haxeValueVariable = freshTmp("exn_v");
		final haxeTagsVariable = freshTmp("exn_tags");
		final haxeFallback = switch (chain.haxeUnmatchedPolicy) {
			case RethrowHaxeExceptionSignal:
				final occurrence = OcamlCatchRuntimeUseContract.rethrowOccurrence(runtimeUsePlan);
				OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(occurrence.id, runtimeUsePlan.planRevision,
					occurrence.exactSymbol)),
					[OcamlExpr.EIdent(haxeValueVariable), OcamlExpr.EIdent(haxeTagsVariable)]);
			case _:
				return controlPlanInvariant('catch chain "${chain.id}" selected invalid Haxe unmatched policy ${chain.haxeUnmatchedPolicy}', position);
		};
		final haxeHandler = buildChain(OcamlExpr.EIdent(haxeValueVariable), OcamlExpr.EIdent(haxeTagsVariable), haxeFallback, false);
		final patternOccurrence = OcamlCatchRuntimeUseContract.patternOccurrence(runtimeUsePlan);
		final haxeCase:OcamlMatchCase = {
			pat: OcamlPat.PRuntimeConstructor(runtimeAuthority.patternIdentifier(patternOccurrence.id, runtimeUsePlan.planRevision,
				patternOccurrence.exactSymbol),
				[OcamlPat.PVar(haxeValueVariable), OcamlPat.PVar(haxeTagsVariable)]),
			guard: null,
			expr: haxeHandler
		};
		try {
			// This small tree contains only the names owned by this catch plan.
			// Catch bodies can carry references owned by other plans, so their local
			// checks stay separate. The projection retains source clause order for tag
			// tests. Final output checking still walks the complete returned try
			// expression and proves that these exact IDs survived.
			final tagProofs:Array<OcamlExpr> = [];
			for (clauseProofs in tagProofsByClause)
				for (proof in clauseProofs)
					tagProofs.push(proof);
			tagProofs.push(haxeFallback);
			final proofCases = privateControlCases.concat([{pat: haxeCase.pat, guard: null, expr: OcamlExpr.ESeq(tagProofs)}]);
			runtimeAuthority.reconcileExpression(OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), proofCases));
		} catch (error:Dynamic) {
			return controlPlanInvariant(Std.string(error), position);
		}

		final nativeExceptionVariable = freshTmp("exn");
		final nativeFallback = switch (chain.targetNativeUnmatchedPolicy) {
			case ReraiseTargetNativeException:
				OcamlExpr.ERaise(OcamlExpr.EIdent(nativeExceptionVariable));
			case _:
				return controlPlanInvariant('catch chain "${chain.id}" selected invalid target-native unmatched policy ${chain.targetNativeUnmatchedPolicy}',
					position);
		};
		final nativeTags = OcamlExpr.EList(chain.targetNativeRuntimeTags.map(tag -> OcamlExpr.EConst(OcamlConst.CString(tag))));
		// One catch body is emitted for Haxe-wrapped exceptions and again for native
		// OCaml exceptions. The chain ID keeps nested copies distinct, so each emitted
		// private runtime name has one permission and one final output location.
		final nativeHandler = ctx.finalRuntimeUses.copyExpressionForOutput(buildChain(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"),
			[OcamlExpr.EIdent(nativeExceptionVariable)]), nativeTags, nativeFallback, true),
			"target-native-catch-channel:"
			+ chain.id, ctx.activateStagedTypeRuntimeUse);
		final nativeCase:OcamlMatchCase = {
			pat: OcamlPat.PVar(nativeExceptionVariable),
			guard: null,
			expr: nativeHandler
		};

		final builtTry = applyCatchBranchResultPolicy(chain.tryBodyResultPolicy, buildExpr(tryExpression), chain.id, position);
		return OcamlExpr.ETry(builtTry, privateControlCases.concat([haxeCase, nativeCase]));
	}

	function applyCatchBranchResultPolicy(policy:OcamlCatchBranchResultPolicy, expression:OcamlExpr, ownerId:String, position:Position):OcamlExpr {
		return switch (policy) {
			case PreserveTypedResult:
				expression;
			case DiscardCompletedValueToUnit:
				OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [expression]);
			case _:
				controlPlanInvariant('catch result policy for "$ownerId" is unsupported: $policy', position);
		}
	}

	/** Builds checked catch patterns for the exact signals used by one sealed loop. */
	function buildPlannedLoopControlCases(target:OcamlControlLoopTarget, decisions:Array<OcamlControlDecision>, position:Position):OcamlLoopControlCases {
		return try {
			final runtimeUsePlan = OcamlLoopRuntimeUseContract.forTarget(target, decisions);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final authority = new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile,
				ctx.runtimeRequirementsByIds(runtimeUsePlan.runtimeRequirementIds), runtimeUsePlan.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final breakCase = loopPatternCase(runtimeUsePlan, authority, OcamlControlTransferKind.Break);
			final continueCase = loopPatternCase(runtimeUsePlan, authority, OcamlControlTransferKind.Continue);
			final references:Array<OcamlMatchCase> = [];
			if (continueCase != null)
				references.push(continueCase);
			if (breakCase != null)
				references.push(breakCase);
			authority.reconcileExpression(OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), references));
			{breakCase: breakCase, continueCase: continueCase};
		} catch (error:Dynamic) {
			controlPlanInvariant(Std.string(error), position);
		}
	}

	function loopPatternCase(plan:OcamlLoopTargetRuntimeUsePlan, authority:OcamlRuntimeUseAuthority, kind:OcamlControlTransferKind):Null<OcamlMatchCase> {
		if (!Lambda.exists(plan.runtimeUseOccurrences, occurrence -> occurrence.exactSymbol == OcamlLoopRuntimeUseContract.signalSymbol(kind)))
			return null;
		final occurrence = OcamlLoopRuntimeUseContract.patternOccurrence(plan, kind);
		return {
			pat: OcamlPat.PRuntimeConstructor(authority.patternIdentifier(occurrence.id, plan.planRevision, occurrence.exactSymbol), []),
			guard: null,
			expr: OcamlExpr.EConst(OcamlConst.CUnit)
		};
	}

	/** Raises one sealed break or continue after checking its lexical target. */
	function buildPlannedLoopTransfer(decision:OcamlControlDecision, expectedKind:OcamlControlTransferKind, position:Position):OcamlExpr {
		try {
			OcamlControlPlan.requireDecision(decision);
		} catch (error:Dynamic) {
			return controlPlanInvariant(Std.string(error), position);
		}
		if (decision.kind != expectedKind || decision.targetKind != OcamlControlTargetKind.Loop)
			return controlPlanInvariant('control decision "${decision.id}" does not represent the expected $expectedKind loop transfer', position);
		if (currentLoopTargetIds.length == 0)
			return controlPlanInvariant('control decision "${decision.id}" reached syntax without an active sealed loop target', position);
		final currentTargetId = currentLoopTargetIds[currentLoopTargetIds.length - 1];
		if (decision.targetId != currentTargetId)
			return
				controlPlanInvariant('control decision "${decision.id}" targets loop "${decision.targetId}" while syntax is building innermost loop "$currentTargetId"',
					position);
		return try {
			final runtimeUsePlan = OcamlLoopRuntimeUseContract.forDecision(decision);
			final occurrence = OcamlLoopRuntimeUseContract.signalOccurrence(runtimeUsePlan);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final authority = new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile,
				ctx.runtimeRequirementsByIds(runtimeUsePlan.runtimeRequirementIds), runtimeUsePlan.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final signal = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(occurrence.id, runtimeUsePlan.planRevision, occurrence.exactSymbol));
			authority.reconcileExpression(signal);
			OcamlExpr.ERaise(signal);
		} catch (error:Dynamic) {
			controlPlanInvariant(Std.string(error), position);
		}
	}

	/**
		Materializes one sealed typed call in its Haxe source order.

		A computed function value is bound before its arguments. Every supplied or
		omitted argument is then bound before invocation, so runtime order does not
		depend on OCaml function-application behavior.
	**/
	function buildPlannedCall(call:OcamlCallDecision, callee:Null<TypedExpr>, arguments:Array<TypedExpr>, position:Position):OcamlExpr {
		try {
			OcamlCallPlan.requireCall(call);
			if (call.kind == OcamlCallKind.DynamicFunctionValue)
				return buildPlannedDynamicFunctionCall(call, callee, arguments, position);
			if (call.kind == OcamlCallKind.StandardArrayMethod)
				return buildPlannedStandardArrayCall(call, callee, arguments, position);
			if (call.kind == OcamlCallKind.StandardIMapMethod)
				return callPlanInvariant('obsolete standard IMap call "${call.id}" reached syntax after the interface-adapter hard cut', position);
			if (call.kind == OcamlCallKind.StructuralIteratorMethod)
				return buildPlannedStructuralIteratorCall(call, callee, arguments, position);
			if (call.kind != OcamlCallKind.TypedFunctionValue)
				functionPlanRegistry.requireCallableDeclaration(call);
		} catch (error:Dynamic) {
			return callPlanInvariant(Std.string(error), position);
		}
		final suppliedArgumentCount = call.arguments.filter(argument -> !OcamlCallPlan.isOmittedConversion(argument.conversion)).length;
		if (arguments.length != suppliedArgumentCount)
			return
				callPlanInvariant('call "${call.id}" has ${arguments.length} source arguments but its sealed plan expects $suppliedArgumentCount supplied arguments',
					position);

		var target:Null<OcamlExpr> = switch (call.kind) {
			case OcamlCallKind.DirectStaticHaxeMethod,
				OcamlCallKind.DirectInstanceHaxeMethod: final moduleName = moduleIdToOcamlModuleName(call.sourceModuleId); final selfModule = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId); final targetName = ctx.scopedValueName(call.sourceModuleId,
					call.sourceTypeName,
					call.sourceFieldName); selfModule != null && selfModule == moduleName ? OcamlExpr.EIdent(targetName) : OcamlExpr.EField(OcamlExpr.EIdent(moduleName),
					targetName);
			case OcamlCallKind.DirectHaxeConstructor: final moduleName = moduleIdToOcamlModuleName(call.sourceModuleId); final selfModule = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId); final targetName = ctx.scopedValueName(call.sourceModuleId,
					call.sourceTypeName,
					"create"); selfModule != null && selfModule == moduleName ? OcamlExpr.EIdent(targetName) : OcamlExpr.EField(OcamlExpr.EIdent(moduleName),
					targetName);
			case OcamlCallKind.TypedFunctionValue:
				null;
			case OcamlCallKind.DynamicFunctionValue:
				return callPlanInvariant('Dynamic function call "${call.id}" bypassed its specialized sealed target', position);
			case OcamlCallKind.StandardArrayMethod:
				return callPlanInvariant('standard Array call "${call.id}" bypassed its specialized sealed target', position);
			case OcamlCallKind.StandardIMapMethod:
				return callPlanInvariant('standard IMap call "${call.id}" bypassed its specialized sealed target', position);
			case OcamlCallKind.StructuralIteratorMethod:
				return callPlanInvariant('structural Iterator call "${call.id}" bypassed its specialized sealed target', position);
		};
		final materialized:Array<{name:String, value:OcamlExpr}> = [];
		final applicationArguments:Array<OcamlExpr> = [];
		var invocationSeen = false;
		for (step in call.evaluationSchedule) {
			switch (step.kind) {
				case OcamlCallEvaluationStepKind.MaterializeCallee:
					if (call.kind != OcamlCallKind.TypedFunctionValue || callee == null || target != null || step.slotId == null)
						return callPlanInvariant('call "${call.id}" has an invalid callee materialization step', position);
					final name = freshTmp("call_callee");
					materialized.push({name: name, value: buildExpr(callee)});
					target = OcamlExpr.EIdent(name);
				case OcamlCallEvaluationStepKind.MaterializeReceiver:
					if (callee == null)
						return callPlanInvariant('call "${call.id}" has no typed instance receiver occurrence', position);
					final receiver = switch (callee.expr) {
						case TField(receiverExpression, FInstance(_, _, _)):
							receiverExpression;
						case _:
							return callPlanInvariant('call "${call.id}" has no typed instance receiver occurrence', position);
					}
					if (call.kind != OcamlCallKind.DirectInstanceHaxeMethod || call.receiver == null || step.slotId == null)
						return callPlanInvariant('call "${call.id}" has an invalid receiver materialization step', position);
					requireCallValue(call.receiver, -2, 'call receiver', receiver.pos);
					final name = freshTmp("call_receiver");
					materialized.push({name: name, value: buildExpr(receiver)});
					applicationArguments.push(OcamlExpr.EIdent(name));
				case OcamlCallEvaluationStepKind.MaterializeArgument:
					final argumentIndex = step.argumentIndex;
					final sourceArgumentIndex = step.sourceArgumentIndex;
					if (argumentIndex == null
						|| argumentIndex < 0
						|| argumentIndex >= call.arguments.length
						|| sourceArgumentIndex == null
						|| sourceArgumentIndex < 0
						|| sourceArgumentIndex >= arguments.length
						|| step.slotId == null)
						return callPlanInvariant('call "${call.id}" has an invalid materialization step', position);
					final name = freshTmp("call_arg_" + argumentIndex);
					materialized.push({
						name: name,
						value: buildPlannedCallArgument(call, call.arguments[argumentIndex], arguments[sourceArgumentIndex])
					});
					applicationArguments.push(OcamlExpr.EIdent(name));
				case OcamlCallEvaluationStepKind.MaterializeOmittedArgument:
					final argumentIndex = step.argumentIndex;
					if (argumentIndex == null
						|| argumentIndex < 0
						|| argumentIndex >= call.arguments.length
						|| step.sourceArgumentIndex != null
						|| step.slotId == null)
						return callPlanInvariant('call "${call.id}" has an invalid omitted-argument materialization step', position);
					final name = freshTmp("call_arg_" + argumentIndex);
					materialized.push({
						name: name,
						value: buildPlannedOmittedArgument(call.id, call.arguments[argumentIndex], position)
					});
					applicationArguments.push(OcamlExpr.EIdent(name));
				case OcamlCallEvaluationStepKind.InvokeCallee:
					if (invocationSeen || target == null)
						return callPlanInvariant('call "${call.id}" invokes its callee more than once', position);
					invocationSeen = true;
			}
		}
		final expectedMaterializations = call.arguments.length
			+ (call.kind == OcamlCallKind.TypedFunctionValue ? 1 : 0)
			+ (call.kind == OcamlCallKind.DirectInstanceHaxeMethod ? 1 : 0);
		if (!invocationSeen || target == null || materialized.length != expectedMaterializations)
			return callPlanInvariant('call "${call.id}" did not materialize every callable parameter before invocation', position);
		final targetArguments = applicationArguments.copy();
		if (call.arguments.length == 0)
			targetArguments.push(OcamlExpr.EConst(OcamlConst.CUnit));
		var out = OcamlExpr.EApp(target, targetArguments);
		for (offset in 0...materialized.length) {
			final binding = materialized[materialized.length - 1 - offset];
			out = OcamlExpr.ELet(binding.name, binding.value, out, false);
		}
		return out;
	}

	/**
		Invokes one sealed `Dynamic` callee in Haxe evaluation order.

		The outer binding evaluates the callee once. The inner sequence then
		evaluates each argument once from left to right before the runtime call.
	**/
	function buildPlannedDynamicFunctionCall(call:OcamlCallDecision, callee:Null<TypedExpr>, arguments:Array<TypedExpr>, position:Position):OcamlExpr {
		final target = call.dynamicFunctionTarget;
		if (target == null)
			return callPlanInvariant('Dynamic function call "${call.id}" has no sealed target', position);
		if (callee == null)
			return callPlanInvariant('Dynamic function call "${call.id}" has no typed callee occurrence', position);
		// The call-plan lookup already checked the call's result type. This local
		// check protects the callee and arguments used by this specialized builder.
		if (!OcamlCallPlanner.matchesDynamicFunctionInputs(target, callee, arguments))
			return callPlanInvariant('Dynamic function call "${call.id}" disagrees with its final typed occurrence', position);
		final callPlan = currentCallPlan;
		if (callPlan == null)
			return callPlanInvariant('Dynamic function call "${call.id}" reached syntax without its sealed call inventory', position);
		final runtimeUsePlan = callPlan.runtimeUsePlanFor(call.id);
		if (runtimeUsePlan == null)
			return callPlanInvariant('Dynamic function call "${call.id}" has no exact runtime-use plan', position);

		return try {
			OcamlCallRuntimeUseContract.requireForCall(call, runtimeUsePlan);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final authority = new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile,
				ctx.runtimeRequirementsByIds(runtimeUsePlan.runtimeRequirementIds), runtimeUsePlan.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final runtimeIdentifiers:Array<OcamlExpr> = [];
			function runtimeIdentifier(role:String):OcamlExpr {
				final occurrence = OcamlCallRuntimeUseContract.occurrenceForDynamicCallRole(runtimeUsePlan, role);
				final expression = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
				runtimeIdentifiers.push(expression);
				return expression;
			}

			final createFunction = runtimeIdentifier("dynamic-call-argument-array-create");
			final pushFunctions = [
				for (index in 0...arguments.length)
					runtimeIdentifier('dynamic-call-argument-push:$index')
			];
			final invokeFunction = runtimeIdentifier("dynamic-call-invoke");
			final nullReceiver = runtimeIdentifier("dynamic-call-null-receiver");
			// Nested argument expressions can own other private runtime calls. Check
			// this call's identifiers in isolation before placing those expressions.
			authority.reconcileExpression(OcamlExpr.ESeq(runtimeIdentifiers));

			final calleeName = freshTmp("dynamic_callee");
			final argumentsName = freshTmp("dynamic_args");
			final sequence:Array<OcamlExpr> = [];
			for (index in 0...arguments.length) {
				sequence.push(OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [
					OcamlExpr.EApp(pushFunctions[index], [
						OcamlExpr.EIdent(argumentsName),
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(arguments[index])])
					])
				]));
			}
			final callObject = OcamlExpr.EApp(invokeFunction, [
				nullReceiver,
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EIdent(calleeName)]),
				OcamlExpr.EIdent(argumentsName)
			]);
			final callValue = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [callObject]);
			if (target.resultKind == OcamlCallResultKind.EffectOnlyVoid) {
				sequence.push(OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [callValue]));
				sequence.push(OcamlExpr.EConst(OcamlConst.CUnit));
			} else {
				sequence.push(callValue);
			}
			OcamlExpr.ELet(calleeName, buildExpr(callee),
				OcamlExpr.ELet(argumentsName, OcamlExpr.EApp(createFunction, [OcamlExpr.EConst(OcamlConst.CUnit)]), OcamlExpr.ESeq(sequence), false), false);
		} catch (error:Dynamic) {
			callPlanInvariant(Std.string(error), position);
		}
	}

	/**
		Renders one standard Array call from its sealed typed target.

		A source call such as `makeArray().concat(makeMore())` evaluates the
		receiver once, then each argument once in source order. The private
		`HxArray` function is available only through this call's runtime-use record.
	**/
	function buildPlannedStandardArrayCall(call:OcamlCallDecision, callee:Null<TypedExpr>, arguments:Array<TypedExpr>, position:Position):OcamlExpr {
		final target = call.standardArrayTarget;
		if (target == null)
			return callPlanInvariant('standard Array call "${call.id}" has no sealed target', position);
		final callPlan = currentCallPlan;
		if (callPlan == null)
			return callPlanInvariant('standard Array call "${call.id}" reached syntax without its sealed call inventory', position);
		final runtimeUsePlan = callPlan.runtimeUsePlanFor(call.id);
		if (runtimeUsePlan == null)
			return callPlanInvariant('standard Array call "${call.id}" has no exact runtime-use plan', position);
		if (callee == null)
			return callPlanInvariant('standard Array call "${call.id}" has no typed receiver occurrence', position);
		final typedField = switch (callee.expr) {
			case TField(receiverExpression, FInstance(classRef, parameters, fieldRef)):
				{
					receiver: receiverExpression,
					classType: classRef.get(),
					parameters: parameters,
					field: fieldRef.get()
				};
			case _:
				return callPlanInvariant('standard Array call "${call.id}" no longer matches an instance field', position);
		}
		final resultType = switch (callee.t) {
			case TFun(_, result): result;
			case _:
				return callPlanInvariant('standard Array call "${call.id}" no longer has a callable field type', position);
		}
		if (!OcamlStandardArrayCallContract.matches(target, typedField.classType, typedField.parameters, typedField.field, typedField.receiver, arguments,
			resultType)) {
			return callPlanInvariant('standard Array call "${call.id}" disagrees with its final typed occurrence', position);
		}

		try {
			OcamlCallRuntimeUseContract.requireForCall(call, runtimeUsePlan);
			final occurrence = OcamlCallRuntimeUseContract.occurrenceForStandardArray(runtimeUsePlan);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			final authority = new OcamlRuntimeUseAuthority(runtimeUsePlan.planRevision, activeProfile,
				ctx.runtimeRequirementsByIds([occurrence.requirementId]), [occurrence], ctx.finalRuntimeUses);
			final runtimeFunction = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
			// Receiver and argument expressions may contain private calls owned by
			// other plans, so reconcile only the identifier introduced here.
			authority.reconcileExpression(runtimeFunction);
			final materialized:Array<{name:String, value:OcamlExpr}> = [];
			final receiverName = freshTmp("array_receiver");
			materialized.push({name: receiverName, value: buildExpr(typedField.receiver)});
			final applicationArguments:Array<OcamlExpr> = [OcamlExpr.EIdent(receiverName)];
			for (index in 0...arguments.length) {
				final argumentName = freshTmp('array_arg_$index');
				materialized.push({name: argumentName, value: buildExpr(arguments[index])});
				applicationArguments.push(OcamlExpr.EIdent(argumentName));
			}
			if (target.runtimeTakesUnitArgument)
				applicationArguments.push(OcamlExpr.EConst(OcamlConst.CUnit));
			var out = OcamlExpr.EApp(runtimeFunction, applicationArguments);
			for (offset in 0...materialized.length) {
				final binding = materialized[materialized.length - 1 - offset];
				out = OcamlExpr.ELet(binding.name, binding.value, out, false);
			}
			return out;
		} catch (error:Dynamic) {
			return callPlanInvariant(Std.string(error), position);
		}
	}

	/**
		Builds the comparator selected for one resolved standard function value.

		For example, contextual typing turns `names.sort(Reflect.compare)` into a
		String comparator before this builder runs. An explicit `Null<String>`
		context selects a separate null-aware String comparator. Both generated
		closures use only the target's String carrier; neither receives `Obj.t`
		values nor asks OCaml to compare arbitrary runtime objects.
	**/
	function buildPlannedReflectCompareFunction(decision:OcamlReflectCompareDecision, position:Position):OcamlExpr {
		try {
			OcamlReflectComparePlan.requireDecision(decision);
		} catch (error:Dynamic) {
			return callPlanInvariant(Std.string(error), position);
		}
		final binding:OcamlFunctionPlanBinding = {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		final runtimeAuthority = new OcamlRuntimeUseAuthority(planRevision, OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile),
			ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
		final leftName = freshTmp("reflect_left");
		final rightName = freshTmp("reflect_right");
		final left = OcamlExpr.EIdent(leftName);
		final right = OcamlExpr.EIdent(rightName);
		final ordered = OcamlExpr.EIf(OcamlExpr.EBinop(OcamlBinop.Lt, left, right), OcamlExpr.EConst(OcamlConst.CInt(-1)),
			OcamlExpr.EIf(OcamlExpr.EBinop(OcamlBinop.Gt, left, right), OcamlExpr.EConst(OcamlConst.CInt(1)), OcamlExpr.EConst(OcamlConst.CInt(0))));
		final parameterType = switch (decision.domain) {
			case Int: OcamlTypeExpr.TIdent("int");
			case Float: OcamlTypeExpr.TIdent("float");
			case String, NullableString: OcamlTypeExpr.TIdent("string");
		}
		final body = switch (decision.domain) {
			case Int:
				ordered;
			case Float:
				final leftNaN = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Float"), "is_nan"), [left]);
				final rightNaN = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Float"), "is_nan"), [right]);
				OcamlExpr.EIf(OcamlExpr.EBinop(OcamlBinop.Or, leftNaN, rightNaN),
					reflectCompareFailure("unordered-nan", runtimeAuthority, decision.runtimeUseOccurrences[0], planRevision), ordered);
			case String:
				final leftNull = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "isNull"), [left]);
				final rightNull = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "isNull"), [right]);
				final bothNull = OcamlExpr.EBinop(OcamlBinop.And, leftNull, rightNull);
				final oneNull = OcamlExpr.EBinop(OcamlBinop.Or, leftNull, rightNull);
				OcamlExpr.EIf(bothNull, OcamlExpr.EConst(OcamlConst.CInt(0)),
					OcamlExpr.EIf(oneNull, reflectCompareFailure("null-mismatch", runtimeAuthority, decision.runtimeUseOccurrences[0], planRevision), ordered));
			case NullableString:
				final leftNull = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "isNull"), [left]);
				final rightNull = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "isNull"), [right]);
				OcamlExpr.EIf(leftNull, OcamlExpr.EIf(rightNull, OcamlExpr.EConst(OcamlConst.CInt(0)), OcamlExpr.EConst(OcamlConst.CInt(-1))),
					OcamlExpr.EIf(rightNull, OcamlExpr.EConst(OcamlConst.CInt(1)), ordered));
		}
		final comparator = OcamlExpr.EFun([
			OcamlPat.PAnnot(OcamlPat.PVar(leftName), parameterType),
			OcamlPat.PAnnot(OcamlPat.PVar(rightName), parameterType)
		], body);
		runtimeAuthority.reconcileExpression(comparator);
		return comparator;
	}

	/**
		Builds the catchable Haxe error selected by one typed comparator.

		The supplied occurrence belongs to that exact comparator decision. The
		authority rejects a different helper name, owner, plan revision, or a second
		use before the structured expression can be printed.
	**/
	function reflectCompareFailure(reason:String, authority:OcamlRuntimeUseAuthority, use:OcamlRuntimeUseOccurrence, planRevision:String):OcamlExpr {
		final message = 'reflaxe.ocaml [ocaml-reflect-compare:$reason]';
		return OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, planRevision, use.exactSymbol)), [
			OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EConst(OcamlConst.CString(message))])
		]);
	}

	/** Evaluates both direct-call operands once, from left to right, then compares. */
	function buildPlannedReflectCompareCall(decision:OcamlReflectCompareDecision, arguments:Array<TypedExpr>, position:Position):OcamlExpr {
		if (arguments.length != 2)
			return callPlanInvariant('Reflect.compare plan "${decision.id}" expected two operands, received ${arguments.length}', position);
		final leftName = freshTmp("reflect_arg_0");
		final rightName = freshTmp("reflect_arg_1");
		final invoke = OcamlExpr.EApp(buildPlannedReflectCompareFunction(decision, position), [OcamlExpr.EIdent(leftName), OcamlExpr.EIdent(rightName)]);
		return OcamlExpr.ELet(leftName, buildExpr(arguments[0]), OcamlExpr.ELet(rightName, buildExpr(arguments[1]), invoke, false), false);
	}

	/**
		Returns the private helper authorized by one resolved standard Reflect call.

		This method checks the exact request-local typed call and the helper selected
		before syntax generation. It reconciles only the identifier introduced here;
		argument expressions keep the runtime-use authority of their own plans.
	**/
	function directReflectRuntimeFunction(call:TypedExpr, expectedKind:OcamlReflectRuntimeUseKind):OcamlExpr {
		final plan = currentReflectRuntimeUsePlan;
		if (plan == null)
			return callPlanInvariant("a direct standard Reflect call has no active sealed runtime-use plan", call.pos);
		final decision = try {
			plan.requireFor(call);
		} catch (error:Dynamic) {
			return callPlanInvariant(Std.string(error), call.pos);
		}
		if (decision.kind != expectedKind)
			return callPlanInvariant('Reflect decision "${decision.id}" selected ${decision.kind}, not $expectedKind', call.pos);
		final occurrence = decision.runtimeUseOccurrences[0];
		final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
		final authority = new OcamlRuntimeUseAuthority(decision.revision, activeProfile, ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds),
			decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
		final identifier = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
		try {
			authority.reconcileExpression(identifier);
		} catch (error:Dynamic) {
			return callPlanInvariant(Std.string(error), call.pos);
		}
		return identifier;
	}

	/**
		Renders one direct structural Iterator call from its sealed target.

		For input such as `iterator.next()`, this method evaluates `iterator` once
		and invokes the preselected `HxIterator.next` helper. It does not build an
		intermediate method closure or infer the operation again from a field name.
	**/
	function buildPlannedStructuralIteratorCall(call:OcamlCallDecision, callee:Null<TypedExpr>, arguments:Array<TypedExpr>, position:Position):OcamlExpr {
		final target = call.structuralIteratorTarget;
		if (target == null)
			return callPlanInvariant('structural Iterator call "${call.id}" has no sealed target', position);
		try {
			OcamlStructuralIteratorCallContract.require(target);
		} catch (error:Dynamic) {
			return callPlanInvariant(Std.string(error), position);
		}
		if (callee == null || arguments.length != 0)
			return callPlanInvariant('structural Iterator call "${call.id}" must have one typed receiver and no source arguments', position);
		final receiver = switch (callee.expr) {
			case TField(receiverExpression, FAnon(fieldRef)) if (fieldRef.get().name == OcamlStructuralIteratorCallContract.sourceFieldName(target.operation)):
				receiverExpression;
			case _:
				return callPlanInvariant('structural Iterator call "${call.id}" no longer matches its typed field occurrence', position);
		}
		if (!OcamlStructuralIteratorCallContract.matches(target, receiver, switch (callee.expr) {
			case TField(_, FAnon(fieldRef)): fieldRef.get();
			case _: return callPlanInvariant('structural Iterator call "${call.id}" lost its typed field', position);
		}, arguments, switch (callee.t) {
			case TFun(_, result): result;
			case _: return callPlanInvariant('structural Iterator call "${call.id}" no longer has a callable field type', position);
		})) {
			return callPlanInvariant('structural Iterator call "${call.id}" disagrees with its final typed occurrence', position);
		}

		final receiverStep = call.evaluationSchedule[0];
		final invocationStep = call.evaluationSchedule[1];
		if (receiverStep.kind != OcamlCallEvaluationStepKind.MaterializeReceiver
			|| receiverStep.slotId == null
			|| invocationStep.kind != OcamlCallEvaluationStepKind.InvokeCallee) {
			return callPlanInvariant('structural Iterator call "${call.id}" has an invalid receiver-first evaluation schedule', position);
		}
		final receiverName = freshTmp("iterator_receiver");
		final runtimeCall = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(target.runtimeModule), target.runtimeFunction), [OcamlExpr.EIdent(receiverName)]);
		return OcamlExpr.ELet(receiverName, buildExpr(receiver), runtimeCall, false);
	}

	/** Resolves one pre-emission static cell and rejects an unsafe late cross-type reference. */
	function requireStaticStorage(classType:ClassType, field:ClassField, position:Position):OcamlStaticStorageEntry {
		final storage = try {
			staticStoragePlan.require(classType.module, classType.name, field.name);
		} catch (error:Dynamic) {
			return placeLoweringInvariant(Std.string(error), position);
		}
		if (ctx.currentModuleId == classType.module
			&& ctx.currentTypeName != null
			&& ctx.currentTypeName != classType.name
			&& !staticStoragePlan.isVisibleFrom(classType.module, classType.name, field.name, ctx.currentModuleId, ctx.currentTypeName)) {
			return placeLoweringInvariant('same-module access to "${storage.key}" requires a carrier proven safe for declaration before both type fragments',
				position);
		}
		return storage;
	}

	/** Resolves an admitted local carrier without repeating target type policy. */
	function localCarrierType(localId:Int, type:Type, position:Position):OcamlTypeExpr {
		final decision = plannedLocalRepresentation(localId, position);
		if (decision == null)
			return typeExprFromHaxeType(type);
		if (OcamlMonomorphicClassMaterializer.isNominalClass(decision)) {
			if (ctx.currentModuleId == null)
				return localStorageInvariant('local $localId selected a nominal class carrier outside an OCaml module', position);
			return OcamlMonomorphicClassMaterializer.typeExpr(decision, moduleIdToOcamlModuleName(ctx.currentModuleId));
		}
		return OcamlTypeExpr.TIdent(decision.carrierTypeId);
	}

	/**
		Returns the representation plan attached to the active sealed function.

		Code outside a sealed function may use the legacy mapper. Once a function
		binding is active, however, losing its companion representation plan is an
		internal lifecycle error rather than permission to guess during syntax
		construction.
	**/
	function activeLocalRepresentationPlan(position:Position):Null<OcamlLocalRepresentationPlan> {
		if (currentLocalRepresentationPlan == null && currentLocalPlanBinding != null)
			return localStorageInvariant("sealed function reached syntax construction without its local representation plan", position);
		if (currentLocalRepresentationPlan != null && currentLocalPlanBinding == null)
			return localStorageInvariant("local representation plan reached syntax construction without its owning function binding", position);
		return currentLocalRepresentationPlan;
	}

	/**
		Resolves one local's sealed program representation, when it has migrated.

		An unmutated local with no choice intentionally stays on the legacy mapper.
		A local that has a storage decision must have a companion representation
		choice. Every present program decision resolves against the exact program
		revision before syntax can use it.
	**/
	function plannedLocalRepresentation(localId:Int, position:Position):Null<OcamlRepresentationDecision> {
		final binding = currentLocalPlanBinding;
		if (binding == null)
			return null;
		final localRepresentations = activeLocalRepresentationPlan(position);
		if (localRepresentations == null)
			return localStorageInvariant('local $localId reached syntax construction without a sealed representation plan', position);
		final stableId = stableLocalId(localId, position);
		final choice = localRepresentations.choiceFor(stableId);
		if (choice == null) {
			final storageDecision = currentLocalStoragePlan == null ? null : currentLocalStoragePlan.decisionFor(stableId);
			if (storageDecision != null)
				return localStorageInvariant('local $stableId has storage decision ${storageDecision.storage}, but no sealed representation choice', position);
			return null;
		}
		return switch (choice) {
			case Unmigrated(_):
				null;
			case ProgramDecision(representationId, representationRevision, semanticTypeId, domain):
				final decision = try {
					representationRegistry.require(representationId, binding.programRevision);
				} catch (error:Dynamic) {
					return localStorageInvariant(Std.string(error), position);
				}
				if (decision.revision != representationRevision
					|| decision.semanticTypeId != semanticTypeId
					|| decision.domain != domain) {
					return
						localStorageInvariant('local $stableId expects $representationId@$representationRevision for $semanticTypeId in representation domain $domain, but ${decision.id}@${decision.revision} selects ${decision.semanticTypeId} in ${decision.domain}',
						position);
				}
				decision;
		}
	}

	/**
		Resolves one exact occurrence-bound conversion from the sealed function plan.

		The caller supplies the typed input/output shape only to validate that the
		final body still matches its seal. The stored conversion remains the sole
		answer for whether syntax preserves, boxes, or checks the value.
	**/
	function requireLocalConversion(localId:Int, role:OcamlLocalConversionRole, expression:TypedExpr, inputSemanticTypeId:String, inputCarrierTypeId:String,
			outputSemanticTypeId:String, outputCarrierTypeId:String):OcamlLocalConversionDecision {
		final conversion = requireLocalConversionOccurrence(localId, role, expression);
		return requireLocalConversionShape(conversion, localId, expression, inputSemanticTypeId, inputCarrierTypeId, outputSemanticTypeId, outputCarrierTypeId);
	}

	/**
		Resolves one occurrence using only its sealed function, local, role, and source.

		Callers that already have a complete semantic plan, such as exact
		enum-to-Dynamic initialization, use this lookup so syntax does not
		reclassify the typed expression and make the same target decision again.
	**/
	function requireLocalConversionOccurrence(localId:Int, role:OcamlLocalConversionRole, expression:TypedExpr):OcamlLocalConversionDecision {
		final binding = currentLocalPlanBinding;
		if (binding == null)
			return localStorageInvariant('local $localId requires an occurrence conversion outside a sealed function body', expression.pos);
		final plan = activeLocalRepresentationPlan(expression.pos);
		if (plan == null)
			return localStorageInvariant('local $localId requires an occurrence conversion without a sealed representation plan', expression.pos);
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		final stableId = stableLocalId(localId, expression.pos);
		final conversion = plan.conversionFor(binding, stableId, role, source);
		if (conversion == null) {
			final occurrenceId = OcamlLocalRepresentationPlan.occurrenceId(binding, stableId, role, source);
			return localStorageInvariant('local $stableId has no sealed $role conversion for occurrence "$occurrenceId"', expression.pos);
		}
		return conversion;
	}

	/** Confirms that a typed occurrence still has the carriers named by its seal. */
	function requireLocalConversionShape(conversion:OcamlLocalConversionDecision, localId:Int, expression:TypedExpr, inputSemanticTypeId:String,
			inputCarrierTypeId:String, outputSemanticTypeId:String, outputCarrierTypeId:String):OcamlLocalConversionDecision {
		if (conversion.inputSemanticTypeId != inputSemanticTypeId
			|| conversion.inputCarrierTypeId != inputCarrierTypeId
			|| conversion.outputSemanticTypeId != outputSemanticTypeId
			|| conversion.outputCarrierTypeId != outputCarrierTypeId) {
			return
				localStorageInvariant('local ${conversion.localId} occurrence "${conversion.id}" expects ${conversion.inputSemanticTypeId}/${conversion.inputCarrierTypeId} -> ${conversion.outputSemanticTypeId}/${conversion.outputCarrierTypeId}, but the final typed occurrence is $inputSemanticTypeId/$inputCarrierTypeId -> $outputSemanticTypeId/$outputCarrierTypeId',
				expression.pos);
		}
		return conversion;
	}

	/**
		Builds one array element using its sealed carrier conversion, when present.

		The independent required-occurrence inventory distinguishes an intentionally
		excluded element from a missing decision. A required occurrence without its
		sealed conversion is an internal compiler error; an excluded element follows
		the ordinary expression path. Syntax never invents an enum name from an OCaml
		tag or rendered expression.
	**/
	function buildArrayLiteralElement(container:TypedExpr, item:TypedExpr, elementIndex:Int):OcamlExpr {
		final plan = currentContainerElementPlan;
		if (plan == null)
			return containerElementInvariant("array literal reached syntax without an exact container-element plan", container.pos);
		final conversion = switch (plan.syntaxLookup(container, elementIndex)) {
			case Unknown:
				return containerElementInvariant("typed array element is absent from the sealed request-local syntax lookup", item.pos);
			case Excluded:
				return buildExpr(item);
			case Required(id, null):
				return containerElementInvariant('required array element occurrence "$id" has no sealed conversion decision', item.pos);
			case Required(_, conversion):
				conversion;
		};
		OcamlEnumDynamicCarrier.requireIdentity(conversion.inputSemanticTypeId, conversion.inputCarrierTypeId);
		final nativeVariant = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(item)]);
		return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(OcamlEnumDynamicCarrier.RUNTIME_MODULE), OcamlEnumDynamicCarrier.RUNTIME_OPERATION), [
			OcamlExpr.EConst(OcamlConst.CString(conversion.inputSemanticTypeId)),
			nativeVariant
		]);
	}

	/**
		Builds one typed array literal from its planning disposition.

		An admitted direct array literal must consume its producer's explicit
		create/evaluate/store/result schedule. Other array shapes remain on the older
		container-element path until their own representation and construction
		contracts exist. `Unknown` is never a fallback: it means planning and syntax
		did not observe the same final typed root.
	**/
	function buildArrayLiteral(container:TypedExpr, items:Array<TypedExpr>):OcamlExpr {
		final producerPlan = currentArrayLiteralProducerPlan;
		if (producerPlan != null) {
			switch (producerPlan.syntaxLookup(container)) {
				case Unknown:
					return arrayLiteralProducerInvariant("typed array literal is absent from the sealed request-local syntax lookup", container.pos);
				case Required(_):
					final decision = try {
						producerPlan.requireFor(container, representationRegistry);
					} catch (error:Dynamic) {
						return arrayLiteralProducerInvariant(Std.string(error), container.pos);
					}
					return try {
						final binding = currentFunctionPlanBinding;
						if (binding == null)
							return arrayLiteralProducerInvariant("represented array literal has no active function-plan binding", container.pos);
						final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
						final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
						final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimePlanRevision, activeProfile,
							ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
						final materialization = OcamlArrayLiteralSyntax.build(decision, items, buildExpr, freshTmp, runtimeAuthority);
						// Element expressions can contain independently owned compiler work.
						// Reconcile only this literal's actual create and push call subtrees.
						runtimeAuthority.reconcileExpression(OcamlExpr.ESeq(materialization.runtimeOperations));
						materialization.expression;
					} catch (error:Dynamic) {
						arrayLiteralProducerInvariant(Std.string(error), container.pos);
					}
				case Excluded:
			}
		}

		final temporary = freshTmp("arr");
		final create = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
		final sequence:Array<OcamlExpr> = [];
		for (elementIndex in 0...items.length) {
			sequence.push(OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "push"), [
					OcamlExpr.EIdent(temporary),
					buildArrayLiteralElement(container, items[elementIndex], elementIndex)
				])
			]));
		}
		sequence.push(OcamlExpr.EIdent(temporary));
		return OcamlExpr.ELet(temporary, create, OcamlExpr.ESeq(sequence), false);
	}

	/** Returns the typed carrier entering an exact `Null<Int>` local write. */
	function nullIntWriteInput(expression:TypedExpr):Null<{semanticTypeId:String, carrierTypeId:String}> {
		return switch (unwrap(expression).expr) {
			case TConst(TNull): {semanticTypeId: "Null<Int>", carrierTypeId: "Obj.t"};
			case TConst(TInt(_)): {semanticTypeId: "Int", carrierTypeId: "int"};
			case _:
				if (OcamlRepresentationRegistry.isExactInt(expression.t)) {
					{semanticTypeId: "Int", carrierTypeId: "int"};
				} else if (OcamlRepresentationRegistry.isExactNullInt(expression.t)) {
					{semanticTypeId: "Null<Int>", carrierTypeId: "Obj.t"};
				} else {
					null;
				}
		}
	}

	/** Returns the typed carrier entering an exact `Null<Bool>` local write. */
	function nullBoolWriteInput(expression:TypedExpr):Null<{semanticTypeId:String, carrierTypeId:String}> {
		return switch (unwrap(expression).expr) {
			case TConst(TNull): {semanticTypeId: "Null<Bool>", carrierTypeId: "Obj.t"};
			case TConst(TBool(_)): {semanticTypeId: "Bool", carrierTypeId: "bool"};
			case TLocal(local) if (OcamlRepresentationRegistry.isExactNullBool(local.t)): {
					final decision = plannedLocalRepresentation(local.id, expression.pos);
					if (decision == null || decision.semanticTypeId != "Null<Bool>" || decision.carrierTypeId != "Obj.t")
						null;
					else
						{
							semanticTypeId: "Null<Bool>",
							carrierTypeId: "Obj.t"
						};
				};
			case TLocal(local) if (OcamlRepresentationRegistry.isExactBool(local.t)): {
					final decision = plannedLocalRepresentation(local.id, expression.pos);
					if (decision == null || decision.semanticTypeId != "Bool" || decision.carrierTypeId != "bool")
						null;
					else
						{
							semanticTypeId: "Bool",
							carrierTypeId: "bool"
						};
				};
			case TCall(_, _):
				if (currentCallPlan != null && currentCallPlan.producesNullableBool(expression)) {
					{semanticTypeId: "Null<Bool>", carrierTypeId: "Obj.t"};
				} else {
					null;
				}
			case _:
				null;
		}
	}

	/** Resolves the exact typed payload entering one sealed Dynamic local. */
	function dynamicWriteInput(expression:TypedExpr):Null<{
		semanticTypeId:String,
		carrierTypeId:String,
		payload:TypedExpr,
		conversion:OcamlLocalCarrierConversion
	}> {
		final unwrapped = unwrap(expression);
		return switch (unwrapped.expr) {
			case TConst(TNull):
				{
					semanticTypeId: "Dynamic",
					carrierTypeId: "Obj.t",
					payload: unwrapped,
					conversion: OcamlLocalCarrierConversion.PreserveDynamicCarrier
				};
			case TLocal(local) if (OcamlRepresentationRegistry.isExactDynamic(local.t)):
				{
					semanticTypeId: "Dynamic",
					carrierTypeId: "Obj.t",
					payload: unwrapped,
					conversion: OcamlLocalCarrierConversion.PreserveDynamicCarrier
				};
			case TCast(child, null):
				final payload = unwrap(child);
				final semanticCarrier = if (OcamlRepresentationRegistry.isExactInt(payload.t)) {
					{semanticTypeId: "Int", carrierTypeId: "int"};
				} else if (OcamlRepresentationRegistry.isExactFloat(payload.t)) {
					{semanticTypeId: "Float", carrierTypeId: "float"};
				} else if (OcamlRepresentationRegistry.isExactString(payload.t)) {
					{semanticTypeId: "String", carrierTypeId: "string"};
				} else {
					final layout = representationRegistry.monomorphicClassForType(payload.t);
					if (layout != null) {
						{semanticTypeId: layout.semanticTypeId, carrierTypeId: layout.targetTypeName};
					} else {
						switch (payload.t) {
							case TAnonymous(_): {semanticTypeId: TypeTools.toString(payload.t), carrierTypeId: "Obj.t"};
							case _: null;
						}
					}
				}
				if (OcamlRepresentationRegistry.isExactBool(payload.t)) {
					{
						semanticTypeId: "Bool",
						carrierTypeId: "bool",
						payload: payload,
						conversion: OcamlLocalCarrierConversion.BoxExactBoolToDynamic
					};
				} else {
					semanticCarrier == null ? null : {
						semanticTypeId: semanticCarrier.semanticTypeId,
						carrierTypeId: semanticCarrier.carrierTypeId,
						payload: payload,
						conversion: OcamlLocalCarrierConversion.BoxConcreteToDynamic
					};
				}
			case _:
				null;
		}
	}

	/** Renders one checked interface call and reports any stale syntax input at its source position. */
	function buildPlannedIMapInterfaceCall(decision:OcamlIMapInterfaceCallDecision, callee:TypedExpr, arguments:Array<TypedExpr>, position:Position):OcamlExpr {
		return try {
			OcamlIMapInterfaceSyntax.buildCall(decision, callee, arguments, iMapInterfaceSyntaxServices());
		} catch (error:Dynamic) {
			callPlanInvariant(Std.string(error), position);
		}
	}

	/** Materializes one concrete-to-interface conversion selected from the final typed body. */
	function buildPlannedIMapInterfaceConversion(materialization:OcamlIMapInterfaceConversionMaterialization, value:TypedExpr):OcamlExpr {
		return try {
			final decision = materialization.decision;
			final binding:OcamlFunctionPlanBinding = {
				functionId: decision.functionId,
				programRevision: decision.programRevision,
				bodyRevision: decision.bodyRevision,
				pipelineRevision: decision.pipelineRevision
			};
			final runtimeAuthority = new OcamlRuntimeUseAuthority(OcamlRuntimeUseModel.planRevision(binding),
				OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile),
				ctx.runtimeRequirementsByIds(OcamlIMapInterfacePlan.runtimeRequirementIds(decision)), decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
			final syntax = OcamlIMapInterfaceSyntax.buildConversion(materialization, value, iMapInterfaceSyntaxServices(), runtimeAuthority);
			// The source value and user-method bodies can contain separately planned
			// work. Check only the private names inserted by this adapter conversion.
			runtimeAuthority.reconcileExpression(OcamlExpr.ESeq(syntax.runtimeReferences));
			syntax.expression;
		} catch (error:Dynamic) {
			callPlanInvariant(Std.string(error), value.pos);
		}
	}

	/** Supplies mechanical expression and target-name operations to the focused syntax module. */
	function iMapInterfaceSyntaxServices():OcamlIMapInterfaceSyntaxServices {
		return {
			buildExpression: expression -> buildExpr(expression),
			freshName: prefix -> freshTmp(prefix),
			typeExpression: type -> typeExprFromHaxeType(type),
			coerceToObjectCarrier: (type, value) -> coerceToObjCarrier(type, value),
			userMethodTarget: method -> iMapInterfaceUserMethodTarget(method)
		};
	}

	/** Resolves the generated implementation name recorded by one user-method materialization. */
	function iMapInterfaceUserMethodTarget(method:OcamlIMapInterfaceMethodMaterialization):OcamlExpr {
		final moduleName = moduleIdToOcamlModuleName(method.owner.module);
		final selfModule = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
		final implementationName = ctx.scopedValueName(method.owner.module, method.owner.name, method.field.name + "__impl");
		return selfModule == moduleName ? OcamlExpr.EIdent(implementationName) : OcamlExpr.EField(OcamlExpr.EIdent(moduleName), implementationName);
	}

	/** Materializes one occurrence-bound initializer into Dynamic's Obj.t carrier. */
	function buildDynamicWrite(localId:Int, rhs:TypedExpr):OcamlExpr {
		final conversion = requireLocalConversionOccurrence(localId, OcamlLocalConversionRole.Initializer, rhs);
		if (conversion.conversion == OcamlLocalCarrierConversion.BoxExactEnumToDynamic) {
			final unwrapped = unwrap(rhs);
			final payload = switch (unwrapped.expr) {
				case TCast(child, null): unwrap(child);
				case _: unwrapped;
			}
			final nativeVariant = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(payload)]);
			return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(OcamlEnumDynamicCarrier.RUNTIME_MODULE), OcamlEnumDynamicCarrier.RUNTIME_OPERATION), [
				OcamlExpr.EConst(OcamlConst.CString(conversion.inputSemanticTypeId)),
				nativeVariant
			]);
		}
		final input = dynamicWriteInput(rhs);
		if (input == null)
			return localStorageInvariant('local $localId has no admitted concrete-to-Dynamic input shape', rhs.pos);
		requireLocalConversionShape(conversion, localId, rhs, input.semanticTypeId, input.carrierTypeId, "Dynamic", "Obj.t");
		if (conversion.conversion != input.conversion)
			return
				localStorageInvariant('local $localId occurrence "${conversion.id}" selected ${conversion.conversion}, but the final typed input requires ${input.conversion}',
				rhs.pos);
		return switch (conversion.conversion) {
			case PreserveDynamicCarrier:
				buildExpr(input.payload);
			case BoxConcreteToDynamic:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(input.payload)]);
			case BoxExactBoolToDynamic:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(input.payload)]);
			case BoxExactEnumToDynamic:
				localStorageInvariant('local $localId occurrence "${conversion.id}" reached generic Dynamic syntax with an enum-specific seal', rhs.pos);
			case LegacyCoercion, Identity, PreserveNullableIntCarrier, BoxExactIntToNullableInt, CheckedUnboxNullableInt, PreserveNullableBoolCarrier,
				BoxExactBoolToNullableBool, NullableBoolTruthiness:
				localStorageInvariant('local $localId occurrence "${conversion.id}" selected invalid Dynamic conversion ${conversion.conversion}', rhs.pos);
		}
	}

	/** Mechanically applies one sealed initializer/assignment conversion. */
	function buildNullIntWrite(localId:Int, role:OcamlLocalConversionRole, rhs:TypedExpr):OcamlExpr {
		final input = nullIntWriteInput(rhs);
		if (input == null)
			return localStorageInvariant('local $localId received an unsupported exact Null<Int> input after final planning', rhs.pos);
		final conversion = requireLocalConversion(localId, role, rhs, input.semanticTypeId, input.carrierTypeId, "Null<Int>", "Obj.t");
		return switch (conversion.conversion) {
			case PreserveNullableIntCarrier:
				buildExpr(rhs);
			case BoxExactIntToNullableInt:
				final value = switch (unwrap(rhs).expr) {
					case TConst(c = TInt(_)): OcamlExpr.EConst(buildConst(c));
					case _: buildExpr(rhs);
				}
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [value]);
			case LegacyCoercion, Identity, CheckedUnboxNullableInt, PreserveNullableBoolCarrier, BoxExactBoolToNullableBool, NullableBoolTruthiness,
				PreserveDynamicCarrier, BoxConcreteToDynamic, BoxExactBoolToDynamic, BoxExactEnumToDynamic:
				localStorageInvariant('local $localId occurrence "${conversion.id}" selected invalid write conversion ${conversion.conversion}', rhs.pos);
		}
	}

	/** Mechanically applies one sealed exact `Null<Bool>` local write. */
	function buildNullBoolWrite(localId:Int, role:OcamlLocalConversionRole, rhs:TypedExpr):OcamlExpr {
		final input = nullBoolWriteInput(rhs);
		if (input == null)
			return localStorageInvariant('local $localId received an unsupported exact Null<Bool> input after final planning', rhs.pos);
		final conversion = requireLocalConversion(localId, role, rhs, input.semanticTypeId, input.carrierTypeId, "Null<Bool>", "Obj.t");
		return switch (conversion.conversion) {
			case PreserveNullableBoolCarrier:
				buildExpr(rhs);
			case BoxExactBoolToNullableBool:
				final value = switch (unwrap(rhs).expr) {
					case TConst(c = TBool(_)): OcamlExpr.EConst(buildConst(c));
					case _: buildExpr(rhs);
				}
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [value]);
			case LegacyCoercion, Identity, NullableBoolTruthiness, PreserveNullableIntCarrier, BoxExactIntToNullableInt, CheckedUnboxNullableInt,
				PreserveDynamicCarrier, BoxConcreteToDynamic, BoxExactBoolToDynamic, BoxExactEnumToDynamic:
				localStorageInvariant('local $localId occurrence "${conversion.id}" selected invalid write conversion ${conversion.conversion}', rhs.pos);
		}
	}

	/** Mechanically applies one sealed exact `Null<Int>` local read conversion. */
	function buildNullIntRead(local:TVar, expression:TypedExpr, base:OcamlExpr):OcamlExpr {
		final outputSemanticTypeId = if (OcamlRepresentationRegistry.isExactNullInt(expression.t)) {
			"Null<Int>";
		} else if (OcamlRepresentationRegistry.isExactInt(expression.t)) {
			"Int";
		} else {
			return localStorageInvariant('local ${local.id} has unsupported typed read ${TypeTools.toString(expression.t)} after final planning',
				expression.pos);
		}
		final outputCarrierTypeId = outputSemanticTypeId == "Int" ? "int" : "Obj.t";
		final conversion = requireLocalConversion(local.id, OcamlLocalConversionRole.Read, expression, "Null<Int>", "Obj.t", outputSemanticTypeId,
			outputCarrierTypeId);
		return switch (conversion.conversion) {
			case PreserveNullableIntCarrier:
				base;
			case CheckedUnboxNullableInt:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_unwrap"), [base]);
			case LegacyCoercion, Identity, BoxExactIntToNullableInt, PreserveNullableBoolCarrier, BoxExactBoolToNullableBool, NullableBoolTruthiness,
				PreserveDynamicCarrier, BoxConcreteToDynamic, BoxExactBoolToDynamic, BoxExactEnumToDynamic:
				localStorageInvariant('local ${local.id} occurrence "${conversion.id}" selected invalid read conversion ${conversion.conversion}',
					expression.pos);
		}
	}

	/** Mechanically preserves an admitted nullable-Bool read outside truthiness. */
	function buildNullBoolRead(local:TVar, expression:TypedExpr, base:OcamlExpr):OcamlExpr {
		if (!OcamlRepresentationRegistry.isExactNullBool(expression.t)) {
			return localStorageInvariant('local ${local.id} has unsupported typed read ${TypeTools.toString(expression.t)} after final planning',
				expression.pos);
		}
		final conversion = requireLocalConversion(local.id, OcamlLocalConversionRole.Read, expression, "Null<Bool>", "Obj.t", "Null<Bool>", "Obj.t");
		return switch (conversion.conversion) {
			case PreserveNullableBoolCarrier:
				base;
			case LegacyCoercion, Identity, NullableBoolTruthiness, BoxExactBoolToNullableBool, PreserveNullableIntCarrier, BoxExactIntToNullableInt,
				CheckedUnboxNullableInt, PreserveDynamicCarrier, BoxConcreteToDynamic, BoxExactBoolToDynamic, BoxExactEnumToDynamic:
				localStorageInvariant('local ${local.id} occurrence "${conversion.id}" selected invalid nullable-Bool read conversion ${conversion.conversion}',
					expression.pos);
		}
	}

	/**
		Consumes the sealed truthiness conversion for a direct exact `Null<Bool>`
		local in a condition or logical operator.

		Returning `null` means this expression is not an admitted local and the
		caller should use the existing condition path.
	**/
	function buildPlannedNullableBoolTruthiness(expression:TypedExpr):Null<OcamlExpr> {
		final unwrapped = unwrap(expression);
		return switch (unwrapped.expr) {
			case TLocal(local):
				final representation = plannedLocalRepresentation(local.id, expression.pos);
				if (representation == null || representation.semanticTypeId != "Null<Bool>") {
					null;
				} else {
					final conversion = requireLocalConversion(local.id, OcamlLocalConversionRole.Read, expression, "Null<Bool>", "Obj.t", "Bool", "bool");
					switch (conversion.conversion) {
						case NullableBoolTruthiness:
							safeUnboxNullableBool(buildLocal(local, expression.pos));
						case LegacyCoercion, Identity, PreserveNullableBoolCarrier, BoxExactBoolToNullableBool, PreserveNullableIntCarrier,
							BoxExactIntToNullableInt, CheckedUnboxNullableInt, PreserveDynamicCarrier, BoxConcreteToDynamic, BoxExactBoolToDynamic,
							BoxExactEnumToDynamic:
							localStorageInvariant('local ${local.id} occurrence "${conversion.id}" selected invalid truthiness conversion ${conversion.conversion}',
								expression.pos);
					}
				}
			case _:
				null;
		}
	}

	/**
		Consumes a checked-read conversion when an exact `Null<Int>` local is used
		as a numeric `Int` operand.

		The generic nullable fallback maps null to zero. Admitted locals bypass
		that fallback: the sealed occurrence requires `nullable_int_unwrap`, which
		rejects the null sentinel and records the unsafe carrier boundary.
	**/
	function buildCheckedNullableIntOperand(expression:TypedExpr):Null<OcamlExpr> {
		final unwrapped = unwrap(expression);
		return switch (unwrapped.expr) {
			case TLocal(local):
				final representation = plannedLocalRepresentation(local.id, expression.pos);
				if (representation == null || representation.semanticTypeId != "Null<Int>") {
					null;
				} else {
					final conversion = requireLocalConversion(local.id, OcamlLocalConversionRole.Read, expression, "Null<Int>", "Obj.t", "Int", "int");
					switch (conversion.conversion) {
						case CheckedUnboxNullableInt:
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_unwrap"), [buildLocal(local, expression.pos)]);
						case LegacyCoercion, Identity, PreserveNullableIntCarrier, BoxExactIntToNullableInt, PreserveNullableBoolCarrier,
							BoxExactBoolToNullableBool, NullableBoolTruthiness, PreserveDynamicCarrier, BoxConcreteToDynamic, BoxExactBoolToDynamic,
							BoxExactEnumToDynamic:
							localStorageInvariant('local ${local.id} occurrence "${conversion.id}" selected invalid numeric-read conversion ${conversion.conversion}',
								expression.pos);
					}
				}
			case _:
				null;
		}
	}

	/**
		Consumes the initializer conversion sealed with one local representation.

		Identity is admitted only when final typed planning already proved that the
		initializer uses the selected carrier. Syntax construction therefore copies
		the value directly instead of falling through the generic same-class cast.
	**/
	function coerceLocalInitializer(localId:Int, lhsType:Type, rhs:TypedExpr):OcamlExpr {
		final representation = plannedLocalRepresentation(localId, rhs.pos);
		if (representation != null && representation.semanticTypeId == "Null<Int>")
			return buildNullIntWrite(localId, OcamlLocalConversionRole.Initializer, rhs);
		if (representation != null && representation.semanticTypeId == "Null<Bool>")
			return buildNullBoolWrite(localId, OcamlLocalConversionRole.Initializer, rhs);
		if (representation != null && representation.semanticTypeId == "Dynamic")
			return buildDynamicWrite(localId, rhs);
		if (currentIMapInterfacePlan != null) {
			final storageAlias = try {
				currentIMapInterfacePlan.storageAliasFor(rhs, lhsType);
			} catch (error:Dynamic) {
				return callPlanInvariant(Std.string(error), rhs.pos);
			}
			if (storageAlias != null) {
				// Haxe's standard Map abstract sometimes introduces an `IMap`-typed
				// temporary even though every later use calls the raw String/Int/Object
				// map runtime directly. The sealed alias proves that closed use pattern
				// for this exact local, so keep its initializer in the same raw carrier.
				// Ordinary source-level Map-to-IMap assignments are not admitted here;
				// they continue through the dispatch-record conversion below.
				return buildIMapStorageAliasInitializer(storageAlias, rhs);
			}
		}
		final localRepresentations = activeLocalRepresentationPlan(rhs.pos);
		if (localRepresentations == null)
			return coerceForAssignment(lhsType, rhs);
		return switch (localRepresentations.initializerConversionFor(stableLocalId(localId, rhs.pos))) {
			case OcamlLocalCarrierConversion.Identity:
				final decision = plannedLocalRepresentation(localId, rhs.pos);
				if (decision == null)
					return localStorageInvariant('local $localId selected identity initializer conversion without a program representation', rhs.pos);
				switch (unwrap(rhs).expr) {
					case TConst(TNull):
						localStorageInvariant('local $localId selected identity initializer conversion for the Haxe null sentinel', rhs.pos);
					case _:
						buildExpr(rhs);
				}
			case OcamlLocalCarrierConversion.LegacyCoercion, null:
				coerceForAssignment(lhsType, rhs);
			case PreserveNullableIntCarrier, BoxExactIntToNullableInt, CheckedUnboxNullableInt, PreserveNullableBoolCarrier, BoxExactBoolToNullableBool,
				NullableBoolTruthiness, PreserveDynamicCarrier, BoxConcreteToDynamic, BoxExactBoolToDynamic, BoxExactEnumToDynamic:
				localStorageInvariant('local $localId leaked an occurrence-only carrier conversion into its initializer summary', rhs.pos);
		}
	}

	/**
		Builds one planned raw Map initializer without guessing from its source type.

		For a nullable static Map field, the field read is evaluated once. A null
		value raises the same catchable `Null Access` error used by other checked
		OCaml-target reads; a non-null value keeps the already-proven `HxMap` carrier.
	**/
	function buildIMapStorageAliasInitializer(decision:OcamlIMapStorageAliasDecision, rhs:TypedExpr):OcamlExpr {
		final built = buildExpr(rhs);
		return switch (decision.nullPolicy) {
			case NonNullableSource:
				built;
			case CheckNullAndUnbox:
				final binding:OcamlFunctionPlanBinding = {
					functionId: decision.functionId,
					programRevision: decision.programRevision,
					bodyRevision: decision.bodyRevision,
					pipelineRevision: decision.pipelineRevision
				};
				final planRevision = OcamlRuntimeUseModel.planRevision(binding);
				final runtimeAuthority = new OcamlRuntimeUseAuthority(planRevision, OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile),
					ctx.runtimeRequirementsByIds(OcamlIMapInterfacePlan.storageAliasRuntimeRequirementIds(decision)), decision.runtimeUseOccurrences,
					ctx.finalRuntimeUses);
				final nullCheckUse = decision.runtimeUseOccurrences[0];
				final nullThrowUse = decision.runtimeUseOccurrences[1];
				final valueName = freshTmp("nullable_standard_map");
				final value = OcamlExpr.EIdent(valueName);
				final isNull = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(nullCheckUse.id, planRevision,
					nullCheckUse.exactSymbol)), [value]);
				final recovered = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [value]);
				final throwNullAccess = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeAuthority.expressionIdentifier(nullThrowUse.id, planRevision,
					nullThrowUse.exactSymbol)), [
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EConst(OcamlConst.CString("Null Access"))]),
						OcamlExpr.EList([
							OcamlExpr.EConst(OcamlConst.CString("String")),
							OcamlExpr.EConst(OcamlConst.CString("Dynamic"))
						])
					]);
				// The source value may contain runtime uses owned by other plans. Reconcile
				// only the two private names this alias inserts, then compose the result.
				runtimeAuthority.reconcileExpression(OcamlExpr.ESeq([isNull, throwNullAccess]));
				OcamlExpr.ELet(valueName, built, OcamlExpr.EIf(isNull, throwNullAccess, recovered), false);
			case _:
				callPlanInvariant('reflaxe.ocaml [ocaml-imap-interface:unknown-storage-alias-null-policy]: storage alias "${decision.id}" has unsupported null policy "${decision.nullPolicy}"',
					rhs.pos);
		};
	}

	/**
		Consumes the whole-value assignment conversion sealed for one local.

		An identity replacement stores the already-selected carrier directly. The
		planner admits it only after checking every replacement in the final typed
		body, so this path never reclassifies the Haxe type.
	**/
	function coerceLocalAssignment(localId:Int, lhsType:Type, rhs:TypedExpr):OcamlExpr {
		final representation = plannedLocalRepresentation(localId, rhs.pos);
		if (representation != null && representation.semanticTypeId == "Null<Int>")
			return buildNullIntWrite(localId, OcamlLocalConversionRole.Assignment, rhs);
		if (representation != null && representation.semanticTypeId == "Null<Bool>")
			return buildNullBoolWrite(localId, OcamlLocalConversionRole.Assignment, rhs);
		final localRepresentations = activeLocalRepresentationPlan(rhs.pos);
		if (localRepresentations == null)
			return coerceForAssignment(lhsType, rhs);
		return switch (localRepresentations.assignmentConversionFor(stableLocalId(localId, rhs.pos))) {
			case OcamlLocalCarrierConversion.Identity:
				final decision = plannedLocalRepresentation(localId, rhs.pos);
				if (decision == null)
					return localStorageInvariant('local $localId selected identity assignment conversion without a program representation', rhs.pos);
				switch (unwrap(rhs).expr) {
					case TConst(TNull):
						localStorageInvariant('local $localId selected identity assignment conversion for the Haxe null sentinel', rhs.pos);
					case _:
						buildExpr(rhs);
				}
			case OcamlLocalCarrierConversion.LegacyCoercion, null:
				coerceForAssignment(lhsType, rhs);
			case PreserveNullableIntCarrier, BoxExactIntToNullableInt, CheckedUnboxNullableInt, PreserveNullableBoolCarrier, BoxExactBoolToNullableBool,
				NullableBoolTruthiness, PreserveDynamicCarrier, BoxConcreteToDynamic, BoxExactBoolToDynamic, BoxExactEnumToDynamic:
				localStorageInvariant('local $localId leaked an occurrence-only carrier conversion into its assignment summary', rhs.pos);
		}
	}

	/** Builds one admitted place operation from a sealed semantic plan. */
	function buildPreservedPlaceOperation(metadata:haxe.macro.Expr.MetadataEntry, expression:TypedExpr):OcamlExpr {
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return placeLoweringInvariant("a final place marker has no stable origin identity", expression.pos);
		final binding = currentPlacePlanBinding;
		if (binding == null)
			return placeLoweringInvariant('origin "$originId" reached syntax construction outside a sealed function body', expression.pos);
		return switch (placeAssignmentLowerer.lower(originId, binding, buildExpr, freshTmp)) {
			case Lowered(lowered): lowered;
			case Invalid(message): placeLoweringInvariant(message, expression.pos);
		}
	}

	static function rawInjectionFailure(message:String, pos:Position):Void {
		#if macro
		Context.error("reflaxe.ocaml: " + message + ".", pos);
		#else
		throw "reflaxe.ocaml: " + message + ".";
		#end
	}

	#if macro
	inline function guardrailError(msg:String, pos:Position):Void {
		if (!ctx.currentIsHaxeStd) {
			haxe.macro.Context.error(msg, pos);
		}
	}
	#end

	inline function isRefLocalId(id:Int):Bool {
		return refLocals.exists(id) && refLocals.get(id) == true;
	}

	inline function isWeakRefLocalId(id:Int):Bool {
		return weakRefLocals.exists(id) && weakRefLocals.get(id) == true;
	}

	inline function isObjRefLocalId(id:Int):Bool {
		return objRefLocals.exists(id) && objRefLocals.get(id) == true;
	}

	static inline function isOcamlNativeEnumType(e:EnumType, name:String):Bool {
		return e.pack != null && e.pack.length == 1 && e.pack[0] == "ocaml" && e.name == name;
	}

	static inline function isStdArrayClass(cls:ClassType):Bool {
		return cls.pack != null && cls.pack.length == 0 && cls.name == "Array";
	}

	static inline function isStdStringClass(cls:ClassType):Bool {
		return cls.pack != null && cls.pack.length == 0 && cls.name == "String";
	}

	static inline function isStdBytesClass(cls:ClassType):Bool {
		return OcamlBytesProducerPlan.isBytesClass(cls);
	}

	static inline function isStdBytesType(t:Type):Bool {
		return switch (followNoAbstracts(unwrapNullType(t))) {
			case TInst(cRef, _):
				isStdBytesClass(cRef.get());
			case _:
				false;
		}
	}

	function arrayIteratorInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-array-iterator:plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/** Builds one checked Array-to-iterator call from its sealed typed occurrence. */
	function ocamlIteratorOfArray(source:TypedExpr, items:OcamlExpr):OcamlExpr {
		final plan = currentArrayIteratorPlan;
		if (plan == null)
			return arrayIteratorInvariant("Array iterator syntax has no active sealed plan", source.pos);
		final decision = try {
			plan.requireFor(source);
		} catch (error:Dynamic) {
			return arrayIteratorInvariant(Std.string(error), source.pos);
		}
		if (decision.kind != OcamlArrayIteratorUseKind.StructuralAdapter)
			return arrayIteratorInvariant('decision "${decision.id}" is not an Array-to-Iterable adapter', source.pos);
		final authority = arrayIteratorRuntimeAuthority(decision);
		final use = decision.runtimeUseOccurrences[0];
		final expression = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol)), [items]);
		try {
			authority.reconcileExpression(expression);
		} catch (error:Dynamic) {
			return arrayIteratorInvariant(Std.string(error), source.pos);
		}
		return expression;
	}

	/** Builds the standard generated `ArrayIterator` value for a direct or stored method. */
	function ocamlStandardArrayIterator(source:TypedExpr, items:OcamlExpr):OcamlExpr {
		final plan = currentArrayIteratorPlan;
		if (plan == null)
			return arrayIteratorInvariant("standard Array iterator syntax has no active sealed plan", source.pos);
		final decision = try {
			plan.requireFor(source);
		} catch (error:Dynamic) {
			return arrayIteratorInvariant(Std.string(error), source.pos);
		}
		if (decision.kind != OcamlArrayIteratorUseKind.DirectCall && decision.kind != OcamlArrayIteratorUseKind.BoundMethod)
			return arrayIteratorInvariant('decision "${decision.id}" is not a direct or stored standard Array iterator', source.pos);
		final moduleId = "haxe.iterators.ArrayIterator";
		final moduleName = moduleIdToOcamlModuleName(moduleId);
		final createName = ctx.scopedValueName(moduleId, "ArrayIterator", "create");
		return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(moduleName), createName), [items]);
	}

	/** Builds one checked `HxIterator.t` application for a structural literal. */
	function ocamlIteratorCarrier(source:TypedExpr, itemType:OcamlTypeExpr):OcamlTypeExpr {
		final plan = currentArrayIteratorPlan;
		if (plan == null)
			return arrayIteratorInvariant("structural Iterator syntax has no active sealed plan", source.pos);
		final decision = try {
			plan.requireFor(source);
		} catch (error:Dynamic) {
			return arrayIteratorInvariant(Std.string(error), source.pos);
		}
		if (decision.kind != OcamlArrayIteratorUseKind.StructuralCarrier)
			return arrayIteratorInvariant('decision "${decision.id}" is not a structural Iterator carrier', source.pos);
		final authority = arrayIteratorRuntimeAuthority(decision);
		final use = decision.runtimeUseOccurrences[0];
		final type = OcamlTypeExpr.TRuntimeApp(authority.typeIdentifier(use.id, use.planRevision, use.exactSymbol), [itemType]);
		try {
			authority.reconcileType(type);
		} catch (error:Dynamic) {
			return arrayIteratorInvariant(Std.string(error), source.pos);
		}
		return type;
	}

	function arrayIteratorRuntimeAuthority(decision:OcamlArrayIteratorDecision):OcamlRuntimeUseAuthority {
		final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
		return new OcamlRuntimeUseAuthority(decision.revision, activeProfile, ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds),
			decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
	}

	function dynamicEqualityInvariant(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-dynamic-equality:plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/** Returns the one runtime function authorized for this typed equality occurrence. */
	function dynamicEqualityFunction(source:TypedExpr, expectedKind:OcamlDynamicEqualityKind):OcamlExpr {
		final plan = currentDynamicEqualityPlan;
		if (plan == null)
			return dynamicEqualityInvariant("Dynamic equality syntax has no active sealed plan", source.pos);
		final decision = try {
			plan.requireFor(source);
		} catch (error:Dynamic) {
			return dynamicEqualityInvariant(Std.string(error), source.pos);
		}
		if (decision.kind != expectedKind)
			return dynamicEqualityInvariant('decision "${decision.id}" has kind ${decision.kind}, not $expectedKind', source.pos);
		final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
		final authority = new OcamlRuntimeUseAuthority(decision.revision, activeProfile, ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds),
			decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
		final use = decision.runtimeUseOccurrences[0];
		final expression = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol));
		try {
			authority.reconcileExpression(expression);
		} catch (error:Dynamic) {
			return dynamicEqualityInvariant(Std.string(error), source.pos);
		}
		return expression;
	}

	function dynamicStringInvariant(message:String, position:Position):OcamlExpr {
		final diagnostic = "reflaxe.ocaml [ocaml-dynamic-string:plan-invariant]: " + message;
		#if macro
		Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/** Returns the one runtime function authorized for this typed string conversion. */
	function dynamicStringFunction(source:TypedExpr, expectedStrategy:OcamlDynamicStringStrategy):OcamlExpr {
		final plan = currentDynamicStringPlan;
		if (plan == null)
			return dynamicStringInvariant("Dynamic string syntax has no active sealed plan", source.pos);
		final decision = try {
			plan.requireFor(source);
		} catch (error:Dynamic) {
			return dynamicStringInvariant(Std.string(error), source.pos);
		}
		if (decision.strategy != expectedStrategy)
			return dynamicStringInvariant('decision "${decision.id}" has strategy ${decision.strategy}, not $expectedStrategy', source.pos);
		final semanticTypeId = TypeTools.toString(source.t);
		if (decision.semanticTypeId != semanticTypeId)
			return dynamicStringInvariant('decision "${decision.id}" expects ${decision.semanticTypeId}, not $semanticTypeId', source.pos);
		final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
		final authority = new OcamlRuntimeUseAuthority(decision.revision, activeProfile, ctx.runtimeRequirementsByIds(decision.runtimeRequirementIds),
			decision.runtimeUseOccurrences, ctx.finalRuntimeUses);
		final use = decision.runtimeUseOccurrences[0];
		final expression = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol));
		try {
			authority.reconcileExpression(expression);
		} catch (error:Dynamic) {
			return dynamicStringInvariant(Std.string(error), source.pos);
		}
		return expression;
	}

	static function isStringType(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, [inner]): final a = aRef.get(); a.pack != null && a.pack.length == 0 && a.name == "Null" && isStringType(inner);
			case TAbstract(aRef, _):
				final a = aRef.get();
				if (a.pack != null && a.pack.length == 1 && a.pack[0] == "haxe" && a.name == "Ucs2") {
					true;
				} else {
					switch (TypeTools.follow(a.type)) {
						case TInst(cRef, _):
							isStdStringClass(cRef.get());
						case _:
							false;
					}
				}
			case TInst(cRef, _):
				final c = cRef.get();
				isStdStringClass(c);
			case _:
				false;
		}
	}

	/**
		Follows monomorphs and typedefs, but intentionally does *not* follow
		abstracts (notably `Null<T>`).

		`haxe.macro.TypeTools.follow` uses `Context.follow`, which can collapse
		`Null<T>` to `T` (core-type behavior). For this backend we must preserve
		`Null<T>` so we can emit correct boxing/unboxing and null comparisons.
	**/
	static function followNoAbstracts(t:Type):Type {
		var current = t;
		while (true) {
			final next = switch (current) {
				case TLazy(f):
					f();
				case TMono(r):
					final inner = r.get();
					inner == null ? current : inner;
				case TType(tRef, params):
					final td = tRef.get();
					TypeTools.applyTypeParameters(td.type, td.params, params);
				case _:
					return current;
			}

			// Guard against unresolved/self-referential monomorphs and other cyclic shapes.
			// If following doesn't make progress, stop.
			if (next == current)
				return current;
			current = next;
		}
	}

	/**
		Unwraps monomorphs/lazy types but intentionally does *not* follow typedefs.

		Used for detecting special typedef-backed anonymous structures where we emit
		idiomatic OCaml records (e.g. `sys.FileStat`).
	**/
	static function unwrapNoTypedef(t:Type):Type {
		var current = t;
		while (true) {
			final next = switch (current) {
				case TLazy(f):
					f();
				case TMono(r):
					final inner = r.get();
					inner == null ? current : inner;
				case _:
					return current;
			}

			if (next == current)
				return current;
			current = next;
		}
	}

	static function isSysFileStatTypedef(t:Type):Bool {
		return switch (unwrapNoTypedef(t)) {
			case TType(tRef, _):
				final td = tRef.get();
				(td.pack ?? []).length == 1 && td.pack[0] == "sys" && td.module == "sys.FileSystem" && td.name == "FileStat";
			case _:
				false;
		}
	}

	static function isSysFileStatAnon(t:Type):Bool {
		final ft = followNoAbstracts(t);
		return switch (ft) {
			case TAnonymous(aRef):
				final a = aRef.get();
				final want = [
					"gid", "uid", "atime", "mtime", "ctime", "size", "dev", "ino", "nlink", "rdev", "mode"
				];
				final have:Map<String, Bool> = [];
				for (f in a.fields)
					have.set(f.name, true);
				for (n in want) {
					if (!have.exists(n))
						return false;
				}
				true;
			case _:
				false;
		}
	}

	static function isStdAnyAbstract(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				(a.pack ?? []).length == 0 && a.name == "Any";
			case _:
				false;
		}
	}

	static function isIteratorAnon(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAnonymous(aRef): final a = aRef.get(); var hasHasNext = false; var hasNext = false; for (f in a.fields) {
					if (f.name == "hasNext")
						hasHasNext = true;
					else if (f.name == "next")
						hasNext = true;
				} hasHasNext && hasNext;
			case _:
				false;
		}
	}

	static function iteratorAnonItemType(t:Type):Null<Type> {
		return switch (followNoAbstracts(t)) {
			case TAnonymous(aRef):
				final a = aRef.get();
				var itemType:Null<Type> = null;
				for (f in a.fields) {
					if (f.name == "next") {
						switch (followNoAbstracts(f.type)) {
							case TFun(args, ret) if (args.length == 0):
								itemType = ret;
							case _:
						}
						break;
					}
				}
				itemType;
			case _:
				null;
		}
	}

	static function isKeyValueAnon(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAnonymous(aRef): final a = aRef.get(); var hasKey = false; var hasValue = false; for (f in a.fields) {
					if (f.name == "key")
						hasKey = true;
					else if (f.name == "value")
						hasValue = true;
				} hasKey && hasValue;
			case _:
				false;
		}
	}

	/**
		Decides whether a `TAnonymous` type should lower to the generic `HxAnon` runtime
		representation (`Obj.t`), or whether it is one of our “record-like”/tuple-like
		structural shapes with a dedicated OCaml representation.

		Why:
		- Haxe uses anonymous structures heavily (typedef-backed structural typing).
		- For most shapes we represent them as `Obj.t` with runtime field access
		  (`HxAnon.get/set`), because generating OCaml record types for arbitrary
		  structural types is not practical.
		- Some anonymous shapes are performance-critical and/or ubiquitous in the stdlib
		  and compiler tests (e.g. `Iterator<T>`, key/value pairs, `sys.FileStat`), so we
		  special-case them to real OCaml data structures.

		This predicate is used by coercions and `Std.string` lowering to avoid boxing
		record-like values into `Obj.t` accidentally (which would break record-field
		access such as `it.hasNext ()`).
	**/
	static function shouldAnonUseHxAnon(t:Type):Bool {
		return OcamlDynamicCarrierModel.anonymousUsesHxAnon(t);
	}

	static function isIntType(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, _): final a = aRef.get(); (a.pack != null && a.pack.length == 0 && a.name == "Int") || (a.pack != null
					&& a.pack.length == 1 && a.pack[0] == "haxe" && a.name == "Int32");
			case _:
				false;
		}
	}

	static function isFloatType(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, _): final a = aRef.get(); a.pack != null && a.pack.length == 0 && a.name == "Float";
			case _:
				false;
		}
	}

	static function isBoolType(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, _): final a = aRef.get(); a.pack != null && a.pack.length == 0 && a.name == "Bool";
			case _:
				false;
		}
	}

	static function isVoidType(t:Type):Bool {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, _): final a = aRef.get(); a.pack != null && a.pack.length == 0 && a.name == "Void";
			case _:
				false;
		}
	}

	static function nullablePrimitiveKind(t:Type):Null<String> {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				if (a.pack != null && a.pack.length == 0 && a.name == "Null") {
					if (isIntType(inner))
						return "int";
					if (isFloatType(inner))
						return "float";
					if (isBoolType(inner))
						return "bool";
				}
				null;
			case _:
				null;
		}
	}

	static function unwrapNullType(t:Type):Type {
		return switch (t) {
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				if (a.pack != null && a.pack.length == 0 && a.name == "Null") inner else t;
			case _:
				t;
		}
	}

	/**
	 * Value used when a callsite omits an optional parameter.
	 *
	 * Nullable primitives carry `HxRuntime.hx_null`; everything else keeps
	 * the existing `Obj.magic hx_null` sentinel behavior.
	 */
	function missingOptionalArgValue(t:Type, ownerRole:String, position:Position):OcamlExpr {
		if (nullablePrimitiveKind(t) != null)
			return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
		if (OcamlRepresentationRegistry.isExactString(t))
			return exactStringNullValue(OcamlRepresentationDomain.InternalValue, ownerRole, position);
		return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);
	}

	inline function paramUsesDirectNullSentinelCompare(t:Type):Bool {
		return isDynamicLike(t) || nullablePrimitiveKind(t) != null || isTypeParameterType(t) || isNullableEnumType(t) != null;
	}

	/**
		Normalizes Haxe default arguments while keeping the OCaml binding intentional.

		Generic typed cleanup can remove the last source read of an optional
		argument. We still retain its default-value normalization so the function's
		carrier type and callable shape do not change. When the resulting OCaml body
		does not read that normalized value, an explicit `ignore` documents the
		discard and prevents warning 26 from becoming a native build error.
	**/
	function wrapFunctionArgDefaults(body:OcamlExpr, args:Array<{name:String, t:Type, value:Null<TypedExpr>}>):OcamlExpr {
		var out = body;
		final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
		for (i in 0...args.length) {
			final a = args[args.length - 1 - i];
			if (a.value == null)
				continue;
			switch (unwrap(a.value).expr) {
				case TConst(TNull):
					continue;
				case _:
			}
			final name = renameVar(a.name);
			final paramExpr = OcamlExpr.EIdent(name);
			final isMissing = OcamlExpr.EBinop(OcamlBinop.PhysEq,
				paramUsesDirectNullSentinelCompare(a.t) ? paramExpr : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [paramExpr]), hxNull);
			final normalized = OcamlExpr.EIf(isMissing, coerceForAssignment(a.t, a.value), paramExpr);
			out = OcamlExpr.ELet(name, normalized, ensureParamUsage(out, [OcamlPat.PVar(name)]), false);
		}
		return out;
	}

	inline function isDynamicLike(t:Type):Bool {
		return OcamlDynamicCarrierModel.usesDynamicCarrier(t);
	}

	static function fullNameOfTypeEnum(t:Type):Null<String> {
		return switch (followNoAbstracts(unwrapNullType(t))) {
			case TEnum(eRef, _):
				fullNameOfEnumType(eRef.get());
			case _:
				null;
		}
	}

	static function isNullableEnumType(t:Type):Null<String> {
		return switch (followNoAbstracts(t)) {
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				if ((a.pack ?? []).length == 0 && a.name == "Null") {
					switch (TypeTools.follow(inner)) {
						case TEnum(eRef, _):
							final e = eRef.get();
							(e.pack ?? []).concat([e.name]).join(".");
						case _:
							null;
					}
				} else {
					null;
				}
			case _:
				null;
		}
	}

	static inline function fullNameOfClassType(cls:ClassType):String {
		return (cls.pack ?? []).concat([cls.name]).join(".");
	}

	static inline function fullNameOfEnumType(e:EnumType):String {
		return (e.pack ?? []).concat([e.name]).join(".");
	}

	/**
		Returns the single "match tag" for a typed catch, or `null` if this is a
		`catch (e:Dynamic)`-style match-all.

		Important: this must be *precise* for the catch type.
		Do not include parent tags here, otherwise `catch (e:Child)` could match
		`throw (new Base())` via the shared base tag.
	**/
	static function catchTagForType(t:Type):Null<String> {
		final ft = followNoAbstracts(t);

		if (isIntType(ft))
			return "Int";
		if (isFloatType(ft))
			return "Float";
		if (isBoolType(ft))
			return "Bool";
		if (isStringType(ft))
			return "String";

		return switch (ft) {
			case TDynamic(_):
				null;
			case TInst(cRef, _):
				fullNameOfClassType(cRef.get());
			case TEnum(eRef, _):
				fullNameOfEnumType(eRef.get());
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				if (a.pack != null && a.pack.length == 0 && a.name == "Null") {
					// Best-effort: treat `Null<T>` catch as a catch on `T` for now.
					catchTagForType(inner);
				} else {
					(a.pack ?? []).concat([a.name]).join(".");
				}
			case _:
				// Structural types and function types are not supported yet.
				null;
		}
	}

	/**
		Compute "throw tags" for a thrown value based on the *static* type of the
		expression being thrown.

		Tags are used to implement typed catches (`catch (e:T)`) without relying on
		OCaml runtime representation checks (which cannot disambiguate e.g. `int`
		and `bool` reliably).

		This is intentionally best-effort: for now it does not attempt to model
		precise runtime shapes for values whose static type is too generic.
	**/
	static function throwTagsForType(t:Type):Array<String> {
		final tags:Array<String> = [];
		final seen:Map<String, Bool> = [];

		inline function add(tag:String):Void {
			if (!seen.exists(tag)) {
				seen.set(tag, true);
				tags.push(tag);
			}
		}

		// Always include Dynamic so a catch-all can match predictably.
		add("Dynamic");

		final ft = followNoAbstracts(t);
		if (isIntType(ft)) {
			add("Int");
			return tags;
		}
		if (isFloatType(ft)) {
			add("Float");
			return tags;
		}
		if (isBoolType(ft)) {
			add("Bool");
			return tags;
		}
		if (isStringType(ft)) {
			add("String");
			return tags;
		}

		function addInterfaceTags(iface:ClassType, visited:Map<String, Bool>):Void {
			final name = fullNameOfClassType(iface);
			if (visited.exists(name))
				return;
			visited.set(name, true);
			add(name);
			for (i in iface.interfaces)
				addInterfaceTags(i.t.get(), visited);
		}

		function addClassTags(cls:ClassType, visited:Map<String, Bool>):Void {
			final name = fullNameOfClassType(cls);
			if (visited.exists(name))
				return;
			visited.set(name, true);
			add(name);
			for (i in cls.interfaces)
				addInterfaceTags(i.t.get(), visited);
			if (cls.superClass != null)
				addClassTags(cls.superClass.t.get(), visited);
		}

		return switch (ft) {
			case TAbstract(aRef, [inner]):
				final a = aRef.get();
				if (a.pack != null && a.pack.length == 0 && a.name == "Null") {
					add("Null");
					for (t in throwTagsForType(inner))
						add(t);
				}
				tags;
			case TInst(cRef, _):
				addClassTags(cRef.get(), []);
				tags;
			case TEnum(eRef, _):
				add(fullNameOfEnumType(eRef.get()));
				tags;
			case _:
				tags;
		}
	}

	function buildArrayJoinStringifier(arrayExpr:TypedExpr, pos:Position):OcamlExpr {
		var elemType:Null<Type> = null;
		switch (arrayExpr.t) {
			case TInst(_, params) if (params != null && params.length > 0):
				elemType = unwrapNullType(params[0]);
			case _:
		}

		if (elemType != null) {
			if (isStringType(elemType)) {
				final v = renameVar("x");
				return OcamlExpr.EFun([OcamlPat.PVar(v)], OcamlExpr.EIdent(v));
			}
			if (isIntType(elemType))
				return OcamlExpr.EIdent("string_of_int");
			if (isBoolType(elemType))
				return OcamlExpr.EIdent("string_of_bool");
			if (isFloatType(elemType))
				return OcamlExpr.EIdent("string_of_float");
		}

		// Fallback: use `Std.string` on the boxed value.
		//
		// This is slower than direct `string_of_*`, but it matches portable expectations
		// and is required by upstream workloads (e.g. `Array.toString` on `Array<Dynamic>`).
		final v = renameVar("x");
		return OcamlExpr.EFun([OcamlPat.PVar(v)], OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Std"), "string"), [
			OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EIdent(v)])
		]));
	}

	static function unwrap(e:TypedExpr):TypedExpr {
		var current = e;
		while (true) {
			switch (current.expr) {
				case TParenthesis(inner):
					current = inner;
				case TMeta(_, inner):
					current = inner;
				case _:
					return current;
			}
		}
	}

	function buildCondition(cond:TypedExpr):OcamlExpr {
		final plannedTruthiness = buildPlannedNullableBoolTruthiness(cond);
		if (plannedTruthiness != null)
			return plannedTruthiness;
		// The Haxe typed AST can sometimes keep `Null<Bool>` in condition position
		// (notably after switch lowering to `if tmp == null ... else if tmp ...`).
		//
		// Our nullable primitive representation is `Obj.t`, so we must unbox to a
		// real OCaml `bool` before emitting `if/while`.
		if (nullablePrimitiveKind(cond.t) == "bool")
			return safeUnboxNullableBool(buildExpr(cond));
		if (isDynamicLike(cond.t)) {
			final asObj = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(cond)]);
			return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [asObj]);
		}
		return buildExpr(cond);
	}

	function exprAsStatement(expr:OcamlExpr, ?source:TypedExpr):OcamlExpr {
		if (source != null && currentControlPlan != null) {
			final policy = try {
				currentControlPlan.statementResultPolicyFor(source);
			} catch (error:Dynamic) {
				return controlPlanInvariant(Std.string(error), source.pos);
			};
			if (policy == OcamlStatementResultPolicy.PreserveNonLocalResult)
				return expr;
		}
		return switch (expr) {
			// A direct `raise` already works where OCaml expects `unit`. Do not wrap it.
			// For an `if` or `switch` whose branches all leave the function, the sealed
			// statement-result policy above preserves the complete expression instead.
			case ERaise(_):
				expr;
			case _:
				OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [expr]);
		}
	}

	public function buildExpr(e:TypedExpr):OcamlExpr {
		final anonymousLiteralCandidate = OcamlAnonymousStructurePlan.isAdmittedLiteralCandidate(e);
		final plannedAnonymousLiteral = currentAnonymousStructurePlan == null
			|| !anonymousLiteralCandidate ? null : currentAnonymousStructurePlan.requireLiteral(e, representationRegistry);
		final plannedAnonymousOperation = currentAnonymousStructurePlan == null ? null : currentAnonymousStructurePlan.operationFor(e, representationRegistry);
		final structuralFieldCandidate = plannedAnonymousOperation == null && OcamlStructuralFieldPlanner.isCandidate(e);
		final plannedStructuralField = currentStructuralFieldPlan == null
			|| !structuralFieldCandidate ? null : currentStructuralFieldPlan.decisionFor(e);
		final bytesAccessOccurrence = OcamlBytesAccessPlan.admittedOccurrence(e);
		final plannedBytesAccess = currentBytesAccessPlan == null
			|| bytesAccessOccurrence == null ? null : currentBytesAccessPlan.requireFor(e, representationRegistry);
		final bytesMutationOccurrence = OcamlBytesMutationPlan.admittedOccurrence(e);
		final plannedBytesMutation = currentBytesMutationPlan == null
			|| bytesMutationOccurrence == null ? null : currentBytesMutationPlan.requireFor(e, representationRegistry);
		final plannedBytesProducer = currentBytesProducerPlan == null
			|| OcamlBytesProducerPlan.admittedKind(e) == null ? null : currentBytesProducerPlan.requireFor(e, representationRegistry);
		final bytesReadOccurrence = OcamlBytesReadPlan.admittedOccurrence(e);
		final plannedBytesRead = currentBytesReadPlan == null
			|| bytesReadOccurrence == null ? null : currentBytesReadPlan.requireFor(e, representationRegistry);
		final arrayReadOccurrence = OcamlArrayReadPlan.admittedOccurrence(e);
		final plannedArrayRead = currentArrayReadPlan == null || arrayReadOccurrence == null ? null : currentArrayReadPlan.requireFor(e);
		final dynamicBracketReadOccurrence = OcamlArrayReadPlan.admittedDynamicOccurrence(e);
		final plannedDynamicBracketRead = currentArrayReadPlan == null
			|| dynamicBracketReadOccurrence == null ? null : currentArrayReadPlan.requireDynamicFor(e);
		final plannedIMapStorageAliasUse = currentIMapInterfacePlan == null ? null : currentIMapInterfacePlan.storageAliasUseFor(e);
		final iMapInterfaceCallCandidate = isExactIMapInterfaceCall(e);
		final plannedIMapInterfaceCall = currentIMapInterfacePlan == null ? null : currentIMapInterfacePlan.callFor(e);
		final plannedCall = currentCallPlan == null ? null : currentCallPlan.decisionFor(e);
		final plannedReflectCompareValue = currentReflectComparePlan == null ? null : currentReflectComparePlan.decisionForValue(e);
		final plannedReflectCompareCall = currentReflectComparePlan == null ? null : currentReflectComparePlan.decisionForCall(e);
		final built:OcamlExpr = switch (e.expr) {
			case TObjectDecl(fields) if (plannedAnonymousLiteral != null):
				buildAnonymousLiteral(plannedAnonymousLiteral, fields.map(field -> ({name: field.name, expr: field.expr})), e.pos);
			case _ if (anonymousLiteralCandidate):
				anonymousStructureInvariant("an admitted object literal reached syntax without its validated structure and initialization plan", e.pos);
			case TField(receiver, FAnon(_))
				if (plannedAnonymousOperation != null && plannedAnonymousOperation.kind == OcamlAnonymousStructureOperationKind.ReadField):
				buildAnonymousRead(plannedAnonymousOperation, receiver, e.pos);
			case TBinop(OpAssign, {expr: TField(receiver, FAnon(_))}, value)
				if (plannedAnonymousOperation != null
					&& plannedAnonymousOperation.kind == OcamlAnonymousStructureOperationKind.WriteField):
				buildAnonymousWrite(plannedAnonymousOperation, receiver, value, e.pos);
			case TBinop(OpAssignOp(OpAdd), {expr: TField(receiver, FAnon(_))}, value)
				if (plannedAnonymousOperation != null
					&& plannedAnonymousOperation.kind == OcamlAnonymousStructureOperationKind.CompoundWriteField):
				buildAnonymousCompoundWrite(plannedAnonymousOperation, receiver, value, e.pos);
			case _ if (plannedAnonymousOperation != null):
				anonymousStructureInvariant('anonymous operation "${plannedAnonymousOperation.id}" no longer matches its typed expression', e.pos);
			case TField(receiver, FAnon(_)) if (plannedStructuralField != null):
				buildStructuralField(plannedStructuralField, receiver, null, e.pos);
			case TField(receiver, FClosure(null, _)) if (plannedStructuralField != null):
				buildStructuralField(plannedStructuralField, receiver, null, e.pos);
			case TBinop(OpAssign, {expr: TField(receiver, FAnon(_))}, value) if (plannedStructuralField != null):
				buildStructuralField(plannedStructuralField, receiver, value, e.pos);
			case _ if (structuralFieldCandidate):
				structuralFieldInvariant("an ambiguous structural field reached syntax without its sealed typed decision", e.pos);
			case _ if (plannedBytesAccess != null && bytesAccessOccurrence != null):
				buildBytesAccess(plannedBytesAccess, bytesAccessOccurrence.receiver, bytesAccessOccurrence.arguments, e.pos);
			case _ if (bytesAccessOccurrence != null):
				bytesAccessInvariant("an admitted Bytes access reached syntax without its sealed occurrence plan", e.pos);
			case _ if (plannedBytesMutation != null && bytesMutationOccurrence != null):
				buildBytesMutation(plannedBytesMutation, bytesMutationOccurrence.receiver, bytesMutationOccurrence.arguments, e.pos);
			case _ if (bytesMutationOccurrence != null):
				bytesMutationInvariant("an admitted mutating Bytes operation reached syntax without its sealed occurrence plan", e.pos);
			case TNew(_, _, arguments) if (plannedBytesProducer != null):
				buildBytesProducer(plannedBytesProducer, arguments, e.pos);
			case TCall(_, arguments) if (plannedBytesProducer != null):
				buildBytesProducer(plannedBytesProducer, arguments, e.pos);
			case _ if (plannedBytesRead != null && bytesReadOccurrence != null):
				buildBytesRead(plannedBytesRead, bytesReadOccurrence.receiver, bytesReadOccurrence.arguments, e.pos);
			case _ if (bytesReadOccurrence != null):
				bytesReadInvariant("an admitted read-only Bytes operation reached syntax without its sealed occurrence plan", e.pos);
			case TArray(_, _) if (plannedArrayRead != null && arrayReadOccurrence != null):
				buildArrayRead(plannedArrayRead, arrayReadOccurrence.receiver, arrayReadOccurrence.index, e.pos);
			case TArray(_, _) if (arrayReadOccurrence != null):
				arrayReadInvariant("an admitted standard Array bracket read reached syntax without its sealed decision", e.pos);
			case TArray(_, _) if (plannedDynamicBracketRead != null && dynamicBracketReadOccurrence != null):
				buildDynamicBracketRead(plannedDynamicBracketRead, dynamicBracketReadOccurrence.receiver, dynamicBracketReadOccurrence.index, e.pos);
			case TArray(_, _) if (dynamicBracketReadOccurrence != null):
				arrayReadInvariant("an admitted non-Array bracket read reached syntax without its sealed compatibility decision", e.pos);
			case TNew(_, _, _) if (OcamlBytesProducerPlan.admittedKind(e) != null):
				bytesProducerInvariant("an admitted non-null Bytes constructor reached syntax without its sealed occurrence plan", e.pos);
			case TCall(_, _) if (OcamlBytesProducerPlan.admittedKind(e) != null):
				bytesProducerInvariant("an admitted non-null Bytes producer reached syntax without its sealed occurrence plan", e.pos);
			case TLocal(local) if (plannedIMapStorageAliasUse != null):
				buildRawStorageAliasLocal(local);
			case TCast(inner, _) if (plannedIMapStorageAliasUse != null):
				buildExpr(inner);
			case _ if (plannedIMapStorageAliasUse != null):
				callPlanInvariant('standard Map storage alias "${plannedIMapStorageAliasUse.id}" no longer matches its sealed local occurrence', e.pos);
			case TCall(callee, arguments) if (plannedIMapInterfaceCall != null):
				buildPlannedIMapInterfaceCall(plannedIMapInterfaceCall, callee, arguments, e.pos);
			case TCall(_, _) if (iMapInterfaceCallCandidate):
				callPlanInvariant("an exact IMap interface call reached syntax without its sealed dispatch decision", e.pos);
			case TCall(_, arguments) if (plannedReflectCompareCall != null):
				buildPlannedReflectCompareCall(plannedReflectCompareCall, arguments, e.pos);
			case TCall(callee, _) if (OcamlReflectComparePlan.isResolvedStandardCompare(callee)):
				callPlanInvariant("a resolved Reflect.compare call reached syntax without its sealed comparison-domain plan", e.pos);
			case TNew(_, _, arguments) if (plannedCall != null):
				buildPlannedCall(plannedCall, null, arguments, e.pos);
			case TCall(callee, arguments) if (plannedCall != null):
				buildPlannedCall(plannedCall, callee, arguments, e.pos);
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, _)
				if (functionPlanRegistry.hasOptionalCallableDeclaration(OcamlCallPlanner.calleeId(classRef.get(), fieldRef.get()))
					|| functionPlanRegistry.hasEffectOnlyCallableDeclaration(OcamlCallPlanner.calleeId(classRef.get(), fieldRef.get()))):
				callPlanInvariant('admitted call "${OcamlCallPlanner.calleeId(classRef.get(), fieldRef.get())}" reached syntax without its sealed occurrence plan',
					e.pos);
			case TCall(callee, arguments) if (OcamlCallPlanner.isAdmittedFunctionValueCall(callee, arguments, e.t, representationRegistry)):
				callPlanInvariant("admitted typed function-value call reached syntax without its sealed occurrence plan", e.pos);
			case _ if (plannedReflectCompareValue != null):
				buildPlannedReflectCompareFunction(plannedReflectCompareValue, e.pos);
			case _ if (OcamlReflectComparePlan.isResolvedStandardCompare(e)):
				final source = OcamlLoweredOrigin.sourceSpan(e.pos);
				final available = currentReflectComparePlan == null ? [] : currentReflectComparePlan.decisions()
					.map(decision -> '${decision.source.file}:${decision.source.min}:${decision.source.max}/${decision.domain}');
				callPlanInvariant('a resolved Reflect.compare function value with type ${TypeTools.toString(e.t)} at ${source.file}:${source.min}:${source.max} reached syntax in ${currentFunctionPlanBinding == null ? "standalone-or-unbound" : currentFunctionPlanBinding.functionId} without its sealed comparison-domain plan; available=${available.join(",")}',
					e.pos);
			case TTypeExpr(_):
				switch (e.expr) {
					case TTypeExpr(t):
						switch (t) {
							case TClassDecl(clsRef):
								final cls = clsRef.get();
								final full = (cls.pack ?? []).concat([cls.name]).join(".");
								final native = extractNativeString(cls.meta);
								final name = native != null ? native : full;
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "class_"), [OcamlExpr.EConst(OcamlConst.CString(name))]);
							case TEnumDecl(enumRef):
								final en = enumRef.get();
								final full = (en.pack ?? []).concat([en.name]).join(".");
								final native = extractNativeString(en.meta);
								final name = native != null ? native : full;
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "enum_"), [OcamlExpr.EConst(OcamlConst.CString(name))]);
							case TAbstract(_):
								// Abstract type expressions (e.g. `Float`) do not correspond to a runtime class/enum
								// value on this target. Represent them as `null` so reflective APIs like
								// `Type.getClass(Float)` behave as expected in upstream unit tests.
								OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
							case _:
								#if macro
								guardrailError("reflaxe.ocaml (M10): type expressions for this type kind are not supported yet. (bd: haxe.ocaml-eli)", e.pos);
								#end
								OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
						}
					case _:
						OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
			case TConst(TThis):
				OcamlExpr.EIdent("self");
			case TConst(TSuper):
				// `super` as a value is lowered as `self`. The callsite decides whether it needs
				// base dispatch (e.g. `super.foo(...)`) or base ctor calls (`super(...)`).
				OcamlExpr.EIdent("self");
			case TConst(TNull):
				// `null` is used across many portable Haxe APIs (e.g. Sys.getEnv).
				//
				// - For nullable primitives (Null<Int>/Null<Float>/Null<Bool>), represent
				//   null as `HxRuntime.hx_null : Obj.t` directly (no cast).
				// - Exact String uses the one runtime-owned String sentinel selected
				//   by the sealed representation.
				// - Unmigrated families retain the compatibility cast.
				if (nullablePrimitiveKind(e.t) != null) {
					OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				} else if (OcamlRepresentationRegistry.isExactString(e.t)) {
					exactStringNullValue(OcamlRepresentationDomain.InternalValue, "null-literal", e.pos);
				} else {
					OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);
				}
			case TConst(c):
				// For nullable primitives, represent non-null values as `Obj.repr <prim>`.
				switch (nullablePrimitiveKind(e.t)) {
					case "int":
						switch (c) {
							case TInt(_):
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EConst(buildConst(c))]);
							case _:
								OcamlExpr.EConst(buildConst(c));
						}
					case "float":
						switch (c) {
							case TFloat(_):
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EConst(buildConst(c))]);
							case TInt(_):
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [
									OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [OcamlExpr.EConst(buildConst(c))])
								]);
							case _:
								OcamlExpr.EConst(buildConst(c));
						}
					case "bool":
						switch (c) {
							case TBool(_):
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EConst(buildConst(c))]);
							case _:
								OcamlExpr.EConst(buildConst(c));
						}
					case _:
						switch (c) {
							case TBool(_) if (isDynamicLike(e.t) || isTypeParameterType(e.t)):
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [OcamlExpr.EConst(buildConst(c))]);
							case _:
								OcamlExpr.EConst(buildConst(c));
						}
				}
			case TLocal(v):
				// Haxe's core-type `Null<T>` can “collapse” in typed expressions depending on
				// target semantics and implicit conversions (e.g. `Null<Int>` used as `Int`).
				//
				// Locals may therefore be *stored* using the nullable representation (`Obj.t`)
				// but *used* in a non-nullable primitive context, which must be coerced to the
				// correct OCaml primitive type at the usage site.
				final base = buildLocal(v, e.pos);
				final plannedRepresentation = plannedLocalRepresentation(v.id, e.pos);
				if (plannedRepresentation != null && plannedRepresentation.semanticTypeId == "Null<Int>")
					return buildNullIntRead(v, e, base);
				if (plannedRepresentation != null && plannedRepresentation.semanticTypeId == "Null<Bool>")
					return buildNullBoolRead(v, e, base);
				final varKind = nullablePrimitiveKind(v.t);
				final useKind = nullablePrimitiveKind(e.t);

				if (varKind != null && useKind == null) {
					return switch (varKind) {
						case "int" if (isIntType(e.t)):
							safeUnboxNullableInt(base);
						case "int" if (isFloatType(e.t)):
							OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [safeUnboxNullableInt(base)]);
						case "float" if (isFloatType(e.t)):
							safeUnboxNullableFloat(base);
						case "bool" if (isBoolType(e.t)):
							safeUnboxNullableBool(base);
						case _:
							base;
					}
				}

				if (varKind == null && useKind != null) {
					return switch (useKind) {
						case "int" if (isIntType(v.t)):
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [base]);
						case "float" if (isFloatType(v.t)):
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [base]);
						case "float" if (isIntType(v.t)):
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [base])]);
						case "bool" if (isBoolType(v.t)):
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [base]);
						case _:
							base;
					}
				}

				base;
			case TIdent(s):
				OcamlExpr.EIdent(s);
			case TParenthesis(inner):
				buildExpr(inner);
			case TBinop(op, e1, e2):
				buildBinop(e, op, e1, e2, e.t);
			case TUnop(op, postFix, inner):
				buildUnop(op, postFix, inner, e.t);
			case TFunction(tfunc):
				buildFunction(e, tfunc);
			case TIf(cond, eif, eelse):
				if (eelse == null) {
					// Haxe `if (cond) stmt;` is statement-typed (Void). Ensure both branches are `unit`
					// so the OCaml `if` is well-typed, even if `stmt` returns a value (e.g. Array.push).
					OcamlExpr.EIf(buildCondition(cond), exprAsStatement(buildExpr(eif), eif), OcamlExpr.EConst(OcamlConst.CUnit));
				} else {
					final expected = e.t;
					if (isVoidType(expected)) {
						return OcamlExpr.EIf(buildCondition(cond), exprAsStatement(buildExpr(eif), eif), exprAsStatement(buildExpr(eelse), eelse));
					}

					// Haxe can flow-type nullable primitives inside conditionals, but the typed AST
					// may still keep branch expressions as `Null<T>` even when the overall `if`
					// expression is typed as non-nullable `T` (notably from `??` lowering).
					//
					// Example (from upstream typed AST dumps):
					//   var a:Null<Int> = null;
					//   var b:Int = a ?? 2;
					// becomes:
					//   var tmp:Null<Int> = a;
					//   var b:Int = if (tmp != null) tmp else 2;
					// where the `then` is still typed as `Null<Int>`.
					//
					// OCaml requires both branches to have the same type, so we coerce between
					// `Null<primitive>` and `primitive` as needed.

					function coerceBranch(branch:TypedExpr):OcamlExpr {
						final toKind = nullablePrimitiveKind(expected);
						final fromKind = nullablePrimitiveKind(branch.t);

						// Null<prim> -> prim
						if (toKind == null) {
							if (isIntType(expected) && fromKind == "int") {
								return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_unwrap"), [buildExpr(branch)]);
							}
							if (isFloatType(expected) && fromKind == "float") {
								return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_float_unwrap"), [buildExpr(branch)]);
							}
							if (isBoolType(expected) && fromKind == "bool") {
								return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_bool_unwrap"), [buildExpr(branch)]);
							}
						}

						// prim -> Null<prim>
						if (toKind != null && fromKind == null) {
							switch (toKind) {
								case "int" if (isIntType(branch.t)):
									return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(branch)]);
								case "float" if (isFloatType(branch.t)):
									return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(branch)]);
								case "float" if (isIntType(branch.t)):
									return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"),
										[OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(branch)])]);
								case "bool" if (isBoolType(branch.t)):
									return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(branch)]);
								case _:
							}
						}

						return buildExpr(branch);
					}

					OcamlExpr.EIf(buildCondition(cond), coerceBranch(eif), coerceBranch(eelse));
				}
			case TBlock(el):
				buildBlock(el);
			case TVar(v, init):
				// Variable declarations should generally be handled by `buildBlock`
				// so that scope covers the remainder of the block.
				OcamlExpr.EConst(OcamlConst.CUnit);
			case TNew(clsRef, parameters, _)
				if (parameters.length == 0
					&& clsRef.get().constructor != null
					&& functionPlanRegistry.hasConstructorDeclaration(OcamlCallPlanner.calleeId(clsRef.get(), clsRef.get().constructor.get()))):
				callPlanInvariant('admitted constructor "${OcamlCallPlanner.calleeId(clsRef.get(), clsRef.get().constructor.get())}" reached syntax without its sealed occurrence plan',
					e.pos);
			case TNew(clsRef, _, args):
				final cls = clsRef.get();
				if (isStdArrayClass(cls) && args.length == 0) {
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
				} else if (cls.isExtern
					&& cls.constructor != null
					&& extractNativeString(cls.constructor.get().meta) != null
					&& OcamlNativeRuntimeBoundary.hasDeclaredRuntimeCapability(cls, cls.constructor.get())) {
					final constructor = cls.constructor.get();
					final nativeClassPath = extractNativeString(cls.meta);
					final nativeFieldPath = extractNativeString(constructor.meta);
					final resolved = resolveNativeStaticPath(moduleIdToOcamlModuleName(cls.module), "new", nativeClassPath, nativeFieldPath);
					OcamlNativeRuntimeBoundary.recordUsedExternCallable(ctx, cls, constructor, resolved.modulePath + "." + resolved.fieldName);
					final builtArgs = args.map(buildExpr);
					OcamlExpr.EApp(OcamlExpr.EField(resolved.moduleExpr, resolved.fieldName),
						builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
				} else if (isStdBytesClass(cls)) {
					bytesProducerInvariant("the internal Bytes constructor reached legacy syntax without its sealed occurrence plan", e.pos);
				} else {
					final modName = moduleIdToOcamlModuleName(cls.module);
					final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
					final createName = ctx.scopedValueName(cls.module, cls.name, "create");
					final fn = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(createName) : OcamlExpr.EField(OcamlExpr.EIdent(modName), createName);

					// Constructor callsites must fully apply all optional parameters.
					//
					// Why:
					// - reflaxe.ocaml represents Haxe optional parameters (`?x:T`) like `Null<T>`:
					//   missing args are supplied as `HxRuntime.hx_null` (cast via `Obj.magic` when needed).
					// - If we omit trailing optional ctor args in the emitted `Foo.create a0 a1`,
					//   OCaml treats it as *partial application* and we end up with a function value
					//   where an instance record is expected (breaking at compile time).
					//
					// This especially matters for `sys.io.Process` parity (optional args + detached)
					// used by HXHX Stage 4 macro transport (bd: haxe.ocaml-xgv.3.3).
					final expectedCtorArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = if (cls.constructor == null) {
						null;
					} else {
						final ctorField = cls.constructor.get();
						switch (TypeTools.follow(ctorField.type)) {
							case TFun(fargs, _): fargs;
							case _: null;
						}
					}

					final builtArgs:Array<OcamlExpr> = [];
					if (expectedCtorArgs != null) {
						inline function hxNullForType(t:Type, index:Int):OcamlExpr {
							return missingOptionalArgValue(t, "constructor-optional:" + index, e.pos);
						}

						for (i in 0...args.length) {
							if (i >= expectedCtorArgs.length)
								break;
							final ea = expectedCtorArgs[i];
							builtArgs.push(coerceForAssignment(ea.t, args[i]));
						}
						if (args.length < expectedCtorArgs.length) {
							for (i in args.length...expectedCtorArgs.length) {
								final ea = expectedCtorArgs[i];
								if (ea.opt) {
									builtArgs.push(hxNullForType(ea.t, i));
								} else {
									#if macro
									guardrailError("reflaxe.ocaml: new " + cls.name + " is missing required constructor argument '" + ea.name + "'.", e.pos);
									#end
									builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
								}
							}
						}
					} else {
						for (a in args)
							builtArgs.push(buildExpr(a));
					}

					OcamlExpr.EApp(fn, builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
				}
			case TCall(fn, args):
				{
					// Escape hatch: raw OCaml injection.
					final injected:Null<OcamlExpr> = switch (unwrap(fn).expr) {
						case TIdent("__ocaml__"):
							if (args.length < 1) {
								#if macro
								guardrailError("reflaxe.ocaml: __ocaml__ expects at least one string argument.", e.pos);
								#end
								OcamlExpr.EConst(OcamlConst.CUnit);
							} else {
								final a = unwrap(args[0]);
								switch (a.expr) {
									case TConst(TString(s)):
										switch (OcamlRawInjection.plan(s, args.length - 1)) {
											case PlanInvalid(message):
												rawInjectionFailure(message, a.pos);
												OcamlExpr.EConst(OcamlConst.CUnit);
											case PlanReady(plan):
												final compiledArgs = new Array<OcamlExpr>();
												for (i in 1...args.length)
													compiledArgs.push(buildExpr(args[i]));
												switch (OcamlRawInjection.materialize(plan, compiledArgs)) {
													case InjectionReady(injection):
														OcamlExpr.ERawInjection(injection);
													case InjectionInvalid(message):
														rawInjectionFailure(message, a.pos);
														OcamlExpr.EConst(OcamlConst.CUnit);
												}
										}
									case _:
										#if macro
										guardrailError("reflaxe.ocaml: __ocaml__ argument must be a constant string.", e.pos);
										#end
										OcamlExpr.EConst(OcamlConst.CUnit);
								}
							}
						case _:
							null;
					};

					if (injected != null) {
						injected;
					} else
						switch (unwrap(fn).expr) {
							case TConst(TSuper):
								// Only lower `super()` when we are using the “virtual class” model (M10),
								// otherwise keep the previous (limited) behavior for upstream stdlib output
								// and other non-virtual cases.
								final curFull = ctx.currentTypeFullName;
								final allowSuperCtor = curFull != null && ctx.dispatchTypes.exists(curFull);
								if (!allowSuperCtor) {
									final builtArgs = args.map(buildExpr);
									OcamlExpr.EApp(buildExpr(fn), builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
								} else {
									#if macro
									if (ctx.currentSuperModuleId == null || ctx.currentSuperTypeName == null) {
										guardrailError("reflaxe.ocaml (M10): encountered super() call, but current super class is unknown.", e.pos);
										OcamlExpr.EConst(OcamlConst.CUnit);
									} else {
									#end
										final supModId = ctx.currentSuperModuleId;
										final supTypeName = ctx.currentSuperTypeName;
										final ctorName = ctx.scopedValueName(supModId, supTypeName, "__ctor");

										final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
										final supModName = moduleIdToOcamlModuleName(supModId);
										final callFn = (selfMod != null && selfMod == supModName) ? OcamlExpr.EIdent(ctorName) : OcamlExpr.EField(OcamlExpr.EIdent(supModName),
											ctorName);

										inline function hxNullForType(t:Type, index:Int):OcamlExpr {
											return missingOptionalArgValue(t, "super-constructor-optional:" + index, e.pos);
										}

										final builtArgs = args.map(buildExpr);
										final callArgs:Array<OcamlExpr> = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"),
											[OcamlExpr.EIdent("self")])].concat(builtArgs);
										final expected = ctx.currentSuperCtorArgs;
										if (expected != null) {
											if (builtArgs.length < expected.length) {
												for (i in builtArgs.length...expected.length) {
													final ea = expected[i];
													if (!ea.opt) {
														#if macro
														guardrailError("reflaxe.ocaml (M10): super() call is missing required argument '" + ea.name + "'.",
															e.pos);
														#end
													}
													callArgs.push(hxNullForType(ea.t, i));
												}
											}
											// Calling convention: if a ctor has zero Haxe args, represent it as `(... -> unit)` and pass `()`.
											if (expected.length == 0)
												callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
										} else {
											// Calling convention: `super()` supplies `unit` when there are no args.
											if (args.length == 0)
												callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
										}
										OcamlExpr.EApp(callFn, callArgs);
									#if macro
									}
									#end
								}
							case _:
								switch (fn.expr) {
									case TField(_, FStatic(clsRef, cfRef)):
										final cls = clsRef.get();
										final cf = cfRef.get();

										// Extern interop: labelled/optional args via @:ocamlLabel("...") on parameters.
										// (bd: haxe.ocaml-28t.8.3)
										if (cls.isExtern) {
											final labelsByArgName = extractOcamlLabelByArgName(cf);
											if (labelsByArgName != null && labelsByArgName.iterator().hasNext()) {
												final expectedArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (TypeTools.follow(cf.type)) {
													case TFun(fargs, _): fargs;
													case _: null;
												}

												final applyArgs:Array<OcamlApplyArg> = [];
												if (expectedArgs != null) {
													for (i in 0...args.length) {
														if (i >= expectedArgs.length)
															break;
														final ea = expectedArgs[i];
														final label = labelsByArgName.get(ea.name);
														final coerced = isTypeParameterType(ea.t) ? buildExpr(args[i]) : coerceForAssignment(ea.t, args[i]);
														if (label != null) {
															if (ea.opt) {
																applyArgs.push({
																	label: label,
																	isOptional: true,
																	expr: buildOptionalArgOptionExprForInterop(args[i], ea.t)
																});
															} else {
																applyArgs.push({label: label, isOptional: false, expr: coerced});
															}
														} else {
															applyArgs.push({label: null, isOptional: false, expr: coerced});
														}
													}
												} else {
													for (a in args)
														applyArgs.push({label: null, isOptional: false, expr: buildExpr(a)});
												}

												final builtFn = buildExpr(fn);
												return OcamlExpr.EAppArgs(builtFn, applyArgs.length == 0 ? [
													{
														label: null,
														isOptional: false,
														expr: OcamlExpr.EConst(OcamlConst.CUnit)
													}
												] : applyArgs);
											}
										}

										// OCaml-native surface: `ocaml.Ref<T>` calls lower to `ref` / `!` / `:=`.
										//
										// This is an opt-in API surface for emitting idiomatic OCaml refs, separate from
										// the backend's internal ref-based lowering for portable Haxe mutability semantics.
										if (cls.pack != null && cls.pack.length == 1 && cls.pack[0] == "ocaml" && cls.name == "Ref") {
											switch (cf.name) {
												case "make" if (args.length == 1):
													return OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [buildExpr(args[0])]);
												case "get" if (args.length == 1):
													return OcamlExpr.EUnop(OcamlUnop.Deref, buildExpr(args[0]));
												case "set" if (args.length == 2):
													return OcamlExpr.EAssign(OcamlAssignOp.RefSet, buildExpr(args[0]), buildExpr(args[1]));
												case _:
											}
										}

										if (cls.pack != null && cls.pack.length == 0 && cls.name == "Type") {
											final anyNull:OcamlExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
											switch (cf.name) {
												case "getClass" if (args.length == 1):
													final a0 = args[0];
													final a0Type = unwrapNullType(a0.t);
													final a0Expr = buildExpr(a0);
													final asObj:OcamlExpr = (nullablePrimitiveKind(a0Type) != null) ? a0Expr : switch (a0Type) {
														case TDynamic(_), TAnonymous(_), TMono(_), TLazy(_): a0Expr;
														case _: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [a0Expr]);
													};
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getClass"), [asObj]);
												case "typeof" if (args.length == 1):
													{
														// `Type.typeof` is defined as `typeof(v:Dynamic):ValueType`, but it is used heavily by
														// assertion/test harnesses (utest) to decide comparison strategies and to build
														// human-friendly error messages.
														//
														// Important: implement this *in generated OCaml code* rather than in the runtime
														// library, because the runtime library must not depend on the compiled `Type`
														// module (dune builds the runtime as a separate library).
														final a0 = args[0];
														final a0Expr = buildExpr(a0);
														final a0Unwrap = unwrapNullType(a0.t);

														inline function toDynamicObj(e:TypedExpr, built:OcamlExpr):OcamlExpr {
															if (isDynamicLike(e.t) || nullablePrimitiveKind(e.t) != null)
																return built;
															final enumName = fullNameOfTypeEnum(e.t);
															final nullableEnumName = isNullableEnumType(e.t);

															var obj:OcamlExpr;
															if (isBoolType(e.t)) {
																obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [built]);
															} else {
																obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
															}

															if (enumName != null) {
																obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
																	[OcamlExpr.EConst(OcamlConst.CString(enumName)), obj]);
															} else if (nullableEnumName != null) {
																obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
																	[OcamlExpr.EConst(OcamlConst.CString(nullableEnumName)), obj]);
															}
															return obj;
														}

														final tmp = freshTmp("typeof_v");
														final v = toDynamicObj(a0, a0Expr);

														inline function vt0(name:String):OcamlExpr {
															return OcamlExpr.EField(OcamlExpr.EIdent("Type"), name);
														}
														inline function vt1(name:String, arg:OcamlExpr):OcamlExpr {
															return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Type"), name), [arg]);
														}

														final isNull = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "is_null"),
															[OcamlExpr.EIdent(tmp)]);
														final isBoxedBool = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "is_boxed_bool"),
															[OcamlExpr.EIdent(tmp)]);
														final isInt = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "is_int"),
															[OcamlExpr.EIdent(tmp)]);
														final tag = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "tag"), [OcamlExpr.EIdent(tmp)]);
														final isDouble = OcamlExpr.EBinop(OcamlBinop.Eq, tag,
															OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "double_tag"));
														final isString = OcamlExpr.EBinop(OcamlBinop.Eq, tag,
															OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "string_tag"));
														final isClosure = OcamlExpr.EBinop(OcamlBinop.Eq, tag,
															OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "closure_tag"));

														final enumNameTmp = freshTmp("enum_name");
														final classTmp = freshTmp("cls");

														final enumCase = OcamlExpr.EMatch(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"),
															"name_opt"), [OcamlExpr.EIdent(tmp)]),
															[
																{
																	pat: OcamlPat.PConstructor("Some", [OcamlPat.PVar(enumNameTmp)]),
																	guard: null,
																	expr: vt1("TEnum",
																		OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "enum_"),
																			[OcamlExpr.EIdent(enumNameTmp)]))
																},
																{
																	pat: OcamlPat.PAny,
																	guard: null,
																	expr: OcamlExpr.ELet(classTmp,
																		OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getClass"),
																			[OcamlExpr.EIdent(tmp)]),
																		OcamlExpr.EIf(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "is_null"),
																			[OcamlExpr.EIdent(classTmp)]),
																			vt0("TObject"), vt1("TClass", OcamlExpr.EIdent(classTmp))),
																		false)
																}
															]);

														final classify = OcamlExpr.EIf(isNull, vt0("TNull"),
															OcamlExpr.EIf(isBoxedBool, vt0("TBool"),
																OcamlExpr.EIf(isInt, vt0("TInt"),
																	OcamlExpr.EIf(isDouble, vt0("TFloat"),
																		OcamlExpr.EIf(isString,
																			vt1("TClass",
																				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "class_"),
																					[OcamlExpr.EConst(OcamlConst.CString("String"))])),
																			OcamlExpr.EIf(isClosure, vt0("TFunction"), enumCase))))));

														OcamlExpr.ELet(tmp, v, classify, false);
													}
												case "getClassName" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getClassName"), [buildExpr(args[0])]);
												case "getEnumName" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getEnumName"), [buildExpr(args[0])]);
												case "getSuperClass" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getSuperClass"), [buildExpr(args[0])]);
												case "getEnum" if (args.length == 1):
													{
														final a0 = args[0];
														switch (followNoAbstracts(unwrapNullType(a0.t))) {
															case TEnum(eRef, _):
																final en = eRef.get();
																final native = extractNativeString(en.meta);
																final runtimeName = native != null ? native : fullNameOfEnumType(en);
																OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "enum_"),
																	[OcamlExpr.EConst(OcamlConst.CString(runtimeName))]);
															case _:
																final built = buildExpr(a0);
																final asObj = (isDynamicLike(a0.t) || nullablePrimitiveKind(a0.t) != null) ? built : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"),
																	"repr"), [built]);
																OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"),
																	[OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getEnum"), [asObj])]);
														}
													}
												case "getInstanceFields" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getInstanceFields"), [buildExpr(args[0])]);
												case "getClassFields" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getClassFields"), [buildExpr(args[0])]);
												case "getEnumConstructs" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "getEnumConstructs"), [buildExpr(args[0])]);
												case "enumConstructor" if (args.length == 1):
													{
														final a0 = args[0];
														final nullString:OcamlExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"),
															[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);

														switch (TypeTools.follow(unwrapNullType(a0.t))) {
															case TEnum(eRef, _):
																final en = eRef.get();

																final tmp = freshTmp("enum_ctor");
																final repr = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(a0)]);
																final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp),
																	OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null"));

																final cases:Array<OcamlMatchCase> = [];
																for (name in en.names) {
																	final ef = en.constructs.get(name);
																	if (ef == null)
																		continue;
																	final native = extractNativeString(ef.meta);
																	final outName = native != null ? native : ef.name;
																	final hasArgs = switch (TypeTools.follow(ef.type)) {
																		case TFun(fargs, _): fargs != null && fargs.length > 0;
																		case _: false;
																	}
																	final patArgs = hasArgs ? [OcamlPat.PAny] : [];
																	cases.push({
																		pat: OcamlPat.PConstructor(ef.name, patArgs),
																		guard: null,
																		expr: OcamlExpr.EConst(OcamlConst.CString(outName))
																	});
																}
																final m = OcamlExpr.EMatch(buildExpr(a0), cases);

																OcamlExpr.ELet(tmp, repr, OcamlExpr.EIf(isNull, nullString, m), false);
															case _:
																// Dynamic-friendly fallback (utest calls `Type.enumConstructor(v)` where `v:Dynamic`).
																final built = buildExpr(a0);
																final asObj = (isDynamicLike(a0.t) || nullablePrimitiveKind(a0.t) != null) ? built : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"),
																	"repr"), [built]);
																OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "enumConstructor"), [asObj]);
														}
													}
												case "enumIndex" if (args.length == 1):
													buildEnumIndex(args[0]);
												case "enumParameters" if (args.length == 1):
													{
														final a0 = args[0];
														final built = buildExpr(a0);
														final asObj = (isDynamicLike(a0.t) || nullablePrimitiveKind(a0.t) != null) ? built : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"),
															"repr"), [built]);
														OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "enumParameters"), [asObj]);
													}
												case "resolveClass" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "resolveClass"), [buildExpr(args[0])]);
												case "resolveEnum" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "resolveEnum"), [buildExpr(args[0])]);
												case "createInstance" if (args.length == 2):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
														OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "createInstance"),
															[buildExpr(args[0]), buildExpr(args[1])])
													]);
												case "createEmptyInstance" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
														OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "createEmptyInstance"),
															[buildExpr(args[0])])
													]);
												case "createEnum" if (args.length == 2 || args.length == 3):
													{
														final enumExpr = unwrap(args[0]);
														final ctorExpr = unwrap(args[1]);

														final paramsExpr:OcamlExpr = if (args.length == 2) {
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"),
																[OcamlExpr.EConst(OcamlConst.CUnit)]);
														} else {
															final a2 = unwrap(args[2]);
															switch (a2.expr) {
																case TConst(TNull):
																	OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"),
																		[OcamlExpr.EConst(OcamlConst.CUnit)]);
																case _:
																	buildExpr(args[2]);
															}
														};

														inline function dynArgToExpected(t:Type, obj:OcamlExpr):OcamlExpr {
															final ot = typeExprFromHaxeType(t);
															return switch (ot) {
																case OcamlTypeExpr.TIdent("Obj.t"):
																	obj;
																case OcamlTypeExpr.TIdent("bool"):
																	OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [obj]);
																case OcamlTypeExpr.TIdent("int") | OcamlTypeExpr.TIdent("float") | OcamlTypeExpr.TIdent("string") | OcamlTypeExpr.TIdent("bytes") | OcamlTypeExpr.TIdent("char"):
																	OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [obj]);
																case _:
																	OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [obj]);
															}
														}

														inline function missingOptionalArg(t:Type):OcamlExpr {
															final ot = typeExprFromHaxeType(t);
															return switch (ot) {
																case OcamlTypeExpr.TIdent("Obj.t"):
																	OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
																case _:
																	OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"),
																		[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);
															}
														}

														inline function ctorExprForEnum(en:EnumType, name:String):OcamlExpr {
															final modName = moduleIdToOcamlModuleName(en.module);
															final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
															final isSameModule = selfMod != null && selfMod == modName;
															return isSameModule ? OcamlExpr.EIdent(name) : OcamlExpr.EField(OcamlExpr.EIdent(modName), name);
														}

														function buildCtorCall(en:EnumType, ef:EnumField, paramsVar:String, lenVar:String):OcamlExpr {
															final argsInfo:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (TypeTools.follow(ef.type)) {
																case TFun(fargs, _): fargs;
																case _: null;
															}
															final argCount = argsInfo != null ? argsInfo.length : 0;
															final ctorName = ef.name;
															final baseCtor = ctorExprForEnum(en, ctorName);

															if (argCount == 0)
																return baseCtor;

															final getArg = function(i:Int, t:Type, opt:Bool):OcamlExpr {
																final len = OcamlExpr.EIdent(lenVar);
																final inBounds = OcamlExpr.EBinop(OcamlBinop.Gt, len, OcamlExpr.EConst(OcamlConst.CInt(i)));
																final fetch = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "get"),
																	[OcamlExpr.EIdent(paramsVar), OcamlExpr.EConst(OcamlConst.CInt(i))]);
																final ok = dynArgToExpected(t, fetch);
																final missing = opt ? missingOptionalArg(t) : OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [
																	OcamlExpr.EConst(OcamlConst.CString("Type.createEnum: missing ctor arg '"
																		+ (argsInfo != null ? argsInfo[i].name : ("a" + i)) + "'"))
																]);
																return OcamlExpr.EIf(inBounds, ok, missing);
															}

															final callArgs:Array<OcamlExpr> = [];
															for (i in 0...argCount) {
																final ai = argsInfo[i];
																callArgs.push(getArg(i, ai.t, ai.opt));
															}

															return (argCount > 1) ? OcamlExpr.EApp(baseCtor,
																[OcamlExpr.ETuple(callArgs)]) : OcamlExpr.EApp(baseCtor, [callArgs[0]]);
														}

														inline function runtimeCreateEnum():OcamlExpr {
															return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
																OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "createEnum"),
																	[buildExpr(args[0]), buildExpr(args[1]), paramsExpr])
															]);
														}

														switch (enumExpr.expr) {
															case TTypeExpr(TEnumDecl(enumRef)):
																final en = enumRef.get();
																switch (ctorExpr.expr) {
																	case TConst(TString(ctorName)):
																		final ef = en.constructs.get(ctorName);
																		if (ef != null) {
																			final paramsVar = freshTmp("params");
																			final lenVar = freshTmp("len");
																			OcamlExpr.ELet(paramsVar, paramsExpr,
																				OcamlExpr.ELet(lenVar,
																					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "length"),
																						[OcamlExpr.EIdent(paramsVar)]),
																					buildCtorCall(en, ef, paramsVar, lenVar), false),
																				false);
																		} else {
																			runtimeCreateEnum();
																		}
																	case _:
																		runtimeCreateEnum();
																}
															case _:
																runtimeCreateEnum();
														}
													}
												case "createEnumIndex" if (args.length == 2 || args.length == 3):
													{
														final enumExpr = unwrap(args[0]);
														final idxExpr = args[1];

														final paramsExpr:OcamlExpr = if (args.length == 2) {
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"),
																[OcamlExpr.EConst(OcamlConst.CUnit)]);
														} else {
															final a2 = unwrap(args[2]);
															switch (a2.expr) {
																case TConst(TNull):
																	OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"),
																		[OcamlExpr.EConst(OcamlConst.CUnit)]);
																case _:
																	buildExpr(args[2]);
															}
														};

														inline function dynArgToExpected(t:Type, obj:OcamlExpr):OcamlExpr {
															final ot = typeExprFromHaxeType(t);
															return switch (ot) {
																case OcamlTypeExpr.TIdent("Obj.t"):
																	obj;
																case OcamlTypeExpr.TIdent("bool"):
																	OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [obj]);
																case OcamlTypeExpr.TIdent("int") | OcamlTypeExpr.TIdent("float") | OcamlTypeExpr.TIdent("string") | OcamlTypeExpr.TIdent("bytes") | OcamlTypeExpr.TIdent("char"):
																	OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [obj]);
																case _:
																	OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [obj]);
															}
														}

														inline function missingOptionalArg(t:Type):OcamlExpr {
															final ot = typeExprFromHaxeType(t);
															return switch (ot) {
																case OcamlTypeExpr.TIdent("Obj.t"):
																	OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
																case _:
																	OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"),
																		[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);
															}
														}

														inline function ctorExprForEnum(en:EnumType, name:String):OcamlExpr {
															final modName = moduleIdToOcamlModuleName(en.module);
															final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
															final isSameModule = selfMod != null && selfMod == modName;
															return isSameModule ? OcamlExpr.EIdent(name) : OcamlExpr.EField(OcamlExpr.EIdent(modName), name);
														}

														function buildCtorCall(en:EnumType, ef:EnumField, paramsVar:String, lenVar:String):OcamlExpr {
															final argsInfo:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (TypeTools.follow(ef.type)) {
																case TFun(fargs, _): fargs;
																case _: null;
															}
															final argCount = argsInfo != null ? argsInfo.length : 0;
															final baseCtor = ctorExprForEnum(en, ef.name);
															if (argCount == 0)
																return baseCtor;

															final getArg = function(i:Int, t:Type, opt:Bool):OcamlExpr {
																final len = OcamlExpr.EIdent(lenVar);
																final inBounds = OcamlExpr.EBinop(OcamlBinop.Gt, len, OcamlExpr.EConst(OcamlConst.CInt(i)));
																final fetch = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "get"),
																	[OcamlExpr.EIdent(paramsVar), OcamlExpr.EConst(OcamlConst.CInt(i))]);
																final ok = dynArgToExpected(t, fetch);
																final missing = opt ? missingOptionalArg(t) : OcamlExpr.EApp(OcamlExpr.EIdent("failwith"),
																	[OcamlExpr.EConst(OcamlConst.CString("Type.createEnumIndex: missing ctor arg"))]);
																return OcamlExpr.EIf(inBounds, ok, missing);
															}

															final callArgs:Array<OcamlExpr> = [];
															for (i in 0...argCount) {
																final ai = argsInfo[i];
																callArgs.push(getArg(i, ai.t, ai.opt));
															}

															return (argCount > 1) ? OcamlExpr.EApp(baseCtor,
																[OcamlExpr.ETuple(callArgs)]) : OcamlExpr.EApp(baseCtor, [callArgs[0]]);
														}

														inline function runtimeCreateEnumIndex():OcamlExpr {
															return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
																OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "createEnumIndex"),
																	[buildExpr(args[0]), buildExpr(idxExpr), paramsExpr])
															]);
														}

														switch (enumExpr.expr) {
															case TTypeExpr(TEnumDecl(enumRef)):
																final en = enumRef.get();
																final paramsVar = freshTmp("params");
																final lenVar = freshTmp("len");
																final idxTmp = freshTmp("idx");

																final ctors:Array<EnumField> = [];
																for (name in en.names) {
																	final ef = en.constructs.get(name);
																	if (ef != null)
																		ctors.push(ef);
																}
																ctors.sort((a, b) -> a.index - b.index);

																final arms:Array<OcamlMatchCase> = [];
																for (ef in ctors) {
																	arms.push({
																		pat: OcamlPat.PConst(OcamlConst.CInt(ef.index)),
																		guard: null,
																		expr: buildCtorCall(en, ef, paramsVar, lenVar)
																	});
																}

																final defaultExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"),
																	[OcamlExpr.EConst(OcamlConst.CUnit)]);
																final body = (arms.length == 0) ? defaultExpr : OcamlExpr.EMatch(OcamlExpr.EIdent(idxTmp),
																	arms.concat([
																		{
																			pat: OcamlPat.PAny,
																			guard: null,
																			expr: defaultExpr
																		}
																	]));

																OcamlExpr.ELet(paramsVar, paramsExpr,
																	OcamlExpr.ELet(lenVar,
																		OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "length"),
																			[OcamlExpr.EIdent(paramsVar)]),
																		OcamlExpr.ELet(idxTmp, buildExpr(idxExpr), body, false), false),
																	false);
															case _:
																runtimeCreateEnumIndex();
														}
													}
												case "enumEq" if (args.length == 2):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "enum_eq"), [
														OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(args[0])]),
														OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(args[1])])
													]);
												case "allEnums" if (args.length == 1):
													switch (unwrap(args[0]).expr) {
														case TTypeExpr(TEnumDecl(enumRef)):
															final en = enumRef.get();
															final modName = moduleIdToOcamlModuleName(en.module);
															final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
															final isSameModule = selfMod != null && selfMod == modName;

															final tmp = freshTmp("allEnums");
															final init = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"),
																[OcamlExpr.EConst(OcamlConst.CUnit)]);
															final pushes:Array<OcamlExpr> = [];
															for (name in en.names) {
																final ef = en.constructs.get(name);
																if (ef == null)
																	continue;
																final hasArgs = switch (TypeTools.follow(ef.type)) {
																	case TFun(args2, _): args2 != null && args2.length > 0;
																	case _: false;
																}
																if (hasArgs)
																	continue;
																final ctorExpr = isSameModule ? OcamlExpr.EIdent(name) : OcamlExpr.EField(OcamlExpr.EIdent(modName),
																	name);
																pushes.push(OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [
																	OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "push"),
																		[OcamlExpr.EIdent(tmp), ctorExpr])
																]));
															}
															OcamlExpr.ELet(tmp, init, OcamlExpr.ESeq(pushes.concat([OcamlExpr.EIdent(tmp)])), false);
														case _:
															#if macro
															guardrailError("reflaxe.ocaml (M10): Type.allEnums currently only supports enum type expressions (e.g. Type.allEnums(MyEnum)). (bd: haxe.ocaml-eli)",
																e.pos);
															#end
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"),
																[OcamlExpr.EConst(OcamlConst.CUnit)]);
													}
												case _:
													#if macro
													guardrailError("reflaxe.ocaml (M10): Type." + cf.name + " is not implemented yet. (bd: haxe.ocaml-eli)",
														e.pos);
													#end
													anyNull;
											}
										} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "Reflect") {
											final anyNull:OcamlExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
											inline function toObjArg(e:TypedExpr):OcamlExpr {
												if (isDynamicLike(e.t) || nullablePrimitiveKind(e.t) != null)
													return buildExpr(e);
												return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e)]);
											}

											inline function toObjValue(e:TypedExpr):OcamlExpr {
												return toObjValueExpr(e);
											}
											switch (cf.name) {
												case "field" if (args.length == 2):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
														OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "get"),
															[toObjArg(args[0]), buildStdString(args[1])])
													]);
												case "getProperty" if (args.length == 2):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
														OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "get"),
															[toObjArg(args[0]), buildStdString(args[1])])
													]);
												case "callMethod" if (args.length == 3):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
														OcamlExpr.EApp(directReflectRuntimeFunction(e, OcamlReflectRuntimeUseKind.CallMethod),
															[toObjArg(args[0]), toObjArg(args[1]), buildExpr(args[2])])
													]);
												case "isFunction" if (args.length == 1):
													{
														final a0 = args[0];
														final a0Type = unwrapNullType(a0.t);
														final a0Expr = buildExpr(a0);
														final asObj:OcamlExpr = (nullablePrimitiveKind(a0Type) != null) ? a0Expr : switch (followNoAbstracts(a0Type)) {
															case TDynamic(_), TAnonymous(_), TMono(_), TLazy(_):
																a0Expr;
															case _:
																OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [a0Expr]);
														};
														OcamlExpr.EApp(directReflectRuntimeFunction(e, OcamlReflectRuntimeUseKind.IsFunction), [asObj]);
													}
												case "makeVarArgs" if (args.length == 1):
													final f = args[0];
													final isVoid = switch (followNoAbstracts(f.t)) {
														case TFun(_, ret): isVoidType(ret);
														case _: false;
													};
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
														OcamlExpr.EApp(directReflectRuntimeFunction(e,
															isVoid ? OcamlReflectRuntimeUseKind.MakeVarArgsVoid : OcamlReflectRuntimeUseKind.MakeVarArgs),
															[
																OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(f)])
															])
													]);
												case "setField" if (args.length == 3):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "set"),
														[toObjArg(args[0]), buildStdString(args[1]), toObjValue(args[2])]);
												case "hasField" if (args.length == 2):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "has"),
														[toObjArg(args[0]), buildStdString(args[1])]);
												case "fields" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "fields"), [toObjArg(args[0])]);
												case "deleteField" if (args.length == 2):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "delete"),
														[toObjArg(args[0]), buildStdString(args[1])]);
												case "copy" if (args.length == 1):
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
														OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "copy"), [toObjArg(args[0])])
													]);
												case "isObject" if (args.length == 1):
													OcamlExpr.EApp(directReflectRuntimeFunction(e, OcamlReflectRuntimeUseKind.IsObject), [toObjValue(args[0])]);
												case "isEnumValue" if (args.length == 1):
													OcamlExpr.EApp(directReflectRuntimeFunction(e, OcamlReflectRuntimeUseKind.IsEnumValue),
														[toObjValue(args[0])]);
												case "compareMethods" if (args.length == 2):
													OcamlExpr.EApp(directReflectRuntimeFunction(e, OcamlReflectRuntimeUseKind.CompareMethods),
														[toObjValue(args[0]), toObjValue(args[1])]);
												case _:
													#if macro
													guardrailError("reflaxe.ocaml (M10): Reflect." + cf.name + " is not implemented yet. (bd: haxe.ocaml-k7o)",
														e.pos);
													#end
													anyNull;
											}
										} else if (isStdStringClass(cls) && cf.name == "fromCharCode" && args.length == 1) {
											final a0 = args[0];
											final coerced = nullablePrimitiveKind(a0.t) == "int" ? safeUnboxNullableInt(buildExpr(a0)) : buildExpr(a0);
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "fromCharCode"), [coerced]);
										} else if (isStdBytesClass(cls)) {
											switch (cf.name) {
												case "alloc", "ofString", "ofData", "ofHex":
													#if macro
													guardrailError("reflaxe.ocaml: supported Bytes producers must use their sealed non-null producer plan; this occurrence was not admitted.",
														e.pos);
													#end
													OcamlExpr.EConst(OcamlConst.CUnit);
												case "fastGet" if (args.length == 2):
													bytesAccessInvariant("standard Bytes.fastGet bypassed its sealed access plan", e.pos);
												case _:
													#if macro
													guardrailError("reflaxe.ocaml (M6): unsupported Bytes static method '" + cf.name
														+ "'. (bd: haxe.ocaml-28t.7.5)",
														e.pos);
													#end
													OcamlExpr.EConst(OcamlConst.CUnit);
											}
										} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "Std" && cf.name == "int" && args.length == 1) {
											final arg = unwrap(args[0]);
											switch (arg.expr) {
												case TBinop(OpDiv, a, b) if (isIntType(a.t) && isIntType(b.t)):
													// Haxe `Std.int(a / b)` with Int operands: lower directly to OCaml int division.
													OcamlExpr.EBinop(OcamlBinop.Div, buildExpr(a), buildExpr(b));
												case _ if (isIntType(arg.t)):
													buildExpr(arg);
												case _:
													OcamlExpr.EApp(OcamlExpr.EIdent("int_of_float"), [buildExpr(arg)]);
											}
										} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "Std" && cf.name == "isOfType" && args.length == 2) {
											final a0 = args[0];
											final a0Type = unwrapNullType(a0.t);
											final a0Expr = buildExpr(a0);
											final asObj:OcamlExpr = (nullablePrimitiveKind(a0Type) != null) ? a0Expr : switch (followNoAbstracts(a0Type)) {
												case TDynamic(_):
													a0Expr;
												case TAbstract(_, _) if (isStdAnyAbstract(a0Type)):
													a0Expr;
												case TAnonymous(_) if (shouldAnonUseHxAnon(a0.t)):
													a0Expr;
												case _:
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [a0Expr]);
											};
											switch (unwrap(args[1]).expr) {
												// Core abstracts are not classes/enums in our runtime; implement best-effort
												// checks directly to support the `is` operator (which lowers to Std.isOfType).
												// (bd: haxe.ocaml-s16)
												case TTypeExpr(TAbstract(absRef)):
													final abs = absRef.get();
													final pack = abs.pack ?? [];
													if (pack.length == 0) {
														switch (abs.name) {
															case "Int":
																if (isIntType(a0.t)) {
																	OcamlExpr.EConst(OcamlConst.CBool(true));
																} else if (isFloatType(a0.t) || isBoolType(a0.t) || isStringType(a0.t)) {
																	OcamlExpr.EConst(OcamlConst.CBool(false));
																} else {
																	final tmp = freshTmp("isInt");
																	final v = OcamlExpr.EIdent(tmp);
																	final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, v,
																		OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null"));
																	final isInt = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "is_int"), [v]);
																	final isBoxedBool = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"),
																		"is_boxed_bool"), [v]);
																	final notBool = OcamlExpr.EUnop(OcamlUnop.Not, isBoxedBool);
																	OcamlExpr.ELet(tmp, asObj,
																		OcamlExpr.EIf(isNull, OcamlExpr.EConst(OcamlConst.CBool(false)),
																			OcamlExpr.EBinop(OcamlBinop.And, isInt, notBool)),
																		false);
																}
															case "Float":
																if (isFloatType(a0.t) || isIntType(a0.t)) {
																	OcamlExpr.EConst(OcamlConst.CBool(true));
																} else if (isBoolType(a0.t) || isStringType(a0.t)) {
																	OcamlExpr.EConst(OcamlConst.CBool(false));
																} else {
																	final tmp = freshTmp("isFloat");
																	final v = OcamlExpr.EIdent(tmp);
																	final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, v,
																		OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null"));
																	final isInt = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "is_int"), [v]);
																	final isBoxedBool = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"),
																		"is_boxed_bool"), [v]);
																	final notBool = OcamlExpr.EUnop(OcamlUnop.Not, isBoxedBool);
																	final intOk = OcamlExpr.EBinop(OcamlBinop.And, isInt, notBool);
																	final isDouble = OcamlExpr.EBinop(OcamlBinop.Eq,
																		OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "tag"), [v]),
																		OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "double_tag"));
																	OcamlExpr.ELet(tmp, asObj,
																		OcamlExpr.EIf(isNull, OcamlExpr.EConst(OcamlConst.CBool(false)),
																			OcamlExpr.EBinop(OcamlBinop.Or, intOk, isDouble)),
																		false);
																}
															case "Bool":
																if (isBoolType(a0.t)) {
																	OcamlExpr.EConst(OcamlConst.CBool(true));
																} else if (isIntType(a0.t) || isFloatType(a0.t) || isStringType(a0.t)) {
																	OcamlExpr.EConst(OcamlConst.CBool(false));
																} else {
																	final tmp = freshTmp("isBool");
																	final v = OcamlExpr.EIdent(tmp);
																	final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, v,
																		OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null"));
																	final isBoxedBool = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"),
																		"is_boxed_bool"), [v]);
																	OcamlExpr.ELet(tmp, asObj,
																		OcamlExpr.EIf(isNull, OcamlExpr.EConst(OcamlConst.CBool(false)), isBoxedBool), false);
																}
															case "String":
																if (isStringType(a0.t)) {
																	OcamlExpr.EConst(OcamlConst.CBool(true));
																} else if (isIntType(a0.t) || isFloatType(a0.t) || isBoolType(a0.t)) {
																	OcamlExpr.EConst(OcamlConst.CBool(false));
																} else {
																	final tmp = freshTmp("isString");
																	final v = OcamlExpr.EIdent(tmp);
																	final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, v,
																		OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null"));
																	final isString = OcamlExpr.EBinop(OcamlBinop.Eq,
																		OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "tag"), [v]),
																		OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "string_tag"));
																	OcamlExpr.ELet(tmp, asObj,
																		OcamlExpr.EIf(isNull, OcamlExpr.EConst(OcamlConst.CBool(false)), isString), false);
																}
															case _:
																OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "isOfType"),
																	[asObj, buildExpr(args[1])]);
														}
													} else {
														OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "isOfType"), [asObj, buildExpr(args[1])]);
													}
												case _:
													OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "isOfType"), [asObj, buildExpr(args[1])]);
											}
										} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "Std" && cf.name == "string" && args.length == 1) {
											buildStdString(args[0]);
										} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "StringTools" && cf.name == "urlEncode"
											&& args.length == 1) {
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "urlEncode"), [buildExpr(args[0])]);
										} else if (cls.pack != null && cls.pack.length == 0 && cls.name == "StringTools" && cf.name == "urlDecode"
											&& args.length == 1) {
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "urlDecode"), [buildExpr(args[0])]);
										} else {
											final expectedArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (TypeTools.follow(cf.type)) {
												case TFun(fargs, _):
													fargs;
												case _:
													switch (followNoAbstracts(unwrapNullType(fn.t))) {
														case TFun(fargs, _): fargs;
														case _: null;
													}
											}
											inline function hxNullForType(t:Type, index:Int):OcamlExpr {
												return missingOptionalArgValue(t, "static-call-optional:" + index, e.pos);
											}
											final builtArgs:Array<OcamlExpr> = [];
											if (expectedArgs != null) {
												final externCall = cls.isExtern;
												for (i in 0...args.length) {
													final argExpr = if (i < expectedArgs.length) {
														final expectedType = expectedArgs[i].t;
														(externCall && isTypeParameterType(expectedType)) ? buildExpr(args[i]) : coerceForAssignment(expectedType,
															args[i]);
													} else {
														buildExpr(args[i]);
													}
													builtArgs.push(argExpr);
												}
												if (args.length < expectedArgs.length) {
													for (i in args.length...expectedArgs.length) {
														final ea = expectedArgs[i];
														if (!ea.opt) {
															#if macro
															guardrailError("reflaxe.ocaml: call is missing required argument '" + ea.name + "'.", e.pos);
															#end
															builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
														} else {
															final isTypedArrayFromArrayPosDefault = cf.name == "fromArray"
																&& i == 1
																&& (cls.module == "haxe.io.Float32Array"
																	|| cls.module == "haxe.io.Float64Array"
																	|| cls.module == "haxe.io.Int32Array"
																	|| cls.module == "haxe.io.UInt16Array");
															if (isTypedArrayFromArrayPosDefault) {
																builtArgs.push(OcamlExpr.EConst(OcamlConst.CInt(0)));
															} else {
																builtArgs.push(hxNullForType(ea.t, i));
															}
														}
													}
												}
											} else {
												for (a in args)
													builtArgs.push(buildExpr(a));
											}
											OcamlExpr.EApp(buildExpr(fn), builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
										}
									case TField(objExpr, FInstance(clsRef, _, cfRef)):
										final cf = cfRef.get();
										switch (cf.kind) {
											case FMethod(_):
												final cls = clsRef.get();
												if (isStdArrayClass(cls)) {
													switch (cf.name) {
														case "iterator" if (args.length == 0):
															ocamlStandardArrayIterator(e, buildExpr(objExpr));
														case "join":
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "join"), [
																buildExpr(objExpr),
																buildExpr(args[0]),
																buildArrayJoinStringifier(objExpr, e.pos)
															]);
														case "toString" if (args.length == 0):
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "toString"),
																[buildExpr(objExpr), buildArrayJoinStringifier(objExpr, e.pos)]);
														case _:
															#if macro
															guardrailError("reflaxe.ocaml (M6): unsupported Array method '" + cf.name
																+ "'. (bd: haxe.ocaml-28t.7.3)",
																e.pos);
															#end
															OcamlExpr.EConst(OcamlConst.CUnit);
													}
												} else if (isStdStringClass(cls)) {
													final self = buildExpr(objExpr);
													switch (cf.name) {
														case "toUpperCase":
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toUpperCase"),
																[self, OcamlExpr.EConst(OcamlConst.CUnit)]);
														case "toLowerCase":
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toLowerCase"),
																[self, OcamlExpr.EConst(OcamlConst.CUnit)]);
														case "charAt":
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "charAt"),
																[self, buildExpr(args[0])]);
														case "charCodeAt":
															final raw = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "charCodeAt"),
																[self, buildExpr(args[0])]);
															// Haxe's `String.charCodeAt` is `Null<Int>` but it is frequently used in
															// non-nullable `Int` contexts (via implicit conversions). Our runtime
															// always returns `Obj.t` (either `hx_null` or `Obj.repr int`), so unwrap
															// when the typed AST expects an `Int`.
															isIntType(e.t) ? OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"),
																"nullable_int_unwrap"), [raw]) : raw;
														case "indexOf":
															final startExpr = if (args.length > 1) {
																final unwrapped = unwrap(args[1]);
																switch (unwrapped.expr) {
																	case TConst(TNull):
																		OcamlExpr.EConst(OcamlConst.CInt(0));
																	case _:
																		coerceNullableIntToInt(args[1]);
																}
															} else {
																OcamlExpr.EConst(OcamlConst.CInt(0));
															}
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "indexOf"),
																[self, buildExpr(args[0]), startExpr]);
														case "lastIndexOf":
															final defaultStart = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "length"),
																[self]);
															final startExpr = if (args.length > 1) {
																final unwrapped = unwrap(args[1]);
																switch (unwrapped.expr) {
																	case TConst(TNull):
																		defaultStart;
																	case _:
																		coerceNullableIntToInt(args[1]);
																}
															} else {
																defaultStart;
															}
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "lastIndexOf"),
																[self, buildExpr(args[0]), startExpr]);
														case "split":
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "split"), [self, buildExpr(args[0])]);
														case "substr":
															final lenExpr = if (args.length > 1) {
																final unwrapped = unwrap(args[1]);
																switch (unwrapped.expr) {
																	case TConst(TNull):
																		OcamlExpr.EConst(OcamlConst.CInt(-1));
																	case _:
																		coerceNullableIntToInt(args[1]);
																}
															} else {
																OcamlExpr.EConst(OcamlConst.CInt(-1));
															}
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "substr"),
																[self, buildExpr(args[0]), lenExpr]);
														case "substring":
															final defaultEnd = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "length"), [self]);
															final endExpr = if (args.length > 1) {
																final unwrapped = unwrap(args[1]);
																switch (unwrapped.expr) {
																	case TConst(TNull):
																		defaultEnd;
																	case _:
																		coerceNullableIntToInt(args[1]);
																}
															} else {
																defaultEnd;
															}
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "substring"),
																[self, buildExpr(args[0]), endExpr]);
														case "toString":
															OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toString"),
																[self, OcamlExpr.EConst(OcamlConst.CUnit)]);
														case _:
															#if macro
															guardrailError("reflaxe.ocaml (M6): unsupported String method '" + cf.name
																+ "'. (bd: haxe.ocaml-28t.7.4)",
																e.pos);
															#end
															OcamlExpr.EConst(OcamlConst.CUnit);
													}
												} else if (isStdBytesClass(cls)) {
													switch (cf.name) {
														case "get" if (args.length == 1):
															bytesAccessInvariant("standard Bytes.get bypassed its sealed access plan", e.pos);
														case "getDouble" if (args.length == 1):
															bytesAccessInvariant("standard Bytes.getDouble bypassed its sealed access plan", e.pos);
														case "getFloat" if (args.length == 1):
															bytesAccessInvariant("standard Bytes.getFloat bypassed its sealed access plan", e.pos);
														case "getUInt16" if (args.length == 1):
															bytesAccessInvariant("standard Bytes.getUInt16 bypassed its sealed access plan", e.pos);
														case "getInt32" if (args.length == 1):
															bytesAccessInvariant("standard Bytes.getInt32 bypassed its sealed access plan", e.pos);
														case "getInt64" if (args.length == 1):
															bytesAccessInvariant("standard Bytes.getInt64 bypassed its sealed access plan", e.pos);
														case "set" if (args.length == 2):
															bytesAccessInvariant("standard Bytes.set bypassed its sealed access plan", e.pos);
														case "setDouble" if (args.length == 2):
															bytesAccessInvariant("standard Bytes.setDouble bypassed its sealed access plan", e.pos);
														case "setFloat" if (args.length == 2):
															bytesAccessInvariant("standard Bytes.setFloat bypassed its sealed access plan", e.pos);
														case "setUInt16" if (args.length == 2):
															bytesAccessInvariant("standard Bytes.setUInt16 bypassed its sealed access plan", e.pos);
														case "setInt32" if (args.length == 2):
															bytesAccessInvariant("standard Bytes.setInt32 bypassed its sealed access plan", e.pos);
														case "setInt64" if (args.length == 2):
															bytesAccessInvariant("standard Bytes.setInt64 bypassed its sealed access plan", e.pos);
														case "blit", "fill":
															bytesMutationInvariant('standard Bytes mutation "${cf.name}" bypassed its sealed mutation plan',
																e.pos);
														case "sub", "compare", "getString", "toString", "toHex":
															bytesReadInvariant('standard Bytes read "${cf.name}" bypassed its sealed read plan', e.pos);
														case "getData" if (args.length == 0):
															bytesAccessInvariant("standard Bytes.getData bypassed its sealed access plan", e.pos);
														case _:
															#if macro
															guardrailError("reflaxe.ocaml (M6): unsupported Bytes method '" + cf.name
																+ "'. (bd: haxe.ocaml-28t.7.5)",
																e.pos);
															#end
															OcamlExpr.EConst(OcamlConst.CUnit);
													}
												} else {
													final expectedArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (TypeTools.follow(cf.type)) {
														case TFun(fargs, _): fargs;
														case _: null;
													}
													inline function hxNullForType(t:Type, index:Int):OcamlExpr {
														return missingOptionalArgValue(t, "instance-call-optional:" + index, e.pos);
													}
													final coercedArgs:Array<OcamlExpr> = [];
													if (expectedArgs != null) {
														final externCall = cls.isExtern;
														for (i in 0...args.length) {
															final argExpr = if (i < expectedArgs.length) {
																final expectedType = expectedArgs[i].t;
																(externCall && isTypeParameterType(expectedType)) ? buildExpr(args[i]) : coerceForAssignment(expectedType,
																	args[i]);
															} else {
																buildExpr(args[i]);
															}
															coercedArgs.push(argExpr);
														}
														if (args.length < expectedArgs.length) {
															for (i in args.length...expectedArgs.length) {
																final ea = expectedArgs[i];
																if (!ea.opt) {
																	#if macro
																	guardrailError("reflaxe.ocaml: call is missing required argument '" + ea.name + "'.",
																		e.pos);
																	#end
																	coercedArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
																} else {
																	coercedArgs.push(hxNullForType(ea.t, i));
																}
															}
														}
													} else {
														for (a in args)
															coercedArgs.push(buildExpr(a));
													}

													final expectsNoArgs = expectedArgs != null ? expectedArgs.length == 0 : args.length == 0;

													final unwrappedObj = unwrap(objExpr);
													final isSuperReceiver = switch (unwrappedObj.expr) {
														case TConst(TSuper): true;
														case _: false;
													}

													// Dynamic dispatch subset (M10): if the receiver's static type participates in
													// inheritance/interfaces, call through the record-stored method function.
													final recvFullName = classFullNameFromType(objExpr.t);
													final isDispatchRecv = recvFullName != null
														&& (ctx.dispatchTypes.exists(recvFullName)
															|| ctx.interfaceTypes.exists(recvFullName));

													final allowSuperCall = ctx.currentTypeFullName != null
														&& ctx.dispatchTypes.exists(ctx.currentTypeFullName);

													if (isSuperReceiver && allowSuperCall) {
														// `super.foo(...)`: call the base implementation directly (no virtual dispatch).
														final modName = moduleIdToOcamlModuleName(cls.module);
														final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
														final implName = ctx.scopedValueName(cls.module, cls.name, cf.name + "__impl");
														final callFn = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(implName) : OcamlExpr.EField(OcamlExpr.EIdent(modName),
															implName);

														final builtArgs = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"),
															[OcamlExpr.EIdent("self")])].concat(coercedArgs);
														// Haxe `foo()` always supplies "unit" at the callsite in OCaml.
														if (expectsNoArgs)
															builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
														OcamlExpr.EApp(callFn, builtArgs);
													} else if (isDispatchRecv) {
														final recvExpr = buildExpr(objExpr);
														final tmpName = switch (recvExpr) {
															case EIdent(_): null;
															case _: freshTmp("obj");
														}
														final recvVar = tmpName == null ? recvExpr : OcamlExpr.EIdent(tmpName);
														final methodOwnerModName = moduleIdToOcamlModuleName(cls.module);
														final methodOwnerSelfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
														final methodOwnerScopedType = ctx.scopedInstanceTypeName(cls.module, cls.name);
														final methodOwnerType = (methodOwnerSelfMod != null
															&& methodOwnerSelfMod == methodOwnerModName) ? methodOwnerScopedType : (methodOwnerModName + "."
																+ methodOwnerScopedType);
														final typedRecvVar = OcamlExpr.EAnnot(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [recvVar]),
															OcamlTypeExpr.TIdent(methodOwnerType));
														final methodField = OcamlExpr.EField(typedRecvVar, ctx.ocamlRecordLabel(cf.name));
														final callArgs = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [recvVar])].concat(coercedArgs);
														// Haxe `foo()` always supplies "unit" at the callsite in OCaml.
														if (expectsNoArgs)
															callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
														final call = OcamlExpr.EApp(methodField, callArgs);
														tmpName == null ? call : OcamlExpr.ELet(tmpName, recvExpr, call, false);
													} else {
														final modName = moduleIdToOcamlModuleName(cls.module);
														final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
														final scoped = ctx.scopedValueName(cls.module, cls.name, cf.name);
														final callFn = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(scoped) : OcamlExpr.EField(OcamlExpr.EIdent(modName),
															scoped);
														final recv = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(objExpr)]);
														final builtArgs = [recv].concat(coercedArgs);
														// Haxe `foo()` always supplies "unit" at the callsite in OCaml.
														if (expectsNoArgs)
															builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
														OcamlExpr.EApp(callFn, builtArgs);
													}
												}
											case _:
												final expectedArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (TypeTools.follow(fn.t)) {
													case TFun(fargs, _): fargs;
													case _: null;
												}
												inline function hxNullForType(t:Type, index:Int):OcamlExpr {
													return missingOptionalArgValue(t, "function-call-optional:" + index, e.pos);
												}
												final builtArgs:Array<OcamlExpr> = [];
												if (expectedArgs != null) {
													for (i in 0...args.length) {
														builtArgs.push(i < expectedArgs.length ? coerceForAssignment(expectedArgs[i].t,
															args[i]) : buildExpr(args[i]));
													}
													if (args.length < expectedArgs.length) {
														for (i in args.length...expectedArgs.length) {
															final ea = expectedArgs[i];
															if (!ea.opt) {
																#if macro
																guardrailError("reflaxe.ocaml: call is missing required argument '" + ea.name + "'.", e.pos);
																#end
																builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
															} else {
																builtArgs.push(hxNullForType(ea.t, i));
															}
														}
													}
												} else {
													for (a in args) {
														builtArgs.push(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(a)]));
													}
												}
												final expectsNoArgs = expectedArgs != null ? expectedArgs.length == 0 : args.length == 0;
												if (expectsNoArgs)
													builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
												OcamlExpr.EApp(buildExpr(fn), builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
										}
									case TField(_, FEnum(eRef, ef)):
										final en = eRef.get();

										// ocaml.List.Cons(h, t) -> h :: t
										if (isOcamlNativeEnumType(en, "List") && ef.name == "Cons" && args.length == 2) {
											OcamlExpr.EBinop(OcamlBinop.Cons, buildExpr(args[0]), buildExpr(args[1]));
										} else if (isOcamlNativeEnumType(en, "List") && ef.name == "Nil" && args.length == 0) {
											OcamlExpr.EList([]);
										} else if (isOcamlNativeEnumType(en, "Option") || isOcamlNativeEnumType(en, "Result")) {
											// OCaml-native enums: keep constructor calls idiomatic (`Some 1`, `Ok 1`)
											// and let OCaml infer type parameters rather than degrading to `Obj.t`.
											(args.length > 1) ? OcamlExpr.EApp(buildExpr(fn),
												[OcamlExpr.ETuple(args.map(buildExpr))]) : OcamlExpr.EApp(buildExpr(fn), args.map(buildExpr));
										} else if (en.pack == null || en.pack.length < 2 || en.pack[0] != "haxe" || en.pack[1] != "macro") {
											// Non-macro enums: still coerce against constructor signatures so nullable
											// enum carriers (`Obj.t`) are unboxed when constructors expect concrete
											// enum payloads.
											final expectedArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (TypeTools.follow(ef.type)) {
												case TFun(fargs, _): fargs;
												case _: null;
											}
											final builtArgs:Array<OcamlExpr> = [];
											if (expectedArgs != null) {
												for (i in 0...args.length) {
													builtArgs.push(i < expectedArgs.length ? coerceForAssignment(expectedArgs[i].t,
														args[i]) : buildExpr(args[i]));
												}
												if (args.length < expectedArgs.length) {
													for (i in args.length...expectedArgs.length) {
														final ea = expectedArgs[i];
														if (!ea.opt) {
															#if macro
															guardrailError("reflaxe.ocaml: enum constructor call is missing required argument '"
																+ ea.name
																+ "'.", e.pos);
															#end
															builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
														} else {
															builtArgs.push(missingOptionalArgValue(ea.t, "enum-constructor-optional:" + i, e.pos));
														}
													}
												}
											} else {
												for (a in args)
													builtArgs.push(buildExpr(a));
											}
											(builtArgs.length > 1) ? OcamlExpr.EApp(buildExpr(fn),
												[OcamlExpr.ETuple(builtArgs)]) : OcamlExpr.EApp(buildExpr(fn), builtArgs);
										} else {
											// Enum constructors: coerce arguments (optional args must be fully applied,
											// and optional enum args use the nullable (Obj.t) representation).
											final expectedArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (TypeTools.follow(ef.type)) {
												case TFun(fargs, _): fargs;
												case _: null;
											}

											inline function hxNullForOptionalArg(ea:{name:String, opt:Bool, t:Type}):OcamlExpr {
												final isEnum = switch (TypeTools.follow(ea.t)) {
													case TEnum(_, _): true;
													case _: false;
												}
												// Nullable primitives and `Null<Enum>` use `Obj.t` with `hx_null`.
												return (nullablePrimitiveKind(ea.t) != null || isEnum) ? OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"),
													"hx_null") : OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"),
														[OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);
											}

											inline function coerceEnumCtorArg(ea:{name:String, opt:Bool, t:Type}, arg:TypedExpr):OcamlExpr {
												// Optional enum args behave like `Null<Enum>` and are represented as `Obj.t`.
												// Box when present so they can safely carry `hx_null` when omitted.
												final enumName = ea.opt ? fullNameOfTypeEnum(ea.t) : null;
												if (enumName != null) {
													final asObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(arg)]);
													return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
														[OcamlExpr.EConst(OcamlConst.CString(enumName)), asObj]);
												}
												return coerceForAssignment(ea.t, arg);
											}

											final builtArgs:Array<OcamlExpr> = [];
											if (expectedArgs != null) {
												for (i in 0...args.length) {
													if (i >= expectedArgs.length) {
														builtArgs.push(buildExpr(args[i]));
														continue;
													}
													builtArgs.push(coerceEnumCtorArg(expectedArgs[i], args[i]));
												}
												if (args.length < expectedArgs.length) {
													for (i in args.length...expectedArgs.length) {
														final ea = expectedArgs[i];
														if (!ea.opt) {
															#if macro
															guardrailError("reflaxe.ocaml: enum constructor call is missing required argument '"
																+ ea.name
																+ "'.", e.pos);
															#end
															builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
														} else {
															builtArgs.push(hxNullForOptionalArg(ea));
														}
													}
												}
											} else {
												for (a in args)
													builtArgs.push(buildExpr(a));
											}

											(builtArgs.length > 1) ? OcamlExpr.EApp(buildExpr(fn),
												[OcamlExpr.ETuple(builtArgs)]) : OcamlExpr.EApp(buildExpr(fn), builtArgs);
										}
									case _:
										final isDynamicCall = switch (followNoAbstracts(unwrap(fn).t)) {
											case TDynamic(_): true;
											case _: false;
										};
										if (isDynamicCall) {
											callPlanInvariant("a Dynamic function call reached syntax without its sealed call and runtime-use plan", e.pos);
										} else {
											final expectedArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (followNoAbstracts(unwrapNullType(fn.t))) {
												case TFun(fargs, _): fargs;
												case _: null;
											}
											inline function hxNullForType(t:Type, index:Int):OcamlExpr {
												return missingOptionalArgValue(t, "dynamic-call-optional:" + index, e.pos);
											}
											final builtArgs:Array<OcamlExpr> = [];
											if (expectedArgs != null) {
												for (i in 0...args.length) {
													builtArgs.push(i < expectedArgs.length ? coerceForAssignment(expectedArgs[i].t,
														args[i]) : buildExpr(args[i]));
												}
												if (args.length < expectedArgs.length) {
													for (i in args.length...expectedArgs.length) {
														final ea = expectedArgs[i];
														if (!ea.opt) {
															#if macro
															guardrailError("reflaxe.ocaml: call is missing required argument '" + ea.name + "'.", e.pos);
															#end
															builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
														} else {
															builtArgs.push(hxNullForType(ea.t, i));
														}
													}
												}
											} else {
												for (a in args)
													builtArgs.push(buildExpr(a));
											}
											final expectsNoArgs = expectedArgs != null ? expectedArgs.length == 0 : args.length == 0;
											if (expectsNoArgs)
												builtArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
											OcamlExpr.EApp(buildExpr(fn), builtArgs.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : builtArgs);
										}
								}
						}
				}
			case TField(obj, fa):
				buildField(e, obj, fa, e.pos);
			case TMeta(metadata, e1):
				OcamlLoweredOrigin.readPlaceId(metadata) != null ? buildPreservedPlaceOperation(metadata, e1) : buildExpr(e1);
			case TCast(e1, _):
				// Haxe uses casts for nullable primitive flows (boxing/unboxing + flow typing).
				//
				// We represent:
				// - `Null<Int>/Null<Float>/Null<Bool>` as `Obj.t` (null is `HxRuntime.hx_null`).
				// - Non-null primitives as `Obj.repr <prim>` when assigned to nullable slots.
				//
				// So we must explicitly box/unbox at cast boundaries.
				switch ({
					from:nullablePrimitiveKind(e1.t), to:nullablePrimitiveKind(e.t)
				}) {
					case {from: null, to: "int"} if (isIntType(e1.t)):
						{
							final inner = buildExpr(e1);
							// Avoid double-boxing: `Obj.repr (Obj.repr x)` is not a valid `Null<Int>` value.
							switch (inner) {
								case OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [_]):
									inner;
								case _:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [inner]);
							}
						}
					case {from: null, to: "float"} if (isFloatType(e1.t)):
						{
							final inner = buildExpr(e1);
							switch (inner) {
								case OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [_]):
									inner;
								case _:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [inner]);
							}
						}
					case {from: null, to: "float"} if (isIntType(e1.t)):
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(e1)])]);
					case {from: null, to: "bool"} if (isBoolType(e1.t)):
						{
							final inner = buildExpr(e1);
							switch (inner) {
								case OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [_]):
									inner;
								case _:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [inner]);
							}
						}
					case {from: "int", to: null} if (isIntType(e.t)):
						safeUnboxNullableInt(buildExpr(e1));
					case {from: "float", to: null} if (isFloatType(e.t)):
						safeUnboxNullableFloat(buildExpr(e1));
					case {from: "bool", to: null} if (isBoolType(e.t)):
						safeUnboxNullableBool(buildExpr(e1));
					case _:
						{
							// `Null<Enum>` is represented as `Obj.t` (null is `HxRuntime.hx_null`).
							// When Haxe inserts a cast to a non-null enum (often after a null-check),
							// we must unbox explicitly so downstream pattern matches typecheck.
							final fromU = unwrapNullType(e1.t);
							final toU = unwrapNullType(e.t);
							final nullableEnumCast = (fromU != e1.t) && (switch (TypeTools.follow(fromU)) {
								case TEnum(_, _): true;
								case _: false;
							}) && (switch (TypeTools.follow(toU)) {
								case TEnum(_, _): true;
								case _: false;
							});
							if (nullableEnumCast) {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [buildExpr(e1)]);
							} else {
								// Dynamic-like -> concrete casts: `Any` / `Dynamic` / HxAnon-backed `TAnonymous`
								// values are represented as `Obj.t`. To cast to a concrete OCaml type we must
								// unbox with `Obj.obj`.
								final fromDynLike = switch (followNoAbstracts(unwrapNullType(e1.t))) {
									case TDynamic(_):
										true;
									case TAbstract(_, _) if (isStdAnyAbstract(e1.t)):
										true;
									case TAnonymous(_) if (shouldAnonUseHxAnon(e1.t)):
										true;
									case _:
										false;
								}
								final toConcrete = switch (followNoAbstracts(unwrapNullType(e.t))) {
									case TInst(_, _), TEnum(_, _):
										true;
									case _:
										false;
								}
									(fromDynLike && toConcrete) ? OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"),
										[buildExpr(e1)]) : buildExpr(e1);
							}
						}
				}
			case TEnumParameter(enumValueExpr, ef, index):
				final key = ef.name + ":" + index;
				final scrutId = enumParamScrutineeLocalId(enumValueExpr);
				if (currentEnumParamNames != null
					&& currentEnumParamScrutineeLocalId != null
					&& scrutId != null
					&& scrutId == currentEnumParamScrutineeLocalId
					&& currentEnumParamNames.exists(key)) {
					OcamlExpr.EIdent(currentEnumParamNames.get(key));
				} else {
					final unwrappedType = unwrapNullType(enumValueExpr.t);
					final isNullable = unwrappedType != enumValueExpr.t;
					final enumType:Null<EnumType> = switch (unwrappedType) {
						case TEnum(eRef, _): eRef.get();
						case _: null;
					}
					if (enumType == null) {
						OcamlExpr.EConst(OcamlConst.CUnit);
					} else {
						final ctorName = if (isOcamlNativeEnumType(enumType, "Option") || isOcamlNativeEnumType(enumType, "Result")) {
							ef.name;
						} else if (isOcamlNativeEnumType(enumType, "List")) {
							ef.name == "Nil" ? "[]" : (ef.name == "Cons" ? "::" : ef.name);
						} else {
							final isSameModule = ctx.currentModuleId != null && enumType.module == ctx.currentModuleId;
							isSameModule ? ef.name : (moduleIdToOcamlModuleName(enumType.module) + "." + ef.name);
						}

						final argCount = switch (ef.type) {
							case TFun(args, _): args.length;
							case _: 0;
						}
						if (index < 0 || index >= argCount) {
							OcamlExpr.EConst(OcamlConst.CUnit);
						} else {
							final wanted = freshTmp("enum_param");
							final patArgs:Array<OcamlPat> = [];
							for (i in 0...argCount) {
								patArgs.push(i == index ? OcamlPat.PVar(wanted) : OcamlPat.PAny);
							}
							final scrutRaw = buildExpr(enumValueExpr);
							final scrut = isNullable ? OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [scrutRaw]) : scrutRaw;

							final includeFallback = enumType.names != null && enumType.names.length > 1;
							final matchCases:Array<OcamlMatchCase> = [
								{
									pat: OcamlPat.PConstructor(ctorName, patArgs),
									guard: null,
									expr: OcamlExpr.EIdent(wanted)
								}
							];
							if (includeFallback) {
								matchCases.push({
									pat: OcamlPat.PAny,
									guard: null,
									expr: OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Unexpected enum parameter"))])
								});
							}
							final matchExpr = OcamlExpr.EMatch(scrut, matchCases);

							if (isNullable) {
								final tmp = freshTmp("enum_param");
								final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
								OcamlExpr.ELet(tmp, scrutRaw,
									OcamlExpr.EIf(OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull),
										OcamlExpr.EApp(OcamlExpr.EIdent("failwith"), [OcamlExpr.EConst(OcamlConst.CString("Unexpected enum parameter"))]),
										OcamlExpr.EMatch(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)]),
											matchCases)),
									false);
							} else {
								matchExpr;
							}
						}
					}
				}
			case TEnumIndex(_):
				switch (e.expr) {
					case TEnumIndex(enumValueExpr):
						buildEnumIndex(enumValueExpr);
					case _:
						OcamlExpr.EConst(OcamlConst.CInt(-1));
				}
			case TBreak:
				if (currentControlPlan == null)
					return controlPlanInvariant("a break reached syntax without a sealed control plan", e.pos);
				if (currentControlPlan.loopFamilyAdmitted) {
					final decision = try {
						currentControlPlan.decisionFor(e);
					} catch (error:Dynamic) {
						return controlPlanInvariant(Std.string(error), e.pos);
					}
					if (decision == null)
						return controlPlanInvariant("an admitted break reached syntax without its sealed loop-transfer decision", e.pos);
					buildPlannedLoopTransfer(decision, OcamlControlTransferKind.Break, e.pos);
				} else {
					controlPlanInvariant("a break reached syntax after its loop-control family was rejected", e.pos);
				}
			case TContinue:
				if (currentControlPlan == null)
					return controlPlanInvariant("a continue reached syntax without a sealed control plan", e.pos);
				if (currentControlPlan.loopFamilyAdmitted) {
					final decision = try {
						currentControlPlan.decisionFor(e);
					} catch (error:Dynamic) {
						return controlPlanInvariant(Std.string(error), e.pos);
					}
					if (decision == null)
						return controlPlanInvariant("an admitted continue reached syntax without its sealed loop-transfer decision", e.pos);
					buildPlannedLoopTransfer(decision, OcamlControlTransferKind.Continue, e.pos);
				} else {
					controlPlanInvariant("a continue reached syntax after its loop-control family was rejected", e.pos);
				}
			case TWhile(cond, body, normalWhile):
				if (currentControlPlan == null)
					return controlPlanInvariant("a loop reached syntax without a sealed control plan", e.pos);
				if (!currentControlPlan.loopFamilyAdmitted)
					return controlPlanInvariant("a loop reached syntax after its control family was rejected", e.pos);
				final condExpr = buildCondition(cond);
				final plannedTarget:Null<OcamlControlLoopTarget> = try {
					currentControlPlan.loopTargetFor(e);
				} catch (error:Dynamic) {
					return controlPlanInvariant(Std.string(error), e.pos);
				};
				if (plannedTarget == null)
					return controlPlanInvariant("an admitted loop reached syntax without its sealed lexical target", e.pos);
				final needsControl = currentControlPlan.hasTransfersForTarget(plannedTarget.id);
				currentLoopTargetIds.push(plannedTarget.id);
				final builtBody = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [buildExpr(body)]);
				currentLoopTargetIds.pop();
				final loopCases = if (!needsControl) {
					null;
				} else {
					buildPlannedLoopControlCases(plannedTarget, currentControlPlan.decisionsForTarget(plannedTarget.id), e.pos);
				}

				if (!normalWhile) {
					var iterationBody = builtBody;
					final breakCase = loopCases == null ? null : loopCases.breakCase;
					final continueCase = loopCases == null ? null : loopCases.continueCase;
					if (continueCase != null) {
						// Keep the try expression inside one function argument. This prevents
						// the following condition from becoming part of the exception handler.
						iterationBody = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.ETry(builtBody, [continueCase])]);
					}

					// A recursive tail call represents the source body once in generated
					// syntax. Runtime-use receipts can therefore keep one occurrence per
					// source call while execution still repeats the body until the condition
					// becomes false. A caught continue proceeds to that condition check.
					final loopName = freshTmp("do_while_loop");
					final repeat = OcamlExpr.EApp(OcamlExpr.EIdent(loopName), [OcamlExpr.EConst(OcamlConst.CUnit)]);
					final loopBody = OcamlExpr.ESeq([
						iterationBody,
						OcamlExpr.EIf(condExpr, repeat, OcamlExpr.EConst(OcamlConst.CUnit))
					]);
					final loop = OcamlExpr.ELet(loopName, OcamlExpr.EFun([OcamlPat.PConst(OcamlConst.CUnit)], loopBody), repeat, true);
					return breakCase == null ? loop : OcamlExpr.ETry(loop, [breakCase]);
				}

				if (loopCases != null) {
					final bodyWithContinue = loopCases.continueCase == null ? builtBody : OcamlExpr.ETry(builtBody, [loopCases.continueCase]);
					final whileExpr = OcamlExpr.EWhile(condExpr, bodyWithContinue);
					final loopExpr = loopCases.breakCase == null ? whileExpr : OcamlExpr.ETry(whileExpr, [loopCases.breakCase]);
					return loopExpr;
				}

				OcamlExpr.EWhile(condExpr, builtBody);
			case TSwitch(scrutinee, cases, edef):
				#if macro
				final log = ctx.profileLogLine;
				final profClass = Context.definedValue("reflaxe_ocaml_telemetry_class");
				final profMatch = log != null
					&& Context.defined("reflaxe_ocaml_telemetry_detail")
					&& profClass != null
					&& ctx.currentTypeFullName != null
					&& ctx.currentTypeFullName == profClass;
				final t0 = profMatch ? haxe.Timer.stamp() : 0.0;
				#end
				final out = buildSwitch(scrutinee, cases, edef, e.t);
				#if macro
				if (profMatch) {
					var valueCount = 0;
					for (c in cases)
						valueCount += (c.values != null ? c.values.length : 0);
					final dtMs = Std.int((haxe.Timer.stamp() - t0) * 1000);
					log("reflaxe.ocaml: builder_switch dt_ms=" + Std.string(dtMs) + " cases=" + Std.string(cases.length) + " values=" + Std.string(valueCount));
				}
				#end
				out;
			case TArray(arr, idx):
				final arrValue = buildExpr(arr);
				final idxUnwrapped = unwrap(idx);
				final idxString = switch (idxUnwrapped.expr) {
					case TConst(TString(name)):
						name;
					case TCast(inner, _):
						final innerUnwrapped = unwrap(inner);
						switch (innerUnwrapped.expr) {
							case TConst(TString(name)):
								name;
							case _:
								null;
						}
					case _:
						null;
				}
				if (isStdBytesType(arr.t)) {
					bytesAccessInvariant("standard Bytes bracket reads are not Haxe 4.3.7 API and must not bypass sealed Bytes.get", e.pos);
				} else {
					final arrExpr = coerceArrayReceiver(arrValue, arr);
					final arrObjExpr = coerceArrayReceiverToObj(arrValue, arr.t);
					switch (idxUnwrapped.expr) {
						case _ if (idxString != null):
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "get"), [arrObjExpr, OcamlExpr.EConst(OcamlConst.CString(idxString))]);
						case _ if (!OcamlArrayReadPlan.hasStandardArrayReceiver(e)):
							arrayReadInvariant("a non-Array bracket read reached legacy syntax without its sealed compatibility decision", e.pos);
						case _:
							arrayReadInvariant("a numeric bracket read reached legacy syntax without a standard Array decision", e.pos);
					}
				}
			case TArrayDecl(items):
				buildArrayLiteral(e, items);
			case TObjectDecl(fields):
				// Anonymous structure literal: `{ foo: 1, bar: "x" }`.
				//
				// Most anonymous values lower to `HxAnon` (`Obj.t`), but structural iterators
				// (`{ hasNext:Void->Bool, next:Void->T }`) are represented as typed OCaml records
				// consumed by `HxIterator.hasNext/next`.
				if (isIteratorAnon(e.t)) {
					final itemType = iteratorAnonItemType(e.t);
					final iteratorType = ocamlIteratorCarrier(e, itemType != null ? typeExprFromHaxeType(itemType) : OcamlTypeExpr.TIdent("Obj.t"));
					OcamlExpr.EAnnot(OcamlExpr.ERecord(fields.map(f -> ({
						name: f.name,
						value: buildExpr(f.expr)
					}))), iteratorType);
				} else {
					final tmp = freshTmp("anon");
					final create = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "create"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
					final seq:Array<OcamlExpr> = [];
					for (f in fields) {
						final rhs = toObjValueExpr(f.expr);
						seq.push(OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "set"),
								[OcamlExpr.EIdent(tmp), OcamlExpr.EConst(OcamlConst.CString(f.name)), rhs])
						]));
					}
					seq.push(OcamlExpr.EIdent(tmp));
					OcamlExpr.ELet(tmp, create, OcamlExpr.ESeq(seq), false);
				}
			case TThrow(expr):
				if (currentControlPlan != null && currentControlPlan.throwFamilyAdmitted) {
					final decision = try {
						currentControlPlan.decisionFor(e);
					} catch (error:Dynamic) {
						return controlPlanInvariant(Std.string(error), e.pos);
					}
					if (decision == null)
						return controlPlanInvariant("an admitted throw reached syntax without its sealed exception-channel decision", e.pos);
					return buildPlannedThrow(decision, expr, e.pos);
				}
				final built = buildExpr(expr);
				final kind = nullablePrimitiveKind(expr.t);
				final enumName = fullNameOfTypeEnum(expr.t);
				final nullableEnumName = isNullableEnumType(expr.t);

				// Produce the thrown payload as `Obj.t`.
				var payload:OcamlExpr;
				if (kind != null) {
					// Nullable primitives already use the `Obj.t` representation.
					payload = built;
				} else if (nullableEnumName != null) {
					// `Null<Enum>` is represented as `Obj.t`.
					payload = built;
				} else {
					switch (followNoAbstracts(unwrapNullType(expr.t))) {
						case TAnonymous(_) if (shouldAnonUseHxAnon(expr.t)):
							// Anonymous structures represented via `HxAnon` already use `Obj.t`.
							payload = built;
						case TAbstract(_, _) if (isStdAnyAbstract(expr.t)):
							// `Std.Any` (and friends) already use `Obj.t`.
							payload = built;
						case _ if (isBoolType(expr.t)):
							// Booleans stored as `Obj.t` must be boxed to avoid int/bool ambiguity.
							payload = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [built]);
						case _:
							payload = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
					}
				}

				// Enums carried as `Obj.t` must be boxed so typed catches can recover the enum identity
				// even for constant constructors (which compile to immediates).
				if (enumName != null) {
					payload = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(enumName)), payload]);
				} else if (nullableEnumName != null) {
					payload = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(nullableEnumName)), payload]);
				}
				final tags = throwTagsForType(expr.t);
				final tagExpr = OcamlExpr.EList(tags.map(t -> OcamlExpr.EConst(OcamlConst.CString(t))));
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "hx_throw_typed_rtti"), [payload, tagExpr]);
			case TTry(tryExpr, catches):
				if (catches.length == 0) {
					buildExpr(tryExpr);
				} else {
					if (currentControlPlan == null)
						return controlPlanInvariant("a non-empty typed catch reached syntax without a sealed function control plan", e.pos);
					if (!currentControlPlan.hasCatchDispositionFor(e))
						return controlPlanInvariant("a non-empty typed catch reached syntax without an exact catch occurrence", e.pos);
					final catchChain = try {
						currentControlPlan.catchChainFor(e);
					} catch (error:Dynamic) {
						return controlPlanInvariant(Std.string(error), e.pos);
					}
					if (catchChain == null)
						return controlPlanInvariant("a non-empty typed catch reached syntax without its admitted sealed chain", e.pos);
					buildPlannedCatchChain(catchChain, tryExpr, catches, e.pos);
				}
			case TReturn(ret):
				if (currentControlPlan == null || !currentControlPlan.returnFamilyAdmitted)
					return controlPlanInvariant("a non-direct typed return reached syntax without an admitted function-owned control plan", e.pos);
				final decision = try {
					currentControlPlan.decisionFor(e);
				} catch (error:Dynamic) {
					return controlPlanInvariant(Std.string(error), e.pos);
				}
				if (decision == null)
					return controlPlanInvariant("an admitted early return reached syntax without its sealed control decision", e.pos);
				buildPlannedReturn(decision, ret, e.pos);
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		};

		#if macro
		if (emitSourceMap && OcamlSourcePositionMapper.shouldWrap(e)) {
			final dp = OcamlSourcePositionMapper.debugPosition(e.pos);
			return dp != null ? OcamlExpr.EPos(dp, built) : built;
		}
		#end
		return built;
	}

	/** Builds the Haxe declaration index from a typed enum match or a Dynamic value's generated layout. */
	function buildEnumIndex(enumValueExpr:TypedExpr):OcamlExpr {
		final unwrappedType = unwrapNullType(enumValueExpr.t);
		final isNullable = unwrappedType != enumValueExpr.t;
		return switch (unwrappedType) {
			case TEnum(eRef, _):
				// OCaml numbers constant and payload constructors separately.
				// Matching the typed value returns its Haxe source index instead.
				final enumType = eRef.get();
				final scrutRaw = buildExpr(enumValueExpr);
				final scrut = isNullable ? OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [scrutRaw]) : scrutRaw;
				final modName = moduleIdToOcamlModuleName(enumType.module);
				final isSameModule = ctx.currentModuleId != null && enumType.module == ctx.currentModuleId;

				final ctors:Array<EnumField> = [];
				for (name in enumType.names) {
					final ef = enumType.constructs.get(name);
					if (ef != null)
						ctors.push(ef);
				}
				ctors.sort((a, b) -> a.index - b.index);

				final arms:Array<OcamlMatchCase> = [];
				for (ef in ctors) {
					final ctorName = if (isOcamlNativeEnumType(enumType, "Option") || isOcamlNativeEnumType(enumType, "Result")) {
						ef.name;
					} else if (isOcamlNativeEnumType(enumType, "List")) {
						ef.name == "Nil" ? "[]" : (ef.name == "Cons" ? "::" : ef.name);
					} else {
						isSameModule ? ef.name : (modName + "." + ef.name);
					}

					final argCount = switch (ef.type) {
						case TFun(args, _): args.length;
						case _: 0;
					}
					final patArgs:Array<OcamlPat> = [];
					for (_ in 0...argCount)
						patArgs.push(OcamlPat.PAny);

					arms.push({
						pat: OcamlPat.PConstructor(ctorName, patArgs),
						guard: null,
						expr: OcamlExpr.EConst(OcamlConst.CInt(ef.index))
					});
				}

				if (isNullable) {
					final tmp = freshTmp("enum_idx");
					final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
					final nonNullIdx = if (arms.length == 0) {
						OcamlExpr.EConst(OcamlConst.CInt(-1));
					} else {
						OcamlExpr.EMatch(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)]), arms);
					}
					OcamlExpr.ELet(tmp, scrutRaw,
						OcamlExpr.EIf(OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull), OcamlExpr.EConst(OcamlConst.CInt(-1)), nonNullIdx),
						false);
				} else {
					// If the enum has constructors, the match is exhaustive: no
					// default arm is needed, which also avoids OCaml warnings.
					if (arms.length == 0)
						OcamlExpr.EConst(OcamlConst.CInt(-1))
					else
						OcamlExpr.EMatch(scrut, arms);
				}
			case _:
				// A Dynamic value has no static enum identity here. Its earlier
				// representation conversion must preserve that identity in an
				// HxEnum box before this runtime lookup can succeed.
				final built = buildExpr(enumValueExpr);
				final asObj = (isDynamicLike(enumValueExpr.t)
					|| nullablePrimitiveKind(enumValueExpr.t) != null) ? built : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "enumIndex"), [asObj]);
		}
	}

	/** Inspects unwrapped syntax but evaluates the original expression so semantic metadata remains authoritative. */
	function buildStdString(inner:TypedExpr):OcamlExpr {
		final e = unwrap(inner);
		final dynamicStrategy = OcamlDynamicStringModel.select(inner);
		if (dynamicStrategy != null) {
			final built = buildExpr(inner);
			final carrier = switch (dynamicStrategy) {
				case DirectCarrier: built;
				case BoxWithObjRepr: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [built]);
			};
			return OcamlExpr.EApp(dynamicStringFunction(inner, dynamicStrategy), [carrier]);
		}

		switch (e.expr) {
			case TConst(TNull):
				return OcamlExpr.EConst(OcamlConst.CString("null"));
			case TConst(TString(_)):
				// String literals are never `null`; avoid redundant runtime wrapping.
				return buildExpr(inner);
			case TBinop(OpAdd, _, _) if (isStringType(e.t)):
				// String concatenation always produces a real OCaml string (never hx_null),
				// because we convert nullable operands via `HxString.toStdString` before `^`.
				// Avoid re-wrapping the result (this prevents `HxString.toStdString (...)` nesting).
				return buildExpr(inner);
			case _:
		}

		inline function toStdString(expr:OcamlExpr):OcamlExpr {
			return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toStdString"), [expr]);
		}

		return switch (e.t) {
			case TAbstract(aRef, params):
				final a = aRef.get();
				switch (a.name) {
					case "Int":
						OcamlExpr.EApp(OcamlExpr.EIdent("string_of_int"), [buildExpr(inner)]);
					case "Float":
						OcamlExpr.EApp(OcamlExpr.EIdent("string_of_float"), [buildExpr(inner)]);
					case "Bool":
						OcamlExpr.EApp(OcamlExpr.EIdent("string_of_bool"), [buildExpr(inner)]);
					case "Null":
						if (params != null && params.length == 1) {
							final innerType = params[0];
							if (isStringType(innerType)) {
								toStdString(buildExpr(inner));
							} else if (isIntType(innerType)) {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_toStdString"), [buildExpr(inner)]);
							} else if (isFloatType(innerType)) {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_float_toStdString"), [buildExpr(inner)]);
							} else if (isBoolType(innerType)) {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_bool_toStdString"), [buildExpr(inner)]);
							} else {
								OcamlExpr.EConst(OcamlConst.CString("<unsupported>"));
							}
						} else {
							OcamlExpr.EConst(OcamlConst.CString("<unsupported>"));
						}
					default:
						OcamlExpr.EConst(OcamlConst.CString("<unsupported>"));
				}
			case TInst(cRef, _):
				final c = cRef.get();
				if (isStdStringClass(c)) {
					toStdString(buildExpr(inner));
				} else {
					var hasToString = false;
					try {
						for (f in c.fields.get()) {
							if (f.name == "toString") {
								hasToString = true;
								break;
							}
						}
					} catch (_:Dynamic) {}

					if (hasToString) {
						final modName = moduleIdToOcamlModuleName(c.module);
						final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
						final callFn = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent("toString") : OcamlExpr.EField(OcamlExpr.EIdent(modName),
							"toString");
						OcamlExpr.EApp(callFn, [buildExpr(inner), OcamlExpr.EConst(OcamlConst.CUnit)]);
					} else {
						dynamicStringInvariant("a nominal value without toString reached syntax without its selected Dynamic strategy", inner.pos);
					}
				}
			case _:
				dynamicStringInvariant("a value without a static string conversion reached syntax without its selected Dynamic strategy", inner.pos);
		}
	}

	function buildConst(c:TConstant):OcamlConst {
		return switch (c) {
			case TInt(v): OcamlConst.CInt(v);
			case TFloat(v): OcamlConst.CFloat(v);
			case TString(v): OcamlConst.CString(v);
			case TBool(v): OcamlConst.CBool(v);
			case TNull: OcamlConst.CUnit;
			case TThis, TSuper:
				OcamlConst.CUnit;
		}
	}

	function buildLocal(v:TVar, ?position:Position):OcamlExpr {
		if (position != null && currentIMapInterfacePlan != null) {
			final storageAlias = try {
				currentIMapInterfacePlan.storageAliasUseForLocal(v.id, position);
			} catch (error:Dynamic) {
				return callPlanInvariant(Std.string(error), position);
			}
			if (storageAlias != null)
				return buildRawStorageAliasLocal(v);
		}
		final name = renameVar(v.name);
		final isRef = isRefLocalId(v.id);
		if (!isRef) {
			return OcamlExpr.EIdent(name);
		}
		final deref = OcamlExpr.EUnop(OcamlUnop.Deref, OcamlExpr.EIdent(name));
		if (!isObjRefLocalId(v.id))
			return deref;
		if (position != null) {
			final representation = plannedLocalRepresentation(v.id, position);
			if (representation != null && (representation.semanticTypeId == "Null<Int>" || representation.semanticTypeId == "Null<Bool>"))
				return deref;
		}
		return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [deref]);
	}

	/** Reads one local in the raw standard-Map carrier proven by the IMap plan. */
	function buildRawStorageAliasLocal(v:TVar):OcamlExpr {
		final value = OcamlExpr.EIdent(renameVar(v.name));
		return isRefLocalId(v.id) ? OcamlExpr.EUnop(OcamlUnop.Deref, value) : value;
	}

	inline function isNullableStdArrayType(t:Type):Bool {
		final unwrapped = unwrapNullType(t);
		if (unwrapped == t) {
			return false;
		}
		return switch (followNoAbstracts(unwrapped)) {
			case TInst(cRef, _):
				isStdArrayClass(cRef.get());
			case _:
				false;
		}
	}

	/**
			Consumes a sealed direct-carrier read when the array receiver is a planned
			local. Every other receiver remains on the existing compatibility cast.
		**/
	inline function coerceArrayReceiver(rawExpr:OcamlExpr, receiver:TypedExpr):OcamlExpr {
		return switch (unwrap(receiver).expr) {
			case TLocal(local):
				final localRepresentations = activeLocalRepresentationPlan(receiver.pos);
				if (localRepresentations == null) {
					legacyArrayReceiverCoercion(rawExpr);
				} else {
					switch (localRepresentations.readConversionFor(stableLocalId(local.id, receiver.pos))) {
						case OcamlLocalCarrierConversion.Identity:
							final decision = plannedLocalRepresentation(local.id, receiver.pos);
							if (decision == null)
								localStorageInvariant('local ${local.id} selected identity read conversion without a program representation', receiver.pos);
							rawExpr;
						case OcamlLocalCarrierConversion.LegacyCoercion, null:
							legacyArrayReceiverCoercion(rawExpr);
						case PreserveNullableIntCarrier, BoxExactIntToNullableInt, CheckedUnboxNullableInt, PreserveNullableBoolCarrier,
							BoxExactBoolToNullableBool, NullableBoolTruthiness, PreserveDynamicCarrier, BoxConcreteToDynamic, BoxExactBoolToDynamic,
							BoxExactEnumToDynamic:
							localStorageInvariant('array receiver local ${local.id} leaked an occurrence-only carrier conversion into its read summary',
								receiver.pos);
					}
				}
			case _:
				legacyArrayReceiverCoercion(rawExpr);
		}
	}

	/** Keeps the pre-migration array receiver cast behind one explicit legacy seam. */
	inline function legacyArrayReceiverCoercion(rawExpr:OcamlExpr):OcamlExpr {
		return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [rawExpr]);
	}

	inline function coerceArrayReceiverToObj(rawExpr:OcamlExpr, t:Type):OcamlExpr {
		return
			(nullablePrimitiveKind(t) != null || isDynamicLike(t) || isNullableStdArrayType(t)) ? rawExpr : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"),
				"repr"), [rawExpr]);
	}

	inline function isFunctionType(t:Type):Bool {
		return switch (followNoAbstracts(unwrapNullType(t))) {
			case TFun(_, _):
				true;
			case _:
				false;
		}
	}

	function renameVar(name:String):String {
		return ctx.localValueName(name);
	}

	function buildVarDecl(v:TVar, init:Null<TypedExpr>):OcamlExpr {
		// Kept for compatibility when TVar occurs outside of a block (rare in typed output).
		// Prefer `buildBlock` handling for correct scoping.
		final declarationPosition:Position = init == null ? cast {file: "(unknown)", min: 0, max: 0} : init.pos;
		final initExprRaw = init != null ? coerceLocalInitializer(v.id, v.t, init) : defaultValueForType(v.t, "local-default:" + v.id, declarationPosition);
		final localType = init == null ? typeExprFromHaxeType(v.t) : localCarrierType(v.id, v.t, init.pos);
		final initExpr = switch (init) {
			case null:
				OcamlExpr.EAnnot(initExprRaw, localType);
			case _:
				switch (unwrap(init).expr) {
					case TConst(TNull):
						OcamlExpr.EAnnot(initExprRaw, localType);
					case _:
						initExprRaw;
				}
		};
		final isMutable = localRequiresRef(v.id, declarationPosition);
		if (isMutable) {
			refLocals.set(v.id, true);
			final hasNullInit = switch (init) {
				case null:
					true;
				case _:
					switch (unwrap(init).expr) {
						case TConst(TNull): true;
						case _: false;
					}
			};
			weakRefLocals.set(v.id, hasNullInit && isFunctionType(v.t));
			final slotType = localType;
			final isObjSlot = switch (slotType) {
				case TIdent(name):
					name == "Obj.t";
				case _:
					false;
			}
			objRefLocals.set(v.id, isObjSlot);
			return OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [initExpr]);
		}
		refLocals.remove(v.id);
		weakRefLocals.remove(v.id);
		objRefLocals.remove(v.id);
		return initExpr;
	}

	/** Materializes an admitted local default after validating its sealed representation. */
	function defaultValueForLocal(localId:Int, type:Type, position:Position):OcamlExpr {
		final representation = plannedLocalRepresentation(localId, position);
		if (representation != null && representation.semanticTypeId == "String") {
			return try {
				exactStringNullValue(representation.domain, "local-default:" + localId, position);
			} catch (error:Dynamic) {
				localStorageInvariant(Std.string(error), position);
			}
		}
		return defaultValueForType(type, "local-default:" + localId, position);
	}

	/** Returns the runtime-owned exact String null after validating its representation domain. */
	function exactStringNullValue(domain:OcamlRepresentationDomain, ownerRole:String, position:Position):OcamlExpr {
		final binding = currentFunctionPlanBinding;
		if (binding == null)
			throw 'reflaxe.ocaml [ocaml-string-default:missing-function-owner]: String null "$ownerRole" reached syntax without a sealed function binding';
		final source = OcamlLoweredOrigin.sourceSpan(position);
		final decision = representationRegistry.selectExactString(domain);
		final ownerId = binding.functionId + ":" + ownerRole + ":" + source.file + ":" + source.min + ":" + source.max;
		final defaultPlan = OcamlStringDefaultPlan.seal(decision, ownerId, OcamlRuntimeUseModel.planRevision(binding), source);
		final authority = OcamlStringDefaultPlan.authority(defaultPlan, OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile),
			ctx.finalRuntimeUses);
		final materialized = OcamlStringRepresentationMaterializer.materializeDefault(decision, domain, defaultPlan, authority);
		authority.reconcileExpression(materialized.implicitDefault);
		return materialized.implicitDefault;
	}

	function defaultValueForType(t:Type, ownerRole:String, position:Position):OcamlExpr {
		if (OcamlRepresentationRegistry.isExactString(t))
			return exactStringNullValue(OcamlRepresentationDomain.InternalValue, ownerRole, position);
		final anyNull:OcamlExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);

		return switch (t) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				switch (a.name) {
					case "Int": OcamlExpr.EConst(OcamlConst.CInt(0));
					case "Float": OcamlExpr.EConst(OcamlConst.CFloat("0."));
					case "Bool": OcamlExpr.EConst(OcamlConst.CBool(false));
					case "Null":
						// Nullable primitives default to null, not a value like 0.
						switch (nullablePrimitiveKind(t)) {
							case "int", "float", "bool":
								OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
							case _:
								anyNull;
						}
					default: anyNull;
				}
			case TInst(_, _):
				anyNull;
			case TEnum(_, _):
				anyNull;
			case _:
				anyNull;
		}
	}

	function buildBinop(source:TypedExpr, op:Binop, e1:TypedExpr, e2:TypedExpr, resultType:Type):OcamlExpr {
		inline function isNullExpr(e:TypedExpr):Bool {
			final u = unwrap(e);
			return switch (u.expr) {
				case TConst(TNull): true;
				case _: false;
			}
		}

		inline function toStdString(expr:OcamlExpr):OcamlExpr {
			return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toStdString"), [expr]);
		}

		inline function objObj(expr:OcamlExpr):OcamlExpr {
			return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [expr]);
		}

		inline function toIntExpr(expr:TypedExpr):OcamlExpr {
			if (nullablePrimitiveKind(expr.t) == "int") {
				final checked = buildCheckedNullableIntOperand(expr);
				return checked != null ? checked : safeUnboxNullableInt(buildExpr(expr));
			}
			return buildExpr(expr);
		}

		inline function toFloatExpr(expr:TypedExpr):OcamlExpr {
			return switch (nullablePrimitiveKind(expr.t)) {
				case "float":
					safeUnboxNullableFloat(buildExpr(expr));
				case "int":
					final checked = buildCheckedNullableIntOperand(expr);
					OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [checked != null ? checked : safeUnboxNullableInt(buildExpr(expr))]);
				case _:
					if (isIntType(expr.t)) {
						OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(expr)]);
					} else {
						buildExpr(expr);
					}
			}
		}

		function buildNullablePrimitiveEq(lhsKind:Null<String>, lhs:TypedExpr, rhsKind:Null<String>, rhs:TypedExpr):Null<OcamlExpr> {
			final kind = lhsKind != null ? lhsKind : rhsKind;
			if (kind == null)
				return null;

			final lhsIsNullable = lhsKind != null;
			final rhsIsNullable = rhsKind != null;

			inline function withTmp(expr:OcamlExpr, f:String->OcamlExpr):OcamlExpr {
				final tmp = freshTmp("nullable");
				return OcamlExpr.ELet(tmp, expr, f(tmp), false);
			}

			final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");

			// Both nullable (only when the underlying primitive kinds match).
			if (lhsIsNullable && rhsIsNullable) {
				if (lhsKind != rhsKind)
					return null;

				return withTmp(buildExpr(lhs), (lName) -> withTmp(buildExpr(rhs), (rName) -> {
					final lId = OcamlExpr.EIdent(lName);
					final rId = OcamlExpr.EIdent(rName);
					final isLNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, lId, hxNull);
					final isRNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, rId, hxNull);
					final bothNull = OcamlExpr.EBinop(OcamlBinop.And, isLNull, isRNull);
					final rNotNull = OcamlExpr.EUnop(OcamlUnop.Not, isRNull);
					final eqPrim = OcamlExpr.EBinop(OcamlBinop.Eq, objObj(lId), objObj(rId));
					final rhsNotNullAndEq = OcamlExpr.EBinop(OcamlBinop.And, rNotNull, eqPrim);
					OcamlExpr.EIf(isLNull, bothNull, rhsNotNullAndEq);
				}));
			}

			// Nullable vs non-nullable primitive (best-effort, same-kind only).
			final nullableExpr = lhsIsNullable ? lhs : rhs;
			final otherExpr = lhsIsNullable ? rhs : lhs;
			final otherType = otherExpr.t;

			switch (kind) {
				case "int":
					if (!isIntType(otherType))
						return null;
				case "float":
					if (!isFloatType(otherType) && !isIntType(otherType))
						return null;
				case "bool":
					if (!isBoolType(otherType))
						return null;
				case _:
					return null;
			}

			return withTmp(buildExpr(nullableExpr), (nName) -> {
				final nId = OcamlExpr.EIdent(nName);
				final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, nId, hxNull);
				final otherBuilt = (kind == "float" && isIntType(otherType)) ? OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"),
					[buildExpr(otherExpr)]) : buildExpr(otherExpr);
				final eqPrim = OcamlExpr.EBinop(OcamlBinop.Eq, objObj(nId), otherBuilt);
				OcamlExpr.EIf(isNull, OcamlExpr.EConst(OcamlConst.CBool(false)), eqPrim);
			});
		}

		function buildNullablePrimitiveCompare(binop:OcamlBinop, lhs:TypedExpr, rhs:TypedExpr):Null<OcamlExpr> {
			final k1 = nullablePrimitiveKind(lhs.t);
			final k2 = nullablePrimitiveKind(rhs.t);
			final kind = k1 != null ? k1 : k2;
			if (kind == null)
				return null;

			// Only numeric comparisons are supported here (int/float).
			if (kind != "int" && kind != "float")
				return null;

			final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");

			inline function withTmp(expr:OcamlExpr, f:String->OcamlExpr):OcamlExpr {
				final tmp = freshTmp("nullable");
				return OcamlExpr.ELet(tmp, expr, f(tmp), false);
			}

			// Decide which side is the nullable one (or both).
			final lhsIsNullable = k1 != null;
			final rhsIsNullable = k2 != null;

			// Reject mismatched underlying kinds when both are nullable.
			if (lhsIsNullable && rhsIsNullable && k1 != k2)
				return null;

			return withTmp(buildExpr(lhs), (lName) -> withTmp(buildExpr(rhs), (rName) -> {
				final lId = OcamlExpr.EIdent(lName);
				final rId = OcamlExpr.EIdent(rName);

				final lNull = lhsIsNullable ? OcamlExpr.EBinop(OcamlBinop.PhysEq, lId, hxNull) : OcamlExpr.EConst(OcamlConst.CBool(false));
				final rNull = rhsIsNullable ? OcamlExpr.EBinop(OcamlBinop.PhysEq, rId, hxNull) : OcamlExpr.EConst(OcamlConst.CBool(false));

				// Haxe semantics for comparisons involving null are target-dependent.
				// For now we choose "null => false" to avoid crashes and match common
				// "nullable used as number" patterns in bootstrapping workloads.
				final anyNull = if (lhsIsNullable && rhsIsNullable) {
					OcamlExpr.EBinop(OcamlBinop.Or, lNull, rNull);
				} else if (lhsIsNullable) {
					lNull;
				} else {
					rNull;
				}

				final lVal:OcamlExpr = lhsIsNullable ? objObj(lId) : lId;
				final rValRaw:OcamlExpr = rhsIsNullable ? objObj(rId) : rId;

				final rVal:OcamlExpr = if (kind == "float" && !rhsIsNullable && isIntType(rhs.t)) {
					// int -> float promotion (Haxe allows Int/Float comparisons)
					OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [rValRaw]);
				} else if (kind == "float" && !lhsIsNullable && isIntType(lhs.t) && rhsIsNullable) {
					// lhs is int (non-null) but kind float due to rhs:Null<Float>
					// Promote lhs when needed by caller; here keep rhs path simple.
					rValRaw;
				} else {
					rValRaw;
				}

				final lVal2:OcamlExpr = if (kind == "float" && !lhsIsNullable && isIntType(lhs.t) && !rhsIsNullable && isFloatType(rhs.t)) {
					OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [lVal]);
				} else {
					lVal;
				}

				final cmp = OcamlExpr.EBinop(binop, lVal2, rVal);
				OcamlExpr.EIf(anyNull, OcamlExpr.EConst(OcamlConst.CBool(false)), cmp);
			}));
		}

		inline function coerceForComparison(left:TypedExpr, right:TypedExpr):{l:OcamlExpr, r:OcamlExpr} {
			// Haxe allows comparisons between `Int` and `Float` by promoting `Int` to `Float`.
			// OCaml requires both operands to have the same type.
			if (isFloatType(left.t) && isIntType(right.t)) {
				return {l: buildExpr(left), r: OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(right)])};
			}
			if (isIntType(left.t) && isFloatType(right.t)) {
				return {l: OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(left)]), r: buildExpr(right)};
			}
			return {l: buildExpr(left), r: buildExpr(right)};
		}

		return switch (op) {
			case OpAssign:
				// Handle local ref assignment: x = v  ->  x := v
				switch (e1.expr) {
					case TLocal(v) if (isRefLocalId(v.id)):
						final tmp = freshTmp("assign");
						var rhs = coerceLocalAssignment(v.id, v.t, e2);
						final localRepresentation = plannedLocalRepresentation(v.id, e2.pos);
						final exactNullablePrimitiveCarrier = localRepresentation != null
							&& (localRepresentation.semanticTypeId == "Null<Int>" || localRepresentation.semanticTypeId == "Null<Bool>");
						final lhsRefObjSlot = isObjRefLocalId(v.id) || switch (followNoAbstracts(unwrapNullType(v.t))) {
							case TDynamic(_):
								true;
							case TAbstract(_, _) if (isStdAnyAbstract(v.t)):
								true;
							case _: isNullableEnumType(v.t) != null || (unwrapNullType(v.t) != v.t && nullablePrimitiveKind(v.t) == null);
						} if (lhsRefObjSlot && !exactNullablePrimitiveCarrier) {
							rhs = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [rhs]);
						}
						if (isWeakRefLocalId(v.id)) {
							rhs = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [rhs]);
						}
						OcamlExpr.ELet(tmp, rhs, OcamlExpr.ESeq([
							OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), OcamlExpr.EIdent(tmp)),
							OcamlExpr.EIdent(tmp)
						]), false);
					case TField(obj, FInstance(clsRef, _, cfRef)):
						if (OcamlPlaceInputPolicy.admitsSimpleInstanceField(e1, e2))
							return placeLoweringInvariant("admitted instance-field assignment reached the legacy syntax branch without a stable origin",
								e1.pos);
						final cls = clsRef.get();
						final cf = cfRef.get();
						switch (cf.kind) {
							case FVar(_, _):
								if (isStdArrayClass(cls) && cf.name == "length") {
									final recvTmp = freshTmp("recv");
									final rhsTmp = freshTmp("assign");
									final rhs = coerceForAssignment(e1.t, e2);
									OcamlExpr.ELet(recvTmp, buildExpr(obj), OcamlExpr.ELet(rhsTmp, rhs, OcamlExpr.ESeq([
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "resize"),
											[OcamlExpr.EIdent(recvTmp), OcamlExpr.EIdent(rhsTmp)]),
										OcamlExpr.EIdent(rhsTmp)
									]), false), false);
								} else {
									final tmp = freshTmp("assign");
									var rhs = coerceForAssignment(e1.t, e2);
									final slotType = typeExprFromHaxeType(cf.type);
									final isObjSlot = switch (slotType) {
										case TIdent(name):
											name == "Obj.t";
										case _:
											false;
									}
									if (isObjSlot) {
										rhs = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [rhs]);
									}
									final fieldName = ctx.ocamlRecordLabel(cf.name);
									final modName = moduleIdToOcamlModuleName(cls.module);
									final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
									final scopedType = ctx.scopedInstanceTypeName(cls.module, cls.name);
									final fullType = (selfMod != null && selfMod == modName) ? scopedType : (modName + "." + scopedType);
									final recvExpr = OcamlExpr.EAnnot(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(obj)]),
										OcamlTypeExpr.TIdent(fullType));
									OcamlExpr.ELet(tmp, rhs, OcamlExpr.ESeq([
										OcamlExpr.EAssign(OcamlAssignOp.FieldSet, OcamlExpr.EField(recvExpr, fieldName), OcamlExpr.EIdent(tmp)),
										OcamlExpr.EIdent(tmp)
									]), false);
								}
							case _:
								OcamlExpr.EConst(OcamlConst.CUnit);
						}
					case TField(_, FStatic(clsRef, cfRef)):
						if (OcamlPlaceInputPolicy.admitsSimpleStaticField(e1, e2, ctx.currentModuleId, ctx.currentTypeName, staticStoragePlan))
							return placeLoweringInvariant("admitted static-field assignment reached the legacy syntax branch without a stable origin", e1.pos);
						final cls = clsRef.get();
						final cf = cfRef.get();
						final key = (cls.pack ?? []).concat([cls.name, cf.name]).join(".");
						final isMutableStatic = switch (cf.kind) {
							case FVar(_, _): !cf.isFinal;
							case FMethod(MethDynamic): true;
							case _: false;
						}
						if (!isMutableStatic) {
							#if macro
							guardrailError("reflaxe.ocaml (M6): assignment to immutable static field '" + key + "' is not supported yet.", e1.pos);
							#end
							OcamlExpr.EConst(OcamlConst.CUnit);
						} else {
							final storage = requireStaticStorage(cls, cf, e1.pos);
							final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
							final modName = moduleIdToOcamlModuleName(cls.module);
							final scoped = storage.targetValueName;
							final lhsCell = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(scoped) : OcamlExpr.EField(OcamlExpr.EIdent(modName),
								scoped);
							final tmp = freshTmp("assign");
							final rhs = coerceForAssignment(e1.t, e2);
							OcamlExpr.ELet(tmp, rhs, OcamlExpr.ESeq([
								OcamlExpr.EAssign(OcamlAssignOp.RefSet, lhsCell, OcamlExpr.EIdent(tmp)),
								OcamlExpr.EIdent(tmp)
							]), false);
						}
					case TField(obj, FAnon(cfRef)):
						final cf = cfRef.get();
						switch (cf.name) {
							case "key", "value", "hasNext", "next":
								structuralFieldInvariant('assignment to overlapping structural field "${cf.name}" reached syntax without its typed owner',
									e1.pos);
							case _:
								if (isSysFileStatAnon(obj.t)) {
									OcamlExpr.EConst(OcamlConst.CUnit);
								} else {
									final tmp = freshTmp("assign");
									final rhs = coerceForAssignment(e1.t, e2);
									final rhsObj = coerceToObjCarrier(e1.t, OcamlExpr.EIdent(tmp));
									OcamlExpr.ELet(tmp, rhs, OcamlExpr.ESeq([
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "set"),
											[buildExpr(obj), OcamlExpr.EConst(OcamlConst.CString(cf.name)), rhsObj]),
										OcamlExpr.EIdent(tmp)
									]), false);
								}
						}
					case TField(obj, FDynamic(name)):
						final tmp = freshTmp("assign");
						final rhs = coerceForAssignment(e1.t, e2);
						final rhsObj = coerceToObjCarrier(e1.t, OcamlExpr.EIdent(tmp));
						OcamlExpr.ELet(tmp, rhs, OcamlExpr.ESeq([
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "set"), [
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(obj)]),
								OcamlExpr.EConst(OcamlConst.CString(name)),
								rhsObj
							]),
							OcamlExpr.EIdent(tmp)
						]), false);
					case TArray(arr, idx):
						if (OcamlPlaceInputPolicy.admitsSimpleArrayElement(e1, e2))
							return placeLoweringInvariant("admitted array-element assignment reached the legacy syntax branch without a stable origin", e1.pos);
						final tmp = freshTmp("assign");
						final rhs = coerceForAssignment(e1.t, e2);
						final arrExpr = buildExpr(arr);
						final idxExpr = buildExpr(idx);
						if (isStdBytesType(arr.t)) {
							bytesAccessInvariant("standard Bytes bracket assignments are not Haxe 4.3.7 API and must not bypass sealed Bytes.set", e1.pos);
						} else {
							final coercedArrExpr = coerceArrayReceiver(arrExpr, arr);
							OcamlExpr.ELet(tmp, rhs, // `HxArray.set` already returns the assigned value, matching Haxe's
								// assignment-expression semantics (`a[i] = v` evaluates to `v`).
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set"), [coercedArrExpr, idxExpr, OcamlExpr.EIdent(tmp)]), false);
						}
					case _:
						OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case OpAssignOp(inner):
				// Handle compound assignment for ref locals:
				// x += v  ->  x := (!x) + v
				switch (e1.expr) {
					case TLocal(v) if (isRefLocalId(v.id)):
						final lhs = buildLocal(v);
						final floatMode = isFloatType(v.t) || nullablePrimitiveKind(v.t) == "float";
						var rhs = switch (inner) {
							case OpAdd:
								if (isStringType(v.t) || isStringType(e2.t)) {
									OcamlExpr.EBinop(OcamlBinop.Concat, toStdString(lhs), buildStdString(e2));
								} else if (floatMode) {
									OcamlExpr.EBinop(OcamlBinop.AddF, lhs, toFloatExpr(e2));
								} else {
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [lhs, toIntExpr(e2)]);
								}
							case OpSub:
								floatMode ? OcamlExpr.EBinop(OcamlBinop.SubF, lhs,
									toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "sub"), [lhs, toIntExpr(e2)]);
							case OpMult:
								floatMode ? OcamlExpr.EBinop(OcamlBinop.MulF, lhs,
									toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "mul"), [lhs, toIntExpr(e2)]);
							case OpDiv:
								floatMode ? OcamlExpr.EBinop(OcamlBinop.DivF, lhs,
									toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "div"), [lhs, toIntExpr(e2)]);
							case OpMod:
								floatMode ? OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"),
									[lhs, toFloatExpr(e2)]) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "rem"), [lhs, toIntExpr(e2)]);
							case OpAnd:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logand"), [lhs, toIntExpr(e2)]);
							case OpOr:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logor"), [lhs, toIntExpr(e2)]);
							case OpXor:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logxor"), [lhs, toIntExpr(e2)]);
							case OpShl:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shl"), [lhs, toIntExpr(e2)]);
							case OpShr:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shr"), [lhs, toIntExpr(e2)]);
							case OpUShr:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "ushr"), [lhs, toIntExpr(e2)]);
							case _: OcamlExpr.EConst(OcamlConst.CUnit);
						}
						final lhsRefObjSlot = isObjRefLocalId(v.id) || switch (followNoAbstracts(unwrapNullType(v.t))) {
							case TDynamic(_):
								true;
							case TAbstract(_, _) if (isStdAnyAbstract(v.t)):
								true;
							case _: isNullableEnumType(v.t) != null || (unwrapNullType(v.t) != v.t && nullablePrimitiveKind(v.t) == null);
						} if (lhsRefObjSlot) {
							rhs = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [rhs]);
						}
						if (isWeakRefLocalId(v.id)) {
							rhs = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [rhs]);
						}
						OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), rhs);
					case TField(_, FStatic(clsRef, cfRef)):
						if (OcamlPlaceInputPolicy.admitsCompoundIntAddStaticField(inner, e1, e2, ctx.currentModuleId, ctx.currentTypeName, staticStoragePlan))
							return placeLoweringInvariant("admitted static-field compound assignment reached the legacy syntax branch without a stable origin",
								e1.pos);
						final cls = clsRef.get();
						final cf = cfRef.get();
						final key = (cls.pack ?? []).concat([cls.name, cf.name]).join(".");
						final isMutableStatic = switch (cf.kind) {
							case FVar(_, _): !cf.isFinal;
							case _: false;
						}
						if (!isMutableStatic) {
							#if macro
							guardrailError("reflaxe.ocaml (M6): compound assignment to immutable static field '" + key + "' is not supported yet.", e1.pos);
							#end
							OcamlExpr.EConst(OcamlConst.CUnit);
						} else {
							final storage = requireStaticStorage(cls, cf, e1.pos);
							final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
							final modName = moduleIdToOcamlModuleName(cls.module);
							final scoped = storage.targetValueName;
							final lhsCell = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(scoped) : OcamlExpr.EField(OcamlExpr.EIdent(modName),
								scoped);
							final lhs = OcamlExpr.EUnop(OcamlUnop.Deref, lhsCell);
							final floatMode = isFloatType(e1.t) || nullablePrimitiveKind(e1.t) == "float";
							final rhs = switch (inner) {
								case OpAdd:
									if (isStringType(e1.t) || isStringType(e2.t)) {
										OcamlExpr.EBinop(OcamlBinop.Concat, toStdString(lhs), buildStdString(e2));
									} else if (floatMode) {
										OcamlExpr.EBinop(OcamlBinop.AddF, lhs, toFloatExpr(e2));
									} else {
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [lhs, toIntExpr(e2)]);
									}
								case OpSub:
									floatMode ? OcamlExpr.EBinop(OcamlBinop.SubF, lhs,
										toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "sub"), [lhs, toIntExpr(e2)]);
								case OpMult:
									floatMode ? OcamlExpr.EBinop(OcamlBinop.MulF, lhs,
										toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "mul"), [lhs, toIntExpr(e2)]);
								case OpDiv:
									floatMode ? OcamlExpr.EBinop(OcamlBinop.DivF, lhs,
										toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "div"), [lhs, toIntExpr(e2)]);
								case OpMod:
									floatMode ? OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"),
										[lhs, toFloatExpr(e2)]) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "rem"), [lhs, toIntExpr(e2)]);
								case OpAnd:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logand"), [lhs, toIntExpr(e2)]);
								case OpOr:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logor"), [lhs, toIntExpr(e2)]);
								case OpXor:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logxor"), [lhs, toIntExpr(e2)]);
								case OpShl:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shl"), [lhs, toIntExpr(e2)]);
								case OpShr:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shr"), [lhs, toIntExpr(e2)]);
								case OpUShr:
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "ushr"), [lhs, toIntExpr(e2)]);
								case _: OcamlExpr.EConst(OcamlConst.CUnit);
							}
							OcamlExpr.EAssign(OcamlAssignOp.RefSet, lhsCell, rhs);
						}
					case TField(obj, FInstance(_, _, cfRef)):
						if (OcamlPlaceInputPolicy.admitsCompoundIntAddInstanceField(inner, e1, e2))
							return
								placeLoweringInvariant("admitted instance-field compound assignment reached the legacy syntax branch without a stable origin",
									e1.pos);
						final cf = cfRef.get();
						switch (cf.kind) {
							case FVar(_, _):
								// Support compound assignment on instance vars (notably used by
								// inline-stdlib code like `StringBuf.add`, which lowers to `b += x`).
								//
								// We avoid re-evaluating the receiver expression by binding it once.
								final recvTmp = freshTmp("recv");
								final recvTypedTmp = freshTmp("recv_typed");
								final recvExpr = buildExpr(obj);
								final recvClassType = switch (classTypeFromType(obj.t)) {
									case null:
										null;
									case recvClass:
										final modName = moduleIdToOcamlModuleName(recvClass.module);
										final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
										final scopedType = ctx.scopedInstanceTypeName(recvClass.module, recvClass.name);
										(selfMod != null && selfMod == modName) ? scopedType : (modName + "." + scopedType);
								}
								final typedRecvExpr = switch (recvClassType) {
									case null:
										OcamlExpr.EIdent(recvTmp);
									case fullType:
										OcamlExpr.EAnnot(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent(recvTmp)]),
											OcamlTypeExpr.TIdent(fullType));
								}
								final lhsField = OcamlExpr.EField(OcamlExpr.EIdent(recvTypedTmp), ctx.ocamlRecordLabel(cf.name));
								final floatMode = isFloatType(e1.t) || nullablePrimitiveKind(e1.t) == "float";
								final rhs = switch (inner) {
									case OpAdd:
										if (isStringType(e1.t) || isStringType(e2.t)) {
											OcamlExpr.EBinop(OcamlBinop.Concat, toStdString(lhsField), buildStdString(e2));
										} else if (floatMode) {
											OcamlExpr.EBinop(OcamlBinop.AddF, lhsField, toFloatExpr(e2));
										} else {
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [lhsField, toIntExpr(e2)]);
										}
									case OpSub:
										floatMode ? OcamlExpr.EBinop(OcamlBinop.SubF, lhsField,
											toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "sub"), [lhsField, toIntExpr(e2)]);
									case OpMult:
										floatMode ? OcamlExpr.EBinop(OcamlBinop.MulF, lhsField,
											toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "mul"), [lhsField, toIntExpr(e2)]);
									case OpDiv:
										floatMode ? OcamlExpr.EBinop(OcamlBinop.DivF, lhsField,
											toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "div"), [lhsField, toIntExpr(e2)]);
									case OpMod:
										floatMode ? OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"),
											[lhsField, toFloatExpr(e2)]) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "rem"),
												[lhsField, toIntExpr(e2)]);
									case OpAnd:
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logand"), [lhsField, toIntExpr(e2)]);
									case OpOr:
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logor"), [lhsField, toIntExpr(e2)]);
									case OpXor:
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logxor"), [lhsField, toIntExpr(e2)]);
									case OpShl:
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shl"), [lhsField, toIntExpr(e2)]);
									case OpShr:
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shr"), [lhsField, toIntExpr(e2)]);
									case OpUShr:
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "ushr"), [lhsField, toIntExpr(e2)]);
									case _:
										OcamlExpr.EConst(OcamlConst.CUnit);
								}
								OcamlExpr.ELet(recvTmp, recvExpr,
									OcamlExpr.ELet(recvTypedTmp, typedRecvExpr, OcamlExpr.EAssign(OcamlAssignOp.FieldSet, lhsField, rhs), false), false);
							case _:
								OcamlExpr.EConst(OcamlConst.CUnit);
						}
					case TArray(arr, idx):
						if (OcamlPlaceInputPolicy.admitsCompoundIntAddArrayElement(inner, e1, e2))
							return
								placeLoweringInvariant("admitted array-element compound assignment reached the legacy syntax branch without a stable origin",
									e1.pos);
						if (isStdBytesType(arr.t))
							return bytesAccessInvariant("standard Bytes bracket compound assignments are not Haxe 4.3.7 API", e1.pos);
						// a[i] += v  ->  set a i ((get a i) + v)
						final arrExpr = buildExpr(arr);
						final idxExpr = buildExpr(idx);
						final tmpArr = freshTmp("arr");
						final tmpIdx = freshTmp("idx");
						final lhs = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "get"), [OcamlExpr.EIdent(tmpArr), OcamlExpr.EIdent(tmpIdx)]);
						final floatMode = isFloatType(e1.t) || nullablePrimitiveKind(e1.t) == "float";
						final rhs = switch (inner) {
							case OpAdd:
								if (isStringType(e1.t) || isStringType(e2.t)) {
									OcamlExpr.EBinop(OcamlBinop.Concat, toStdString(lhs), buildStdString(e2));
								} else if (floatMode) {
									OcamlExpr.EBinop(OcamlBinop.AddF, lhs, toFloatExpr(e2));
								} else {
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [lhs, toIntExpr(e2)]);
								}
							case OpSub:
								floatMode ? OcamlExpr.EBinop(OcamlBinop.SubF, lhs,
									toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "sub"), [lhs, toIntExpr(e2)]);
							case OpMult:
								floatMode ? OcamlExpr.EBinop(OcamlBinop.MulF, lhs,
									toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "mul"), [lhs, toIntExpr(e2)]);
							case OpDiv:
								floatMode ? OcamlExpr.EBinop(OcamlBinop.DivF, lhs,
									toFloatExpr(e2)) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "div"), [lhs, toIntExpr(e2)]);
							case OpMod:
								floatMode ? OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"),
									[lhs, toFloatExpr(e2)]) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "rem"), [lhs, toIntExpr(e2)]);
							case OpAnd:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logand"), [lhs, toIntExpr(e2)]);
							case OpOr:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logor"), [lhs, toIntExpr(e2)]);
							case OpXor:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logxor"), [lhs, toIntExpr(e2)]);
							case OpShl:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shl"), [lhs, toIntExpr(e2)]);
							case OpShr:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shr"), [lhs, toIntExpr(e2)]);
							case OpUShr:
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "ushr"), [lhs, toIntExpr(e2)]);
							case _:
								OcamlExpr.EConst(OcamlConst.CUnit);
						}
						final setExpr = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set"),
							[OcamlExpr.EIdent(tmpArr), OcamlExpr.EIdent(tmpIdx), rhs]);
						OcamlExpr.ELet(tmpArr, coerceArrayReceiver(arrExpr, arr), OcamlExpr.ELet(tmpIdx, idxExpr, setExpr, false), false);
					case _:
						OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case OpAdd:
				if (isStringType(e1.t) || isStringType(e2.t) || isStringType(resultType)) {
					// Haxe string concat: always uses `Std.string` semantics on both sides
					// (e.g. `"x" + null == "xnull"`).
					function collectConcatParts(expr:TypedExpr, out:Array<TypedExpr>):Void {
						final u = unwrap(expr);
						switch (u.expr) {
							case TBinop(OpAdd, a, b) if (isStringType(u.t) || isStringType(a.t) || isStringType(b.t)):
								collectConcatParts(a, out);
								collectConcatParts(b, out);
							case _:
								out.push(expr);
						}
					}

					final parts:Array<TypedExpr> = [];
					collectConcatParts(e1, parts);
					collectConcatParts(e2, parts);

					var acc:OcamlExpr = buildStdString(parts[0]);
					for (i in 1...parts.length) {
						acc = OcamlExpr.EBinop(OcamlBinop.Concat, acc, buildStdString(parts[i]));
					}
					acc;
				} else {
					final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
					if (floatMode) {
						OcamlExpr.EBinop(OcamlBinop.AddF, toFloatExpr(e1), toFloatExpr(e2));
					} else {
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [toIntExpr(e1), toIntExpr(e2)]);
					}
				}
			case OpSub:
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EBinop(OcamlBinop.SubF, toFloatExpr(e1), toFloatExpr(e2));
				} else {
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "sub"), [toIntExpr(e1), toIntExpr(e2)]);
				}
			case OpMult:
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EBinop(OcamlBinop.MulF, toFloatExpr(e1), toFloatExpr(e2));
				} else {
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "mul"), [toIntExpr(e1), toIntExpr(e2)]);
				}
			case OpDiv:
				// Haxe `/` always produces Float (Int/Int => Float). OCaml needs `/.` with
				// float operands, so we promote ints as needed.
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EBinop(OcamlBinop.DivF, toFloatExpr(e1), toFloatExpr(e2));
				} else {
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "div"), [toIntExpr(e1), toIntExpr(e2)]);
				}
			case OpMod:
				final floatMode = isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float";
				if (floatMode) {
					OcamlExpr.EApp(OcamlExpr.EIdent("mod_float"), [toFloatExpr(e1), toFloatExpr(e2)]);
				} else {
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "rem"), [toIntExpr(e1), toIntExpr(e2)]);
				}
			case OpAnd:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logand"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpOr:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logor"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpXor:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "logxor"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpShl:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shl"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpShr:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "shr"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpUShr:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "ushr"), [toIntExpr(e1), toIntExpr(e2)]);
			case OpEq:
				// Null checks must use physical equality (==) so we don't accidentally invoke
				// specialized structural equality (notably for strings).
				if (isNullExpr(e1) || isNullExpr(e2)) {
					OcamlExpr.EBinop(OcamlBinop.PhysEq, buildExpr(e1), buildExpr(e2));
				} else {
					inline function toDynamicObj(e:TypedExpr):OcamlExpr {
						if (isDynamicLike(e.t) || nullablePrimitiveKind(e.t) != null)
							return buildExpr(e);
						final enumName = fullNameOfTypeEnum(e.t);
						final nullableEnumName = isNullableEnumType(e.t);

						// Map `Null<String>` sentinel to the canonical `hx_null` when crossing into `Obj.t`
						// comparisons by relying on `HxRuntime.dynamic_equals` to treat the sentinel as null.
						if (isBoolType(e.t)) {
							return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(e)]);
						}

						var obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e)]);
						if (enumName != null) {
							obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
								[OcamlExpr.EConst(OcamlConst.CString(enumName)), obj]);
						} else if (nullableEnumName != null) {
							obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
								[OcamlExpr.EConst(OcamlConst.CString(nullableEnumName)), obj]);
						}
						return obj;
					}

					if (isDynamicLike(e1.t) || isDynamicLike(e2.t)) {
						return OcamlExpr.EApp(dynamicEqualityFunction(source, OcamlDynamicEqualityKind.Equal), [toDynamicObj(e1), toDynamicObj(e2)]);
					}

					inline function shouldUsePhysicalEq(t:Type):Bool {
						if (isStringType(t) || nullablePrimitiveKind(t) != null)
							return false;
						return switch (followNoAbstracts(unwrapNullType(t))) {
							case TInst(_, _): true; // class instances use reference equality in Haxe
							case TAnonymous(_):
								// Anonymous structures compare by identity in Haxe.
								// Use physical equality, but avoid double-boxing `HxAnon` values (handled above).
								!shouldAnonUseHxAnon(t);
							case TFun(_, _): true; // functions compare by identity in Haxe
							case _: false;
						}
					}

					final k1 = nullablePrimitiveKind(e1.t);
					final k2 = nullablePrimitiveKind(e2.t);
					final primEq = buildNullablePrimitiveEq(k1, e1, k2, e2);
					if (primEq != null) {
						primEq;
					} else if (isStringType(e1.t) || isStringType(e2.t)) {
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "equals"), [buildExpr(e1), buildExpr(e2)]);
					} else if (shouldUsePhysicalEq(e1.t) || shouldUsePhysicalEq(e2.t)) {
						OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e1)]),
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e2)]));
					} else {
						final c = coerceForComparison(e1, e2);
						OcamlExpr.EBinop(OcamlBinop.Eq, c.l, c.r);
					}
				}
			case OpNotEq:
				if (isNullExpr(e1) || isNullExpr(e2)) {
					OcamlExpr.EBinop(OcamlBinop.PhysNeq, buildExpr(e1), buildExpr(e2));
				} else {
					inline function toDynamicObj(e:TypedExpr):OcamlExpr {
						if (isDynamicLike(e.t) || nullablePrimitiveKind(e.t) != null)
							return buildExpr(e);
						final enumName = fullNameOfTypeEnum(e.t);
						final nullableEnumName = isNullableEnumType(e.t);

						if (isBoolType(e.t)) {
							return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(e)]);
						}

						var obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e)]);
						if (enumName != null) {
							obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
								[OcamlExpr.EConst(OcamlConst.CString(enumName)), obj]);
						} else if (nullableEnumName != null) {
							obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
								[OcamlExpr.EConst(OcamlConst.CString(nullableEnumName)), obj]);
						}
						return obj;
					}

					if (isDynamicLike(e1.t) || isDynamicLike(e2.t)) {
						return OcamlExpr.EUnop(OcamlUnop.Not,
							OcamlExpr.EApp(dynamicEqualityFunction(source, OcamlDynamicEqualityKind.NotEqual), [toDynamicObj(e1), toDynamicObj(e2)]));
					}

					inline function shouldUsePhysicalEq(t:Type):Bool {
						if (isStringType(t) || nullablePrimitiveKind(t) != null)
							return false;
						return switch (followNoAbstracts(unwrapNullType(t))) {
							case TInst(_, _): true;
							case TAnonymous(_): !shouldAnonUseHxAnon(t);
							case TFun(_, _): true;
							case _: false;
						}
					}

					final k1 = nullablePrimitiveKind(e1.t);
					final k2 = nullablePrimitiveKind(e2.t);
					final primEq = buildNullablePrimitiveEq(k1, e1, k2, e2);
					if (primEq != null) {
						OcamlExpr.EUnop(OcamlUnop.Not, primEq);
					} else if (isStringType(e1.t) || isStringType(e2.t)) {
						OcamlExpr.EUnop(OcamlUnop.Not,
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "equals"), [buildExpr(e1), buildExpr(e2)]));
					} else if (shouldUsePhysicalEq(e1.t) || shouldUsePhysicalEq(e2.t)) {
						OcamlExpr.EBinop(OcamlBinop.PhysNeq, OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e1)]),
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(e2)]));
					} else {
						final c = coerceForComparison(e1, e2);
						OcamlExpr.EBinop(OcamlBinop.Neq, c.l, c.r);
					}
				}
			case OpLt:
				final cmp = buildNullablePrimitiveCompare(OcamlBinop.Lt, e1, e2);
				if (cmp != null) cmp else {
					final c = coerceForComparison(e1, e2);
					OcamlExpr.EBinop(OcamlBinop.Lt, c.l, c.r);
				}
			case OpLte:
				final cmp = buildNullablePrimitiveCompare(OcamlBinop.Lte, e1, e2);
				if (cmp != null) cmp else {
					final c = coerceForComparison(e1, e2);
					OcamlExpr.EBinop(OcamlBinop.Lte, c.l, c.r);
				}
			case OpGt:
				final cmp = buildNullablePrimitiveCompare(OcamlBinop.Gt, e1, e2);
				if (cmp != null) cmp else {
					final c = coerceForComparison(e1, e2);
					OcamlExpr.EBinop(OcamlBinop.Gt, c.l, c.r);
				}
			case OpGte:
				final cmp = buildNullablePrimitiveCompare(OcamlBinop.Gte, e1, e2);
				if (cmp != null) cmp else {
					final c = coerceForComparison(e1, e2);
					OcamlExpr.EBinop(OcamlBinop.Gte, c.l, c.r);
				}
			case OpBoolAnd:
				final plannedLhs = buildPlannedNullableBoolTruthiness(e1);
				final plannedRhs = buildPlannedNullableBoolTruthiness(e2);
				final lhs = plannedLhs != null ? plannedLhs : (nullablePrimitiveKind(e1.t) == "bool" ? safeUnboxNullableBool(buildExpr(e1)) : buildExpr(e1));
				final rhs = plannedRhs != null ? plannedRhs : (nullablePrimitiveKind(e2.t) == "bool" ? safeUnboxNullableBool(buildExpr(e2)) : buildExpr(e2));
				OcamlExpr.EBinop(OcamlBinop.And, lhs, rhs);
			case OpBoolOr:
				final plannedLhs = buildPlannedNullableBoolTruthiness(e1);
				final plannedRhs = buildPlannedNullableBoolTruthiness(e2);
				final lhs = plannedLhs != null ? plannedLhs : (nullablePrimitiveKind(e1.t) == "bool" ? safeUnboxNullableBool(buildExpr(e1)) : buildExpr(e1));
				final rhs = plannedRhs != null ? plannedRhs : (nullablePrimitiveKind(e2.t) == "bool" ? safeUnboxNullableBool(buildExpr(e2)) : buildExpr(e2));
				OcamlExpr.EBinop(OcamlBinop.Or, lhs, rhs);
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	function coerceNullableIntToInt(value:TypedExpr):OcamlExpr {
		return nullablePrimitiveKind(value.t) == "int" ? safeUnboxNullableInt(buildExpr(value)) : buildExpr(value);
	}

	function safeUnboxNullableInt(expr:OcamlExpr):OcamlExpr {
		final tmp = freshTmp("nullable_int");
		final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
		return OcamlExpr.ELet(tmp, expr,
			OcamlExpr.EIf(OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull), OcamlExpr.EConst(OcamlConst.CInt(0)),
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])),
			false);
	}

	function safeUnboxNullableFloat(expr:OcamlExpr):OcamlExpr {
		final tmp = freshTmp("nullable_float");
		final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
		return OcamlExpr.ELet(tmp, expr,
			OcamlExpr.EIf(OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull), OcamlExpr.EConst(OcamlConst.CFloat("0.")),
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])),
			false);
	}

	function safeUnboxNullableBool(expr:OcamlExpr):OcamlExpr {
		final tmp = freshTmp("nullable_bool");
		final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
		return OcamlExpr.ELet(tmp, expr,
			OcamlExpr.EIf(OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull), OcamlExpr.EConst(OcamlConst.CBool(false)),
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [OcamlExpr.EIdent(tmp)])),
			false);
	}

	inline function coerceToObjCarrier(valueType:Type, value:OcamlExpr):OcamlExpr {
		if (isDynamicLike(valueType) || nullablePrimitiveKind(valueType) != null || isTypeParameterType(valueType)) {
			return value;
		}

		final nullableEnumName = isNullableEnumType(valueType);
		if (nullableEnumName != null) {
			return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
				[OcamlExpr.EConst(OcamlConst.CString(nullableEnumName)), value]);
		}

		var obj:OcamlExpr = isBoolType(valueType) ? OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"),
			[value]) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [value]);

		final enumName = fullNameOfTypeEnum(valueType);
		if (enumName != null) {
			obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"), [OcamlExpr.EConst(OcamlConst.CString(enumName)), obj]);
		}

		return obj;
	}

	inline function toObjValueExpr(e:TypedExpr):OcamlExpr {
		return coerceToObjCarrier(e.t, buildExpr(e));
	}

	function coerceForAssignment(lhsType:Type, rhs:TypedExpr):OcamlExpr {
		// A standard `Map` inline expansion can pass its hidden `IMap` local to a
		// target-owned raw-map operation. The sealed alias proves this exact argument
		// occurrence, so the ordinary class/interface cast must not re-box it.
		if (currentIMapInterfacePlan != null) {
			final storageAlias = try {
				currentIMapInterfacePlan.storageAliasUseFor(rhs);
			} catch (error:Dynamic) {
				return callPlanInvariant(Std.string(error), rhs.pos);
			}
			if (storageAlias != null)
				return buildExpr(rhs);
		}
		if (isExactIMapType(lhsType)) {
			// Haxe may give a constructor expression its expected interface type. The
			// typed `TNew` node still names the concrete class that will exist at
			// runtime, so use that source when deciding whether an adapter is needed.
			if (isExactIMapType(OcamlIMapInterfacePlanner.conversionSourceType(rhs)))
				return buildExpr(rhs);
			return switch (unwrap(rhs).expr) {
				case TConst(TNull):
					OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				case _:
					if (currentIMapInterfacePlan == null)
						return callPlanInvariant("a concrete value reached an IMap boundary without an active interface-conversion plan", rhs.pos);
					final materialization = try {
						currentIMapInterfacePlan.requireConversion(rhs, lhsType);
					} catch (error:Dynamic) {
						return callPlanInvariant(Std.string(error), rhs.pos);
					}
					buildPlannedIMapInterfaceConversion(materialization, rhs);
			};
		}
		final lhsKind = nullablePrimitiveKind(lhsType);
		final rhsKind = nullablePrimitiveKind(rhs.t);
		final rhsDynamicCarrier = switch (followNoAbstracts(unwrapNullType(rhs.t))) {
			case TDynamic(_):
				true;
			case TAbstract(_, _) if (isStdAnyAbstract(rhs.t)):
				true;
			case _:
				false;
		}

		// String / Null<String> slots: keep OCaml inference anchored to `string`.
		//
		// Why
		// - Some upstream stdlib parser helpers initialize local string slots with `null`
		//   and later assign string-producing calls.
		// - Without an explicit type anchor, OCaml can infer those locals/functions as `unit`
		//   through try/raise control-flow joins, which then explodes at string callsites.
		//
		// How
		// - Preserve exact String `null` through the runtime-owned sentinel.
		// - Annotate non-null RHS values against the LHS string type.
		if (isStringType(lhsType)) {
			final lhsTypeExpr = typeExprFromHaxeType(lhsType);
			final lhsIsObjCarrier = switch (lhsTypeExpr) {
				case TIdent("Obj.t"): true;
				case _: false;
			}
			final rhsUnwrapped = unwrap(rhs);
			return switch (rhsUnwrapped.expr) {
				case TConst(TNull):
					if (lhsIsObjCarrier) {
						OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
					} else if (OcamlRepresentationRegistry.isExactString(lhsType)) {
						exactStringNullValue(OcamlRepresentationDomain.InternalValue, "assignment-explicit-null", rhs.pos);
					} else {
						OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);
					}
				case _:
					if (rhsDynamicCarrier) {
						lhsIsObjCarrier ? coerceToObjCarrier(rhs.t, buildExpr(rhs)) : OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(rhs)]);
					} else if (lhsIsObjCarrier) {
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
					} else {
						OcamlExpr.EAnnot(buildExpr(rhs), lhsTypeExpr);
					}
			}
		}

		final lhsUnwrapped = unwrapNullType(lhsType);

		// Structural iterator coercion: class instance -> `{ hasNext, next }` record.
		//
		// Why:
		// - OCaml runtime helpers (`HxIterator.hasNext/next`) expect iterator values with
		//   record fields `hasNext` and `next`.
		// - Haxe iterators often arrive as class instances (e.g. `haxe.iterators.ArrayIterator`)
		//   and must be adapted when assigned/coerced to `Iterator<T>`.
		//
		// Without this bridge, callsites can cast class instances to iterator records and
		// crash at runtime when invoking `it.next`.
		if (isIteratorAnon(lhsUnwrapped)) {
			function findField(owner:ClassType, name:String):Null<{owner:ClassType, field:ClassField}> {
				for (f in owner.fields.get()) {
					if (f.name == name)
						return {owner: owner, field: f};
				}
				return owner.superClass != null ? findField(owner.superClass.t.get(), name) : null;
			}

			switch (followNoAbstracts(unwrapNullType(rhs.t))) {
				case TInst(cRef, _) if (!isDynamicLike(rhs.t)):
					final cls = cRef.get();
					final hasNextField = findField(cls, "hasNext");
					final nextField = findField(cls, "next");
					if (hasNextField != null && nextField != null) {
						final recvTmp = freshTmp("iter_obj");
						final recvVar = OcamlExpr.EIdent(recvTmp);
						return OcamlExpr.ELet(recvTmp, buildExpr(rhs), OcamlExpr.ERecord([
							{
								name: "hasNext",
								value: buildBoundMethodClosureFromReceiverVar(rhs, recvVar, rhs.t, hasNextField.owner, hasNextField.field, rhs.pos)
							},
							{
								name: "next",
								value: buildBoundMethodClosureFromReceiverVar(rhs, recvVar, rhs.t, nextField.owner, nextField.field, rhs.pos)
							}
						]), false);
					}
				case _:
			}
		}

		// Dynamic / anonymous slots: represent arbitrary values as `Obj.t`.
		//
		// This is required for patterns like:
		//   `final d:Dynamic = new Child();`
		//
		// Without boxing (`Obj.repr`), OCaml infers `d` as `child_t`, which then fails when
		// passed to runtime APIs expecting `Obj.t` (e.g. `Type.getClass(d)`).
		//
		// Important: anonymous structures already use the `HxAnon` runtime representation (`Obj.t`),
		// so we must *not* double-box those.
		switch (followNoAbstracts(lhsUnwrapped)) {
			case TDynamic(_):
				final rhsUnwrapped = unwrap(rhs);
				final rhsIsNull = switch (rhsUnwrapped.expr) {
					case TConst(TNull): true;
					case _: false;
				}
				if (rhsIsNull) {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
				if (rhsKind != null) {
					return buildExpr(rhs);
				}
				if (isTypeParameterType(rhs.t)) {
					return buildExpr(rhs);
				}
				// Enums stored as `Obj.t` must be boxed to preserve enum identity at runtime.
				final rhsNullableEnumName = isNullableEnumType(rhs.t);
				if (rhsNullableEnumName != null) {
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsNullableEnumName)), buildExpr(rhs)]);
				}
				final rhsEnumName = fullNameOfTypeEnum(rhs.t);
				if (rhsEnumName != null) {
					final asObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsEnumName)), asObj]);
				}
				// Booleans stored as `Obj.t` must be boxed to avoid int/bool ambiguity.
				if (isBoolType(rhs.t)) {
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(rhs)]);
				}
				switch (followNoAbstracts(unwrapNullType(rhs.t))) {
					case TDynamic(_):
						return buildExpr(rhs);
					case TAbstract(_, _) if (isStdAnyAbstract(rhs.t)):
						return buildExpr(rhs);
					case TAnonymous(_) if (shouldAnonUseHxAnon(rhs.t)):
						return buildExpr(rhs);
					case _:
						return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				}
			case TInst(cRef, _) if (switch (cRef.get().kind) {
					case KTypeParameter(_): true;
					case _: false;
				}):
				// Portable mode represents class type parameters as `Obj.t` in OCaml.
				// This means generic method parameters (e.g. `StringBuf.add<T>(x:T)`) must
				// box their arguments when crossing from a concrete value type (like `string`)
				// into that `Obj.t` slot.
				final rhsUnwrapped = unwrap(rhs);
				final rhsIsNull = switch (rhsUnwrapped.expr) {
					case TConst(TNull): true;
					case _: false;
				}
				if (rhsIsNull) {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
				if (rhsKind != null) {
					return buildExpr(rhs);
				}
				if (isTypeParameterType(rhs.t)) {
					return buildExpr(rhs);
				}
				if (isBoolType(rhs.t)) {
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(rhs)]);
				}
				switch (followNoAbstracts(unwrapNullType(rhs.t))) {
					case TDynamic(_):
						return buildExpr(rhs);
					case TAbstract(_, _) if (isStdAnyAbstract(rhs.t)):
						return buildExpr(rhs);
					case TAnonymous(_) if (shouldAnonUseHxAnon(rhs.t)):
						return buildExpr(rhs);
					case _:
						return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				}
			case TAbstract(_, _) if (!isStdAnyAbstract(lhsUnwrapped) && switch (typeExprFromHaxeType(lhsType)) {
					case TIdent("Obj.t"): true;
					case _: false;
				}):
				final rhsUnwrapped = unwrap(rhs);
				final rhsIsNull = switch (rhsUnwrapped.expr) {
					case TConst(TNull): true;
					case _: false;
				}
				if (rhsIsNull) {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
				return coerceToObjCarrier(rhs.t, buildExpr(rhs));
			case TAbstract(_, _) if (isStdAnyAbstract(lhsUnwrapped)):
				final rhsUnwrapped = unwrap(rhs);
				final rhsIsNull = switch (rhsUnwrapped.expr) {
					case TConst(TNull): true;
					case _: false;
				}
				if (rhsIsNull) {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
				if (rhsKind != null) {
					return buildExpr(rhs);
				}
				if (isTypeParameterType(rhs.t)) {
					return buildExpr(rhs);
				}
				final rhsNullableEnumName = isNullableEnumType(rhs.t);
				if (rhsNullableEnumName != null) {
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsNullableEnumName)), buildExpr(rhs)]);
				}
				final rhsEnumName = fullNameOfTypeEnum(rhs.t);
				if (rhsEnumName != null) {
					final asObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsEnumName)), asObj]);
				}
				if (isBoolType(rhs.t)) {
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(rhs)]);
				}
				switch (followNoAbstracts(unwrapNullType(rhs.t))) {
					case TDynamic(_):
						return buildExpr(rhs);
					case TAbstract(_, _) if (isStdAnyAbstract(rhs.t)):
						return buildExpr(rhs);
					case TAnonymous(_) if (shouldAnonUseHxAnon(rhs.t)):
						return buildExpr(rhs);
					case _:
						return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				}
			case TAnonymous(_) if (shouldAnonUseHxAnon(lhsUnwrapped)):
				final rhsUnwrapped = unwrap(rhs);
				final rhsIsNull = switch (rhsUnwrapped.expr) {
					case TConst(TNull): true;
					case _: false;
				}
				if (rhsIsNull) {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
				if (rhsKind != null) {
					return buildExpr(rhs);
				}

				// Structural typing: class instance -> anonymous-structure slot (HxAnon).
				//
				// Example (upstream Issue8537):
				//   typedef A = { function bar():String; }
				//   function extract(a:A) return invoke(a.bar);
				//
				// Here `new C()` is structurally compatible with `A`, but our portable representation
				// for `A` is `HxAnon` (`Obj.t`). To preserve Haxe semantics for method closures, we
				// must wrap the class instance into an `HxAnon` object whose fields are *bound*
				// closures/values extracted from the class instance.
				switch (followNoAbstracts(unwrapNullType(rhs.t))) {
					case TInst(cRef, _) if (!isDynamicLike(rhs.t)):
						switch (followNoAbstracts(lhsUnwrapped)) {
							case TAnonymous(aRef):
								final anon = aRef.get();
								final cls0 = cRef.get();

								function findField(owner:ClassType, name:String):Null<{owner:ClassType, field:ClassField}> {
									for (f in owner.fields.get()) {
										if (f.name == name)
											return {owner: owner, field: f};
									}
									return owner.superClass != null ? findField(owner.superClass.t.get(), name) : null;
								}

								inline function boxExprForObj(t:Type, expr:OcamlExpr):OcamlExpr {
									if (nullablePrimitiveKind(t) != null || isDynamicLike(t))
										return expr;
									if (isBoolType(t)) {
										return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [expr]);
									}

									var obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [expr]);
									final enumName = fullNameOfTypeEnum(t);
									final nullableEnumName = isNullableEnumType(t);
									if (enumName != null) {
										obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
											[OcamlExpr.EConst(OcamlConst.CString(enumName)), obj]);
									} else if (nullableEnumName != null) {
										obj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
											[OcamlExpr.EConst(OcamlConst.CString(nullableEnumName)), obj]);
									}
									return obj;
								}

								final objTmp = freshTmp("struct_obj");
								final anonTmp = freshTmp("struct_anon");
								final objVar = OcamlExpr.EIdent(objTmp);

								final initAnon = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "create"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
								final sets:Array<OcamlExpr> = [];

								for (f in anon.fields) {
									final found = findField(cls0, f.name);
									if (found == null) {
										#if macro
										guardrailError("reflaxe.ocaml (M10): structural coercion expected field '"
											+ f.name
											+ "' on class '"
											+ fullNameOfClassType(cls0)
											+ "', but it was not found.",
											rhs.pos);
										#end
										continue;
									}

									final valueObj:OcamlExpr = switch (found.field.kind) {
										case FMethod(_):
											OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [
												buildBoundMethodClosureFromReceiverVar(rhs, objVar, rhs.t, found.owner, found.field, rhs.pos)
											]);
										case FVar(_, _):
											boxExprForObj(found.field.type, OcamlExpr.EField(objVar, found.field.name));
										case _:
											OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
									}

									sets.push(OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [
										OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "set"), [
											OcamlExpr.EIdent(anonTmp),
											OcamlExpr.EConst(OcamlConst.CString(f.name)),
											valueObj
										])
									]));
								}

								return OcamlExpr.ELet(objTmp, buildExpr(rhs),
									OcamlExpr.ELet(anonTmp, initAnon, OcamlExpr.ESeq(sets.concat([OcamlExpr.EIdent(anonTmp)])), false), false);
							case _:
						}
					case _:
				}

				final rhsNullableEnumName = isNullableEnumType(rhs.t);
				if (rhsNullableEnumName != null) {
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsNullableEnumName)), buildExpr(rhs)]);
				}
				final rhsEnumName = fullNameOfTypeEnum(rhs.t);
				if (rhsEnumName != null) {
					final asObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
						[OcamlExpr.EConst(OcamlConst.CString(rhsEnumName)), asObj]);
				}
				if (isBoolType(rhs.t)) {
					return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(rhs)]);
				}
				switch (followNoAbstracts(unwrapNullType(rhs.t))) {
					case TDynamic(_):
						return buildExpr(rhs);
					case TAbstract(_, _) if (isStdAnyAbstract(rhs.t)):
						return buildExpr(rhs);
					case TAnonymous(_) if (shouldAnonUseHxAnon(rhs.t)):
						return buildExpr(rhs);
					case _:
						return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				}
			case _:
		}

		// Dynamic/Any source -> primitive destination.
		//
		// Flow-typed branches can keep source values typed as Dynamic in the AST while
		// assignments expect primitives. Unbox explicitly so downstream primitive
		// operations typecheck in OCaml.
		if (rhsDynamicCarrier) {
			final lhsEnumName = fullNameOfTypeEnum(lhsType);
			if (lhsEnumName != null) {
				return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "unbox_or_obj"),
					[OcamlExpr.EConst(OcamlConst.CString(lhsEnumName)), buildExpr(rhs)]);
			}
		}
		if (rhsDynamicCarrier) {
			if (isIntType(lhsType)) {
				return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [buildExpr(rhs)]);
			}
			if (isFloatType(lhsType)) {
				return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [buildExpr(rhs)]);
			}
			if (isBoolType(lhsType)) {
				return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [buildExpr(rhs)]);
			}
		}

		// Non-null primitive slot <- nullable primitive value.
		if (lhsKind == null && rhsKind != null) {
			return switch (rhsKind) {
				case "int" if (isIntType(lhsType)):
					safeUnboxNullableInt(buildExpr(rhs));
				case "float" if (isFloatType(lhsType)):
					safeUnboxNullableFloat(buildExpr(rhs));
				case "bool" if (isBoolType(lhsType)):
					safeUnboxNullableBool(buildExpr(rhs));
				case _:
					buildExpr(rhs);
			}
		}

		// Nullable primitive slot <- non-null primitive value.
		if (lhsKind != null && rhsKind == null) {
			return switch (lhsKind) {
				case "int" if (isIntType(rhs.t)):
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				case "float" if (isFloatType(rhs.t)):
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				case "float" if (isIntType(rhs.t)):
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(rhs)])]);
				case "bool" if (isBoolType(rhs.t)):
					// Box bools to avoid int/bool ambiguity when carried as `Obj.t`.
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [buildExpr(rhs)]);
				case _:
					buildExpr(rhs);
			}
		}

		// Float slots can accept Int values (promote).
		if (isFloatType(lhsType) && isIntType(rhs.t)) {
			return OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(rhs)]);
		}

		// Nullable enum slot (Obj.t) <- enum value
		//
		// We represent `Null<Enum>` as `Obj.t` so we can carry the `hx_null` sentinel.
		// Passing an enum value to a parameter typed as `Null<Enum>` should therefore
		// box with `Obj.repr` (unless the value is literally `null`).
		final lhsNullEnumName:Null<String> = switch (followNoAbstracts(lhsType)) {
			case TAbstract(aRef, [inner]) if ((aRef.get().pack ?? []).length == 0 && aRef.get().name == "Null"):
				switch (TypeTools.follow(inner)) {
					case TEnum(eRef, _):
						final e = eRef.get();
						(e.pack ?? []).concat([e.name]).join(".");
					case _:
						null;
				}
			case _:
				null;
		}
		if (lhsNullEnumName != null) {
			// Only box when RHS is a *non-null* enum value.
			// If RHS is already `Null<Enum>` (i.e. already `Obj.t`), boxing would double-wrap.
			final rhsWasNullable = unwrapNullType(rhs.t) != rhs.t;
			final rhsEnumName:Null<String> = (!rhsWasNullable) ? switch (TypeTools.follow(rhs.t)) {
				case TEnum(eRef, _):
					final e = eRef.get();
					(e.pack ?? []).concat([e.name]).join(".");
				case _:
					null;
			} : null;
			if (rhsEnumName != null) {
				final rhsUnwrapped = unwrap(rhs);
				final rhsIsNull = switch (rhsUnwrapped.expr) {
					case TConst(TNull): true;
					case _: false;
				}
				if (rhsIsNull) {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				}
				final asObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(rhs)]);
				return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "box_if_needed"),
					[OcamlExpr.EConst(OcamlConst.CString(rhsEnumName)), asObj]);
			}
		}

		// Nullable enum (Obj.t) -> enum value
		//
		// We represent `Null<Enum>` as `Obj.t` to carry the `hx_null` sentinel safely.
		// When Haxe flow-typing refines a nullable enum to a non-null enum (e.g. after
		// `if (e != null)`), it often passes that value to functions expecting `Enum`,
		// without inserting an explicit cast expression.
		//
		// At those callsites we must unbox (`Obj.obj`) to satisfy OCaml typing.
		final lhsEnumName:Null<String> = switch (TypeTools.follow(lhsType)) {
			case TEnum(eRef, _):
				final e = eRef.get();
				(e.pack ?? []).concat([e.name]).join(".");
			case _:
				null;
		}
		if (lhsEnumName != null) {
			final rhsU = unwrapNullType(rhs.t);
			final rhsEnumName:Null<String> = switch (TypeTools.follow(rhsU)) {
				case TEnum(eRef, _):
					final e = eRef.get();
					(e.pack ?? []).concat([e.name]).join(".");
				case _:
					null;
			}
			if (rhsEnumName != null && rhsEnumName == lhsEnumName && rhsU != rhs.t) {
				final unboxed = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "unbox_or_obj"),
					[OcamlExpr.EConst(OcamlConst.CString(lhsEnumName)), buildExpr(rhs)]);
				return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [unboxed]);
			}
			return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(rhs)]);
		}

		// Function return adaptation: when a callsite expects `Void` but the provided
		// closure returns a value expression (commonly assignment expressions), wrap it
		// and discard the result so OCaml sees `unit -> unit`.
		switch ([
			followNoAbstracts(unwrapNullType(lhsType)),
			followNoAbstracts(unwrapNullType(rhs.t))
		]) {
			case [TFun(lhsArgs, lhsRet), TFun(_, rhsRet)] if (isVoidType(lhsRet) && !isVoidType(rhsRet)):
				final callee = buildExpr(rhs);
				final pats:Array<OcamlPat> = [];
				final callArgs:Array<OcamlExpr> = [];
				if (lhsArgs.length == 0) {
					pats.push(OcamlPat.PConst(OcamlConst.CUnit));
					callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
				} else {
					for (i in 0...lhsArgs.length) {
						final n = freshTmp("arg");
						pats.push(OcamlPat.PVar(n));
						callArgs.push(OcamlExpr.EIdent(n));
					}
				}
				final invoke = OcamlExpr.EApp(callee, callArgs);
				return OcamlExpr.EFun(pats, OcamlExpr.ESeq([
					OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [invoke]),
					OcamlExpr.EConst(OcamlConst.CUnit)
				]));
			case _:
		}

		// Class upcasts (inheritance + interfaces): Derived -> Base or Impl -> IFace
		// requires an explicit cast at the OCaml type level.
		final lhsCls = classTypeFromType(lhsType);
		final rhsCls = classTypeFromType(rhs.t);
		if (lhsCls != null && rhsDynamicCarrier) {
			return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(rhs)]);
		}
		if (lhsCls != null && rhsCls == null) {
			return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(rhs)]);
		}
		if (lhsCls != null && rhsCls != null) {
			final lhsName = (lhsCls.pack ?? []).concat([lhsCls.name]).join(".");
			final rhsName = (rhsCls.pack ?? []).concat([rhsCls.name]).join(".");
			if (lhsName == rhsName) {
				return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(rhs)]);
			}
			if (isSubclassOf(rhsCls, lhsCls)) {
				return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(rhs)]);
			}
			if (lhsCls.isInterface && implementsInterface(rhsCls, lhsCls)) {
				return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(rhs)]);
			}
		}

		return buildExpr(rhs);
	}

	static inline function isTypeParameterType(t:Type):Bool {
		return switch (followNoAbstracts(unwrapNullType(t))) {
			case TInst(cRef, _):
				switch (cRef.get().kind) {
					case KTypeParameter(_): true;
					case _: false;
				}
			case _:
				false;
		}
	}

	function buildUnop(op:Unop, postFix:Bool, e:TypedExpr, resultType:Type):OcamlExpr {
		return switch (op) {
			case OpNot:
				final plannedTruthiness = buildPlannedNullableBoolTruthiness(e);
				OcamlExpr.EUnop(OcamlUnop.Not, plannedTruthiness == null ? buildExpr(e) : plannedTruthiness);
			case OpNegBits:
				final kind = nullablePrimitiveKind(e.t);
				final v = kind == "int" ? safeUnboxNullableInt(buildExpr(e)) : buildExpr(e);
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "lognot"), [v]);
			case OpNeg:
				if (isFloatType(resultType) || nullablePrimitiveKind(resultType) == "float") {
					final kind = nullablePrimitiveKind(e.t);
					final v = switch (kind) {
						case "float":
							safeUnboxNullableFloat(buildExpr(e));
						case "int":
							OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [safeUnboxNullableInt(buildExpr(e))]);
						case _:
							if (isDynamicLike(e.t)) {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [buildExpr(e)]);
							} else if (isIntType(e.t)) {
								OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"), [buildExpr(e)]);
							} else {
								buildExpr(e);
							}
					}
					OcamlExpr.EUnop(OcamlUnop.NegF, v);
				} else {
					final kind = nullablePrimitiveKind(e.t);
					final v = kind == "int" ? safeUnboxNullableInt(buildExpr(e)) : buildExpr(e);
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "neg"), [v]);
				}
			case OpIncrement, OpDecrement:
				// ++x / x++ / --x / x--:
				//
				// Haxe semantics:
				// - prefix: ++x returns the updated value
				// - postfix: x++ returns the old value
				//
				// We support:
				// - ref locals (`let x = ref ...`)
				// - instance var fields (record fields on `t`)
				// - array elements (`HxArray.get/set`)
				final lvalueNullableKind = nullablePrimitiveKind(e.t);
				function numericKind(t:Type, depth:Int):Null<String> {
					if (depth > 16)
						return null;
					if (isDynamicLike(t))
						return "dynamic";

					final direct = if (isIntType(t)) {
						"int";
					} else if (isFloatType(t)) {
						"float";
					} else if (nullablePrimitiveKind(t) != null) {
						nullablePrimitiveKind(t);
					} else {
						null;
					}
					if (direct != null)
						return direct;

					return switch (followNoAbstracts(unwrapNullType(t))) {
						case TAbstract(aRef, params):
							final a = aRef.get();
							// Follow the underlying representation of the abstract with the current type params applied.
							final under = TypeTools.applyTypeParameters(a.type, a.params, params);
							numericKind(under, depth + 1);
						case TInst(cRef, _):
							switch (cRef.get().kind) {
								case KTypeParameter(constraints):
									var out:Null<String> = null;
									if (constraints != null) {
										for (c in constraints) {
											if (out == null && isFloatType(c))
												out = "float";
											if (out == null && isIntType(c))
												out = "int";
										}
									}
									out;
								case _:
									null;
							}
						case _:
							null;
					}
				}

				final kind = numericKind(e.t, 0);

				final resultNullableKind = nullablePrimitiveKind(resultType);
				final resultIsNullable = resultNullableKind != null;
				final resultIsDynamic = isDynamicLike(resultType);

				if (kind == null || kind == "bool") {
					#if macro
					guardrailError("reflaxe.ocaml (M10): ++/-- is only supported for Int/Float (and their nullable forms) for now.", e.pos);
					#end
					OcamlExpr.EConst(OcamlConst.CUnit);
				} else if (kind == "dynamic") {
					final deltaInt = op == OpIncrement ? 1 : -1;
					final deltaFloatLiteral = op == OpIncrement ? "1." : "-1.";
					final deltaFloatExpr = OcamlExpr.EConst(OcamlConst.CFloat(deltaFloatLiteral));

					inline function incDecDynamic(getOldObj:OcamlExpr, setNewObj:OcamlExpr->OcamlExpr):OcamlExpr {
						final oldName = freshTmp("old");
						final isNullName = freshTmp("isNull");
						final isRawIntName = freshTmp("isInt");
						final oldFloatName = freshTmp("oldf");
						final oldIntName = freshTmp("oldi");
						final isIntName = freshTmp("useInt");
						final newFloatName = freshTmp("newf");
						final newIntName = freshTmp("newi");
						final newRepName = freshTmp("new");

						final isNullExpr = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "is_null"), [OcamlExpr.EIdent(oldName)]);
						final isRawIntExpr = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "is_int"), [OcamlExpr.EIdent(oldName)]);
						final isDoubleExpr = OcamlExpr.EBinop(OcamlBinop.Eq,
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "tag"), [OcamlExpr.EIdent(oldName)]),
							OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "double_tag"));

						final oldFloatExpr:OcamlExpr = OcamlExpr.EIf(OcamlExpr.EIdent(isNullName), OcamlExpr.EConst(OcamlConst.CFloat("0.")),
							OcamlExpr.EIf(OcamlExpr.EIdent(isRawIntName), OcamlExpr.EApp(OcamlExpr.EIdent("float_of_int"),
								[
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(oldName)])
								]),
								OcamlExpr.EIf(isDoubleExpr, OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(oldName)]),
									OcamlExpr.EConst(OcamlConst.CFloat("0.")))));

						final oldIntExpr:OcamlExpr = OcamlExpr.EIf(OcamlExpr.EIdent(isNullName), OcamlExpr.EConst(OcamlConst.CInt(0)),
							OcamlExpr.EIf(OcamlExpr.EIdent(isRawIntName),
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(oldName)]),
								OcamlExpr.EApp(OcamlExpr.EIdent("int_of_float"), [OcamlExpr.EIdent(oldFloatName)])));

						final isIntExpr:OcamlExpr = OcamlExpr.EBinop(OcamlBinop.Or, OcamlExpr.EIdent(isNullName), OcamlExpr.EIdent(isRawIntName));

						final newFloatExpr = OcamlExpr.EBinop(OcamlBinop.AddF, OcamlExpr.EIdent(oldFloatName), deltaFloatExpr);
						final newIntExpr = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"),
							[OcamlExpr.EIdent(oldIntName), OcamlExpr.EConst(OcamlConst.CInt(deltaInt))]);
						final newRepExpr = OcamlExpr.EIf(OcamlExpr.EIdent(isIntName),
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EIdent(newIntName)]),
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EIdent(newFloatName)]));

						final resultExpr:OcamlExpr = if (resultIsDynamic || resultIsNullable) {
							postFix ? OcamlExpr.EIdent(oldName) : OcamlExpr.EIdent(newRepName);
						} else {
							final resKind = numericKind(resultType, 0);
							(resKind == "float") ? (postFix ? OcamlExpr.EIdent(oldFloatName) : OcamlExpr.EIdent(newFloatName)) : (postFix ? OcamlExpr.EIdent(oldIntName) : OcamlExpr.EIdent(newIntName));
						}

						final setExpr = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [setNewObj(OcamlExpr.EIdent(newRepName))]);

						return OcamlExpr.ELet(oldName, getOldObj,
							OcamlExpr.ELet(isNullName, isNullExpr,
								OcamlExpr.ELet(isRawIntName, isRawIntExpr,
									OcamlExpr.ELet(oldFloatName, oldFloatExpr,
										OcamlExpr.ELet(oldIntName, oldIntExpr,
											OcamlExpr.ELet(isIntName, isIntExpr,
												OcamlExpr.ELet(newFloatName, newFloatExpr,
													OcamlExpr.ELet(newIntName, newIntExpr,
														OcamlExpr.ELet(newRepName, newRepExpr, OcamlExpr.ESeq([setExpr, resultExpr]), false), false),
													false),
												false),
											false),
										false),
									false),
								false),
							false);
					}

					switch (e.expr) {
						case TLocal(v) if (isRefLocalId(v.id)):
							incDecDynamic(buildLocal(v), (newVal) -> OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), newVal));
						case TField(obj, FStatic(clsRef, cfRef)):
							if (OcamlPlaceInputPolicy.admitsIntUpdateStaticField(op, e, ctx.currentModuleId, ctx.currentTypeName, staticStoragePlan))
								return placeLoweringInvariant("admitted static-field update reached the legacy dynamic syntax branch without a stable origin",
									e.pos);
							final cls = clsRef.get();
							final cf = cfRef.get();
							final key = (cls.pack ?? []).concat([cls.name, cf.name]).join(".");
							final isMutableStatic = switch (cf.kind) {
								case FVar(_, _): !cf.isFinal;
								case _: false;
							}
							if (!isMutableStatic) {
								#if macro
								guardrailError("reflaxe.ocaml (M10): ++/-- on immutable static field '" + key + "' is not supported yet.", e.pos);
								#end
								OcamlExpr.EConst(OcamlConst.CUnit);
							} else {
								final storage = requireStaticStorage(cls, cf, e.pos);
								final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
								final modName = moduleIdToOcamlModuleName(cls.module);
								final scoped = storage.targetValueName;
								final lhsCell = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(scoped) : OcamlExpr.EField(OcamlExpr.EIdent(modName),
									scoped);
								incDecDynamic(OcamlExpr.EUnop(OcamlUnop.Deref, lhsCell), (newVal) -> OcamlExpr.EAssign(OcamlAssignOp.RefSet, lhsCell, newVal));
							}
						case TField(obj, FInstance(clsRef, _, cfRef)):
							final cf = cfRef.get();
							switch (cf.kind) {
								case FVar(_, _):
									final cls = clsRef.get();
									final objName = freshTmp("obj");
									final fieldName = ctx.ocamlRecordLabel(cf.name);
									final modName = moduleIdToOcamlModuleName(cls.module);
									final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
									final scopedType = ctx.scopedInstanceTypeName(cls.module, cls.name);
									final fullType = (selfMod != null && selfMod == modName) ? scopedType : (modName + "." + scopedType);
									final recvExpr = OcamlExpr.EAnnot(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent(objName)]),
										OcamlTypeExpr.TIdent(fullType));
									OcamlExpr.ELet(objName, buildExpr(obj),
										incDecDynamic(OcamlExpr.EField(recvExpr, fieldName),
											(newVal) -> OcamlExpr.EAssign(OcamlAssignOp.FieldSet, OcamlExpr.EField(recvExpr, fieldName), newVal)),
										false);
								case _:
									OcamlExpr.EConst(OcamlConst.CUnit);
							}
						case TField(obj, FDynamic(name)):
							final objName = freshTmp("obj");
							final recvObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [OcamlExpr.EIdent(objName)]);
							final fieldName = OcamlExpr.EConst(OcamlConst.CString(name));
							OcamlExpr.ELet(objName, buildExpr(obj),
								incDecDynamic(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "get"), [recvObj, fieldName]),
									(newVal) -> OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "set"), [recvObj, fieldName, newVal])),
								false);
						case TArray(arr, idx):
							if (OcamlPlaceInputPolicy.admitsIntUpdateArrayElement(op, e))
								return placeLoweringInvariant("admitted array-element update reached the legacy syntax branch without a stable origin", e.pos);
							if (isStdBytesType(arr.t))
								return bytesAccessInvariant("standard Bytes bracket updates are not Haxe 4.3.7 API", e.pos);
							final arrName = freshTmp("arr");
							final idxName = freshTmp("idx");
							OcamlExpr.ELet(arrName, coerceArrayReceiver(buildExpr(arr), arr),
								OcamlExpr.ELet(idxName, buildExpr(idx),
									incDecDynamic(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "get"),
										[OcamlExpr.EIdent(arrName), OcamlExpr.EIdent(idxName)]),
										(newVal) -> OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set"),
											[OcamlExpr.EIdent(arrName), OcamlExpr.EIdent(idxName), newVal])),
									false),
								false);
						case _:
							OcamlExpr.EConst(OcamlConst.CUnit);
					}
				} else {
					final lvalueIsNullable = lvalueNullableKind != null;
					final deltaInt = op == OpIncrement ? 1 : -1;
					final deltaFloatLiteral = op == OpIncrement ? "1." : "-1.";
					final deltaPrimExpr = kind == "float" ? OcamlExpr.EConst(OcamlConst.CFloat(deltaFloatLiteral)) : OcamlExpr.EConst(OcamlConst.CInt(deltaInt));

					inline function incDec(getOldRep:OcamlExpr, setNewRep:OcamlExpr->OcamlExpr):OcamlExpr {
						// Fast path: non-null primitive lvalue with non-null primitive result.
						// Keep generated OCaml compact and stable for existing Int-only code.
						if (!lvalueIsNullable && !resultIsNullable) {
							final oldName = freshTmp("old");
							final newName = freshTmp("new");
							final updated = kind == "float" ? OcamlExpr.EBinop(OcamlBinop.AddF, OcamlExpr.EIdent(oldName),
								deltaPrimExpr) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [OcamlExpr.EIdent(oldName), deltaPrimExpr]);
							final setExpr = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [setNewRep(OcamlExpr.EIdent(newName))]);
							final resultName = postFix ? oldName : newName;
							return OcamlExpr.ELet(oldName, getOldRep,
								OcamlExpr.ELet(newName, updated, OcamlExpr.ESeq([setExpr, OcamlExpr.EIdent(resultName)]), false), false);
						}

						final oldRepName = freshTmp("old");
						final oldPrimName = freshTmp("oldp");
						final newPrimName = freshTmp("newp");
						final newRepName = freshTmp("new");

						final oldPrimExpr:OcamlExpr = if (lvalueIsNullable) {
							kind == "float" ? safeUnboxNullableFloat(OcamlExpr.EIdent(oldRepName)) : safeUnboxNullableInt(OcamlExpr.EIdent(oldRepName));
						} else {
							OcamlExpr.EIdent(oldRepName);
						}

						final newPrimExpr = kind == "float" ? OcamlExpr.EBinop(OcamlBinop.AddF, OcamlExpr.EIdent(oldPrimName),
							deltaPrimExpr) : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [OcamlExpr.EIdent(oldPrimName), deltaPrimExpr]);
						final newRepExpr:OcamlExpr = lvalueIsNullable ? OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"),
							[OcamlExpr.EIdent(newPrimName)]) : OcamlExpr.EIdent(newPrimName);

						final setExpr = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [setNewRep(OcamlExpr.EIdent(newRepName))]);

						final resultExpr:OcamlExpr = resultIsNullable ? (postFix ? OcamlExpr.EIdent(oldRepName) : OcamlExpr.EIdent(newRepName)) : (postFix ? OcamlExpr.EIdent(oldPrimName) : OcamlExpr.EIdent(newPrimName));

						return OcamlExpr.ELet(oldRepName, getOldRep,
							OcamlExpr.ELet(oldPrimName, oldPrimExpr,
								OcamlExpr.ELet(newPrimName, newPrimExpr, OcamlExpr.ELet(newRepName, newRepExpr, OcamlExpr.ESeq([setExpr, resultExpr]), false),
									false),
								false),
							false);
					}

					switch (e.expr) {
						case TLocal(v) if (isRefLocalId(v.id)):
							incDec(buildLocal(v), (newVal) -> OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(renameVar(v.name)), newVal));
						case TField(_, FStatic(clsRef, cfRef)):
							if (OcamlPlaceInputPolicy.admitsIntUpdateStaticField(op, e, ctx.currentModuleId, ctx.currentTypeName, staticStoragePlan))
								return placeLoweringInvariant("admitted static-field update reached the legacy syntax branch without a stable origin", e.pos);
							final cls = clsRef.get();
							final cf = cfRef.get();
							final key = (cls.pack ?? []).concat([cls.name, cf.name]).join(".");
							final isMutableStatic = switch (cf.kind) {
								case FVar(_, _): !cf.isFinal;
								case _: false;
							}
							if (!isMutableStatic) {
								#if macro
								guardrailError("reflaxe.ocaml (M10): ++/-- on immutable static field '" + key + "' is not supported yet.", e.pos);
								#end
								OcamlExpr.EConst(OcamlConst.CUnit);
							} else {
								final storage = requireStaticStorage(cls, cf, e.pos);
								final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
								final modName = moduleIdToOcamlModuleName(cls.module);
								final scoped = storage.targetValueName;
								final lhsCell = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(scoped) : OcamlExpr.EField(OcamlExpr.EIdent(modName),
									scoped);
								incDec(OcamlExpr.EUnop(OcamlUnop.Deref, lhsCell), (newVal) -> OcamlExpr.EAssign(OcamlAssignOp.RefSet, lhsCell, newVal));
							}
						case TField(obj, FInstance(clsRef, _, cfRef)):
							if (OcamlPlaceInputPolicy.admitsIntUpdateInstanceField(op, e))
								return placeLoweringInvariant("admitted instance-field update reached the legacy syntax branch without a stable origin", e.pos);
							final cf = cfRef.get();
							switch (cf.kind) {
								case FVar(_, _):
									final cls = clsRef.get();
									final objName = freshTmp("obj");
									final fieldName = ctx.ocamlRecordLabel(cf.name);
									final modName = moduleIdToOcamlModuleName(cls.module);
									final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
									final scopedType = ctx.scopedInstanceTypeName(cls.module, cls.name);
									final fullType = (selfMod != null && selfMod == modName) ? scopedType : (modName + "." + scopedType);
									final recvExpr = OcamlExpr.EAnnot(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent(objName)]),
										OcamlTypeExpr.TIdent(fullType));
									OcamlExpr.ELet(objName, buildExpr(obj),
										incDec(OcamlExpr.EField(recvExpr, fieldName),
											(newVal) -> OcamlExpr.EAssign(OcamlAssignOp.FieldSet, OcamlExpr.EField(recvExpr, fieldName), newVal)),
										false);
								case _:
									OcamlExpr.EConst(OcamlConst.CUnit);
							}
						case TArray(arr, idx):
							if (OcamlPlaceInputPolicy.admitsIntUpdateArrayElement(op, e))
								return placeLoweringInvariant("admitted array-element update reached the legacy syntax branch without a stable origin", e.pos);
							if (isStdBytesType(arr.t))
								return bytesAccessInvariant("standard Bytes bracket updates are not Haxe 4.3.7 API", e.pos);
							final arrName = freshTmp("arr");
							final idxName = freshTmp("idx");
							OcamlExpr.ELet(arrName, coerceArrayReceiver(buildExpr(arr), arr),
								OcamlExpr.ELet(idxName, buildExpr(idx),
									incDec(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "get"),
										[OcamlExpr.EIdent(arrName), OcamlExpr.EIdent(idxName)]),
										(newVal) -> OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set"),
											[OcamlExpr.EIdent(arrName), OcamlExpr.EIdent(idxName), newVal])),
									false),
								false);
						case _:
							OcamlExpr.EConst(OcamlConst.CUnit);
					}
				}
			case _:
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	function buildBlock(exprs:Array<TypedExpr>):OcamlExpr {
		final usedIds = collectUsedLocalIdsFromExprs(exprs);
		final prevUsed = currentUsedLocalIds;
		currentUsedLocalIds = usedIds;
		final result = buildBlockFromIndex(exprs, 0, false);
		currentUsedLocalIds = prevUsed;
		return result;
	}

	function buildBlockFromIndex(exprs:Array<TypedExpr>, index:Int, allowDirectReturn:Bool):OcamlExpr {
		// NOTE: This must be iterative, not recursive.
		//
		// Why
		// - Upstream macro/unit workloads contain some very large blocks (thousands of
		//   sequential expressions after typing/lowering).
		// - A naive recursive `buildBlockFromIndex(i+1)` approach can overflow the
		//   Haxe macro VM stack during codegen.
		//
		// Approach
		// - Scan forward to build a list of "wrappers" (let-bindings and ignored side-effect
		//   statements) while updating `refLocals` *before* compiling statements that
		//   depend on that mutability classification.
		// - Determine the base expression (the last expression or an early `return`).
		// - Apply wrappers in reverse order to build the final expression tree.
		if (index >= exprs.length)
			return OcamlExpr.EConst(OcamlConst.CUnit);

		inline function seq2(unitExpr:OcamlExpr, rest:OcamlExpr):OcamlExpr {
			return switch (rest) {
				case ESeq(items): OcamlExpr.ESeq([unitExpr].concat(items));
				case _: OcamlExpr.ESeq([unitExpr, rest]);
			}
		}

		inline function isNullInitializer(initExpr:Null<TypedExpr>):Bool {
			if (initExpr == null)
				return false;
			return switch (unwrap(initExpr).expr) {
				case TConst(TNull): true;
				case _: false;
			}
		}

		final wraps:Array<{kind:String, name:Null<String>, expr:OcamlExpr}> = [];

		var base:OcamlExpr = OcamlExpr.EConst(OcamlConst.CUnit);
		var hasBase = false;

		var i = index;
		while (i < exprs.length) {
			final e = exprs[i];
			final isLast = i == exprs.length - 1;

			switch (e.expr) {
				case TVar(v, init):
					final isUsed = currentUsedLocalIds != null && currentUsedLocalIds.exists(v.id) && currentUsedLocalIds.get(v.id) == true;

					if (!isUsed) {
						if (init != null) {
							wraps.push({
								kind: "seq",
								name: null,
								expr: OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [buildExpr(init)])
							});
						}
						if (isLast) {
							base = OcamlExpr.EConst(OcamlConst.CUnit);
							hasBase = true;
						}
					} else {
						final isMutable = localRequiresRef(v.id, e.pos);
						final shouldBind = isMutable || isLocalReadBeforeNextWrite(exprs, i + 1, v.id);

						// Haxe can type a generated local as a declaration followed by an
						// assignment. If no read occurs before that assignment, no program
						// behavior can observe an initial value. Do not construct a String
						// null sentinel or another default that final OCaml will discard.
						if (init != null || shouldBind) {
							final initExprRaw = init != null ? coerceLocalInitializer(v.id, v.t, init) : defaultValueForLocal(v.id, v.t, e.pos);
							final localType = localCarrierType(v.id, v.t, e.pos);
							final initExpr = (init == null || isNullInitializer(init)) ? OcamlExpr.EAnnot(initExprRaw, localType) : initExprRaw;

							if (!isMutable) {
								if (!shouldBind) {
									if (init != null) {
										wraps.push({
											kind: "seq",
											name: null,
											expr: OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [initExpr])
										});
									}
								} else {
									refLocals.remove(v.id);
									weakRefLocals.remove(v.id);
									objRefLocals.remove(v.id);
									wraps.push({kind: "let", name: renameVar(v.name), expr: initExpr});
								}
							} else {
								refLocals.set(v.id, true);
								weakRefLocals.set(v.id, (init == null || isNullInitializer(init)) && isFunctionType(v.t));
								final slotType = localType;
								final isObjSlot = switch (slotType) {
									case TIdent(name):
										name == "Obj.t";
									case _:
										false;
								}
								objRefLocals.set(v.id, isObjSlot);
								wraps.push({
									kind: "let",
									name: renameVar(v.name),
									expr: OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [initExpr])
								});
							}
						}

						if (isLast) {
							base = OcamlExpr.EConst(OcamlConst.CUnit);
							hasBase = true;
						}
					}

				case TBinop(OpAssign, lhs, rhs):
					switch (lhs.expr) {
						case TLocal(v) if (!isRefLocalId(v.id)):
							final rhsExpr = coerceLocalAssignment(v.id, v.t, rhs);
							final shouldBind = isLocalReadBeforeNextWrite(exprs, i + 1, v.id);
							if (isLast) {
								base = rhsExpr;
								hasBase = true;
							} else if (shouldBind) {
								wraps.push({kind: "let", name: renameVar(v.name), expr: rhsExpr});
							} else {
								wraps.push({kind: "seq", name: null, expr: OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [rhsExpr])});
							}
						case _:
							final current = buildExpr(e);
							if (isLast) {
								base = current;
								hasBase = true;
							} else {
								wraps.push({kind: "seq", name: null, expr: OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [current])});
							}
					}

				case TReturn(ret):
					// `return` terminates the block: ignore any following expressions.
					base = if (allowDirectReturn) {
						ret != null ? buildDirectFunctionResult(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
					} else if (currentControlPlan != null && currentControlPlan.returnFamilyAdmitted) {
						final decision = try {
							currentControlPlan.decisionFor(e);
						} catch (error:Dynamic) {
							return controlPlanInvariant(Std.string(error), e.pos);
						}
						if (decision == null)
							return controlPlanInvariant("an admitted exact-value early return reached block syntax without its sealed control decision", e.pos);
						buildPlannedReturn(decision, ret, e.pos);
					} else {
						controlPlanInvariant("a non-direct block return reached syntax without an admitted function-owned control plan", e.pos);
					}
					hasBase = true;
					break;

				case _:
					final current = buildExpr(e);
					if (isLast) {
						base = current;
						hasBase = true;
					} else {
						wraps.push({kind: "seq", name: null, expr: OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [current])});
					}
			}

			i += 1;
		}

		var out = hasBase ? base : OcamlExpr.EConst(OcamlConst.CUnit);
		var j = wraps.length - 1;
		while (j >= 0) {
			final w = wraps[j];
			out = switch (w.kind) {
				case "let":
					OcamlExpr.ELet(w.name, w.expr, out, false);
				case "seq":
					seq2(w.expr, out);
				case _:
					out;
			}
			j -= 1;
		}

		return out;
	}

	function buildFunctionBodyBlock(exprs:Array<TypedExpr>):OcamlExpr {
		#if macro
		final log = ctx.profileLogLine;
		final profClass = Context.definedValue("reflaxe_ocaml_telemetry_class");
		final profMatch = log != null
			&& Context.defined("reflaxe_ocaml_telemetry_detail")
			&& profClass != null
			&& ctx.currentTypeFullName != null
			&& ctx.currentTypeFullName == profClass;
		final t0 = profMatch ? haxe.Timer.stamp() : 0.0;
		#end
		final usedIds = collectUsedLocalIdsFromExprs(exprs);
		#if macro
		final t1 = profMatch ? haxe.Timer.stamp() : 0.0;
		#end
		final prevUsed = currentUsedLocalIds;
		currentUsedLocalIds = usedIds;
		#if macro
		if (profMatch)
			log("reflaxe.ocaml: builder_block_used dt_ms="
				+ Std.string(Std.int((t1 - t0) * 1000))
				+ " stmts="
				+ Std.string(exprs.length));
		final t2 = profMatch ? haxe.Timer.stamp() : 0.0;
		#end
		final result = buildBlockFromIndex(exprs, 0, true);
		#if macro
		final t3 = profMatch ? haxe.Timer.stamp() : 0.0;
		if (profMatch)
			log("reflaxe.ocaml: builder_block_build dt_ms="
				+ Std.string(Std.int((t3 - t2) * 1000))
				+ " stmts="
				+ Std.string(exprs.length));
		#end
		currentUsedLocalIds = prevUsed;
		return result;
	}

	/**
			Builds a direct source return against the function's declared Haxe result.
			An `IMap` result is more than an OCaml type annotation: a concrete map must
			be wrapped in the dispatch record that implements the Haxe interface. The
			function's sealed interface plan records that conversion, so it is applied
			here before the surrounding callable boundary validates the result carrier.
			Other fully admitted callables still apply their general result conversion
			around the complete body later. The fallback below retains the older exact
			nullable-primitive handling for functions outside that call matrix.
		**/
	function buildDirectFunctionResult(value:TypedExpr):OcamlExpr {
		final returnType = currentFunctionReturnType;
		if (returnType == null || isVoidType(returnType))
			return buildExpr(value);
		if (isExactIMapType(returnType) && !isExactIMapType(OcamlIMapInterfacePlanner.conversionSourceType(value)))
			return coerceForAssignment(returnType, value);
		if (currentCallableBoundary != null)
			return buildExpr(value);
		final valueNullableKind = nullablePrimitiveKind(value.t);
		if (valueNullableKind == "int" && isIntType(returnType)) {
			return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_int_unwrap"), [buildExpr(value)]);
		}
		if (valueNullableKind == "bool" && isBoolType(returnType)) {
			return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "nullable_bool_unwrap"), [buildExpr(value)]);
		}
		return buildExpr(value);
	}

	/**
			Builds one non-function expression after rechecking every validated plan.
			A non-function root is a typed initializer or other expression compiled
			outside a method body. It still needs the same anonymous-object, storage,
			and Bytes decisions as a function so syntax cannot silently choose a
			different representation.
		**/
	public function buildStandaloneExpr(expression:TypedExpr, localIdentities:LexicalLocalIdentityPlan, storagePlan:OcamlLocalStoragePlan,
			expressionPlan:OcamlSealedStandaloneExpressionPlan):OcamlExpr {
		final previousStoragePlan = currentLocalStoragePlan;
		final previousLocalIdentities = currentLocalIdentities;
		final previousContainerElementPlan = currentContainerElementPlan;
		final previousAnonymousStructurePlan = currentAnonymousStructurePlan;
		final previousStructuralFieldPlan = currentStructuralFieldPlan;
		final previousBytesAccessPlan = currentBytesAccessPlan;
		final previousBytesMutationPlan = currentBytesMutationPlan;
		final previousBytesProducerPlan = currentBytesProducerPlan;
		final previousBytesReadPlan = currentBytesReadPlan;
		final previousArrayReadPlan = currentArrayReadPlan;
		final previousArrayIteratorPlan = currentArrayIteratorPlan;
		final previousDynamicEqualityPlan = currentDynamicEqualityPlan;
		final previousDynamicStringPlan = currentDynamicStringPlan;
		final previousReflectComparePlan = currentReflectComparePlan;
		final previousReflectRuntimeUsePlan = currentReflectRuntimeUsePlan;
		final previousControlPlan = currentControlPlan;
		final previousFunctionPlanBinding = currentFunctionPlanBinding;
		final previousLoopTargetIds = currentLoopTargetIds;
		currentLocalStoragePlan = storagePlan;
		currentLocalIdentities = localIdentities;
		final validatedPlan = functionPlanRegistry.requireStandaloneExpressionPlan(expression, expressionPlan, representationRegistry);
		currentFunctionPlanBinding = validatedPlan.binding;
		currentContainerElementPlan = validatedPlan.containerElements;
		currentAnonymousStructurePlan = validatedPlan.anonymousStructures;
		currentStructuralFieldPlan = validatedPlan.structuralFields;
		currentBytesAccessPlan = validatedPlan.bytesAccesses;
		currentBytesMutationPlan = validatedPlan.bytesMutations;
		currentBytesProducerPlan = validatedPlan.bytesProducers;
		currentBytesReadPlan = validatedPlan.bytesReads;
		currentArrayReadPlan = validatedPlan.arrayReads;
		currentArrayIteratorPlan = validatedPlan.arrayIterators;
		currentDynamicEqualityPlan = validatedPlan.dynamicEquality;
		currentDynamicStringPlan = validatedPlan.dynamicString;
		currentReflectComparePlan = validatedPlan.reflectCompare;
		currentReflectRuntimeUsePlan = validatedPlan.reflectRuntimeUses;
		currentControlPlan = validatedPlan.controls;
		currentLoopTargetIds = [];
		final result = buildExpr(expression);
		currentLocalStoragePlan = previousStoragePlan;
		currentLocalIdentities = previousLocalIdentities;
		currentContainerElementPlan = previousContainerElementPlan;
		currentAnonymousStructurePlan = previousAnonymousStructurePlan;
		currentStructuralFieldPlan = previousStructuralFieldPlan;
		currentBytesAccessPlan = previousBytesAccessPlan;
		currentBytesMutationPlan = previousBytesMutationPlan;
		currentBytesProducerPlan = previousBytesProducerPlan;
		currentBytesReadPlan = previousBytesReadPlan;
		currentArrayReadPlan = previousArrayReadPlan;
		currentArrayIteratorPlan = previousArrayIteratorPlan;
		currentDynamicEqualityPlan = previousDynamicEqualityPlan;
		currentDynamicStringPlan = previousDynamicStringPlan;
		currentReflectComparePlan = previousReflectComparePlan;
		currentReflectRuntimeUsePlan = previousReflectRuntimeUsePlan;
		currentControlPlan = previousControlPlan;
		currentFunctionPlanBinding = previousFunctionPlanBinding;
		currentLoopTargetIds = previousLoopTargetIds;
		return result;
	}

	/**
			Applies the destination type conversion to one planned non-function value.
			The anonymous-object plan is installed while the right-hand side is built
			so a field access cannot fall back to the older syntax-time guess merely
			because it appears in a static initializer or another standalone root.
		**/
	public function buildStandaloneExprForAssignment(lhsType:Type, rhs:TypedExpr, localIdentities:LexicalLocalIdentityPlan, storagePlan:OcamlLocalStoragePlan,
			expressionPlan:OcamlSealedStandaloneExpressionPlan):OcamlExpr {
		final previousStoragePlan = currentLocalStoragePlan;
		final previousLocalIdentities = currentLocalIdentities;
		final previousContainerElementPlan = currentContainerElementPlan;
		final previousAnonymousStructurePlan = currentAnonymousStructurePlan;
		final previousStructuralFieldPlan = currentStructuralFieldPlan;
		final previousBytesAccessPlan = currentBytesAccessPlan;
		final previousBytesMutationPlan = currentBytesMutationPlan;
		final previousBytesProducerPlan = currentBytesProducerPlan;
		final previousBytesReadPlan = currentBytesReadPlan;
		final previousArrayReadPlan = currentArrayReadPlan;
		final previousArrayIteratorPlan = currentArrayIteratorPlan;
		final previousDynamicEqualityPlan = currentDynamicEqualityPlan;
		final previousDynamicStringPlan = currentDynamicStringPlan;
		final previousReflectComparePlan = currentReflectComparePlan;
		final previousReflectRuntimeUsePlan = currentReflectRuntimeUsePlan;
		final previousControlPlan = currentControlPlan;
		final previousFunctionPlanBinding = currentFunctionPlanBinding;
		final previousLoopTargetIds = currentLoopTargetIds;
		currentLocalStoragePlan = storagePlan;
		currentLocalIdentities = localIdentities;
		final validatedPlan = functionPlanRegistry.requireStandaloneExpressionPlan(rhs, expressionPlan, representationRegistry);
		currentFunctionPlanBinding = validatedPlan.binding;
		currentContainerElementPlan = validatedPlan.containerElements;
		currentAnonymousStructurePlan = validatedPlan.anonymousStructures;
		currentStructuralFieldPlan = validatedPlan.structuralFields;
		currentBytesAccessPlan = validatedPlan.bytesAccesses;
		currentBytesMutationPlan = validatedPlan.bytesMutations;
		currentBytesProducerPlan = validatedPlan.bytesProducers;
		currentBytesReadPlan = validatedPlan.bytesReads;
		currentArrayReadPlan = validatedPlan.arrayReads;
		currentArrayIteratorPlan = validatedPlan.arrayIterators;
		currentDynamicEqualityPlan = validatedPlan.dynamicEquality;
		currentDynamicStringPlan = validatedPlan.dynamicString;
		currentReflectComparePlan = validatedPlan.reflectCompare;
		currentReflectRuntimeUsePlan = validatedPlan.reflectRuntimeUses;
		currentControlPlan = validatedPlan.controls;
		currentLoopTargetIds = [];
		final result = coerceForAssignment(lhsType, rhs);
		currentLocalStoragePlan = previousStoragePlan;
		currentLocalIdentities = previousLocalIdentities;
		currentContainerElementPlan = previousContainerElementPlan;
		currentAnonymousStructurePlan = previousAnonymousStructurePlan;
		currentStructuralFieldPlan = previousStructuralFieldPlan;
		currentBytesAccessPlan = previousBytesAccessPlan;
		currentBytesMutationPlan = previousBytesMutationPlan;
		currentBytesProducerPlan = previousBytesProducerPlan;
		currentBytesReadPlan = previousBytesReadPlan;
		currentArrayReadPlan = previousArrayReadPlan;
		currentArrayIteratorPlan = previousArrayIteratorPlan;
		currentDynamicEqualityPlan = previousDynamicEqualityPlan;
		currentDynamicStringPlan = previousDynamicStringPlan;
		currentReflectComparePlan = previousReflectComparePlan;
		currentReflectRuntimeUsePlan = previousReflectRuntimeUsePlan;
		currentControlPlan = previousControlPlan;
		currentFunctionPlanBinding = previousFunctionPlanBinding;
		currentLoopTargetIds = previousLoopTargetIds;
		return result;
	}

	static function paramNameFromPattern(p:OcamlPat):Null<String> {
		return switch (p) {
			case PVar(name):
				name;
			case PAnnot(inner, _):
				paramNameFromPattern(inner);
			case _:
				null;
		}
	}

	static function exprMentionsIdent(expr:OcamlExpr, target:String):Bool {
		function any(list:Array<OcamlExpr>):Bool {
			for (item in list) {
				if (exprMentionsIdent(item, target))
					return true;
			}
			return false;
		}

		return switch (expr) {
			case EPos(_, inner):
				exprMentionsIdent(inner, target);
			case EConst(_):
				false;
			case ERawInjection(injection):
				var found = false;
				for (part in injection.segments()) {
					switch (part) {
						case RawText(_):
						case RawExpression(child):
							if (exprMentionsIdent(child, target)) {
								found = true;
								break;
							}
					}
				}
				found;
			case EIdent(name):
				name == target;
			case ERuntimeIdent(reference):
				reference.exactSymbol == target;
			case ELet(name, value, body, _): exprMentionsIdent(value, target) || (name != target && exprMentionsIdent(body, target));
			case EFun(params, body):
				var shadowed = false;
				for (param in params) {
					final paramName = paramNameFromPattern(param);
					if (paramName != null && paramName == target) {
						shadowed = true;
						break;
					}
				}
				shadowed ? false : exprMentionsIdent(body, target);
			case EApp(fn, args): exprMentionsIdent(fn, target) || any(args);
			case EAppArgs(fn, args): exprMentionsIdent(fn, target) || any(args.map(a -> a.expr));
			case EBinop(_, left, right): exprMentionsIdent(left, target) || exprMentionsIdent(right, target);
			case EUnop(_, inner):
				exprMentionsIdent(inner, target);
			case EIf(cond, thenExpr, elseExpr): exprMentionsIdent(cond, target) || exprMentionsIdent(thenExpr, target) || exprMentionsIdent(elseExpr, target);
			case EMatch(scrutinee, cases):
				if (exprMentionsIdent(scrutinee, target)) {
					true;
				} else {
					var found = false;
					for (c in cases) {
						if (exprMentionsIdent(c.expr, target)) {
							found = true;
							break;
						}
						if (c.guard != null && exprMentionsIdent(c.guard, target)) {
							found = true;
							break;
						}
					}
					found;
				}
			case ETry(body, cases):
				if (exprMentionsIdent(body, target)) {
					true;
				} else {
					var found = false;
					for (c in cases) {
						if (exprMentionsIdent(c.expr, target)) {
							found = true;
							break;
						}
						if (c.guard != null && exprMentionsIdent(c.guard, target)) {
							found = true;
							break;
						}
					}
					found;
				}
			case ESeq(exprs):
				any(exprs);
			case EWhile(cond, body): exprMentionsIdent(cond, target) || exprMentionsIdent(body, target);
			case EList(items):
				any(items);
			case ERecord(fields):
				any(fields.map(f -> f.value));
			case EField(owner, _):
				exprMentionsIdent(owner, target);
			case EAssign(_, lhs, rhs): exprMentionsIdent(lhs, target) || exprMentionsIdent(rhs, target);
			case ETuple(items):
				any(items);
			case EAnnot(inner, _):
				exprMentionsIdent(inner, target);
			case ERaise(exn):
				exprMentionsIdent(exn, target);
		}
	}

	static function ensureParamUsage(body:OcamlExpr, params:Array<OcamlPat>):OcamlExpr {
		var out = body;
		var index = params.length - 1;
		while (index >= 0) {
			final name = paramNameFromPattern(params[index]);
			if (name != null && name != "_" && !exprMentionsIdent(out, name)) {
				out = OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.EIdent(name)]), out]);
			}
			index -= 1;
		}
		return out;
	}

	public function buildFunctionFromArgsAndExpr(args:Array<{
		id:Int,
		name:String,
		t:Type,
		value:Null<TypedExpr>
	}>,
			bodyExpr:TypedExpr, functionPlan:OcamlSealedFunctionPlan, localIdentities:LexicalLocalIdentityPlan, ?expectedReturnType:Null<Type>):OcamlExpr {
		#if macro
		final log = ctx.profileLogLine;
		final profClass = Context.definedValue("reflaxe_ocaml_telemetry_class");
		final profMatch = log != null
			&& Context.defined("reflaxe_ocaml_telemetry_detail")
			&& profClass != null
			&& ctx.currentTypeFullName != null
			&& ctx.currentTypeFullName == profClass;
		final t0 = profMatch ? haxe.Timer.stamp() : 0.0;
		#end
		final storagePlan = functionPlan.localStorage;
		final localRepresentationPlan = functionPlan.localRepresentations;
		final previousFunctionPlanBinding = currentFunctionPlanBinding;
		final previousLocalPlanBinding = currentLocalPlanBinding;
		final previousPlacePlanBinding = currentPlacePlanBinding;
		final previousAnonymousStructurePlan = currentAnonymousStructurePlan;
		final previousStructuralFieldPlan = currentStructuralFieldPlan;
		final previousBytesAccessPlan = currentBytesAccessPlan;
		final previousBytesMutationPlan = currentBytesMutationPlan;
		final previousBytesProducerPlan = currentBytesProducerPlan;
		final previousBytesReadPlan = currentBytesReadPlan;
		final previousIMapInterfacePlan = currentIMapInterfacePlan;
		final previousCallPlan = currentCallPlan;
		final previousReflectComparePlan = currentReflectComparePlan;
		final previousReflectRuntimeUsePlan = currentReflectRuntimeUsePlan;
		final previousControlPlan = currentControlPlan;
		final previousArrayLiteralProducerPlan = currentArrayLiteralProducerPlan;
		final previousArrayReadPlan = currentArrayReadPlan;
		final previousArrayIteratorPlan = currentArrayIteratorPlan;
		final previousDynamicEqualityPlan = currentDynamicEqualityPlan;
		final previousDynamicStringPlan = currentDynamicStringPlan;
		final previousLoopTargetIds = currentLoopTargetIds;
		currentFunctionPlanBinding = functionPlan.binding;
		currentLocalPlanBinding = functionPlan.binding;
		currentPlacePlanBinding = functionPlan.binding;
		functionPlan.bytesAccesses.requireRepresentations(representationRegistry);
		functionPlan.bytesMutations.requireRepresentations(representationRegistry);
		functionPlan.bytesProducers.requireRepresentations(representationRegistry);
		functionPlan.bytesReads.requireRepresentations(representationRegistry);
		functionPlan.anonymousStructures.requireRepresentations(representationRegistry);
		functionPlan.arrayLiteralProducers.requireRepresentations(representationRegistry);
		functionPlan.imapInterfaces.requirePlanBinding(functionPlan.binding);
		currentAnonymousStructurePlan = functionPlan.anonymousStructures;
		currentStructuralFieldPlan = functionPlan.structuralFields;
		currentBytesAccessPlan = functionPlan.bytesAccesses;
		currentBytesMutationPlan = functionPlan.bytesMutations;
		currentBytesProducerPlan = functionPlan.bytesProducers;
		currentBytesReadPlan = functionPlan.bytesReads;
		currentIMapInterfacePlan = functionPlan.imapInterfaces;
		currentCallPlan = functionPlan.calls;
		currentReflectComparePlan = functionPlan.reflectCompare;
		currentReflectRuntimeUsePlan = functionPlan.reflectRuntimeUses;
		currentControlPlan = functionPlan.controls;
		currentArrayLiteralProducerPlan = functionPlan.arrayLiteralProducers;
		currentArrayReadPlan = functionPlan.arrayReads;
		currentArrayIteratorPlan = functionPlan.arrayIterators;
		currentDynamicEqualityPlan = functionPlan.dynamicEquality;
		currentDynamicStringPlan = functionPlan.dynamicString;
		currentLoopTargetIds = [];
		#if macro
		final t1 = profMatch ? haxe.Timer.stamp() : 0.0;
		if (profMatch)
			log("reflaxe.ocaml: builder_fn_plan_bind dt_ms=" + Std.string(Std.int((t1 - t0) * 1000)));
		#end

		final callableBoundary = functionPlan.callableBoundary;
		final functionResultBoundary = functionPlan.functionResultBoundary;
		// Instance-method return control remains deferred, but its existing callable
		// boundary may still own the ordinary completed result. Keep that old result
		// contract until a later slice gives instance returns their own checked
		// control admission; do not silently drop its conversion or type annotation.
		final completionBoundaryId:Null<String> = functionResultBoundary != null ? functionResultBoundary.id : (callableBoundary == null ? null : callableBoundary.id);
		final completionResultKind:Null<OcamlCallResultKind> = functionResultBoundary != null ? functionResultBoundary.resultKind : (callableBoundary == null ? null : callableBoundary.resultKind);
		final completionResult:Null<OcamlCallValuePlan> = functionResultBoundary != null ? functionResultBoundary.result : (callableBoundary == null ? null : callableBoundary.result);
		final previousCallableBoundary = currentCallableBoundary;
		currentCallableBoundary = callableBoundary;
		final params = if (callableBoundary == null) {
			args.length == 0 ? [OcamlPat.PConst(OcamlConst.CUnit)] : args.map(a -> OcamlPat.PVar(renameVar(a.name)));
		} else {
			if (args.length != callableBoundary.arguments.length) {
				return
					callPlanInvariant('callable boundary "${callableBoundary.id}" has ${callableBoundary.arguments.length} planned parameters but ${args.length} typed parameters',
					bodyExpr.pos);
			}
			for (index in 0...args.length)
				requireCallValue(callableBoundary.arguments[index], index, 'callable boundary "${callableBoundary.id}" argument $index', bodyExpr.pos);
			if (callableBoundary.result != null)
				requireCallValue(callableBoundary.result, -1, 'callable boundary "${callableBoundary.id}" result', bodyExpr.pos);
			args.length == 0 ? [OcamlPat.PConst(OcamlConst.CUnit)] : [
				for (index in 0...args.length)
					OcamlPat.PAnnot(OcamlPat.PVar(renameVar(args[index].name)), callableOutputType(callableBoundary.arguments[index], bodyExpr.pos))
			];
		}

		final previousStoragePlan = currentLocalStoragePlan;
		final previousLocalRepresentationPlan = currentLocalRepresentationPlan;
		final previousContainerElementPlan = currentContainerElementPlan;
		final previousLocalIdentities = currentLocalIdentities;
		currentLocalStoragePlan = storagePlan;
		currentLocalRepresentationPlan = localRepresentationPlan;
		currentContainerElementPlan = functionPlan.containerElements;
		currentLocalIdentities = localIdentities;
		for (a in args) {
			final stableId = stableLocalId(a.id, bodyExpr.pos);
			if (storagePlan.decisionFor(stableId) != null)
				localCarrierType(a.id, a.t, bodyExpr.pos);
			if (storagePlan.requiresRef(stableId)) {
				refLocals.set(a.id, true);
			}
		}

		#if macro
		final t2 = profMatch ? haxe.Timer.stamp() : 0.0;
		#end
		final needsReturnCatch = functionPlan.controls.hasReturnTransfers();
		#if macro
		final t3 = profMatch ? haxe.Timer.stamp() : 0.0;
		if (profMatch)
			log("reflaxe.ocaml: builder_fn_return_scan dt_ms=" + Std.string(Std.int((t3 - t2) * 1000)));
		final t4 = profMatch ? haxe.Timer.stamp() : 0.0;
		#end

		final resolvedReturnType:Type = expectedReturnType != null ? expectedReturnType : bodyExpr.t;
		final prevFunctionReturnType = currentFunctionReturnType;
		currentFunctionReturnType = resolvedReturnType;

		var body:OcamlExpr = switch (unwrap(bodyExpr).expr) {
			case TReturn(ret):
				ret != null ? buildDirectFunctionResult(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
			case TBlock(exprs):
				buildFunctionBodyBlock(exprs);
			case _:
				buildExpr(bodyExpr);
		}

		#if macro
		final t5 = profMatch ? haxe.Timer.stamp() : 0.0;
		if (profMatch)
			log("reflaxe.ocaml: builder_fn_body dt_ms=" + Std.string(Std.int((t5 - t4) * 1000)));
		#end

		var resultConvertedInsideControl = false;
		if (needsReturnCatch) {
			final returnVar = freshTmp("ret");
			final plannedReturn = functionPlan.controls.returnBoundaryDecision();
			if (plannedReturn == null)
				return controlPlanInvariant("an admitted return family requires a return catch but has no sealed return-boundary decision", bodyExpr.pos);
			final returnCase:OcamlMatchCase = switch (plannedReturn.mechanism) {
				case RuntimeVoidReturnSignal:
					{
						pat: buildAuthorizedReturnBoundaryPattern(plannedReturn, [], bodyExpr.pos),
						guard: null,
						expr: OcamlExpr.EConst(OcamlConst.CUnit)
					};
				case RuntimeReturnSignal:
					{
						pat: buildAuthorizedReturnBoundaryPattern(plannedReturn, [OcamlPat.PVar(returnVar)], bodyExpr.pos),
						guard: null,
						expr: buildPlannedReturnBoundary(plannedReturn, returnVar, bodyExpr.pos)
					};
				case _:
					return controlPlanInvariant('return decision "${plannedReturn.id}" selected unsupported boundary mechanism ${plannedReturn.mechanism}',
						bodyExpr.pos);
			}
			final fallbackBody = if (isVoidType(resolvedReturnType)) {
				exprAsStatement(body);
			} else {
				if (functionResultBoundary != null
					&& functionResultBoundary.result != null
					&& functionResultBoundary.result.conversion != OcamlCallCarrierConversion.Identity) {
					resultConvertedInsideControl = true;
					buildPlannedFunctionResult(functionResultBoundary.result, body, bodyExpr.pos);
				} else {
					body;
				}
			}
			body = OcamlExpr.ETry(fallbackBody, [returnCase]);
		}
		if (isVoidType(resolvedReturnType)) {
			if (completionBoundaryId != null && (completionResultKind != OcamlCallResultKind.EffectOnlyVoid || completionResult != null)) {
				return
					callPlanInvariant('function completion boundary "$completionBoundaryId" does not own the effect-only Void result selected by its typed function',
					bodyExpr.pos);
			}
			body = exprAsStatement(body);
		} else if (completionBoundaryId != null) {
			if (completionResultKind != OcamlCallResultKind.Value || completionResult == null)
				return
					callPlanInvariant('function completion boundary "$completionBoundaryId" has no represented result for its value-returning typed function',
						bodyExpr.pos);
			if (needsReturnCatch && completionResult.conversion != OcamlCallCarrierConversion.Identity && !resultConvertedInsideControl)
				return
					callPlanInvariant('function completion boundary "$completionBoundaryId" selected a straight-line result conversion for a body with nested return control',
					bodyExpr.pos);
			if (!resultConvertedInsideControl)
				body = buildPlannedFunctionResult(completionResult, body, bodyExpr.pos);
			body = OcamlExpr.EAnnot(body, callableOutputType(completionResult, bodyExpr.pos));
		}

		for (a in args) {
			if (storagePlan.requiresRef(stableLocalId(a.id, bodyExpr.pos))) {
				final n = renameVar(a.name);
				body = OcamlExpr.ELet(n, OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [OcamlExpr.EIdent(n)]), body, false);
			}
		}
		body = wrapFunctionArgDefaults(body, args.map(a -> ({name: a.name, t: a.t, value: a.value})));
		body = ensureParamUsage(body, params);

		currentLocalStoragePlan = previousStoragePlan;
		currentLocalRepresentationPlan = previousLocalRepresentationPlan;
		currentContainerElementPlan = previousContainerElementPlan;
		currentLocalIdentities = previousLocalIdentities;
		currentFunctionReturnType = prevFunctionReturnType;
		currentCallableBoundary = previousCallableBoundary;
		currentFunctionPlanBinding = previousFunctionPlanBinding;
		currentLocalPlanBinding = previousLocalPlanBinding;
		currentPlacePlanBinding = previousPlacePlanBinding;
		currentAnonymousStructurePlan = previousAnonymousStructurePlan;
		currentStructuralFieldPlan = previousStructuralFieldPlan;
		currentBytesAccessPlan = previousBytesAccessPlan;
		currentBytesMutationPlan = previousBytesMutationPlan;
		currentBytesProducerPlan = previousBytesProducerPlan;
		currentBytesReadPlan = previousBytesReadPlan;
		currentIMapInterfacePlan = previousIMapInterfacePlan;
		currentCallPlan = previousCallPlan;
		currentReflectComparePlan = previousReflectComparePlan;
		currentReflectRuntimeUsePlan = previousReflectRuntimeUsePlan;
		currentControlPlan = previousControlPlan;
		currentArrayLiteralProducerPlan = previousArrayLiteralProducerPlan;
		currentArrayReadPlan = previousArrayReadPlan;
		currentArrayIteratorPlan = previousArrayIteratorPlan;
		currentDynamicEqualityPlan = previousDynamicEqualityPlan;
		currentDynamicStringPlan = previousDynamicStringPlan;
		currentLoopTargetIds = previousLoopTargetIds;
		#if macro
		final t6 = profMatch ? haxe.Timer.stamp() : 0.0;
		if (profMatch)
			log("reflaxe.ocaml: builder_fn_total dt_ms=" + Std.string(Std.int((t6 - t0) * 1000)));
		#end
		return OcamlExpr.EFun(params, body);
	}

	/**
			Builds one function literal from its parent-approved planning disposition. For
			example, an admitted `Bool` closure with an early `return true` raises and
			recovers the already-selected Bool carrier without an unchecked fallback cast.
			A `null` plan is allowed only when the parent catalog explicitly records that
			this literal has an unsupported result or an incompletely represented return,
			loop, throw, or catch family.
			Syntax must not decide eligibility from the expression on its own.
		**/
	public function buildFunction(expression:TypedExpr, tfunc:haxe.macro.Type.TFunc):OcamlExpr {
		final storagePlan = currentLocalStoragePlan;
		if (storagePlan == null)
			return localStorageInvariant("a function expression reached syntax construction without a selected local-storage plan", tfunc.expr.pos);
		final parentBinding = currentFunctionPlanBinding;
		final nestedDisposition = parentBinding == null ? null : functionPlanRegistry.nestedFunctionSyntaxDispositionFor(expression, parentBinding);
		final nestedPlan:Null<OcamlSealedNestedFunctionPlan> = nestedDisposition == null ? null : nestedDisposition.plan;
		final callableBoundary = nestedPlan == null ? null : nestedPlan.callableBoundary;
		final functionResultBoundary = nestedPlan == null ? null : nestedPlan.functionResultBoundary;

		// Determine parameters and wrap mutated parameters as refs inside the body.
		if (callableBoundary != null) {
			if (tfunc.args.length != callableBoundary.arguments.length) {
				return
					callPlanInvariant('nested callable boundary "${callableBoundary.id}" has ${callableBoundary.arguments.length} planned parameters but ${tfunc.args.length} typed parameters',
					tfunc.expr.pos);
			}
			for (index in 0...tfunc.args.length)
				requireCallValue(callableBoundary.arguments[index], index, 'nested callable boundary "${callableBoundary.id}" argument $index', tfunc.expr.pos);
			if (callableBoundary.result != null)
				requireCallValue(callableBoundary.result, -1, 'nested callable boundary "${callableBoundary.id}" result', tfunc.expr.pos);
		}
		final params = if (callableBoundary == null) {
			tfunc.args.length == 0 ? [OcamlPat.PConst(OcamlConst.CUnit)] : tfunc.args.map(a -> OcamlPat.PVar(renameVar(a.v.name)));
		} else {
			tfunc.args.length == 0 ? [OcamlPat.PConst(OcamlConst.CUnit)] : [
				for (index in 0...tfunc.args.length)
					OcamlPat.PAnnot(OcamlPat.PVar(renameVar(tfunc.args[index].v.name)), callableOutputType(callableBoundary.arguments[index], tfunc.expr.pos))
			];
		};

		for (a in tfunc.args) {
			final stableId = stableLocalId(a.v.id, tfunc.expr.pos);
			if (storagePlan.decisionFor(stableId) != null)
				localCarrierType(a.v.id, a.v.t, tfunc.expr.pos);
			if (storagePlan.requiresRef(stableId)) {
				refLocals.set(a.v.id, true);
			}
		}

		final previousControlPlan = currentControlPlan;
		final previousArrayLiteralProducerPlan = currentArrayLiteralProducerPlan;
		final previousArrayReadPlan = currentArrayReadPlan;
		final previousArrayIteratorPlan = currentArrayIteratorPlan;
		final previousDynamicEqualityPlan = currentDynamicEqualityPlan;
		final previousDynamicStringPlan = currentDynamicStringPlan;
		final previousReflectRuntimeUsePlan = currentReflectRuntimeUsePlan;
		final previousIMapInterfacePlan = currentIMapInterfacePlan;
		final previousFunctionPlanBinding = currentFunctionPlanBinding;
		final previousLoopTargetIds = currentLoopTargetIds;
		currentControlPlan = nestedDisposition == null ? null : nestedDisposition.controls;
		currentArrayLiteralProducerPlan = nestedPlan == null ? null : nestedPlan.arrayLiteralProducers;
		// Array-read ownership is independent from the optional represented-return
		// plan. Every observed nested body has its own exact decisions, including
		// iterator closures that do not contain an early return.
		currentArrayReadPlan = nestedDisposition == null ? null : nestedDisposition.arrayReads;
		currentArrayIteratorPlan = nestedDisposition == null ? null : nestedDisposition.arrayIterators;
		currentDynamicEqualityPlan = nestedDisposition == null ? null : nestedDisposition.dynamicEquality;
		currentDynamicStringPlan = nestedDisposition == null ? null : nestedDisposition.dynamicString;
		currentReflectRuntimeUsePlan = nestedDisposition == null ? null : nestedDisposition.reflectRuntimeUses;
		if (nestedDisposition != null) {
			nestedDisposition.imapInterfaces.requirePlanBinding(nestedDisposition.binding);
			currentIMapInterfacePlan = nestedDisposition.imapInterfaces;
			currentFunctionPlanBinding = nestedDisposition.binding;
		} else {
			// A nested body without a planning disposition must not inherit the
			// enclosing function's occurrence-indexed IMap decisions.
			currentIMapInterfacePlan = null;
		}
		currentLoopTargetIds = [];
		final needsReturnCatch = nestedDisposition != null && nestedDisposition.controls.hasReturnTransfers();
		final functionReturnType:Type = switch (tfunc.t) {
			case TFun(_, ret): ret;
			case _: tfunc.t;
		};
		final prevFunctionReturnType = currentFunctionReturnType;
		final previousCallableBoundary = currentCallableBoundary;
		currentFunctionReturnType = functionReturnType;
		currentCallableBoundary = callableBoundary;

		var body:OcamlExpr = switch (unwrap(tfunc.expr).expr) {
			case TReturn(ret):
				ret != null ? buildDirectFunctionResult(ret) : OcamlExpr.EConst(OcamlConst.CUnit);
			case TBlock(exprs):
				buildFunctionBodyBlock(exprs);
			case _:
				buildExpr(tfunc.expr);
		}

		if (needsReturnCatch) {
			final returnVar = freshTmp("ret");
			final plannedReturn = nestedDisposition == null ? null : nestedDisposition.controls.returnBoundaryDecision();
			if (plannedReturn == null)
				return controlPlanInvariant("an admitted nested return plan has no sealed return-boundary decision", tfunc.expr.pos);
			final returnCase:OcamlMatchCase = switch (plannedReturn.mechanism) {
				case RuntimeVoidReturnSignal:
					{
						pat: buildAuthorizedReturnBoundaryPattern(plannedReturn, [], tfunc.expr.pos),
						guard: null,
						expr: OcamlExpr.EConst(OcamlConst.CUnit)
					};
				case RuntimeReturnSignal:
					{
						pat: buildAuthorizedReturnBoundaryPattern(plannedReturn, [OcamlPat.PVar(returnVar)], tfunc.expr.pos),
						guard: null,
						expr: buildPlannedReturnBoundary(plannedReturn, returnVar, tfunc.expr.pos)
					};
				case _:
					return
						controlPlanInvariant('nested return decision "${plannedReturn.id}" selected unsupported boundary mechanism ${plannedReturn.mechanism}',
							tfunc.expr.pos);
			}
			final fallbackBody = if (isVoidType(functionReturnType)) {
				exprAsStatement(body);
			} else {
				body;
			}
			body = OcamlExpr.ETry(fallbackBody, [returnCase]);
		}
		if (isVoidType(functionReturnType)) {
			body = exprAsStatement(body);
		} else if (functionResultBoundary != null) {
			if (functionResultBoundary.resultKind != OcamlCallResultKind.Value || functionResultBoundary.result == null)
				return
					callPlanInvariant('nested function result boundary "${functionResultBoundary.id}" has no represented result for its value-returning typed function',
					tfunc.expr.pos);
			body = buildPlannedFunctionResult(functionResultBoundary.result, body, tfunc.expr.pos);
			body = OcamlExpr.EAnnot(body, callableOutputType(functionResultBoundary.result, tfunc.expr.pos));
		}

		// Shadow mutated params as refs (`let x = ref x in ...`).
		for (a in tfunc.args) {
			if (storagePlan.requiresRef(stableLocalId(a.v.id, tfunc.expr.pos))) {
				final n = renameVar(a.v.name);
				body = OcamlExpr.ELet(n, OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [OcamlExpr.EIdent(n)]), body, false);
			}
		}
		body = wrapFunctionArgDefaults(body, tfunc.args.map(a -> {name: a.v.name, t: a.v.t, value: a.value}));
		body = ensureParamUsage(body, params);

		currentFunctionReturnType = prevFunctionReturnType;
		currentCallableBoundary = previousCallableBoundary;
		currentFunctionPlanBinding = previousFunctionPlanBinding;
		currentControlPlan = previousControlPlan;
		currentArrayLiteralProducerPlan = previousArrayLiteralProducerPlan;
		currentArrayReadPlan = previousArrayReadPlan;
		currentArrayIteratorPlan = previousArrayIteratorPlan;
		currentDynamicEqualityPlan = previousDynamicEqualityPlan;
		currentDynamicStringPlan = previousDynamicStringPlan;
		currentReflectRuntimeUsePlan = previousReflectRuntimeUsePlan;
		currentIMapInterfacePlan = previousIMapInterfacePlan;
		currentLoopTargetIds = previousLoopTargetIds;
		return OcamlExpr.EFun(params, body);
	}

	function collectUsedLocalIdsFromExprs(exprs:Array<TypedExpr>):Map<Int, Bool> {
		final used:Map<Int, Bool> = [];
		for (e in exprs)
			collectUsedLocalIdsInto(e, used);
		return used;
	}

	function collectUsedLocalIdsInto(e:TypedExpr, used:Map<Int, Bool>):Void {
		function visit(e:TypedExpr):Void {
			switch (e.expr) {
				case TLocal(v):
					used.set(v.id, true);
				case _:
			}
			TypedExprTools.iter(e, visit);
		}

		visit(e);
	}

	function collectUsedLocalIds(e:TypedExpr):Map<Int, Bool> {
		final used:Map<Int, Bool> = [];
		collectUsedLocalIdsInto(e, used);
		return used;
	}

	/**
		 * Returns true if the given local is *read* before it is *written* again in the suffix
		 * of the current straight-line block.
		 *
		 * Why:
		 * - The M14.5.1 "let-shadowing" optimization replaces `x := rhs` with `let x = rhs in ...`.
		 * - If `x` is never read before the next write, binding `let x = rhs` is a dead-store and
		 *   triggers OCaml's "unused var" warning (which is an error under dune's warn-error).
		 *
		 * How:
		 * - Scan forward:
		 *   - If we see a read of `id`, return true.
		 *   - If we see a write to `id` first, return false (this assignment's value will never be observed).
		 *   - If we reach the end, return false.
		 */
	static function isLocalReadBeforeNextWrite(exprs:Array<TypedExpr>, startIndex:Int, id:Int):Bool {
		for (i in startIndex...exprs.length) {
			final e = exprs[i];
			if (exprReadsLocalId(e, id))
				return true;
			if (exprWritesLocalId(e, id))
				return false;
		}
		return false;
	}

	static function exprWritesLocalId(e:TypedExpr, id:Int):Bool {
		function visit(e:TypedExpr):Bool {
			switch (e.expr) {
				case TBinop(OpAssign, lhs, _):
					switch (lhs.expr) {
						case TLocal(v) if (v.id == id):
							return true;
						case _:
					}
				case TBinop(OpAssignOp(_), lhs, _):
					switch (lhs.expr) {
						case TLocal(v) if (v.id == id):
							return true;
						case _:
					}
				case TUnop(OpIncrement, _, inner) | TUnop(OpDecrement, _, inner):
					switch (inner.expr) {
						case TLocal(v) if (v.id == id):
							return true;
						case _:
					}
				case _:
			}

			var found = false;
			TypedExprTools.iter(e, (x) -> {
				if (!found && visit(x))
					found = true;
			});
			return found;
		}

		return visit(e);
	}

	static function exprReadsLocalId(e:TypedExpr, id:Int):Bool {
		function visit(e:TypedExpr, writeOnly:Bool):Bool {
			switch (e.expr) {
				case TLocal(v) if (!writeOnly && v.id == id):
					return true;
				case TBinop(OpAssign, lhs, rhs):
					// LHS is write-only for simple assignment; RHS is read-context.
					if (visit(lhs, true))
						return true;
					if (visit(rhs, false))
						return true;
					return false;
				case _:
			}

			var found = false;
			TypedExprTools.iter(e, (x) -> {
				if (!found && visit(x, false))
					found = true;
			});
			return found;
		}

		return visit(e, false);
	}

	function buildSwitch(scrutinee:TypedExpr, cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>, edef:Null<TypedExpr>, switchType:Type):OcamlExpr {
		final wantUnit = isVoidType(switchType);

		inline function wrapCaseExpr(source:Null<TypedExpr>, expr:OcamlExpr):OcamlExpr {
			return wantUnit ? exprAsStatement(expr, source) : expr;
		}

		final defaultExpr:OcamlExpr = edef != null ? buildExpr(edef) : (wantUnit ? OcamlExpr.EConst(OcamlConst.CUnit) : OcamlExpr.EApp(OcamlExpr.EIdent("failwith"),
			[OcamlExpr.EConst(OcamlConst.CString("Non-exhaustive switch"))]));

		// Enum pattern matching: Haxe's pattern matcher often lowers enum switches to:
		// switch (TEnumIndex(e)) { case 0: ...; case 1: ... }
		// Reconstruct a direct OCaml match on the enum value.
		final scrutineeUnwrapped = unwrap(scrutinee);
		switch (scrutineeUnwrapped.expr) {
			case TEnumIndex(enumValueExpr):
				switch (enumValueExpr.t) {
					case TEnum(eRef, _):
						final enumType = eRef.get();
						final scrut = buildExpr(enumValueExpr);
						final arms:Array<OcamlMatchCase> = [];
						final isExhaustive = enumIndexSwitchIsExhaustive(enumType, cases);

						for (c in cases) {
							// Only support a single constructor index per case for now.
							final patRes = (c.values.length == 1) ? buildEnumIndexCasePat(enumType, c.values[0]) : null;
							final pat = patRes != null ? patRes.pat : OcamlPat.PAny;

							final prev = currentEnumParamNames;
							final prevScrut = currentEnumParamScrutineeLocalId;
							currentEnumParamNames = patRes != null ? patRes.enumParams : null;
							currentEnumParamScrutineeLocalId = patRes != null ? enumParamScrutineeLocalId(enumValueExpr) : null;
							final expr = wrapCaseExpr(c.expr, buildExpr(c.expr));
							currentEnumParamNames = prev;
							currentEnumParamScrutineeLocalId = prevScrut;

							arms.push({pat: pat, guard: null, expr: expr});
						}

						if (!isExhaustive) {
							arms.push({
								pat: OcamlPat.PAny,
								guard: null,
								expr: wrapCaseExpr(edef, defaultExpr)
							});
						}

						return OcamlExpr.EMatch(scrut, arms);
					case _:
				}
			case _:
		}

		final arms:Array<OcamlMatchCase> = [];
		inline function isAnyPat(p:OcamlPat):Bool {
			return switch (p) {
				case PAny:
					true;
				case _:
					false;
			}
		}
		var needsIfChain = false;
		for (c in cases) {
			for (v in c.values) {
				if (isAnyPat(buildSwitchValuePat(v))) {
					needsIfChain = true;
					break;
				}
			}
			if (needsIfChain) {
				break;
			}
		}
		if (needsIfChain) {
			inline function toDynamicObjExpr(t:Type, expr:OcamlExpr):OcamlExpr {
				final unwrapped = unwrapNullType(t);
				if (nullablePrimitiveKind(t) != null || isNullableEnumType(t) != null) {
					return expr;
				}
				return switch (followNoAbstracts(unwrapped)) {
					case TDynamic(_):
						expr;
					case TAbstract(_, _) if (isStdAnyAbstract(t)):
						expr;
					case TAnonymous(_) if (shouldAnonUseHxAnon(t)):
						expr;
					case _:
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [expr]);
				}
			}

			final scrutTmp = freshTmp("switch");
			final scrutVar = OcamlExpr.EIdent(scrutTmp);
			final scrutObj = toDynamicObjExpr(scrutinee.t, scrutVar);
			var chain = wrapCaseExpr(edef, defaultExpr);

			for (ci in 0...cases.length) {
				final c = cases[cases.length - 1 - ci];
				var cond:Null<OcamlExpr> = null;
				for (v in c.values) {
					final vu = unwrap(v);
					final thisCond = switch (vu.expr) {
						case TConst(TNull):
							OcamlExpr.EBinop(OcamlBinop.PhysEq, scrutObj, OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null"));
						case _:
							OcamlExpr.EApp(dynamicEqualityFunction(v, OcamlDynamicEqualityKind.SwitchCase), [scrutObj, toDynamicObjExpr(v.t, buildExpr(v))]);
					}
					cond = cond == null ? thisCond : OcamlExpr.EBinop(OcamlBinop.Or, cond, thisCond);
				}

				final caseExpr = wrapCaseExpr(c.expr, buildExpr(c.expr));
				chain = cond == null ? caseExpr : OcamlExpr.EIf(cond, caseExpr, chain);
			}

			return OcamlExpr.ELet(scrutTmp, buildExpr(scrutinee), chain, false);
		}
		for (c in cases) {
			// NOTE: For now, only support enum-parameter binding for a single pattern.
			final patRes = c.values.length == 1 ? buildSwitchValuePatAndEnumParams(c.values[0]) : null;
			final pat = if (patRes != null) {
				patRes.pat;
			} else {
				final pats = c.values.map(buildSwitchValuePat);
				pats.length == 1 ? pats[0] : OcamlPat.POr(pats);
			}

			final prev = currentEnumParamNames;
			final prevScrut = currentEnumParamScrutineeLocalId;
			currentEnumParamNames = patRes != null ? patRes.enumParams : null;
			currentEnumParamScrutineeLocalId = patRes != null ? enumParamScrutineeLocalId(scrutinee) : null;
			final expr = wrapCaseExpr(c.expr, buildExpr(c.expr));
			currentEnumParamNames = prev;
			currentEnumParamScrutineeLocalId = prevScrut;

			arms.push({pat: pat, guard: null, expr: expr});
		}
		arms.push({
			pat: OcamlPat.PAny,
			guard: null,
			expr: wrapCaseExpr(edef, defaultExpr)
		});

		// Nullable primitive switches (notably `Null<Int>` lowered by the compiler in
		// dynamic-target mode) frequently appear with integer constant patterns.
		//
		// We represent nullable primitives as `Obj.t`, so we must guard against `null`
		// before unboxing for an OCaml `match`.
		switch (nullablePrimitiveKind(scrutinee.t)) {
			case "int", "float", "bool":
				inline function isNullCaseValue(v:TypedExpr):Bool {
					return switch (unwrap(v).expr) {
						case TConst(TNull): true;
						case _: false;
					}
				}

				final tmp = freshTmp("switch");
				final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
				final defaultBranch = wrapCaseExpr(edef, defaultExpr);

				// Support `case null`: for nullable primitives the scrutinee is `Obj.t`, so
				// the `null` case must be handled *before* unboxing to a primitive.
				var firstNullCaseExpr:Null<OcamlExpr> = null;
				for (c in cases) {
					var hasNull = false;
					for (v in c.values) {
						if (isNullCaseValue(v)) {
							hasNull = true;
							break;
						}
					}
					if (hasNull) {
						firstNullCaseExpr = wrapCaseExpr(c.expr, buildExpr(c.expr));
						break;
					}
				}

				final nullBranch = firstNullCaseExpr != null ? firstNullCaseExpr : defaultBranch;

				// Rebuild match arms, excluding `null` literals (handled by the guard).
				final nonNullArms:Array<OcamlMatchCase> = [];
				for (c in cases) {
					final valuesNonNull = c.values.filter(v -> !isNullCaseValue(v));
					if (valuesNonNull.length == 0)
						continue;

					final patRes = valuesNonNull.length == 1 ? buildSwitchValuePatAndEnumParams(valuesNonNull[0]) : null;
					final pat = if (patRes != null) {
						patRes.pat;
					} else {
						final pats = valuesNonNull.map(buildSwitchValuePat);
						pats.length == 1 ? pats[0] : OcamlPat.POr(pats);
					}

					final prev = currentEnumParamNames;
					final prevScrut = currentEnumParamScrutineeLocalId;
					currentEnumParamNames = patRes != null ? patRes.enumParams : null;
					currentEnumParamScrutineeLocalId = patRes != null ? enumParamScrutineeLocalId(scrutinee) : null;
					final expr = wrapCaseExpr(c.expr, buildExpr(c.expr));
					currentEnumParamNames = prev;
					currentEnumParamScrutineeLocalId = prevScrut;

					nonNullArms.push({pat: pat, guard: null, expr: expr});
				}
				nonNullArms.push({pat: OcamlPat.PAny, guard: null, expr: defaultBranch});

				final unboxed = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)]);
				return OcamlExpr.ELet(tmp, buildExpr(scrutinee),
					OcamlExpr.EIf(OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull), nullBranch, OcamlExpr.EMatch(unboxed, nonNullArms)),
					false);
			case _:
		}

		return OcamlExpr.EMatch(buildExpr(scrutinee), arms);
	}

	function enumIndexSwitchIsExhaustive(enumType:EnumType, cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>):Bool {
		final allIndices:Map<Int, Bool> = [];
		for (name in enumType.names) {
			final ef = enumType.constructs.get(name);
			if (ef != null)
				allIndices.set(ef.index, true);
		}
		if (enumType.names.length == 0)
			return false;

		final covered:Map<Int, Bool> = [];
		for (c in cases) {
			for (v in c.values) {
				switch (v.expr) {
					case TConst(TInt(i)):
						covered.set(i, true);
					case _:
						return false;
				}
			}
		}

		for (idx in allIndices.keys()) {
			if (!(covered.exists(idx) && covered.get(idx) == true))
				return false;
		}
		return true;
	}

	function buildEnumIndexCasePat(enumType:EnumType, indexExpr:TypedExpr):Null<{pat:OcamlPat, enumParams:Map<String, String>}> {
		final idx:Null<Int> = switch (indexExpr.expr) {
			case TConst(TInt(v)): v;
			case _: null;
		}
		if (idx == null)
			return null;

		var field:Null<EnumField> = null;
		for (name in enumType.names) {
			final ef = enumType.constructs.get(name);
			if (ef != null && ef.index == idx) {
				field = ef;
				break;
			}
		}
		if (field == null)
			return null;

		final modName = moduleIdToOcamlModuleName(enumType.module);
		final isSameModule = ctx.currentModuleId != null && enumType.module == ctx.currentModuleId;
		final ctorName = if (isOcamlNativeEnumType(enumType, "Option") || isOcamlNativeEnumType(enumType, "Result")) {
			field.name;
		} else if (isOcamlNativeEnumType(enumType, "List")) {
			field.name == "Nil" ? "[]" : (field.name == "Cons" ? "::" : field.name);
		} else {
			isSameModule ? field.name : (modName + "." + field.name);
		}

		final argCount = switch (field.type) {
			case TFun(args, _): args.length;
			case _: 0;
		}

		final enumParams:Map<String, String> = [];
		final patArgs:Array<OcamlPat> = [];
		for (i in 0...argCount) {
			final n = "_p" + i;
			patArgs.push(OcamlPat.PVar(n));
			enumParams.set(field.name + ":" + i, n);
		}

		return {pat: OcamlPat.PConstructor(ctorName, patArgs), enumParams: enumParams};
	}

	function buildSwitchValuePat(v:TypedExpr):OcamlPat {
		return switch (v.expr) {
			case TConst(c):
				OcamlPat.PConst(buildConst(c));
			case TField(_, FEnum(eRef, ef)):
				final e = eRef.get();
				if (isOcamlNativeEnumType(e, "List") && ef.name == "Nil") {
					OcamlPat.PConstructor("[]", []);
				} else if (isOcamlNativeEnumType(e, "Option") || isOcamlNativeEnumType(e, "Result")) {
					OcamlPat.PConstructor(ef.name, []);
				} else {
					final isSameModule = ctx.currentModuleId != null && e.module == ctx.currentModuleId;
					final ctorName = isSameModule ? ef.name : (moduleIdToOcamlModuleName(e.module) + "." + ef.name);
					OcamlPat.PConstructor(ctorName, []);
				}
			case _:
				OcamlPat.PAny;
		}
	}

	function buildSwitchValuePatAndEnumParams(v:TypedExpr):{pat:OcamlPat, enumParams:Null<Map<String, String>>} {
		return switch (v.expr) {
			case TCall(fn, args):
				switch (fn.expr) {
					case TField(_, FEnum(eRef, ef)):
						final e = eRef.get();
						final ctorName = if (isOcamlNativeEnumType(e, "Option") || isOcamlNativeEnumType(e, "Result")) {
							ef.name;
						} else if (isOcamlNativeEnumType(e, "List") && ef.name == "Cons") {
							"::";
						} else {
							final isSameModule = ctx.currentModuleId != null && e.module == ctx.currentModuleId;
							isSameModule ? ef.name : (moduleIdToOcamlModuleName(e.module) + "." + ef.name);
						}

						final enumParams:Map<String, String> = [];
						final patArgs:Array<OcamlPat> = [];
						for (i in 0...args.length) {
							final a = args[i];
							switch (a.expr) {
								case TLocal(v):
									final n = renameVar(v.name);
									patArgs.push(OcamlPat.PVar(n));
									enumParams.set(ef.name + ":" + i, n);
								case TConst(c):
									patArgs.push(OcamlPat.PConst(buildConst(c)));
								case TIdent("_"):
									patArgs.push(OcamlPat.PAny);
								case _:
									patArgs.push(OcamlPat.PAny);
							}
						}
						{pat: OcamlPat.PConstructor(ctorName, patArgs), enumParams: enumParams};
					case _:
						{pat: buildSwitchValuePat(v), enumParams: null};
				}
			case _:
				{pat: buildSwitchValuePat(v), enumParams: null};
		}
	}

	/**
			Returns the sealed nominal payload type for one admitted direct receiver;
			only `this` in the owning monomorphic class and locals whose final function
			plan selected the same class decision are admitted. Every other receiver
			keeps the legacy compatibility path until its conversion owner exists.
		**/
	function plannedMonomorphicReceiverType(obj:TypedExpr, owner:ClassType, position:Position):Null<OcamlTypeExpr> {
		final layout = representationRegistry.monomorphicClassForType(obj.t);
		if (layout == null)
			return null;
		final ownerSemanticTypeId = (owner.pack ?? []).concat([owner.name]).join(".");
		if (layout.semanticTypeId != ownerSemanticTypeId)
			return null;
		final decision:Null<OcamlRepresentationDecision> = switch (unwrap(obj).expr) {
			case TConst(TThis) if (ctx.currentTypeFullName == layout.semanticTypeId):
				representationRegistry.monomorphicClassValue(layout.semanticTypeId);
			case TLocal(local):
				final localDecision = plannedLocalRepresentation(local.id, position);
				if (localDecision != null
					&& localDecision.semanticTypeId == layout.semanticTypeId
					&& OcamlMonomorphicClassMaterializer.isNominalClass(localDecision)) localDecision else null;
			case _:
				null;
		}
		if (decision == null || ctx.currentModuleId == null)
			return null;
		return OcamlMonomorphicClassMaterializer.typeExpr(decision, moduleIdToOcamlModuleName(ctx.currentModuleId));
	}

	function buildField(source:TypedExpr, obj:TypedExpr, fa:FieldAccess, pos:Position):OcamlExpr {
		return switch (fa) {
			case FEnum(eRef, ef):
				final e = eRef.get();
				if (isOcamlNativeEnumType(e, "Option") || isOcamlNativeEnumType(e, "Result")) {
					OcamlExpr.EIdent(ef.name);
				} else if (isOcamlNativeEnumType(e, "List")) {
					switch (ef.name) {
						case "Nil": OcamlExpr.EList([]);
						case "Cons": OcamlExpr.EIdent("::");
						case _: OcamlExpr.EConst(OcamlConst.CUnit);
					}
				} else {
					final isSameModule = ctx.currentModuleId != null && e.module == ctx.currentModuleId;
					if (isSameModule) {
						OcamlExpr.EIdent(ef.name);
					} else {
						final modName = moduleIdToOcamlModuleName(e.module);
						OcamlExpr.EField(OcamlExpr.EIdent(modName), ef.name);
					}
				}
			case FStatic(clsRef, cfRef):
				final cls = clsRef.get();
				final cf = cfRef.get();
				if (isStdStringClass(cls) && cf.name == "fromCharCode") {
					return OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "fromCharCode");
				}
				#if macro
				if (!ctx.currentIsHaxeStd && cls.pack != null && cls.pack.length == 0 && cls.name == "Type") {
					guardrailError("reflaxe.ocaml (M5): Haxe reflection is not supported yet (Type."
						+ cfRef.get().name
						+ "). "
						+ "Avoid Type for now, or add an OCaml extern and call native APIs. (bd: haxe.ocaml-eli)",
						pos);
				}
				#end
				final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);

				// Extern OCaml interop: allow `@:native("PMap") extern class PMap { ... }` to map
				// to the actual OCaml module path, and allow `@:native("add")` (or a full
				// `@:native("ExtLib.PMap.add")`) on the field to map to the native identifier.
				//
				// This is intentionally conservative for now: we only apply @:native mapping for extern classes.
				// (bd: haxe.ocaml-28t.8.1)
				if (cls.isExtern) {
					final nativeClassPath = extractNativeString(cls.meta);
					final nativeFieldPath = extractNativeString(cf.meta);

					// OCaml-native functor instantiations (M12): if user code references our
					// defunctorized `Map`/`Set` modules (emitted as standalone `.ml` files),
					// record that so `OcamlCompiler.onOutputComplete()` can emit them.
					if (nativeClassPath != null) {
						switch (nativeClassPath) {
							case "OcamlNativeStringMap", "OcamlNativeIntMap", "OcamlNativeStringSet", "OcamlNativeIntSet":
								ctx.needsOcamlNativeMapSet = true;
							case _:
						}
					}

					final resolved = resolveNativeStaticPath(moduleIdToOcamlModuleName(cls.module), cf.name, nativeClassPath, nativeFieldPath);
					OcamlNativeRuntimeBoundary.recordUsedExternCallable(ctx, cls, cf, resolved.modulePath + "." + resolved.fieldName);

					return OcamlExpr.EField(resolved.moduleExpr, resolved.fieldName);
				} else {
					final modName = moduleIdToOcamlModuleName(cls.module);
					final isMutableStatic = switch (cf.kind) {
						case FVar(_, _): !cf.isFinal;
						case FMethod(MethDynamic): true;
						case _: false;
					}
					final storage = isMutableStatic ? requireStaticStorage(cls, cf, pos) : null;
					final scoped = storage == null ? ctx.scopedValueName(cls.module, cls.name, cf.name) : storage.targetValueName;
					final baseExpr = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(scoped) : OcamlExpr.EField(OcamlExpr.EIdent(modName), scoped);
					return isMutableStatic ? OcamlExpr.EUnop(OcamlUnop.Deref, baseExpr) : baseExpr;
				}
			case FInstance(clsRef, _, cfRef):
				final cls = clsRef.get();
				final cf = cfRef.get();
				final instanceFieldName = ctx.ocamlRecordLabel(cf.name);
				switch (cf.kind) {
					case FVar(_, _):
						if (isStdArrayClass(cls) && cf.name == "length") {
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "length"), [buildExpr(obj)]);
						} else if (isStdStringClass(cls) && cf.name == "length") {
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "length"), [buildExpr(obj)]);
						} else if (isStdBytesClass(cls) && cf.name == "length") {
							bytesReadInvariant("standard Bytes length bypassed its sealed read plan", pos);
						} else if (cls.pack != null && cls.pack.length == 2 && cls.pack[0] == "haxe" && cls.pack[1] == "_Int64" && cls.name == "___Int64"
							&& (cf.name == "low" || cf.name == "high")) {
							// OCaml record-label resolution gotcha:
							// - `haxe.Int64` aggressively inlines accessors to direct `this.low/this.high` field reads.
							// - Without a type annotation, `ocamlc` resolves record labels globally and can fail with
							//   "Unbound record field low/high" if it cannot infer the record type yet (or if dune
							//   orders compilation before `Haxe_Int64`).
							//
							// Fix: annotate the receiver expression with the concrete record type so `ocamlc` can
							// resolve the label deterministically.
							final modName = moduleIdToOcamlModuleName(cls.module);
							final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
							final scopedType = ctx.scopedInstanceTypeName(cls.module, cls.name);
							final fullType = (selfMod != null && selfMod == modName) ? scopedType : (modName + "." + scopedType);
							final coerced = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(obj)]);
							OcamlExpr.EField(OcamlExpr.EAnnot(coerced, OcamlTypeExpr.TIdent(fullType)), instanceFieldName);
						} else {
							final plannedReceiverType = plannedMonomorphicReceiverType(obj, cls, pos);
							if (plannedReceiverType != null) {
								OcamlExpr.EField(OcamlExpr.EAnnot(buildExpr(obj), plannedReceiverType), instanceFieldName);
							} else {
								final modName = moduleIdToOcamlModuleName(cls.module);
								final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
								final scopedType = ctx.scopedInstanceTypeName(cls.module, cls.name);
								final fullType = (selfMod != null && selfMod == modName) ? scopedType : (modName + "." + scopedType);
								final coerced = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [buildExpr(obj)]);
								OcamlExpr.EField(OcamlExpr.EAnnot(coerced, OcamlTypeExpr.TIdent(fullType)), instanceFieldName);
							}
						}
					case FMethod(_):
						// Array iterator bring-up: allow `arr.iterator` to be used as a value when
						// arrays are coerced into `Iterable<T>` structural types (e.g. `Lambda.has(arr, x)`).
						// Upstream expects this to be a `Void -> Iterator<T>` closure.
						if (isStdArrayClass(cls) && cf.name == "iterator") {
							final recvTmp = freshTmp("arr");
							OcamlExpr.ELet(recvTmp, buildExpr(obj),
								OcamlExpr.EFun([OcamlPat.PConst(OcamlConst.CUnit)], ocamlStandardArrayIterator(source, OcamlExpr.EIdent(recvTmp))), false);
						} else {
							buildBoundMethodClosure(obj, cls, cf, pos);
						}
					case _:
						// Methods/properties are handled at callsites; as values, we only support real methods for now.
						OcamlExpr.EConst(OcamlConst.CUnit);
				}
			case FClosure(c, cfRef):
				final cf = cfRef.get();
				final owner:Null<ClassType> = c != null ? c.c.get() : classTypeFromType(obj.t);
				if (owner == null) {
					// Structural typing can produce method closures where the compiler does not provide an
					// "owner class" (e.g. `typedef A = { function foo():Int; }` and `function f(a:A) a.foo`).
					//
					// In portable mode we represent most anonymous structures as `HxAnon` (`Obj.t`), so in
					// that case we can lower to a dynamic field read and cast the stored closure back.
					//
					// Note: this relies on callsites coercing class instances into `HxAnon` when assigned
					// to such structural types (see `coerceForAssignment`).
					if (isDynamicLike(obj.t) || (switch (followNoAbstracts(unwrapNullType(obj.t))) {
						case TAnonymous(_) if (shouldAnonUseHxAnon(obj.t)): true;
						case _: false;
					})) {
						final recv = buildExpr(obj);
						final asObj = (isDynamicLike(obj.t) || nullablePrimitiveKind(obj.t) != null) ? recv : OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"),
							"repr"), [recv]);
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
							OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "get"), [asObj, OcamlExpr.EConst(OcamlConst.CString(cf.name))])
						]);
					} else {
						#if macro
						guardrailError("reflaxe.ocaml (M10): unsupported method-closure without owner class metadata ('" + cf.name + "').", pos);
						#end
						OcamlExpr.EConst(OcamlConst.CUnit);
					}
				} else if (isStdArrayClass(owner) && cf.name == "iterator") {
					final recvTmp = freshTmp("arr");
					OcamlExpr.ELet(recvTmp, buildExpr(obj),
						OcamlExpr.EFun([OcamlPat.PConst(OcamlConst.CUnit)], ocamlStandardArrayIterator(source, OcamlExpr.EIdent(recvTmp))), false);
				} else {
					buildBoundMethodClosure(obj, owner, cf, pos);
				}
			case FDynamic(name):
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "get"), [
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [buildExpr(obj)]),
						OcamlExpr.EConst(OcamlConst.CString(name))
					])
				]);
			case FAnon(cfRef):
				// `key`, `value`, `next`, and `hasNext` can mean either ordinary object
				// fields or target protocol operations. Their typed structural-field plan
				// must choose that behavior before this general field renderer runs.
				final cf = cfRef.get();
				switch (cf.name) {
					case "key", "value", "hasNext", "next":
						structuralFieldInvariant('read from overlapping structural field "${cf.name}" reached syntax without its typed owner', pos);
					case _:
						// Some typedef-backed anonymous structures are represented as real OCaml records
						// for better performance/ergonomics (e.g. `sys.FileStat`).
						// For those, anonymous-field access should lower to record field access.
						if (isSysFileStatTypedef(obj.t) || isSysFileStatAnon(obj.t)) {
							OcamlExpr.EField(buildExpr(obj), cf.name);
						} else {
							final fieldObj = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxAnon"), "get"),
								[buildExpr(obj), OcamlExpr.EConst(OcamlConst.CString(cf.name))]);
							if (isBoolType(cf.type)) {
								OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [fieldObj]);
							} else {
								final nullableEnumName = isNullableEnumType(cf.type);
								final enumName = nullableEnumName != null ? nullableEnumName : fullNameOfTypeEnum(cf.type);
								if (enumName != null) {
									final unboxed = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxEnum"), "unbox_or_obj"),
										[OcamlExpr.EConst(OcamlConst.CString(enumName)), fieldObj]);
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [unboxed]);
								} else {
									OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [fieldObj]);
								}
							}
						}
				}
			case _:
				// For now, treat unknown field access as unit.
				OcamlExpr.EConst(OcamlConst.CUnit);
		}
	}

	/**
		 * Build a bound-closure value for an instance method access (`obj.method`).
		 *
		 * Why:
		 * - In Haxe, taking an instance method as a value produces a closure which captures
		 *   the receiver (`this`) and can be called later: `var f = obj.foo; f(1);`.
		 * - In OCaml, our generated instance methods are top-level functions that take an
		 *   explicit receiver parameter (and, for 0-arg methods, an extra `unit` arg).
		 * - For interface/virtual dispatch (M10), the receiver may be a “dispatch record”
		 *   that stores method fields; the call must go through that record field to
		 *   preserve dynamic dispatch semantics.
		 *
		 * What this returns:
		 * - An OCaml `fun ... -> ...` that evaluates the receiver once and forwards calls
		 *   to the appropriate implementation (`Module.foo recv ...` or `recv.foo (Obj.magic recv) ...`).
		 *
		 * Notes:
		 * - This does not currently implement bound-closures for stdlib “magic” methods
		 *   (e.g. `Array.push` lowered to `HxArray.push`). If upstream suites rely on that,
		 *   add explicit mappings. (bd: haxe.ocaml-d3c)
		 */
	function buildBoundMethodClosure(objExpr:TypedExpr, cls:ClassType, cf:ClassField, pos:Position):OcamlExpr {
		final expectedArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (cf.type) {
			case TFun(fargs, _): fargs;
			case _: null;
		}
		final argCount = expectedArgs != null ? expectedArgs.length : 0;

		final paramNames:Array<String> = [];
		final params:Array<OcamlPat> = argCount == 0 ? [OcamlPat.PConst(OcamlConst.CUnit)] : {
			final out:Array<OcamlPat> = [];
			for (i in 0...argCount) {
				final n = "a" + Std.string(i);
				paramNames.push(n);
				out.push(OcamlPat.PVar(n));
			}
			out;
		};

		final recvExpr = buildExpr(objExpr);
		final tmpName = switch (recvExpr) {
			case EIdent(_): null;
			case _: freshTmp("obj");
		}
		final recvVar = tmpName == null ? recvExpr : OcamlExpr.EIdent(tmpName);

		final argExprs:Array<OcamlExpr> = [];
		for (n in paramNames)
			argExprs.push(OcamlExpr.EIdent(n));

		final unwrappedObj = unwrap(objExpr);
		final isSuperReceiver = switch (unwrappedObj.expr) {
			case TConst(TSuper): true;
			case _: false;
		}

		final recvFullName = classFullNameFromType(objExpr.t);
		final isDispatchRecv = recvFullName != null && (ctx.dispatchTypes.exists(recvFullName) || ctx.interfaceTypes.exists(recvFullName));
		final allowSuperCall = ctx.currentTypeFullName != null && ctx.dispatchTypes.exists(ctx.currentTypeFullName);

		final call:OcamlExpr = if (isSuperReceiver && allowSuperCall) {
			// `super.foo` as a value: bind to the base implementation (no virtual dispatch).
			final modName = moduleIdToOcamlModuleName(cls.module);
			final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
			final implName = ctx.scopedValueName(cls.module, cls.name, cf.name + "__impl");
			final callFn = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(implName) : OcamlExpr.EField(OcamlExpr.EIdent(modName), implName);

			final callArgs = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent("self")])].concat(argExprs);
			if (argCount == 0)
				callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
			OcamlExpr.EApp(callFn, callArgs);
		} else if (isDispatchRecv) {
			final methodField = OcamlExpr.EField(recvVar, ctx.ocamlRecordLabel(cf.name));
			final callArgs = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [recvVar])].concat(argExprs);
			if (argCount == 0)
				callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
			OcamlExpr.EApp(methodField, callArgs);
		} else {
			final modName = moduleIdToOcamlModuleName(cls.module);
			final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
			final scoped = ctx.scopedValueName(cls.module, cls.name, cf.name);
			final callFn = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(scoped) : OcamlExpr.EField(OcamlExpr.EIdent(modName), scoped);

			final callArgs = [recvVar].concat(argExprs);
			if (argCount == 0)
				callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
			OcamlExpr.EApp(callFn, callArgs);
		}

		final body = tmpName == null ? call : OcamlExpr.ELet(tmpName, recvExpr, call, false);
		return OcamlExpr.EFun(params, body);
	}

	/**
		 * Builds a bound method closure when the receiver is already available as an OCaml expression.
		 *
		 * Why:
		 * - Some coercions (notably class -> structural anonymous `HxAnon`) must evaluate the receiver once,
		 *   bind it to a temporary, and then build multiple closures that capture that receiver.
		 * - The regular `buildBoundMethodClosure` takes a `TypedExpr` receiver and will re-emit `buildExpr`
		 *   (which would duplicate side effects for expressions like `new C()`).
		 */
	function buildBoundMethodClosureFromReceiverVar(source:TypedExpr, recvVar:OcamlExpr, recvType:Type, cls:ClassType, cf:ClassField, pos:Position):OcamlExpr {
		final expectedArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (cf.type) {
			case TFun(fargs, _): fargs;
			case _: null;
		}
		final argCount = expectedArgs != null ? expectedArgs.length : 0;

		// Array iterator bring-up: structural coercions (`Array<T>` -> `Iterable<T>`) need a
		// bound `Void -> Iterator<T>` closure. Our regular bound-closure builder would call
		// the generated `Array.iterator recv ()`, but `Array` is not a real OCaml module.
		// Use the runtime iterator representation instead.
		if (isStdArrayClass(cls) && cf.name == "iterator" && argCount == 0) {
			return OcamlExpr.EFun([OcamlPat.PConst(OcamlConst.CUnit)], ocamlIteratorOfArray(source, recvVar));
		}

		final paramNames:Array<String> = [];
		final params:Array<OcamlPat> = argCount == 0 ? [OcamlPat.PConst(OcamlConst.CUnit)] : {
			final out:Array<OcamlPat> = [];
			for (i in 0...argCount) {
				final n = "a" + Std.string(i);
				paramNames.push(n);
				out.push(OcamlPat.PVar(n));
			}
			out;
		};

		final argExprs:Array<OcamlExpr> = [];
		for (n in paramNames)
			argExprs.push(OcamlExpr.EIdent(n));

		final recvFullName = classFullNameFromType(recvType);
		final isDispatchRecv = recvFullName != null && (ctx.dispatchTypes.exists(recvFullName) || ctx.interfaceTypes.exists(recvFullName));

		final call:OcamlExpr = if (isDispatchRecv) {
			final methodField = OcamlExpr.EField(recvVar, ctx.ocamlRecordLabel(cf.name));
			final callArgs = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [recvVar])].concat(argExprs);
			if (argCount == 0)
				callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
			OcamlExpr.EApp(methodField, callArgs);
		} else {
			final modName = moduleIdToOcamlModuleName(cls.module);
			final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
			final scoped = ctx.scopedValueName(cls.module, cls.name, cf.name);
			final callFn = (selfMod != null && selfMod == modName) ? OcamlExpr.EIdent(scoped) : OcamlExpr.EField(OcamlExpr.EIdent(modName), scoped);

			final callArgs = [recvVar].concat(argExprs);
			if (argCount == 0)
				callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
			OcamlExpr.EApp(callFn, callArgs);
		}

		return OcamlExpr.EFun(params, call);
	}

	inline function moduleIdToOcamlModuleName(moduleId:String):String {
		return ctx.ocamlModuleNameForModuleId(moduleId);
	}

	static function classFullNameFromType(t:Type):Null<String> {
		return switch (TypeTools.follow(t)) {
			case TInst(cRef, _):
				final c = cRef.get();
				(c.pack ?? []).concat([c.name]).join(".");
			case _:
				null;
		}
	}

	/** Returns whether a type is the exact upstream `haxe.Constraints.IMap<K,V>` interface. */
	static function isExactIMapType(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TInst(classRef, parameters): parameters.length == 2 && OcamlStandardIMapCallContract.isIMapClass(classRef.get());
			case _:
				false;
		};
	}

	/** Returns whether an expression is a method call on that exact interface declaration. */
	static function isExactIMapInterfaceCall(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TCall({expr: TField(_, FInstance(classRef, parameters, fieldRef))}, arguments): OcamlStandardIMapCallContract.isIMapClass(classRef.get()) && parameters.length == 2 && OcamlStandardIMapCallContract.operationFor(fieldRef.get()
					.name, arguments.length) != null;
			case _:
				false;
		};
	}

	static function classTypeFromType(t:Type):Null<ClassType> {
		return switch (TypeTools.follow(t)) {
			case TInst(cRef, _):
				cRef.get();
			case _:
				null;
		}
	}

	static function isSubclassOf(child:ClassType, parent:ClassType):Bool {
		inline function fullNameOf(c:ClassType):String
			return (c.pack ?? []).concat([c.name]).join(".");
		final parentName = fullNameOf(parent);

		var cur:Null<ClassType> = child;
		var guard = 0;
		while (cur != null && guard++ < 64) {
			if (fullNameOf(cur) == parentName)
				return true;
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}
		return false;
	}

	static function implementsInterface(child:ClassType, iface:ClassType):Bool {
		inline function fullNameOf(c:ClassType):String
			return (c.pack ?? []).concat([c.name]).join(".");
		final ifaceName = fullNameOf(iface);

		final seen:Map<String, Bool> = [];
		function ifaceMatchesOrExtends(i:ClassType):Bool {
			final n = fullNameOf(i);
			if (seen.exists(n))
				return false;
			seen.set(n, true);
			if (n == ifaceName)
				return true;
			if (i.interfaces != null) {
				for (x in i.interfaces) {
					final it = x.t.get();
					if (ifaceMatchesOrExtends(it))
						return true;
				}
			}
			return false;
		}

		var cur:Null<ClassType> = child;
		var guard = 0;
		while (cur != null && guard++ < 64) {
			if (cur.interfaces != null) {
				for (x in cur.interfaces) {
					final it = x.t.get();
					if (ifaceMatchesOrExtends(it))
						return true;
				}
			}
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}
		return false;
	}

	/**
		 		 * Extracts the string argument from a `@:native("...")` metadata entry, if present.
		 *
		 * Why:
		 * - Haxe uses `@:native` for target name mapping.
		 * - For the OCaml backend, this is especially important for **extern interop**: Haxe names
		 *   should map onto existing OCaml module paths / values.
		 *
		 * What:
		 * - Returns the raw string given to `@:native`, or `null` if absent/invalid.
		 *
		 * How:
		 * - Only supports constant-string params for now (non-string params are ignored).
		 */
	static function extractNativeString(meta:MetaAccess):Null<String> {
		for (m in meta.get()) {
			if (m.name != ":native")
				continue;
			if (m.params == null || m.params.length == 0)
				continue;
			return switch (m.params[0].expr) {
				case EConst(CString(s)): s;
				case _: null;
			}
		}
		return null;
	}

	static function buildOcamlModulePathExpr(path:String):Null<OcamlExpr> {
		if (path == null)
			return null;
		final parts = path.split(".").filter(p -> p != null && p.length > 0);
		if (parts.length == 0)
			return null;
		var expr:OcamlExpr = OcamlExpr.EIdent(parts[0]);
		for (i in 1...parts.length) {
			expr = OcamlExpr.EField(expr, parts[i]);
		}
		return expr;
	}

	/**
		 * Resolves an extern static callsite path from `@:native` metadata.
		 *
		 * Rules:
		 * - `nativeFieldPath` may be:
		 *   - `foo` (rename only) -> `<module>.<foo>`
		 *   - `A.B.foo` (full path) -> `A.B.foo` (overrides module too)
		 * - If `nativeFieldPath` doesn't specify a module, `nativeClassPath` (module) is used.
		 * - If no native metadata exists, falls back to `<defaultModuleName>.<defaultFieldName>`.
		 */
	static function resolveNativeStaticPath(defaultModuleName:String, defaultFieldName:String, nativeClassPath:Null<String>,
			nativeFieldPath:Null<String>):{moduleExpr:OcamlExpr, modulePath:String, fieldName:String} {
		var modulePath:Null<String> = nativeClassPath;
		var fieldName:String = defaultFieldName;

		if (nativeFieldPath != null) {
			final parts = nativeFieldPath.split(".").filter(p -> p != null && p.length > 0);
			if (parts.length >= 2) {
				fieldName = parts[parts.length - 1];
				modulePath = parts.slice(0, parts.length - 1).join(".");
			} else if (parts.length == 1) {
				fieldName = parts[0];
			}
		}

		final resolvedModulePath = modulePath != null ? modulePath : defaultModuleName;
		final moduleExpr = if (modulePath != null) {
			final expr = buildOcamlModulePathExpr(resolvedModulePath);
			expr == null ? OcamlExpr.EIdent(defaultModuleName) : expr;
		} else {
			OcamlExpr.EIdent(defaultModuleName);
		}

		return {moduleExpr: moduleExpr, modulePath: resolvedModulePath, fieldName: fieldName};
	}

	/**
		 * Extract per-parameter `@:ocamlLabel("...")` metadata for a class field.
		 *
		 * Why:
		 * - Haxe doesn't have labelled arguments, but OCaml does. For extern interop we need a way
		 *   to map positional Haxe arguments to labelled OCaml callsites.
		 *
		 * How:
		 * - Haxe stores argument metadata in a synthetic `:haxe.arguments` entry on the field's meta.
		 *   We parse that AST and build a map from parameter name → label string.
		 *
		 * Returns:
		 * - `null` if no relevant metadata exists.
		 * - Otherwise, a map from argument name to OCaml label string.
		 */
	static function extractOcamlLabelByArgName(field:ClassField):Null<Map<String, String>> {
		final meta = field.meta.get();
		var out:Null<Map<String, String>> = null;

		for (m in meta) {
			if (m.name != ":haxe.arguments")
				continue;
			if (m.params == null || m.params.length == 0)
				continue;

			switch (m.params[0].expr) {
				case EFunction(_, f):
					for (a in f.args) {
						if (a.meta == null)
							continue;
						for (am in a.meta) {
							if (am.name != ":ocamlLabel")
								continue;
							if (am.params == null || am.params.length != 1)
								continue;
							final label = switch (am.params[0].expr) {
								case EConst(CString(s)): s;
								case _: null;
							}
							if (label == null)
								continue;
							if (out == null)
								out = [];
							out.set(a.name, label);
						}
					}
				case _:
			}
		}

		return out;
	}

	/**
		 * Builds the value passed to an OCaml **optional labelled argument** (`?label:`) at a callsite.
		 *
		 * Why:
		 * - OCaml optional labelled parameters have type `'a option`.
		 * - For extern interop we want Haxe callsites to feel natural, so we allow passing:
		 *   - an actual value (`Some v`)
		 *   - `null` as "omit" (`None`)
		 * - reflaxe.ocaml represents nullable primitives (`Null<Int>`, etc.) as `Obj.t` carrying the
		 *   `HxRuntime.hx_null` sentinel. If we unbox too early, we lose that sentinel and can no
		 *   longer distinguish "null means None" from "a real value".
		 *
		 * What:
		 * - Returns an OCaml expression of type `'a option`:
		 *   - literal `null` -> `None`
		 *   - nullable primitive `Obj.t` -> `let tmp = <expr> in if tmp == hx_null then None else Some <unboxed>`
		 *   - non-null value -> `Some (<coerced>)`
		 *
		 * How:
		 * - Uses physical equality (`==`) against `HxRuntime.hx_null` to detect null-sentinel values.
		 * - Avoids producing invalid double-boxing patterns like `Obj.repr (Obj.repr 2)` when Haxe
		 *   inserts redundant casts around `Null<T>` flows.
		 */
	function buildOptionalArgOptionExprForInterop(arg:TypedExpr, expectedType:Type):OcamlExpr {
		final hxNull = OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");

		inline function stripDoubleObjRepr(e:OcamlExpr):OcamlExpr {
			function peelAnnot(x:OcamlExpr):OcamlExpr {
				var cur = x;
				while (true) {
					switch (cur) {
						case OcamlExpr.EAnnot(inner, _):
							cur = inner;
						case _:
							return cur;
					}
				}
				return cur;
			}

			function peelObjReprApp(x:OcamlExpr):Null<OcamlExpr> {
				final p = peelAnnot(x);
				return switch (p) {
					case OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [inner]): inner;
					case _: null;
				}
			}

			final inner1 = peelObjReprApp(e);
			if (inner1 == null)
				return e;
			final inner2 = peelObjReprApp(inner1);
			return inner2 == null ? e : inner1;
		}

		// Fast-path literal null.
		final unwrapped = unwrap(arg);
		final isLiteralNull = switch (unwrapped.expr) {
			case TConst(TNull): true;
			case _: false;
		}
		if (isLiteralNull)
			return OcamlExpr.EIdent("None");

		final tmp = freshTmp("optarg");

		// Optional labelled args in OCaml are `'a option`. For Haxe interop we accept:
		// - `null` (meaning "omit" / None)
		// - a value
		//
		// For primitive optional args, Haxe will often type arguments as `Null<T>`, which in
		// reflaxe.ocaml is represented as `Obj.t` with the `HxRuntime.hx_null` sentinel.
		//
		// If we eagerly coerce `Null<Int>` to `Int` here (unboxing), we lose the null sentinel
		// and cannot correctly produce `None`. So we build the option wrapper directly.
		if (isIntType(expectedType)) {
			return switch (nullablePrimitiveKind(arg.t)) {
				case "int":
					final v0 = switch (unwrapped.expr) {
						// Haxe can insert redundant casts around `Null<T>` flows, e.g. `cast (cast 2 : Null<Int>)`.
						// Avoid double-boxing (`Obj.repr (Obj.repr 2)`) by stripping casts where the inner
						// expression is already represented as `Obj.t`.
						case TCast(inner, _):
							nullablePrimitiveKind(inner.t) != null ? buildExpr(inner) : buildExpr(arg);
						case _:
							buildExpr(arg);
					}
					final v = stripDoubleObjRepr(v0);
					final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull);
					final someVal = OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])
					]);
					OcamlExpr.ELet(tmp, v, OcamlExpr.EIf(isNull, OcamlExpr.EIdent("None"), someVal), false);
				case _:
					OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [coerceForAssignment(expectedType, arg)]);
			}
		}

		if (isFloatType(expectedType)) {
			return switch (nullablePrimitiveKind(arg.t)) {
				case "float":
					final v0 = switch (unwrapped.expr) {
						case TCast(inner, _):
							nullablePrimitiveKind(inner.t) != null ? buildExpr(inner) : buildExpr(arg);
						case _:
							buildExpr(arg);
					}
					final v = stripDoubleObjRepr(v0);
					final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull);
					final someVal = OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])
					]);
					OcamlExpr.ELet(tmp, v, OcamlExpr.EIf(isNull, OcamlExpr.EIdent("None"), someVal), false);
				case _:
					OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [coerceForAssignment(expectedType, arg)]);
			}
		}

		if (isBoolType(expectedType)) {
			return switch (nullablePrimitiveKind(arg.t)) {
				case "bool":
					final v0 = switch (unwrapped.expr) {
						case TCast(inner, _):
							nullablePrimitiveKind(inner.t) != null ? buildExpr(inner) : buildExpr(arg);
						case _:
							buildExpr(arg);
					}
					final v = stripDoubleObjRepr(v0);
					final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull);
					final someVal = OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [OcamlExpr.EIdent(tmp)])
					]);
					OcamlExpr.ELet(tmp, v, OcamlExpr.EIf(isNull, OcamlExpr.EIdent("None"), someVal), false);
				case _:
					OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [coerceForAssignment(expectedType, arg)]);
			}
		}

		// Non-primitive optional arg: compare via `Obj.repr` so the null sentinel can be detected
		// consistently even when null is represented as `Obj.magic hx_null : t`.
		final coerced = coerceForAssignment(expectedType, arg);
		final objVal = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [coerced]);
		final isNull = OcamlExpr.EBinop(OcamlBinop.PhysEq, OcamlExpr.EIdent(tmp), hxNull);
		final someVal = OcamlExpr.EApp(OcamlExpr.EIdent("Some"), [
			OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [OcamlExpr.EIdent(tmp)])
		]);
		return OcamlExpr.ELet(tmp, objVal, OcamlExpr.EIf(isNull, OcamlExpr.EIdent("None"), someVal), false);
	}
}
#end
