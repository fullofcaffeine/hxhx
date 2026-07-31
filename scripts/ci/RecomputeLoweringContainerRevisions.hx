import haxe.Json;
import haxe.crypto.Sha256;
import sys.io.File;

/**
 * Recomputes container-conversion integrity hashes in an intentionally edited
 * lowering report.
 *
 * Corruption fixtures remove or alter one semantic record and then ask the
 * public inspector to reject the deeper ownership error. Refreshing the three
 * surrounding section hashes prevents the test from stopping at a generic
 * stale-hash diagnostic. This helper uses the same Haxe JSON serializer as the
 * report writer and inspector.
 */
class RecomputeLoweringContainerRevisions {
	/** Updates the single lowering-report path supplied on the command line. */
	static function main():Void {
		final arguments = Sys.args();
		if (arguments.length != 1)
			throw "Usage: RecomputeLoweringContainerRevisions <ocaml_lowering_report.json>";

		final report:Dynamic = Json.parse(File.getContent(arguments[0]));
		recompute(report, "containerElementConversionRevision", "containerElementConversions");
		recompute(report, "unsafeOperationRevision", "unsafeOperations");
		recompute(report, "runtimeRequirementRevision", "runtimeRequirements");
		File.saveContent(arguments[0], Json.stringify(report, null, "  ") + "\n");
	}

	/** Hashes one report array with the compiler's canonical serializer. */
	static function recompute(report:Dynamic, revisionField:String, inventoryField:String):Void {
		final inventory = Reflect.field(report, inventoryField);
		Reflect.setField(report, revisionField, "sha256:" + Sha256.encode(Json.stringify(inventory)));
	}
}
