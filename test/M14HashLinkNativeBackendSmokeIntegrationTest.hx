import backend.BackendContext;
import backend.BackendDispatchBoundary;
import backend.BackendRegistry;
import haxe.io.Path;

class M14HashLinkNativeBackendSmokeIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "` in `" + haystack + "`)";
	}

	static function assertFailsContains(fn:Void->Void, expected:String):Void {
		var message = "";
		try {
			fn();
		} catch (e:haxe.Exception) {
			message = e.message;
		} catch (e:String) {
			message = e;
		}
		assertContains(message, expected, "expected failure diagnostic");
	}

	static function program(source:String) {
		final parsed = ParserStage.parse(source, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function main():Void {
		final descriptor = BackendRegistry.descriptorForTarget("hl-native");
		assertTrue(descriptor != null, "expected hl-native descriptor");
		assertTrue(descriptor.implId == "builtin/hl-native-bytecode-boundary", "expected HashLink bytecode-boundary impl");
		assertTrue(descriptor.capabilities.supportsNoEmit, "HashLink boundary should support no-emit target selection");
		assertTrue(!descriptor.capabilities.supportsBuildExecutable, "HashLink boundary must not claim executable build support yet");

		final backend = BackendRegistry.createForTarget("hl-native");
		final context = new BackendContext(Path.join([".tmp", "m14_hashlink_native_backend_smoke"]), "main.hl", "Main", true, false,
			new haxe.ds.StringMap<String>());
		assertFailsContains(() -> BackendDispatchBoundary.emit(backend, program('class Main { static function main() { Sys.println("hello hl"); } }'), context),
			"HashLink native backend reached Stage3 dispatch, but hxhx does not yet have a HashLink bytecode emitter");
	}
}
