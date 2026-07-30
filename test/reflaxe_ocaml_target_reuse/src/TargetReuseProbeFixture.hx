#if macro
import haxe.macro.Context;
import reflaxe.BaseCompiler;
import reflaxe.ReflectCompiler;
import reflaxe.ocaml.OcamlCompiler;
#end

/**
	Checks the real Reflaxe-to-OCaml observation boundary during target startup.

	Registering this callback intentionally adds Reflaxe's unrevisioned-callback
	blocker. The fixture verifies that both framework and target blockers are
	present before any future replay implementation could inspect the probe.
**/
class TargetReuseProbeFixture {
	#if macro
	public static function install():Void {
		ReflectCompiler.onCompileBegin((compiler:BaseCompiler) -> {
			if (!Std.isOfType(compiler, OcamlCompiler))
				Context.fatalError("target reuse probe fixture received the wrong compiler", Context.currentPos());
			final ocaml:OcamlCompiler = cast compiler;
			final snapshot = ocaml.finalProgramFingerprint;
			final probe = ocaml.targetReuseProbe;
			final realm = ocaml.targetReuseCatalogRealm;
			if (snapshot == null || probe == null || probe.requestRevision == null || realm == null)
				Context.fatalError("OCaml target reuse observation was not sealed before target startup", Context.currentPos());
			if (probe.eligible)
				Context.fatalError("the incomplete OCaml target must not authorize source replay", Context.currentPos());
			final blockers = probe.blockers();
			for (required in [
				"reflaxe:unrevisioned-compile-begin-callback",
				"reflaxe.ocaml:lowering-report-enabled",
				"reflaxe.ocaml:observation-report-enabled",
				"reflaxe.ocaml:target-reuse-disabled"
			])
				if (!blockers.contains(required))
					Context.fatalError('OCaml target reuse probe is missing blocker "$required"', Context.currentPos());
		});
	}
	#end
}
