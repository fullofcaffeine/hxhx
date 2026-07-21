#if macro
import haxe.macro.Context;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan.OcamlStaticStorageDeclarationSite;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan.OcamlStaticStorageKind;

/** Focused executable checks for the pre-emission mutable-static storage plan. */
class StaticStoragePlanFixture {
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
			if (message.indexOf(expectedMessage) < 0)
				throw '$label failed with an unexpected message: $message';
		}
		if (!failed)
			throw '$label should have failed.';
	}

	static function registerInt(plan:OcamlStaticStoragePlan, owner:String, field:String, target:String, order:Int,
			declarationSite:OcamlStaticStorageDeclarationSite):Void {
		plan.register({
			moduleId: "Main",
			ownerTypeName: owner,
			fieldName: field,
			targetValueName: target,
			semanticTypeId: "Int",
			carrierTypeId: "int",
			fieldType: Context.typeof(macro(0 : Int)),
			carrierType: OcamlTypeExpr.TIdent("int"),
			kind: OcamlStaticStorageKind.Variable,
			declarationSite: declarationSite,
			declarationTypeName: null,
			declarationTypeOrder: -1,
			ownerTypeOrder: order,
			declarationOrder: order,
			initializationOrder: order,
			hasInitializer: true,
			representationId: declarationSite == OcamlStaticStorageDeclarationSite.ModulePrelude ? "representation:Int:static-field" : null
		});
	}

	static function registerTypePrelude(plan:OcamlStaticStoragePlan):Void {
		plan.register({
			moduleId: "Main",
			ownerTypeName: "Main",
			fieldName: "pending",
			targetValueName: "pending",
			semanticTypeId: "Worker",
			carrierTypeId: "worker_t",
			fieldType: Context.typeof(macro(0 : Int)),
			carrierType: OcamlTypeExpr.TIdent("worker_t"),
			kind: OcamlStaticStorageKind.Variable,
			declarationSite: OcamlStaticStorageDeclarationSite.TypePrelude,
			declarationTypeName: "Worker",
			declarationTypeOrder: 0,
			ownerTypeOrder: 1,
			declarationOrder: 2,
			initializationOrder: 2,
			hasInitializer: false,
			representationId: null
		});
	}

	/** Runs during compilation so exact Haxe field types are available. */
	public static function run():Void {
		final plan = new OcamlStaticStoragePlan();
		expectFailure("unstarted plan", "beginProgram", () -> plan.seal());
		plan.beginProgram("program:static-storage-fixture");
		plan.registerTypeOrder("Main", "Worker", 0);
		plan.registerTypeOrder("Main", "Main", 1);
		registerInt(plan, "Main", "value", "value", 1, OcamlStaticStorageDeclarationSite.ModulePrelude);
		registerInt(plan, "Worker", "counter", "worker_counter", 0, OcamlStaticStorageDeclarationSite.OwnerBinding);
		registerTypePrelude(plan);
		plan.seal();

		final entries = plan.entriesForModule("Main");
		assertTrue(entries.length == 3
			&& entries[0].ownerTypeName == "Worker"
			&& entries[1].fieldName == "value"
			&& entries[2].fieldName == "pending",
			"module entries should preserve deterministic declaration order");
		assertTrue(plan.hasModulePrelude("Main", "Main", "value"), "the selected early cell should be visible to preceding type fragments");
		assertTrue(!plan.hasModulePrelude("Main", "Worker", "counter"), "an owner binding must not be reported as an early declaration");
		assertTrue(plan.isVisibleFrom("Main", "Main", "value", "Main", "Worker"), "a module-prelude cell should be visible from an earlier type");
		assertTrue(plan.isVisibleFrom("Main", "Worker", "counter", "Main", "Main"), "an owner binding should be visible from a later type in the same module");
		assertTrue(plan.isVisibleFrom("Main", "Main", "pending", "Main", "Worker"),
			"a type-prelude cell should be visible immediately after its carrier type declaration");
		final value = plan.require("Main", "Main", "value");
		assertTrue(value.targetValueName == "value"
			&& value.semanticTypeId == "Int"
			&& value.carrierTypeId == "int"
			&& value.initializationId == "static-initialization:Main::Main::value",
			"the plan should retain stable owner, target, type, carrier, and initialization identities");
		expectFailure("sealed mutation", "cannot change",
			() -> registerInt(plan, "Later", "value", "later_value", 2, OcamlStaticStorageDeclarationSite.OwnerBinding));
		expectFailure("missing entry", "no pre-emission storage decision", () -> plan.require("Main", "Missing", "value"));

		final collision = new OcamlStaticStoragePlan();
		collision.beginProgram("program:static-storage-collision");
		collision.registerTypeOrder("Main", "First", 0);
		collision.registerTypeOrder("Main", "Second", 1);
		registerInt(collision, "First", "value", "shared", 0, OcamlStaticStorageDeclarationSite.OwnerBinding);
		expectFailure("target collision", "target-name-collision",
			() -> registerInt(collision, "Second", "value", "shared", 1, OcamlStaticStorageDeclarationSite.OwnerBinding));

		final unavailable = new OcamlStaticStoragePlan();
		unavailable.beginProgram("program:static-storage-unavailable");
		unavailable.registerTypeOrder("Main", "Worker", 0);
		unavailable.registerTypeOrder("Main", "Main", 1);
		registerInt(unavailable, "Main", "late", "late", 1, OcamlStaticStorageDeclarationSite.OwnerBinding);
		unavailable.seal();
		assertTrue(!unavailable.isVisibleFrom("Main", "Main", "late", "Main", "Worker"),
			"a cell declared with a later owner must not be admitted from an earlier type");

		final repeated = new OcamlStaticStoragePlan();
		repeated.beginProgram("program:static-storage-fixture");
		repeated.registerTypeOrder("Main", "Main", 1);
		repeated.registerTypeOrder("Main", "Worker", 0);
		registerInt(repeated, "Worker", "counter", "worker_counter", 0, OcamlStaticStorageDeclarationSite.OwnerBinding);
		registerInt(repeated, "Main", "value", "value", 1, OcamlStaticStorageDeclarationSite.ModulePrelude);
		registerTypePrelude(repeated);
		repeated.seal();
		assertTrue(repeated.revision() == plan.revision(), "registration order should not change the sealed plan revision");

		Sys.println("REFLAXE_OCAML_STATIC_STORAGE_PLAN_FIXTURE:PASS");
	}
}
#end
