import backend.cpp.CppRenderScope;
import backend.cpp.CppTargetCore;

/** Nested rendering must restore representation facts even when the child rejects source. */
class M14CppLocalScopeRestorationTest {
	static function scope():CppRenderScope {
		final owner = new HxClassDecl("ScopeOwner", false, [], []);
		final lookup = {names: new haxe.ds.StringMap<Bool>(), byName: new haxe.ds.StringMap<HxClassDecl>()};
		return @:privateAccess CppTargetCore.renderScope(owner, lookup, "void");
	}

	static function facts(scope:CppRenderScope):Array<haxe.ds.StringMap<String>> {
		return [
			scope.localTypes,
			scope.localTypeHints,
			scope.localNames,
			scope.argTypeOverrides,
			scope.localTypeOverrides
		];
	}

	static function seed(scope:CppRenderScope):Void {
		for (map in facts(scope))
			map.set("outer", "original");
		scope.localNameCounts.set("outer", 3);
	}

	static function change(scope:CppRenderScope):Void {
		for (map in facts(scope)) {
			map.set("outer", "child");
			map.set("inner", "child");
		}
		scope.localNameCounts.set("outer", 9);
		scope.localNameCounts.set("inner", 1);
	}

	static function assertRestored(scope:CppRenderScope, failed:Bool):Void {
		for (map in facts(scope))
			if (map.get("outer") != "original" || map.exists("inner"))
				throw "Nested C++ scope leaked child facts; rejected=" + failed;
		if (scope.localNameCounts.get("outer") != 3 || scope.localNameCounts.exists("inner"))
			throw "Nested C++ scope leaked legacy probe allocation state";
	}

	public static function run():Void {
		assertBindingRestoration();
		assertInferenceOutputs();
		for (failed in [false, true]) {
			final current = scope();
			seed(current);
			var rejected = false;
			try {
				@:privateAccess CppTargetCore.withLocalScope(current, () -> {
					change(current);
					if (failed)
						throw "child rejection";
				});
			} catch (error:haxe.Exception) {
				if (error.message != "child rejection")
					throw error;
				rejected = true;
			}
			if (rejected != failed)
				throw "Nested C++ scope changed rejection behavior";
			assertRestored(current, failed);
		}
		Sys.println("CPP_LOCAL_SCOPE_RESTORATION:PASS");
	}

	/** Failed analysis must not publish partial overrides; successful analysis retains them. */
	static function assertInferenceOutputs():Void {
		for (failed in [false, true]) {
			final current = scope();
			seed(current);
			var rejected = false;
			try {
				backend.cpp.CppLocalScope.inferOverrides(current, () -> {
					change(current);
					if (failed)
						throw "analysis rejection";
				});
			} catch (error:haxe.Exception) {
				if (error.message != "analysis rejection")
					throw error;
				rejected = true;
			}
			if (rejected != failed)
				throw "C++ analysis scope changed rejection behavior";
			if (!failed) {
				for (map in [current.argTypeOverrides, current.localTypeOverrides]) {
					if (map.get("outer") != "child" || map.get("inner") != "child")
						throw "C++ analysis scope lost successful overrides";
					map.set("outer", "original");
					map.remove("inner");
				}
			}
			assertRestored(current, failed);
		}
	}

	/** A binding scope restores its own keys while retaining discoveries about captures. */
	static function assertBindingRestoration():Void {
		for (failed in [false, true]) {
			final current = scope();
			seed(current);
			var rejected = false;
			try {
				backend.cpp.CppLocalScope.withBinding(current, "outer", "int", () -> {
					change(current);
					if (failed)
						throw "binding rejection";
				});
			} catch (error:haxe.Exception) {
				if (error.message != "binding rejection")
					throw error;
				rejected = true;
			}
			for (map in facts(current))
				if (map.get("outer") != "original" || map.get("inner") != "child")
					throw "C++ binding scope lost captured inference or leaked its own facts";
			if (rejected != failed || current.localNameCounts.get("outer") != 3 || current.localNameCounts.get("inner") != 1)
				throw "C++ binding scope changed rejection or allocation facts";
		}
	}

	static function main():Void
		run();
}
