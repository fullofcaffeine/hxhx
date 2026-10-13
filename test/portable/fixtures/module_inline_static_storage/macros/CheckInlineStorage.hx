import haxe.macro.Context;
import reflaxe.ocaml.OcamlCompiler;

/** Check the storage decision itself, before generated text could hide an extra cell. */
class CheckInlineStorage {
	public static function install():Void {
		Context.onAfterGenerate(() -> {
			if (OcamlCompiler.instance.staticStoragePlan.entriesForModule("Left").length != 0)
				throw "inline constants acquired mutable static storage";
		});
	}
}
