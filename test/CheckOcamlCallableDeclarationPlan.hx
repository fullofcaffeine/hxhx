#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallableDeclarationCarrier;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlanner;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlanner;
import reflaxe.ocaml.reports.OcamlCallableViewInventory;
import reflaxe.ocaml.reports.OcamlCallableViewInventory.CallableViewParameterOwner;

using reflaxe.helpers.ClassFieldHelper;

/** Checks real declaration publication and rejects forged callback layouts before syntax. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckOcamlCallableDeclarationPlan {
	/** The unchanged source regression supplies declarations; expectations below describe their contracts independently. */
	public static function run():Void {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing stored callback source fixture";
		};
		final compiler = new OcamlCompiler();
		final revision = "callback-declaration-fixture";
		compiler.functionPlanRegistry.beginProgram(revision);
		compiler.representationRegistry.beginProgram(revision);
		compiler.planCallableDeclarations([owner.module], [owner.module => [owner]], revision);
		function field(name:String):haxe.macro.Type.ClassField {
			return Lambda.find(owner.statics.get(), field -> field.name == name) ?? throw "missing callback fixture method";
		}
		function declared(name:String):OcamlCallableDeclarationPlan {
			return compiler.functionPlanRegistry.callableDeclaration(OcamlCallPlanner.calleeId(owner,
				field(name))) ?? throw "production catalog omitted callback method";
		}
		function expectFailure(action:Void->Void, expected:String):Void {
			var failed = false;
			try
				action()
			catch (error:Dynamic) {
				// Compiler diagnostics are thrown values at the macro API boundary.
				// Validate the expected diagnostic immediately; other failures escape.
				if (!StringTools.contains(Std.string(error), expected))
					throw error;
				failed = true;
			}
			if (!failed)
				throw "callback catalog accepted invalid evidence: " + expected;
		}
		final unaryInt = describe(FunctionValue([Integer], Integer));
		final unaryDynamic = describe(FunctionValue([DynamicValue], DynamicValue));
		for (name in ["literal", "captured", "preserve", "staticCallback", "forwarded", "relay"]) {
			final declaration = declared(name);
			OcamlCallPlan.requireCallableDeclarationPlan(declaration);
			final expected = name == "relay" ? unaryDynamic : unaryInt;
			if (declaration.proofId != SIGNATURE_PROOF || declaration.result == null || !same(declaration.result.callableView, expected))
				throw "callback declaration exported the wrong result layout: " + name;
			if (name == "preserve" || name == "relay") {
				if (declaration.arguments.length != 1 || !same(declaration.arguments[0].callableView, expected))
					throw "callback declaration lost its parameter layout";
			}
			final data = field(name).findFuncData(owner, true);
			if (data == null)
				throw "callback fixture lost its function body";
			data.bindProgramRevision(revision);
			final binding = compiler.functionPlanRegistry.planningBindingFor(data);
			final planner = new OcamlCallPlanner(compiler.representationRegistry, binding, null, null, null, compiler.functionPlanRegistry.callableDeclaration);
			final boundary = planner.boundaryFor(data);
			if (boundary == null || boundary.callbackReturns == null || boundary.callbackReturns.length != 1)
				throw "production callback boundary has no return occurrence";
			OcamlCallPlan.requireCallableBoundary(boundary);
			CheckOcamlCallableCallReports.verifyReturn(reflaxe.ocaml.reports.OcamlReportJson.encode(reflaxe.ocaml.reports.OcamlCallableCallReport.returnToReport(boundary.callbackReturns[0])));
			boundary.callbackReturns.resize(0);
			expectFailure(() -> OcamlCallPlan.requireCallableBoundary(boundary), "callback returns require");
		}
		if (declared("declared").proofId != OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID)
			throw "scalar method acquired an unnecessary callback calling convention";
		final preserved = declared("preserve");
		final copied = OcamlCallPlan.copyDeclaration(preserved);
		copied.arguments.resize(0);
		if (declared("preserve").arguments.length != 1 || OcamlCallPlan.sameDeclaration(preserved, copied))
			throw "catalog getter leaked its parameter array or ignored changed arity";
		final result = preserved.result ?? throw "preserve lost its callback result";
		final layout = result.callableView ?? throw "preserve lost its callback layout";
		switch (layout.shape) {
			case FunctionValue(arguments, _):
				arguments.push(Boolean);
			case _:
				throw "preserve result is not callable";
		}
		expectFailure(() -> OcamlCallPlan.requireCallableDeclarationPlan(preserved), "stale-descriptor");
		expectFailure(() -> OcamlCallPlan.copyDeclaration(preserved), "stale-descriptor");
		OcamlCallPlan.requireCallableDeclarationPlan(declared("preserve"));
		final forgedReceiver = value(-2, FunctionValue([Integer], Integer), compiler.representationRegistry);
		expectFailure(() -> OcamlCallPlan.requireCallValue(forgedReceiver, -2, "forged receiver"), "invalid-carrier");
		expectFailure(() -> requireSignature(describe(FunctionValue([unaryDynamic.shape], unaryInt.shape)), declared("preserve").arguments,
			declared("preserve").result),
			"invocation parameter differs");
		expectFailure(() -> declaration(owner, field("preserve"), {
			calleeId: OcamlCallPlanner.calleeId(owner, field("literal")),
			fieldName: "preserve",
			signature: FunctionValue([unaryInt.shape], unaryInt.shape)
		},
			compiler.representationRegistry, revision, reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.PIPELINE_REVISION), "source-mismatch");
		final main = field("main").findFuncData(owner, true) ?? throw "callback fixture lost its main body";
		main.bindProgramRevision(revision);
		final mainBinding = compiler.functionPlanRegistry.planningBindingFor(main);
		final identities = LexicalLocalIdentityPlan.build(mainBinding.functionId, main.expr);
		final storage = OcamlLocalStoragePlanner.planExpression(main.expr, identities);
		final locals = OcamlLocalRepresentationPlanner.planExpression(main.expr, identities, storage, compiler.representationRegistry, mainBinding, null,
			null, null, null, {
				parameters: [],
				boundary: null,
				declaration: compiler.functionPlanRegistry.callableDeclaration
			});
		var preserveCall:Null<TypedExpr> = null;
		function findPreserveCall(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value) if (local.name == "preserved"):
					preserveCall = value;
				case _:
			}
			TypedExprTools.iter(expression, findPreserveCall);
		}
		findPreserveCall(main.expr);
		final call = preserveCall ?? throw "callback fixture lost its identity-forwarding call";
		final preliminary = new OcamlCallPlanner(compiler.representationRegistry, mainBinding, null, null, null,
			compiler.functionPlanRegistry.callableDeclaration);
		if (preliminary.preliminaryProducesExactString(call))
			throw "callback result was classified as a string before local planning";
		// Positive scalar function probes also precede callback storage selection.
		// Reusing their raw-arrow decisions would lose final invocation evidence.
		function primeCalls(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TCall(_, _):
					preliminary.preliminaryProducesExactString(expression);
				case _:
			}
			TypedExprTools.iter(expression, primeCalls);
		}
		primeCalls(main.expr);
		function finalPlanner():OcamlCallPlanner {
			return new OcamlCallPlanner(compiler.representationRegistry, mainBinding, locals, identities, null,
				compiler.functionPlanRegistry.callableDeclaration);
		}
		final cold = finalPlanner().plan(main.expr);
		final reused = finalPlanner().plan(main.expr, preliminary);
		if (cold.decisionFor(call) == null || cold.decisionFor(call).arguments[0].callbackArgument == null)
			throw "final callback call lost its source argument preparation";
		if (reused.decisionFor(call) == null || reused.revision != cold.revision)
			throw "preliminary negative callback result hid the final call after local planning";
		function comparisons(calls:OcamlCallPlan):Array<reflaxe.ocaml.lowered.OcamlCallableComparison.OcamlCallableComparisonDecision> {
			return new reflaxe.ocaml.lowered.OcamlCallableExpressionPlanner(compiler.representationRegistry, mainBinding, locals, identities,
				(owner, field) -> compiler.functionPlanRegistry.callableDeclaration(OcamlCallPlanner.calleeId(owner, field)),
				calls.decisionFor).comparisons(main.expr);
		}
		final prepared = cold.decisionFor(call).arguments[0].callbackArgument;
		CheckOcamlCallableCallReports.verifyArgument(reflaxe.ocaml.reports.OcamlReportJson.encode(reflaxe.ocaml.reports.OcamlCallableCallReport.argumentToReport(prepared)));
		final compared = comparisons(cold);
		if (compared.length != 12
			|| compared.map(value -> value.revision)
				.join("|") != comparisons(reused)
				.map(value -> value.revision)
				.join("|"))
			throw "callback comparisons lost an occurrence or changed after preliminary query reuse";
		final comparedLocals = locals.withCallableComparisons(compared);
		comparedLocals.requirePlanBinding(mainBinding);
		if (comparedLocals.count != locals.count || comparedLocals.revision == locals.revision)
			throw "callback comparisons invented storage or disappeared from the final plan revision";
		final returnedComparison = Lambda.find(compared,
			decision -> switch ([decision.left.input, decision.right.input]) {
				case [CallResult(_), RawOrigin(StaticDeclaration(_))]: true;
				case _: false;
			}) ?? throw "returned static callback has no call-result to raw-method comparison";
		if (returnedComparison.notEqual)
			throw "returned static callback changed its equality operator";
		expectFailure(() -> reflaxe.ocaml.lowered.OcamlCallableComparison.requireBinding(returnedComparison, {
			functionId: mainBinding.functionId,
			programRevision: mainBinding.programRevision,
			bodyRevision: mainBinding.bodyRevision + "-changed",
			pipelineRevision: mainBinding.pipelineRevision
		}), "foreign-binding");
		expectFailure(() -> locals.withCallableComparisons(compared.concat(compared)), "duplicate-occurrence");
		final detached = comparedLocals.callableComparisons();
		detached.resize(0);
		if (comparedLocals.callableComparisons().length != 12)
			throw "callback comparison getter leaked its mutable array";
		var aliasInitializer:Null<TypedExpr> = null;
		var aliasComparison:Null<TypedExpr> = null;
		function findAlias(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value) if (local.name == "alias"):
					aliasInitializer = value;
				case TBinop(OpEq, _, {expr: TLocal(local)}) if (local.name == "alias"):
					aliasComparison = expression;
				case _:
			}
			TypedExprTools.iter(expression, findAlias);
		}
		findAlias(main.expr);
		final initializer = aliasInitializer ?? throw "callback fixture lost its alias initializer";
		final original = aliasComparison ?? throw "callback fixture lost its alias comparison";
		// Model the real optimizer's substitution without changing either source
		// position. Ownership follows the final typed body, not text containment.
		final substituted:TypedExpr = {
			expr: switch (original.expr) {
				case TBinop(op, left, _): TBinop(op, left, initializer);
				case _: throw "lost alias comparison";
			},
			pos: original.pos,
			t: original.t
		};
		final optimized = new reflaxe.ocaml.lowered.OcamlCallableExpressionPlanner(compiler.representationRegistry, mainBinding, locals, identities,
			(owner, field) -> compiler.functionPlanRegistry.callableDeclaration(OcamlCallPlanner.calleeId(owner, field)),
			cold.decisionFor).comparisons(substituted);
		if (optimized.length != 1 || optimized[0].right.source.min >= optimized[0].source.min)
			throw "alias substitution lost its independently retained initializer position";
		final stale:reflaxe.ocaml.lowered.OcamlCallableComparison.OcamlCallableComparisonDecision = {
			id: optimized[0].id,
			revision: optimized[0].revision,
			binding: optimized[0].binding,
			source: optimized[0].source,
			notEqual: optimized[0].notEqual,
			left: optimized[0].left,
			right: {
				input: optimized[0].right.input,
				layout: optimized[0].right.layout,
				source: {file: optimized[0].right.source.file, min: 0, max: optimized[0].right.source.max}
			}
		};
		expectFailure(() -> reflaxe.ocaml.lowered.OcamlCallableComparison.requireDecision(stale), "stale-decision");
		final mainInventory = build([
			for (reference in locals.references())
				{
					binding: mainBinding,
					reference: reference
				}
		], locals.callableViewConversions(), [], compared);
		final mainEncoded = reflaxe.ocaml.reports.OcamlReportJson.encode(mainInventory);
		if (reflaxe.ocaml.reports.OcamlReportJson.encode(fromReport(haxe.Json.parse(mainEncoded))) != mainEncoded
			|| mainInventory.comparisons.length != 12)
			throw "callback comparison inventory did not preserve every ordered occurrence";
		final unsafeCount = Lambda.fold(mainInventory.comparisons, (entry, count) -> count + entry.unsafeOperations.length, 0);
		if (unsafeCount != 1)
			throw "callback comparisons lost the one raw static identity operation or invented extra operations";
		final comparisonJson = reflaxe.ocaml.reports.OcamlReportJson.encode(reflaxe.ocaml.reports.OcamlCallableComparisonReport.toReport(returnedComparison));
		for (mutation in ["operator", "order", "body", "source"]) {
			// Model altered wire data at the JSON boundary, then immediately decode
			// it through the same strict API available to report consumers.
			final changed:Dynamic = haxe.Json.parse(comparisonJson);
			switch (mutation) {
				case "operator":
					Reflect.setField(changed, "notEqual", true);
				case "order":
					final left:Dynamic = Reflect.field(changed, "left");
					Reflect.setField(changed, "left", Reflect.field(changed, "right"));
					Reflect.setField(changed, "right", left);
				case "body":
					Reflect.setField(Reflect.field(changed, "binding"), "bodyRevision", "changed-body");
				case "source":
					Reflect.setField(Reflect.field(Reflect.field(changed, "right"), "source"), "min", 0);
			}
			expectFailure(() -> reflaxe.ocaml.reports.OcamlCallableComparisonReport.fromReport(changed), "stale-decision");
		}
		final stripped = build(mainInventory.requiredLocals, locals.callableViewConversions(), [], compared);
		for (entry in stripped.comparisons)
			entry.unsafeOperations.resize(0);
		expectFailure(() -> fromReport(stripped), "unsafe-operation evidence");
		expectFailure(() -> build(mainInventory.requiredLocals, locals.callableViewConversions(), [], compared.concat(compared)), "duplicate comparison");
		for (name in ["preserve", "relay"]) {
			final data = field(name).findFuncData(owner, true) ?? throw "callback fixture lost its parameter body";
			data.bindProgramRevision(revision);
			compiler.sealFunctionPlans(data);
		}
		final inventory = compiler.functionPlanRegistry.callableViewInventory(compiler.representationRegistry);
		if (inventory.requiredLocals.length != 2 || inventory.parameters.length != 2 || inventory.entries.length != 0)
			throw "callback parameters were omitted or given invented initializer conversions";
		final owners:Array<CallableViewParameterOwner> = compiler.functionPlanRegistry.callableBoundaries().map(boundary -> {
			id: boundary.id,
			calleeId: boundary.calleeId,
			binding: {
				functionId: boundary.functionId,
				programRevision: boundary.programRevision,
				bodyRevision: boundary.bodyRevision,
				pipelineRevision: boundary.pipelineRevision
			},
			arguments: boundary.arguments.map(argument -> argument.callableView)
		});
		requireParameterCoverage(inventory, owners);
		final encoded = reflaxe.ocaml.reports.OcamlReportJson.encode(inventory);
		if (reflaxe.ocaml.reports.OcamlReportJson.encode(fromReport(haxe.Json.parse(encoded))) != encoded)
			throw "callback parameter inventory did not round trip";
		expectFailure(() -> build(inventory.requiredLocals, [], []), "missing its initializer conversion or declared parameter");
		expectFailure(() -> build(inventory.requiredLocals, [], inventory.parameters.concat(inventory.parameters)), "exactly one matching selected local");
		expectFailure(() -> requireParameterCoverage(build([], []), owners), "missing its selected parameter storage");
		final parameter = inventory.parameters[0];
		if (parameter.index != 0 || ![declared("preserve").calleeId, declared("relay").calleeId].contains(parameter.calleeId))
			throw "callback parameter invented a declaration or argument position";
		final changed = build(inventory.requiredLocals, [], inventory.parameters.map(value -> {
			binding: value.binding,
			reference: value.reference,
			boundaryId: value.boundaryId,
			calleeId: value.calleeId,
			index: 1,
			layout: value.layout
		}));
		expectFailure(() -> requireParameterCoverage(changed, owners), "declared callable owner");
		Sys.println("OCAML_CALLABLE_DECLARATION_PLAN:PASS");
	}
}
#end
