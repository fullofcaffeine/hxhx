import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

using StringTools;

/** Focused checks for runtime explanations recorded at compiler decision points. **/
class RuntimeRequirementLedgerFixture {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectFailure(label:String, expectedMessage:String, action:Void->Void):Void {
		var failed = false;
		try {
			action();
		} catch (error:Dynamic) {
			failed = true;
			final message = Std.string(error);
			if (!message.contains(expectedMessage))
				throw '$label failed with an unexpected message: $message';
		}
		if (!failed)
			throw '$label should have failed.';
	}

	static function requirementById(requirements:Array<OcamlRuntimeRequirement>, id:String):OcamlRuntimeRequirement {
		for (requirement in requirements)
			if (requirement.id == id)
				return requirement;
		throw 'Missing runtime requirement "$id".';
	}

	static function main():Void {
		final macHaxePath = ["", "Users", "alice", "haxe", "versions", "4.3.7", "std", "haxe", "Exception.hx"].join("/");
		assertTrue(OcamlLoweredOrigin.normalizeSourcePath(macHaxePath) == "haxe-stdlib/haxe/Exception.hx",
			"upstream Haxe paths should not retain a home-directory prefix");
		assertTrue(OcamlLoweredOrigin.normalizeSourcePath("C:\\HaxeToolkit\\haxe\\std\\haxe\\Exception.hx") == "haxe-stdlib/haxe/Exception.hx",
			"Windows Haxe paths should use the same stable standard-library identity");
		assertTrue(OcamlLoweredOrigin.normalizeSourcePath("/opt/cache/acme/src/acme/Thing.hx") == "external-source/acme/Thing.hx",
			"external libraries should keep useful package context without a machine-local prefix");
		assertTrue(OcamlLoweredOrigin.normalizeSourcePath(Sys.getCwd() + "/src/Main.hx") == "src/Main.hx",
			"project source should retain its repository-relative path");
		assertTrue(OcamlLoweredOrigin.normalizeSourcePath("../../private/acme/Thing.hx") == "external-source/acme/Thing.hx",
			"parent-directory segments should not leak a path outside the project");
		final source:OcamlLoweredSourceSpan = {file: "../../private/acme/Thing.hx", min: 10, max: 18};
		expectFailure("record before program", "before the program revision begins", () -> {
			final unbound = new OcamlRuntimeRequirementLedger();
			unbound.recordPlacePlan("place:a:int-update", "place:a", source, "Int", ["place:a:runtime:haxe-int32-add"]);
		});
		final ledger = new OcamlRuntimeRequirementLedger();
		ledger.beginProgram("program:fixture-a");
		ledger.recordPlacePlan("place:a:int-update", "place:a", source, "Int", ["place:a:runtime:haxe-int32-add"]);
		ledger.recordPlacePlan("place:b:array-update", "place:b", source, "Int", [
			"place:b:runtime:haxe-array-element-get",
			"place:b:runtime:haxe-int32-add",
			"place:b:runtime:haxe-array-element-set"
		]);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.CORE_RUNTIME);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_NULL);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_RUNTIME_UNBOX);
		final requirements = ledger.requirementsSorted();
		assertTrue(requirements.length == 9, "each lowering and compiler decision should retain its own runtime explanation");
		assertTrue(requirements[0].id == "compiler:generated:HxTypeRegistry:dynamic-arguments", "requirements should be sorted by stable identity");
		final placeRequirement = requirementById(requirements, "place:a:runtime:haxe-int32-add");
		assertTrue(placeRequirement.sourceId == "place:a", "the requirement should retain its Haxe-expression identity");
		assertTrue(placeRequirement.subject.kind == OcamlRuntimeRequirementSubjectKind.HaxeType && placeRequirement.subject.id == "Int",
			"a Haxe operation should identify the semantic type it supports");
		assertTrue(placeRequirement.source.file == "external-source/acme/Thing.hx",
			"the ledger should remove machine-local parent paths before retaining a source location");
		assertTrue(placeRequirement.decisionId == "place:a:int-update", "the requirement should name the lowering decision that caused it");
		assertTrue(placeRequirement.rootModules[0] == "HxInt", "Haxe Int addition should select the HxInt implementation root");
		final registryRequirement = requirementById(requirements, "compiler:generated:HxTypeRegistry:type-registry");
		assertTrue(registryRequirement.subject.kind == OcamlRuntimeRequirementSubjectKind.GeneratedModule
			&& registryRequirement.subject.id == "HxTypeRegistry",
			"compiler-generated output should identify the module it supports");
		assertTrue(registryRequirement.rootModules[0] == "HxType", "the generated type registry should select the HxType implementation root");
		final coreRequirement = requirementById(requirements, "compiler:runtime-packaging:core");
		assertTrue(coreRequirement.subject.kind == OcamlRuntimeRequirementSubjectKind.CompilerPolicy
			&& coreRequirement.subject.id == "runtime-packaging",
			"the runtime core should name the compiler policy that requires it");
		assertTrue(ledger.rootModulesSorted().join(",") == "HxArray,HxInt,HxRuntime,HxType", "root modules should be deduplicated and sorted");
		final firstRevision = ledger.revision();
		ledger.recordPlacePlan("place:a:int-update", "place:a", source, "Int", ["place:a:runtime:haxe-int32-add"]);
		assertTrue(ledger.revision() == firstRevision, "recording the same facts twice should be deterministic");

		expectFailure("unscoped requirement", "is not scoped to origin",
			() -> ledger.recordPlacePlan("place:c:update", "place:c", source, "Int", ["haxe-int32-add"]));
		expectFailure("unknown capability", "Unknown place runtime capability",
			() -> ledger.recordPlacePlan("place:c:update", "place:c", source, "Int", ["place:c:runtime:not-supported"]));
		expectFailure("unknown compiler capability", "Unknown compiler runtime capability",
			() -> ledger.recordCompilerInfrastructure("compiler-not-supported"));
		expectFailure("subject/source mismatch", "does not match source kind", () -> ledger.record({
			id: "invalid:subject",
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: "place:invalid",
			source: source,
			semanticCapability: "invalid-subject-fixture",
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: "fixture:invalid-subject",
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
				id: "WrongOwner"
			},
			implementationFeature: "invalid-fixture-v1",
			rootModules: ["HxRuntime"],
			profileEligibility: ["portable"],
			explanation: "This intentionally invalid record proves subject ownership is checked."
		}));
		ledger.beginProgram("program:fixture-b");
		assertTrue(ledger.requirementsSorted().length == 0, "a new program must not inherit requirements from the previous compile");
		assertTrue(ledger.revision() != firstRevision, "the requirement revision must identify its normalized program");
		Sys.println("REFLAXE_OCAML_RUNTIME_REQUIREMENT_LEDGER_FIXTURE:PASS");
	}
}
