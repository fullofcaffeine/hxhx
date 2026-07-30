package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.ast.OcamlAnonymousStructureSyntax;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureContract;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureFieldOperator;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationKind;
import reflaxe.ocaml.lowered.OcamlAnonymousStructurePlan;
import reflaxe.ocaml.lowered.OcamlAnonymousStructurePlan.OcamlAnonymousStructurePlanner;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.runtimegen.OcamlAnonymousStructureRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

/**
	Checks the complete decision boundary for ordinary anonymous objects.

	A successful fixture proves that one direct literal and its unchanged local
		alias receive deterministic create, initialization, read, plain-write,
		`Int +=`, carrier, and runtime-support decisions before OCaml syntax is
		built. Parameters,
	reassigned locals, iterators, key/value pairs, `sys.FileStat`, and
	method-bearing shapes remain outside that boundary, so a matching field list
	alone cannot select the generic `HxAnon` representation.
**/
class AnonymousStructurePlanFixture {
	static inline final PROGRAM_REVISION = "program:anonymous-structure-fixture";
	static inline final BODY_REVISION = "body:anonymous-structure-fixture";
	static inline final PIPELINE_REVISION = "pipeline:anonymous-structure-fixture";

	public static macro function run():Expr {
		final registry = new OcamlRepresentationRegistry();
		registry.beginProgram(PROGRAM_REVISION);

		final admittedBody = requireBody(requireField("admitted"));
		final binding = functionBinding("admitted");
		final first = new OcamlAnonymousStructurePlanner(binding, registry).plan(admittedBody);
		final second = new OcamlAnonymousStructurePlanner(binding, registry).plan(admittedBody);
		assertTrue(first.revision == second.revision, "the same typed body should produce one deterministic anonymous-object plan");

		final structures = first.structures();
		final operations = first.operations();
		assertTrue(structures.length == 1, 'the admitted case should own one structure, received ${structures.length}');
		assertTrue(operations.length == 7, 'the admitted case should own seven operations, received ${operations.length}');
		final structure = structures[0];
		assertTrue(structure.semanticTypeId == "anonymous{count:Int,enabled:Bool,name:String}",
			"the normalized shape should use field-name order and exact Haxe types");
		assertTrue(structure.carrierTypeId == "Obj.t"
			&& structure.identityPolicy == "reference-identity"
			&& structure.aliasingPolicy == "shared-reference-aliases"
			&& structure.mutationPolicy == "mutable-runtime-container",
			"the structure should preserve one mutable reference across local aliases");

		final creates = operations.filter(operation -> operation.kind == OcamlAnonymousStructureOperationKind.Create);
		final initializers = operations.filter(operation -> operation.kind == OcamlAnonymousStructureOperationKind.InitializeField);
		final reads = operations.filter(operation -> operation.kind == OcamlAnonymousStructureOperationKind.ReadField);
		final writes = operations.filter(operation -> operation.kind == OcamlAnonymousStructureOperationKind.WriteField);
		final compoundWrites = operations.filter(operation -> operation.kind == OcamlAnonymousStructureOperationKind.CompoundWriteField);
		initializers.sort((left, right) -> left.fieldSourceOrder - right.fieldSourceOrder);
		assertTrue(creates.length == 1 && initializers.length == 3 && reads.length == 1 && writes.length == 1 && compoundWrites.length == 1,
			"the plan should contain one create, three source fields, one read, one plain write, and one Int += write");
		assertTrue(initializers.map(operation -> operation.fieldName).join(",") == "name,count,enabled",
			"literal initialization should retain Haxe source order instead of canonical name order");
		assertTrue(initializers[2].storeConversion == "box-bool"
			&& compoundWrites[0].fieldCarrierTypeId == "int"
			&& compoundWrites[0].fieldOperator == OcamlAnonymousStructureFieldOperator.IntAdd
			&& compoundWrites[0].runtimeReadOperation == "get",
			"Bool should use the distinct runtime box while Int keeps its exact direct carrier");

		first.requirePlanBinding(binding);
		first.requireRepresentations(registry);
		for (expression in fieldOperations(admittedBody)) {
			final decision = first.operationFor(expression, registry);
			assertTrue(decision != null, "every admitted local-alias field operation should reconnect to its exact typed expression");
		}

		final ledger = new OcamlRuntimeRequirementLedger();
		ledger.beginProgram(PROGRAM_REVISION);
		for (operation in operations)
			OcamlAnonymousStructureRuntimeRequirementRecorder.record(ledger, operation);
		final requirements = ledger.requirementsSorted();
		assertTrue(requirements.length == operations.length + 1,
			"each anonymous operation should explain HxAnon, while Int += should additionally explain HxInt arithmetic");
		for (requirement in requirements) {
			final anonymousReason = requirement.semanticCapability == OcamlAnonymousStructureContract.RUNTIME_CAPABILITY
				&& requirement.rootModules.join(",") == OcamlAnonymousStructureContract.RUNTIME_MODULE;
			final intAddReason = requirement.semanticCapability == OcamlAnonymousStructureContract.INT32_ADD_CAPABILITY
				&& requirement.rootModules.join(",") == OcamlAnonymousStructureContract.INT32_ADD_MODULE;
			assertTrue(anonymousReason || intAddReason,
				"each anonymous operation should select HxAnon, and its admitted Int += should also select checked HxInt arithmetic");
		}

		requireWriteSyntaxOrder(admittedBody, first, registry);
		requireCompoundWriteSyntaxOrder(admittedBody, first, registry);
		requireUnowned("parameterOnly", 0, 0, registry);
		requireUnowned("reassigned", 1, 4, registry);
		requireUnowned("keyValuePair", 0, 0, registry);
		requireUnowned("iteratorShape", 0, 0, registry);
		requireUnowned("fileStatShape", 0, 0, registry);
		requireUnowned("methodBearing", 0, 0, registry);
		requireUnowned("dynamicCrossing", 1, 4, registry);
		requireUnowned("structuralConversion", 0, 0, registry);
		requireUnowned("patternOnly", 1, 4, registry);
		final unsupportedCompoundBody = requireBody(requireField("unsupportedCompound"));
		expectFailure("unsupported anonymous compound write", "unsupported-compound-write",
			() -> new OcamlAnonymousStructurePlanner(functionBinding("unsupportedCompound"), registry).plan(unsupportedCompoundBody));

		expectFailure("duplicate structure", "duplicate-structure", () -> new OcamlAnonymousStructurePlan([structure, structure], operations));
		expectFailure("duplicate operation", "duplicate-operation", () -> new OcamlAnonymousStructurePlan(structures, [operations[0], operations[0]]));
		expectFailure("missing structure", "missing-structure", () -> new OcamlAnonymousStructurePlan([], [operations[0]]));
		expectFailure("missing typed occurrence", "missing-operation-occurrence", () -> new OcamlAnonymousStructurePlan(structures, operations, [], []));

		final staleStructure = clone(structure);
		Reflect.setField(staleStructure, "revision", "sha256:" + StringTools.lpad("", "0", 64));
		expectFailure("stale structure revision", "stale-structure", () -> new OcamlAnonymousStructurePlan([staleStructure], []));

		final reorderedStructure = clone(structure);
		final firstName = reorderedStructure.fields[0].name;
		Reflect.setField(reorderedStructure.fields[0], "name", reorderedStructure.fields[1].name);
		Reflect.setField(reorderedStructure.fields[1], "name", firstName);
		expectFailure("reordered structure fields", "reordered-field", () -> new OcamlAnonymousStructurePlan([reorderedStructure], []));

		final wrongField = clone(reads[0]);
		Reflect.setField(wrongField, "fieldName", "missing");
		expectFailure("wrong field identity", "wrong-field", () -> new OcamlAnonymousStructurePlan(structures, [wrongField]));

		final wrongCarrier = clone(reads[0]);
		Reflect.setField(wrongCarrier, "fieldCarrierTypeId", "bool");
		expectFailure("wrong field carrier", "wrong-field", () -> new OcamlAnonymousStructurePlan(structures, [wrongCarrier]));

		final wrongBody = clone(reads[0]);
		Reflect.setField(wrongBody, "bodyRevision", "body:wrong");
		expectFailure("wrong body revision", "stale-operation", () -> new OcamlAnonymousStructurePlan(structures, [wrongBody]));

		final wrongProgram = clone(reads[0]);
		Reflect.setField(wrongProgram, "programRevision", "program:wrong");
		expectFailure("wrong program revision", "stale-operation", () -> new OcamlAnonymousStructurePlan(structures, [wrongProgram]));

		final wrongPipeline = clone(reads[0]);
		Reflect.setField(wrongPipeline, "pipelineRevision", "pipeline:wrong");
		expectFailure("wrong pipeline revision", "stale-operation", () -> new OcamlAnonymousStructurePlan(structures, [wrongPipeline]));

		final missingOperator = clone(compoundWrites[0]);
		Reflect.setField(missingOperator, "fieldOperator", null);
		expectFailure("missing compound operator", "invalid-compound-write", () -> new OcamlAnonymousStructurePlan(structures, [missingOperator]));

		final corruptRuntime = OcamlAnonymousStructureContract.copyOperation(operations[0], operations[0].id);
		corruptRuntime.runtimeRequirementIds.pop();
		expectFailure("missing runtime requirement", "wrong-runtime", () -> new OcamlAnonymousStructurePlan(structures, [corruptRuntime]));
		final missingArithmeticRuntime = clone(compoundWrites[0]);
		missingArithmeticRuntime.runtimeRequirementIds.pop();
		expectFailure("missing compound arithmetic runtime", "wrong-runtime", () -> new OcamlAnonymousStructurePlan(structures, [missingArithmeticRuntime]));

		trace("REFLAXE_OCAML_ANONYMOUS_STRUCTURE_PLAN_FIXTURE:PASS");
		return macro null;
	}

	/**
		Verifies the full single-evaluation order of the admitted `Int +=` path.

		The syntax must bind the receiver, old field, right-hand side, and new
		result in that order. This catches regressions where `+=` is omitted,
		reads the field after the right-hand side, or evaluates either source
		expression more than once.
	**/
	static function requireCompoundWriteSyntaxOrder(body:TypedExpr, plan:OcamlAnonymousStructurePlan, registry:OcamlRepresentationRegistry):Void {
		final writeExpression = Lambda.find(fieldOperations(body), expression -> switch (expression.expr) {
			case TBinop(OpAssignOp(OpAdd), {expr: TField(_, FAnon(fieldRef))}, _):
				fieldRef.get().name == "count";
			case _:
				false;
		});
		if (writeExpression == null)
			throw "the admitted fixture should contain a count-field Int += write";
		final pieces = switch (writeExpression.expr) {
			case TBinop(OpAssignOp(OpAdd), {expr: TField(receiver, FAnon(_))}, value):
				{receiver: receiver, value: value};
			case _:
				throw "the selected compound-write expression changed shape";
		}
		final operation = plan.operationFor(writeExpression, registry);
		if (operation == null)
			throw "the count-field Int += write should have a validated operation";
		var suffix = 0;
		final syntax = OcamlAnonymousStructureSyntax.buildCompoundWrite(operation, pieces.receiver, pieces.value, expression -> {
			if (expression == pieces.receiver)
				return OcamlExpr.EIdent("receiver-source");
			if (expression == pieces.value)
				return OcamlExpr.EIdent("value-source");
			throw "anonymous compound-write syntax requested an unexpected source expression";
		}, prefix -> prefix + "_" + suffix++);
		final preservesOrder = switch (syntax) {
			case ELet(_, EIdent("receiver-source"),
				ELet(_, EApp(EField(EIdent("Obj"), "obj"), [_]),
					ELet(_, EIdent("value-source"), ELet(_, EApp(EField(EIdent("HxInt"), "add"), _), ESeq(_), false), false), false),
				false):
				true;
			case _:
				false;
		}
		assertTrue(preservesOrder, "anonymous Int += syntax should read the old field before evaluating the right-hand side, then store and return the sum");
	}

	/**
		Verifies that syntax evaluates a write receiver before its assigned value.

		The source case uses locals, so runtime output alone cannot reveal a
		reordering. Inspecting the generated OCaml expression confirms the first
		`let` binds the receiver and the nested `let` then binds the right-hand
		side, with neither input rebuilt.
	**/
	static function requireWriteSyntaxOrder(body:TypedExpr, plan:OcamlAnonymousStructurePlan, registry:OcamlRepresentationRegistry):Void {
		final writeExpression = Lambda.find(fieldOperations(body), expression -> switch (expression.expr) {
			case TBinop(OpAssign, {expr: TField(_, FAnon(fieldRef))}, _):
				fieldRef.get().name == "enabled";
			case _:
				false;
		});
		if (writeExpression == null)
			throw "the admitted fixture should contain an enabled-field write";
		final pieces = switch (writeExpression.expr) {
			case TBinop(OpAssign, {expr: TField(receiver, FAnon(_))}, value):
				{receiver: receiver, value: value};
			case _:
				throw "the selected write expression changed shape";
		}
		final operation = plan.operationFor(writeExpression, registry);
		if (operation == null)
			throw "the enabled-field write should have a validated operation";
		var suffix = 0;
		final syntax = OcamlAnonymousStructureSyntax.buildWrite(operation, pieces.receiver, pieces.value, expression -> {
			if (expression == pieces.receiver)
				return OcamlExpr.EIdent("receiver-source");
			if (expression == pieces.value)
				return OcamlExpr.EIdent("value-source");
			throw "anonymous write syntax requested an unexpected source expression";
		}, prefix -> prefix + "_" + suffix++);
		final preservesOrder = switch (syntax) {
			case ELet(_, EIdent("receiver-source"), ELet(_, EIdent("value-source"), ESeq(_), false), false):
				true;
			case _:
				false;
		}
		assertTrue(preservesOrder, "anonymous write syntax should bind the receiver before the assigned value");
	}

	/**
		Checks a case that must not gain field operations from shape matching.

		Some cases still contain a direct literal, so their create and
		initialization records remain valid. Their field reads stay unowned when
		the receiver is a parameter, a reassigned local, or a dedicated iterator,
		key/value, or file-metadata shape with its own OCaml representation.
	**/
	static function requireUnowned(name:String, expectedStructures:Int, expectedOperations:Int, registry:OcamlRepresentationRegistry):Void {
		final body = requireBody(requireField(name));
		final plan = new OcamlAnonymousStructurePlanner(functionBinding(name), registry).plan(body);
		assertTrue(plan.structures().length == expectedStructures && plan.operations().length == expectedOperations,
			'$name should have $expectedStructures structures and $expectedOperations operations, received ${plan.structures().length}/${plan.operations().length}');
		for (expression in fieldOperations(body))
			assertTrue(plan.operationFor(expression, registry) == null, '$name should leave same-shaped field access on the existing path');
	}

	/** Returns direct anonymous reads and writes from one typed function body. */
	static function fieldOperations(body:TypedExpr):Array<TypedExpr> {
		final out = new Array<TypedExpr>();
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TBinop(OpAssign, {expr: TField(receiver, FAnon(_))}, value):
					out.push(expression);
					visit(receiver);
					visit(value);
				case TBinop(OpAssignOp(_), {expr: TField(receiver, FAnon(_))}, value):
					out.push(expression);
					visit(receiver);
					visit(value);
				case TField(_, FAnon(_)):
					out.push(expression);
					TypedExprTools.iter(expression, visit);
				case _:
					TypedExprTools.iter(expression, visit);
			}
		}
		visit(body);
		return out;
	}

	/** Retrieves one static fixture method by its Haxe source name. */
	static function requireField(name:String):ClassField {
		return switch (Context.getType("AnonymousStructurePlanCases")) {
			case TInst(classRef, _):
				final matches = classRef.get().statics.get().filter(field -> field.name == name);
				if (matches.length != 1)
					throw 'expected one AnonymousStructurePlanCases.$name method';
				matches[0];
			case _:
				throw "AnonymousStructurePlanCases should be a class";
		}
	}

	/** Extracts the typed body supplied to the target planner. */
	static function requireBody(field:ClassField):TypedExpr {
		final expression = field.expr();
		if (expression == null)
			throw 'fixture method "${field.name}" has no typed expression';
		return switch (expression.expr) {
			case TFunction(fn): fn.expr;
			case _: throw 'fixture method "${field.name}" should be a function';
		}
	}

	/** Builds the exact request identity used by one fixture plan. */
	static function functionBinding(name:String):OcamlFunctionPlanBinding {
		return {
			functionId: "AnonymousStructurePlanCases." + name,
			programRevision: PROGRAM_REVISION,
			bodyRevision: BODY_REVISION + ":" + name,
			pipelineRevision: PIPELINE_REVISION
		};
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Copies plain decision data so one corruption test cannot affect another. */
	static function clone<T>(value:T):T {
		return cast haxe.Json.parse(haxe.Json.stringify(value));
	}

	/** Requires malformed decision data to fail with the named diagnostic. */
	static function expectFailure(label:String, expectedMessage:String, action:Void->Void):Void {
		var failed = false;
		try {
			action();
		} catch (error:Dynamic) {
			failed = true;
			final message = Std.string(error);
			if (message.indexOf(expectedMessage) < 0)
				throw '$label failed with an unexpected message: $message';
		}
		if (!failed)
			throw '$label should have failed';
	}
}
