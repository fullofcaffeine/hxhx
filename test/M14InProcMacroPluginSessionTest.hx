import hxhx.macro.InProcMacroSession;

/**
	One in-process compilation session loads at most one project-macro plugin.

	Loading a plugin clears the native registration table before Dynlink runs
	(`HxHxMacroModuleDynlink.load_and_capture`), while the session keeps the
	declarations it already accepted. A second load would leave the session
	believing earlier declarations are still callable. The plan allows one
	plugin per project, so a second load is rejected before anything is loaded.
**/
class M14InProcMacroPluginSessionTest {
	static function failureOf(action:Void->Void):String {
		try {
			action();
		} catch (error:String) {
			return error;
		}
		return "";
	}

	static function main():Void {
		final session = new InProcMacroSession();
		// Outside an OCaml-native compiler the load itself fails, but it still uses the session's one plugin slot.
		final first = failureOf(() -> session.loadNativeModule("first.cma", "fixture.first"));
		if (first.indexOf("OCaml-native") < 0)
			throw "first load did not reach the native loader: " + first;
		final second = failureOf(() -> session.loadNativeModule("second.cma", "fixture.second"));
		if (second.indexOf("one project macro plugin per compilation") < 0)
			throw "a second plugin load was not rejected: " + second;
		Sys.println("M14_INPROC_MACRO_PLUGIN_SESSION:PASS");
	}
}
