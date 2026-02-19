import backend.ocaml.OcamlStage3Backend;
import backend.ocaml.OcamlTargetCore;

class M14TargetCoreWiringIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function main():Void {
		final core = new OcamlTargetCore();
		assertTrue(core.coreId() == OcamlTargetCore.CORE_ID, "unexpected OCaml target core id");

		final backend = new OcamlStage3Backend();
		assertTrue(backend.id() == "ocaml-stage3", "unexpected backend id");
		assertTrue(OcamlStage3Backend.targetCore().coreId() == core.coreId(), "stage3 backend is not wired to OCaml target core");
	}
}
