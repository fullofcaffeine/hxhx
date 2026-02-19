import M14ResolverCtorFailureProvider;
import M14ResolverFixtureProvider;
import M14ResolverInvalidProvider;
import hxhx.BackendProviderResolver;

class M14BackendProviderResolverIntegrationTest {
	static final keepFixtureProvider = M14ResolverFixtureProvider;
	static final keepInvalidProvider = M14ResolverInvalidProvider;
	static final keepCtorFailureProvider = M14ResolverCtorFailureProvider;

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition) throw message;
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
		final known = BackendProviderResolver.registrationsForType("backend.js.JsBackend");
		assertTrue(known.length == 1, "known provider should return one registration");
		assertTrue(known[0].descriptor.implId == "provider/js-native-wrapper", "unexpected known provider impl id");

		final custom = BackendProviderResolver.registrationsForType("M14ResolverFixtureProvider");
		assertTrue(custom.length == 1, "custom provider should return one registration");
		assertTrue(custom[0].descriptor.implId == "plugin/js-native@fixture", "unexpected custom provider impl id");

		assertFailsContains(
			function() BackendProviderResolver.registrationsForType("does.not.Exist"),
			"backend provider type not found"
		);
		assertFailsContains(
			function() BackendProviderResolver.registrationsForType("M14ResolverInvalidProvider"),
			"must implement ITargetBackendProvider"
		);
		assertFailsContains(
			function() BackendProviderResolver.registrationsForType("M14ResolverCtorFailureProvider"),
			"construction failed"
		);
	}
}
