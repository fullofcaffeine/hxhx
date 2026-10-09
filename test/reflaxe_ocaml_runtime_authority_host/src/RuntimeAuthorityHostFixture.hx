import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifest;

/**
	Require runtime-use validation in an ordinary compiled Haxe host.
	The fixture uses synthetic plan inputs, not source locations for a real program.
	It must compile without macro, eval, or reflaxe_runtime defines.
**/
class RuntimeAuthorityHostFixture {
	static final revision = OcamlRuntimeUseModel.planRevision({
		functionId: "fixture:nullable",
		programRevision: "program:fixture",
		bodyRevision: "body:fixture",
		pipelineRevision: "pipeline:fixture"
	});

	static function requirement(root:String = "HxRuntime"):OcamlRuntimeRequirement
		return {
			id: "requirement:nullable",
			sourceKind: RepresentationDecision,
			sourceId: "fixture:nullable",
			source: {file: "fixture/Main.hx", min: 0, max: 4},
			semanticCapability: "fixture-nullable-int",
			cause: RepresentationDecision,
			decisionId: "decision:nullable",
			subject: {kind: HaxeType, id: "Null<Int>"},
			implementationFeature: "fixture-nullable-unwrapping",
			rootModules: [root],
			profileEligibility: ["portable"],
			explanation: "Synthetic fixture checks ownership of one nullable integer runtime operation."
		};

	static function occurrence():OcamlRuntimeUseOccurrence
		return {
			id: "use:unwrap",
			planRevision: revision,
			ownerId: "fixture:nullable",
			requirementId: "requirement:nullable",
			domain: ExpressionIdentifier,
			exactSymbol: "HxRuntime.nullable_int_unwrap",
			role: "unwrap",
			order: 0,
			source: {
				file: "fixture/Main.hx",
				min: 0,
				max: 4
			},
			profileEligibility: ["portable"],
			cardinality: 1
		};

	static function authority(?finalOutput:OcamlFinalRuntimeUseAuthority, root:String = "HxRuntime"):OcamlRuntimeUseAuthority
		return new OcamlRuntimeUseAuthority(revision, "portable", [requirement(root)], [occurrence()], finalOutput);

	static function main():Void {
		checkSources();
		final finalOutput = new OcamlFinalRuntimeUseAuthority();
		finalOutput.beginProgram("program:fixture", "portable");
		final valid = authority(finalOutput);
		final expression = OcamlExpr.ERuntimeIdent(valid.expressionIdentifier("use:unwrap", revision, "HxRuntime.nullable_int_unwrap"));
		valid.reconcileExpression(expression);
		finalOutput.observeExpression(expression, "Main.ml");
		finalOutput.finishProgram();

		reject(() -> authority().expressionIdentifier("use:unwrap", "stale", "HxRuntime.nullable_int_unwrap"), "stale runtime use");
		reject(() -> authority(null, "HxInt").expressionIdentifier("use:unwrap", revision, "HxRuntime.nullable_int_unwrap"), "direct runtime root");
		reject(() -> authority().expressionIdentifier("use:unwrap", revision, "HxRuntime.is_null"), "wrong target symbol");
		reject(() -> authority().reconcileExpression(OcamlExpr.EIdent("HxRuntime.nullable_int_unwrap")), "plain private runtime reference");
		final duplicate = authority();
		final repeated = OcamlExpr.ERuntimeIdent(duplicate.expressionIdentifier("use:unwrap", revision, "HxRuntime.nullable_int_unwrap"));
		reject(() -> duplicate.reconcileExpression(OcamlExpr.ESeq([repeated, repeated])), "duplicate runtime use use:unwrap");

		final missing = new OcamlFinalRuntimeUseAuthority();
		missing.beginProgram("program:fixture", "portable");
		final incomplete = authority(missing);
		incomplete.reconcileExpression(OcamlExpr.ERuntimeIdent(incomplete.expressionIdentifier("use:unwrap", revision, "HxRuntime.nullable_int_unwrap")));
		reject(() -> missing.finishProgram(), "missing final runtime use");
		Sys.println("RUNTIME_AUTHORITY_HOST:PASS");
	}

	/** Use the real checked catalog; never infer dependencies from runtime source text. **/
	static function checkSources():Void {
		final args = Sys.args();
		if (args.length != 1)
			throw "Runtime authority host fixture requires its runtime source directory";
		final snapshot = RuntimeSourceManifest.load(args[0]);
		final selected = RuntimeSourceManifest.resolveClosure(snapshot, ["HxRuntime"], "portable", false);
		if (selected.length != 1
			|| selected[0].module != "HxRuntime"
			|| selected[0].files.length != 1
			|| selected[0].files[0].path != "HxRuntime.ml")
			throw "Nullable runtime root did not select its exact checked source";
		reject(() -> RuntimeSourceManifest.resolveClosure(snapshot, ["MissingFixtureModule"], "portable", false), "Unknown OCaml runtime module");
		final tooling = snapshot.modules.filter(module -> module.scope == RuntimeSourceManifest.TOOLING_SCOPE);
		if (tooling.length == 0)
			throw "Runtime source fixture lost its tooling-only negative case";
		reject(() -> RuntimeSourceManifest.resolveClosure(snapshot, [tooling[0].module], "portable", false), "tooling-only");
	}

	static function reject(action:() -> Void, expected:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) >= 0)
				return;
			throw error;
		}
		throw "Expected runtime-authority rejection: " + expected;
	}
}
