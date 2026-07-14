package hxhx.macro;

import hxhxmacrohost.NativeMacroModuleActivation;
import hxhxmacrohost.NativeMacroModuleReceipt;

/**
	Activates the optional project-macro plugin selected by its validated receipt.

	Receipt validation is shared by both macro modes. This helper then asks the selected runtime to
	load the artifact and requires the plugin's actual registration list to match the receipt exactly.
	A mismatch is fatal; it never falls back to an installed Haxe compiler.
**/
class NativeMacroModuleRuntimeLoader {
	public static function loadConfigured(artifactKind:String, loadModule:(String, String) -> Array<String>):Null<NativeMacroModuleActivation> {
		final activation = NativeMacroModuleReceipt.loadFromEnvironment(artifactKind);
		if (activation == null)
			return null;
		final actualExpressions = loadModule(activation.artifactPath, activation.pluginId);
		if (actualExpressions.length != activation.expressions.length)
			throw "native macro module receipt: registered expression count mismatch for plugin `"
				+ activation.pluginId
				+ "` (receipt="
				+ activation.expressions.length
				+ ", module="
				+ actualExpressions.length
				+ ")";
		for (idx in 0...activation.expressions.length) {
			final expected = activation.expressions[idx];
			final actual = actualExpressions[idx];
			if (actual != expected)
				throw "native macro module receipt: registered expression mismatch at index "
					+ idx
					+ " (receipt=`"
					+ expected
					+ "`, module=`"
					+ actual
					+ "`)";
		}
		return activation;
	}
}
