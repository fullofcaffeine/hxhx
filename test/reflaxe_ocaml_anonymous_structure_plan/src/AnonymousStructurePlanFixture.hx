package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.ast.OcamlAnonymousStructureSyntax;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureContract;
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
	alias receive deterministic create, initialization, read, write, carrier,
	and runtime-support decisions before OCaml syntax is built. Parameters,
	reassigned locals, key/value pairs, and method-bearing shapes remain outside
	that boundary, so a matching field list alone cannot select `HxAnon`.
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
		initializers.sort((left, right) -> left.fieldSourceOrder - right.fieldSourceOrder);
		assertTrue(creates.length == 1 && initializers.length == 3 && reads.length == 1 && writes.length == 2,
			"the plan should contain one create, three source fields, one read, and two writes");
		assertTrue(initializers.map(operation -> operation.fieldName).join(",") == "name,count,enabled",
			"literal initialization should retain Haxe source order instead of canonical name order");
		assertTrue(initializers[2].storeConversion == "box-bool"
			&& Lambda.find(reads.concat(writes), operation -> operation.fieldName == "count").fieldCarrierTypeId == "int",
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
		assertTrue(requirements.length == operations.length,
			"each anonymous create, field initialization, read, and write should explain its own runtime dependency");
		for (requirement in requirements) {
			assertTrue(requirement.semanticCapability == OcamlAnonymousStructureContract.RUNTIME_CAPABILITY
				&& requirement.rootModules.join(",") == OcamlAnonymousStructureContract.RUNTIME_MODULE,
				"each anonymous operation should select only the checked HxAnon runtime module");
		}

		requireWriteSyntaxOrder(admittedBody, first, registry);
		requireUnowned("parameterOnly", 0, 0, registry);
		requireUnowned("reassigned", 1, 4, registry);
		requireUnowned("keyValuePair", 0, 0, registry);
		requireUnowned("methodBearing", 0, 0, registry);

		expectFailure("duplicate structure", "duplicate-structure", () -> new OcamlAnonymousStructurePlan([structure, structure], operations));
		expectFailure("duplicate operation", "duplicate-operation", () -> new OcamlAnonymousStructurePlan(structures, [operations[0], operations[0]]));
		final corruptRuntime = OcamlAnonymousStructureContract.copyOperation(operations[0], operations[0].id);
		corruptRuntime.runtimeRequirementIds.pop();
		expectFailure("missing runtime requirement", "wrong-runtime", () -> new OcamlAnonymousStructurePlan(structures, [corruptRuntime]));

		trace("REFLAXE_OCAML_ANONYMOUS_STRUCTURE_PLAN_FIXTURE:PASS");
		return macro null;
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
				fieldRef.get().name == "count";
			case _:
				false;
		});
		if (writeExpression == null)
			throw "the admitted fixture should contain a count-field write";
		final pieces = switch (writeExpression.expr) {
			case TBinop(OpAssign, {expr: TField(receiver, FAnon(_))}, value):
				{receiver: receiver, value: value};
			case _:
				throw "the selected write expression changed shape";
		}
		final operation = plan.operationFor(writeExpression, registry);
		if (operation == null)
			throw "the count-field write should have a validated operation";
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
		the receiver is a parameter, a reassigned local, or a dedicated shape.
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
