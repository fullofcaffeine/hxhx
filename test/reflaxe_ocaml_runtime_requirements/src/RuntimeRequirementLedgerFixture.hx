import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

using StringTools;

/** Focused checks for source-rooted runtime explanations. **/
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
		final requirements = ledger.requirementsSorted();
		assertTrue(requirements.length == 4, "each lowering decision should retain its own runtime explanation");
		assertTrue(requirements[0].id == "place:a:runtime:haxe-int32-add", "requirements should be sorted by stable identity");
		assertTrue(requirements[0].sourceId == "place:a", "the requirement should retain its Haxe-expression identity");
		assertTrue(requirements[0].source.file == "external-source/acme/Thing.hx",
			"the ledger should remove machine-local parent paths before retaining a source location");
		assertTrue(requirements[0].decisionId == "place:a:int-update", "the requirement should name the lowering decision that caused it");
		assertTrue(requirements[0].rootModules[0] == "HxInt", "Haxe Int addition should select the HxInt implementation root");
		assertTrue(requirements[1].rootModules[0] == "HxArray", "Haxe array access should select the HxArray implementation root");
		assertTrue(ledger.rootModulesSorted().join(",") == "HxArray,HxInt", "root modules should be deduplicated and sorted");
		final firstRevision = ledger.revision();
		ledger.recordPlacePlan("place:a:int-update", "place:a", source, "Int", ["place:a:runtime:haxe-int32-add"]);
		assertTrue(ledger.revision() == firstRevision, "recording the same facts twice should be deterministic");

		expectFailure("unscoped requirement", "is not scoped to origin",
			() -> ledger.recordPlacePlan("place:c:update", "place:c", source, "Int", ["haxe-int32-add"]));
		expectFailure("unknown capability", "Unknown place runtime capability",
			() -> ledger.recordPlacePlan("place:c:update", "place:c", source, "Int", ["place:c:runtime:not-supported"]));
		ledger.beginProgram("program:fixture-b");
		assertTrue(ledger.requirementsSorted().length == 0, "a new program must not inherit requirements from the previous compile");
		assertTrue(ledger.revision() != firstRevision, "the requirement revision must identify its normalized program");
		Sys.println("REFLAXE_OCAML_RUNTIME_REQUIREMENT_LEDGER_FIXTURE:PASS");
	}
}
