import backend.BackendRegistry;
import hxhx.BackendPluginLoadRequest;
import hxhx.BackendPluginLoader;
import hxhx.BackendPluginSource;

class M14BackendPluginLoaderIntegrationTest {
	static final keepBundledProvider = M14LoaderBundledProvider;
	static final keepExplicitProvider = M14LoaderExplicitProvider;
	static final keepDuplicateProvider = M14LoaderDuplicateBundledProvider;

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertFailsContains(fn:Void->Void, expected:String):Void {
		var message = "";
		try {
			fn();
		} catch (error:haxe.Exception) {
			message = error.message;
		}
		assertTrue(message.length > 0, "expected failing call with message containing: " + expected);
		assertTrue(message.indexOf(expected) >= 0, "error mismatch: " + message);
	}

	static function main():Void {
		BackendRegistry.clearDynamicRegistrations();

		final requests:Array<BackendPluginLoadRequest> = [
			{
				source: BackendPluginSource.Bundled,
				providerType: "M14LoaderBundledProvider",
				origin: "bundled-provider:M14LoaderBundledProvider"
			},
			{
				source: BackendPluginSource.Explicit,
				providerType: "M14LoaderExplicitProvider",
				origin: "explicit-provider:M14LoaderExplicitProvider"
			}
		];

		final regs = BackendPluginLoader.registrationsForRequests(requests);
		assertTrue(regs.length == 1, "explicit request should override bundled request for shared implId");
		assertTrue(regs[0].descriptor.implId == "plugin/js-native@loader-shared", "unexpected implId resolved from loader");
		assertTrue(regs[0].descriptor.priority >= (BackendPluginLoader.SOURCE_PRIORITY_STEP * 2), "explicit source tier priority band not applied");

		final registered = BackendRegistry.registerProvider(regs);
		assertTrue(registered == 1, "expected one plugin registration");
		final selected = BackendRegistry.requireForTarget("js-native");
		assertTrue(selected.describe() == "Explicit loader fixture", "explicit plugin should win loader precedence");
		BackendRegistry.clearDynamicRegistrations();

		assertFailsContains(function() BackendPluginLoader.registrationsForRequests([
			{
				source: BackendPluginSource.Bundled,
				providerType: "M14LoaderBundledProvider",
				origin: "bundled-provider:M14LoaderBundledProvider"
			},
			{
				source: BackendPluginSource.Bundled,
				providerType: "M14LoaderDuplicateBundledProvider",
				origin: "bundled-provider:M14LoaderDuplicateBundledProvider"
			}
		]), "duplicate backend plugin implementation id");

		assertFailsContains(function() BackendPluginLoader.registrationsForRequests([
			{
				source: BackendPluginSource.Explicit,
				providerType: "does.not.Exist",
				origin: "explicit-provider:does.not.Exist"
			}
		]), "backend provider type not found");
	}
}
