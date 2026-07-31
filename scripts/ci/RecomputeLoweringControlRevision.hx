import haxe.Json;
import haxe.crypto.Sha256;
import sys.io.File;

/**
 * Recomputes the control-section integrity hash in a deliberately edited
 * lowering report.
 *
 * Corruption fixtures change one control decision so the public inspector can
 * test the decision's semantic validation. The report must first receive a
 * matching integrity hash; otherwise inspection correctly stops at the earlier
 * stale-hash check. This helper uses Haxe's own JSON serializer, which is the
 * serializer used by both the report writer and the inspector.
 */
class RecomputeLoweringControlRevision {
	/**
	 * Updates the single report path supplied on the command line.
	 */
	static function main():Void {
		final arguments = Sys.args();
		if (arguments.length != 1)
			throw "Usage: RecomputeLoweringControlRevision <ocaml_lowering_report.json>";

		final report:Dynamic = Json.parse(File.getContent(arguments[0]));
		final canonicalControls = Json.stringify({
			targets: Reflect.field(report, "controlTargets"),
			decisions: Reflect.field(report, "controls"),
			catchChains: Reflect.field(report, "controlCatches")
		});
		Reflect.setField(report, "controlRevision", "sha256:" + Sha256.encode(canonicalControls));
		File.saveContent(arguments[0], Json.stringify(report, null, "  ") + "\n");
	}
}
