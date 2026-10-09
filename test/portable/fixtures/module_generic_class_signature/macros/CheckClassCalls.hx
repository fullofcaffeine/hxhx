import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.select as selectCall;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.decision as callDecision;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.fingerprint;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.nominalProofs;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.representationsMatch;
import reflaxe.ocaml.lowered.OcamlMonomorphicClassPlanner;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.reports.OcamlGenericCallReport.targetToReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport.targetFromReport;
import reflaxe.ocaml.reports.OcamlReportJson.encode;

/** Requires exact class proofs and retains them through typed-call and report round trips. */
@:access(reflaxe.ocaml.lowered.OcamlLoweringReportWriter)
class CheckClassCalls {
	public static function install():Void {
		Context.onAfterTyping(_ -> {
			final registry = registryFor(["Scope", "model.Payload", "model.OtherPayload", "model.EmptyPayload"]);
			for (representation in registry.decisions())
				reflaxe.ocaml.lowered.OcamlLoweringReportWriter.validateNominalRepresentation(representation);
			final receiverOnly = registryFor(["Scope"]);
			if (registry.monomorphicClassValue("Scope") != null || registry.monomorphicClassValue("model.Payload") != null)
				throw "Opaque class transport incorrectly granted scalar-field layout admission";
			final main = classType("Main");
			var count = 0;
			function visit(expression:TypedExpr):Void {
				switch (expression.expr) {
					case TCall({expr: TField(_, FInstance(_, _, method))}, _) if (method.get().params.length > 0):
						final target = selectCall(expression, registry);
						if (target == null || nominalProofs(target).length != 1)
							throw "Class callback lost its exact nominal representation";
						if (selectCall(expression, receiverOnly) != null)
							throw "Unregistered class value acquired a generic conversion";
						if (!representationsMatch(target, registry, "class-call-test")
							|| representationsMatch(target, registry, "other-program")
							|| representationsMatch(target, receiverOnly, "class-call-test"))
							throw "Code generation accepted missing or stale class transport proofs";
						final encoded = encode(targetToReport(target));
						final decoded = targetFromReport(haxe.Json.parse(encoded));
						if (fingerprint(decoded) != fingerprint(target) || encode(targetToReport(decoded)) != encoded)
							throw "Class callback report changed its representation proof";
						final decision = callDecision(expression, target, {
							functionId: "Main|main",
							programRevision: "class-call-test",
							bodyRevision: "body:current",
							pipelineRevision: "pipeline:test"
						});
						final plan = new OcamlCallPlan([decision]);
						if (plan.decisionFor(expression) == null)
							throw "Exact class call did not match its retained proof";
						final proof = nominalProofs(target)[0];
						final foreign = Context.getType(proof.typeId == "model.Payload" ? "model.OtherPayload" : "model.Payload");
						if (plan.decisionFor({expr: expression.expr, pos: expression.pos, t: foreign}) != null)
							throw "Different nominal result matched the same call";
						count++;
					case _:
				}
				TypedExprTools.iter(expression, visit);
			}
			for (field in main.statics.get()) {
				final expression = field.expr();
				if (expression != null)
					visit(expression);
			}
			if (count != 8)
				throw 'Expected eight class-valued generic calls, got $count';
			Sys.println("GENERIC_CLASS_CALL_PROOFS:PASS");
		});
	}

	static function classType(name:String):ClassType {
		return switch (Context.getType(name)) {
			case TInst(reference, []): reference.get();
			case _: throw 'Expected ordinary class $name';
		};
	}

	static function registryFor(names:Array<String>):OcamlRepresentationRegistry {
		final registry = new OcamlRepresentationRegistry();
		registry.beginProgram("class-call-test");
		final context = new CompilationContext();
		context.virtualTypesComputed = true;
		final classes = names.map(classType);
		final modules:Map<String, Array<ClassType>> = [];
		for (type in classes)
			modules.set(type.module, [type]);
		OcamlMonomorphicClassPlanner.plan(classes.map(type -> type.module), modules, context, registry, _ -> true);
		return registry;
	}
}
