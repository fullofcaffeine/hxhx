import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;

class M14ConditionalCompilationIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + " (missing `" + needle + "`)";
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) >= 0)
			throw label + " (unexpected `" + needle + "`)";
	}

	static function assertTrue(condition:Bool, label:String):Void {
		if (!condition)
			throw label;
	}

	static function defines(values:Array<String>):StringMap<String> {
		final out = new StringMap<String>();
		for (value in values)
			out.set(value, "1");
		return out;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function ensureDirectory(path:String):Void {
		if (!FileSystem.exists(path))
			FileSystem.createDirectory(path);
	}

	static function modulePaths(modules:Array<ResolvedModule>):String {
		final out = [];
		for (m in modules)
			out.push(ResolvedModule.getModulePath(m));
		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return out.join(",");
	}

	static function testInactiveTargetQualifiedDeps():Void {
		final tmpRoot = haxe.io.Path.normalize(".tmp/m14_conditional_compilation_" + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, "src"]);
		final haxeDir = haxe.io.Path.join([srcDir, "haxe"]);
		final phpDir = haxe.io.Path.join([srcDir, "php"]);
		deleteRecursive(tmpRoot);
		ensureDirectory(tmpRoot);
		ensureDirectory(srcDir);
		ensureDirectory(haxeDir);
		ensureDirectory(phpDir);

		File.saveContent(haxe.io.Path.join([srcDir, "Main.hx"]), [
			"class Main {",
			"  static function main():Void {",
			"    haxe.Serializer.run(null);",
			"  }",
			"}",
		].join("\n"));
		File.saveContent(haxe.io.Path.join([haxeDir, "Serializer.hx"]), [
			"package haxe;",
			"class Serializer {",
			"  public static function run(v:Dynamic):Bool {",
			"    return php.Global.method_exists(v, \"hxSerialize\");",
			"  }",
			"}",
		].join("\n"));
		File.saveContent(haxe.io.Path.join([phpDir, "Global.hx"]), [
			"package php;",
			"class Global {",
			"  public static function method_exists(v:Dynamic, name:String):Bool return false;",
			"}",
		].join("\n"));

		var thrown:Dynamic = null;
		try {
			final resolved = ResolverStage.parseProjectRoots([srcDir], ["Main"], defines(["js"]));
			final paths = modulePaths(resolved);
			assertContains(paths, "haxe.Serializer", "JS resolver should keep active qualified haxe deps");
			assertNotContains(paths, "php.Global", "JS resolver should skip inactive target qualified deps found only by heuristic scans");

			final index = new TyperIndex();
			final loader = new ModuleLoader([srcDir], defines(["js"]), index);
			loader.ensureTypeAvailable("haxe.Serializer", "", []);
			final lazyPaths = modulePaths(loader.drainNewModules());
			assertContains(lazyPaths, "haxe.Serializer", "JS module loader should load the requested module");
			assertNotContains(lazyPaths, "php.Global", "JS module loader should skip inactive target qualified deps found only by heuristic scans");
		} catch (e:Dynamic) {
			thrown = e;
		}

		if (thrown != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw thrown;
		}
		deleteRecursive(tmpRoot);
	}

	static function testActiveTargetNativeExternImports():Void {
		final tmpRoot = haxe.io.Path.normalize(".tmp/m14_conditional_compilation_target_extern_" + Std.string(Date.now().getTime()));
		final javaStdDir = haxe.io.Path.join([tmpRoot, "java_std"]);
		final csStdDir = haxe.io.Path.join([tmpRoot, "cs_std"]);
		deleteRecursive(tmpRoot);
		ensureDirectory(tmpRoot);
		ensureDirectory(javaStdDir);
		ensureDirectory(csStdDir);

		File.saveContent(haxe.io.Path.join([javaStdDir, "String.hx"]), [
			"import java.lang.CharSequence;",
			"class String {",
			"  public static function accepts(value:CharSequence):Void {}",
			"}",
		].join("\n"));
		File.saveContent(haxe.io.Path.join([csStdDir, "Type.hx"]), [
			"import cs.system.Type;",
			"class Type {",
			"  public static function accepts(value:cs.system.Type):Void {}",
			"}",
		].join("\n"));

		var thrown:Dynamic = null;
		try {
			final javaResolved = ResolverStage.parseProjectRoots([javaStdDir], ["String"], defines(["java"]));
			final javaPaths = modulePaths(javaResolved);
			assertContains(javaPaths, "String", "active Java std override should resolve root String");
			assertNotContains(javaPaths, "java.lang.CharSequence", "active Java extern import should not require a .hx module");

			final csResolved = ResolverStage.parseProjectRoots([csStdDir], ["Type"], defines(["cs"]));
			final csPaths = modulePaths(csResolved);
			assertContains(csPaths, "Type", "active C# std override should resolve root Type");
			assertNotContains(csPaths, "cs.system.Type", "active C# extern import should not require a .hx module");
		} catch (e:Dynamic) {
			thrown = e;
		}

		if (thrown != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw thrown;
		}

		var inactiveFailed = false;
		try {
			ResolverStage.parseProjectRoots([javaStdDir], ["String"], defines(["cs"]));
		} catch (e:Dynamic) {
			inactiveFailed = Std.string(e).indexOf("import_missing java.lang.CharSequence") >= 0;
		}
		deleteRecursive(tmpRoot);
		assertTrue(inactiveFailed, "inactive target extern imports should still fail like ordinary missing imports");
	}

	static function testActiveNativeLibraryExternImports():Void {
		final tmpRoot = haxe.io.Path.normalize(".tmp/m14_conditional_compilation_native_lib_extern_" + Std.string(Date.now().getTime()));
		final javaSrcDir = haxe.io.Path.join([tmpRoot, "java_src"]);
		final csSrcDir = haxe.io.Path.join([tmpRoot, "cs_src"]);
		final javaUnitDir = haxe.io.Path.join([javaSrcDir, "unit"]);
		final csUnitDir = haxe.io.Path.join([csSrcDir, "unit"]);
		deleteRecursive(tmpRoot);
		ensureDirectory(tmpRoot);
		ensureDirectory(javaSrcDir);
		ensureDirectory(csSrcDir);
		ensureDirectory(javaUnitDir);
		ensureDirectory(csUnitDir);

		File.saveContent(haxe.io.Path.join([javaUnitDir, "TestJava.hx"]), [
			"package unit;",
			"import haxe.test.Base.Base_InnerClass;",
			"class TestJava { public static function main():Void {} }",
		].join("\n"));
		File.saveContent(haxe.io.Path.join([csUnitDir, "TestCSharp.hx"]), [
			"package unit;",
			"import haxe.test.Base.Base_InnerClass;",
			"import NoPackage;",
			"class TestCSharp { public static function main():Void {} }",
		].join("\n"));

		var thrown:Dynamic = null;
		try {
			var javaWithoutLibFailed = false;
			try {
				ResolverStage.parseProjectRoots([javaSrcDir], ["unit.TestJava"], defines(["java"]));
			} catch (e:Dynamic) {
				javaWithoutLibFailed = Std.string(e).indexOf("import_missing haxe.test.Base.Base_InnerClass") >= 0;
			}
			assertTrue(javaWithoutLibFailed, "missing Java native-library import should stay strict without --java-lib evidence");

			final javaResolved = ResolverStage.parseProjectRoots([javaSrcDir], ["unit.TestJava"], defines(["java", "hxhx_java_lib"]));
			final javaPaths = modulePaths(javaResolved);
			assertContains(javaPaths, "unit.TestJava", "Java native-library root should resolve");
			assertNotContains(javaPaths, "haxe.test.Base.Base_InnerClass", "Java native-library extern import should not require a .hx module");

			var csWithoutLibFailed = false;
			try {
				ResolverStage.parseProjectRoots([csSrcDir], ["unit.TestCSharp"], defines(["cs"]));
			} catch (e:Dynamic) {
				csWithoutLibFailed = Std.string(e).indexOf("import_missing haxe.test.Base.Base_InnerClass") >= 0;
			}
			assertTrue(csWithoutLibFailed, "missing C# native-library import should stay strict without --net-lib evidence");

			final csResolved = ResolverStage.parseProjectRoots([csSrcDir], ["unit.TestCSharp"], defines(["cs", "hxhx_net_lib"]));
			final csPaths = modulePaths(csResolved);
			assertContains(csPaths, "unit.TestCSharp", "C# native-library root should resolve");
			assertNotContains(csPaths, "haxe.test.Base.Base_InnerClass", "C# native-library extern import should not require a .hx module");
			assertNotContains(csPaths, "unit.NoPackage", "C# no-package native-library extern import should not be rewritten into the current Haxe package");
			assertNotContains(csPaths, "NoPackage", "C# no-package native-library extern import should not require a .hx module");
		} catch (e:Dynamic) {
			thrown = e;
		}

		if (thrown != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw thrown;
		}
		deleteRecursive(tmpRoot);
	}

	static function testInlineInactiveModifierKeepsSuffix():Void {
		final luaInlineModifier = '#if (!java && !cpp && !lua && !eval) inline #end public static function urlDecode(s:String):String {';
		final luaModifierFiltered = HxConditionalCompilation.filterSource(luaInlineModifier, defines(["lua"]));
		assertContains(luaModifierFiltered, "public static function urlDecode", "inline conditional with no matching branch should preserve suffix after #end");
		assertNotContains(luaModifierFiltered, "inline", "inactive inline modifier should be blanked for lua");
		assertNotContains(luaModifierFiltered, "#if", "inline conditional directive should be blanked for lua");
		assertNotContains(luaModifierFiltered, "#end", "inline conditional terminator should be blanked for lua");

		final luaSource = [
			"class LuaFilteredCallback {",
			"  #if (!java && !cpp && !lua && !eval) inline #end public static function decode(s:String):String {",
			"    #if java",
			"    return s;",
			"    #elseif lua",
			'    s = lua.NativeStringTools.gsub(s, "%%(%x%x)", function(h) {',
			"      return lua.NativeStringTools.char(lua.Lua.tonumber(h, 16));",
			"    });",
			"    return s;",
			"    #end",
			"  }",
			"}",
		].join("\n");
		final luaFiltered = HxConditionalCompilation.filterSource(luaSource, defines(["lua"]));
		assertContains(luaFiltered, "public static function decode", "inline modifier filtering should leave the method declaration parseable");
		assertNotContains(luaFiltered, "#elseif", "block conditional directives should be blanked before parsing");
		ParserStage.parse(luaFiltered, "LuaFilteredCallback.hx");
	}

	static function testBlockConditionalEndWithSemicolonAfterInlineGuard():Void {
		final source = [
			"class ConditionalAsyncProbe {",
			"  static final ENABLED =",
			"    #if !github false && #end // local-only opt-in guard",
			"    #if (github && (java || flash || (cs && Windows)))",
			"      false",
			"    #elseif (js && !nodejs)",
			"      js.Browser.supported",
			"    #else",
			"      true",
			"    #end;",
			"",
			"  function run(done:()->Void, work:()->Void):Void {",
			"    if (ENABLED) {",
			"      work();",
			"      return;",
			"    }",
			"    done();",
			"  }",
			"",
			"  public function ping(done:()->Void):Void run(done, () -> {",
			"    final payload = 'ok';",
			"    if (payload != 'ok') throw payload;",
			"    done();",
			"  });",
			"}",
		].join("\n");
		final filtered = HxConditionalCompilation.filterSource(source, defines(["github", "js", "nodejs", "Linux"]));
		assertContains(filtered, "static final ENABLED", "static final initializer should remain after filtering");
		assertContains(filtered, "true", "nodejs/js branch should select the fallback payload");
		assertNotContains(filtered, "false &&", "inactive same-line guard payload should be blanked");
		assertNotContains(filtered, "js.Browser", "inactive target-specific branch should be blanked");
		assertNotContains(filtered, "#if", "block and inline conditionals should be blanked before parsing");
		assertNotContains(filtered, "#elseif", "elseif directives should be blanked before parsing");
		assertNotContains(filtered, "#end", "terminator directives with semicolon suffix should be blanked before parsing");
		ParserStage.parse(filtered, "ConditionalAsyncProbe.hx");
	}

	static function testConditionalObservation():Void {
		assertTrue(CompilerDependencyKindTools.name(CompilerDependencyKind.ConditionalCompilation) == "conditional-compilation"
			&& CompilerDependencyKindTools.name(CompilerDependencyKind.FeatureSelection) == "feature-selection",
			"conditional compilation should have distinct vocabulary from later @:ifFeature and DCE selection work");
		final source = [
			"class ConditionalObservation {",
			"  #if enabled || fallback",
			"  static final mode = 1;",
			"  #elseif mode == \"debug\"",
			"  static final mode = 2;",
			"  #else",
			"  static final mode = 3;",
			"  #end",
			"}",
		].join("\n");

		final enabledDefines = new StringMap<String>();
		enabledDefines.set("enabled", "private-value-not-for-reports");
		enabledDefines.set("fallback", "another-private-value");
		enabledDefines.set("unrelated", "a");
		final enabled = HxConditionalCompilation.filterSourceObserved(source, enabledDefines);
		assertContains(enabled.getFilteredSource(), "static final mode = 1", "observed filtering should keep the selected branch");
		assertTrue(enabled.getObservation().getObservedDefineNames().join(",") == "enabled",
			"short-circuit observation should record only the definition that was read");

		final unrelatedChange = new StringMap<String>();
		unrelatedChange.set("enabled", "private-value-not-for-reports");
		unrelatedChange.set("fallback", "changed-but-still-short-circuited");
		unrelatedChange.set("unrelated", "b");
		final unchanged = HxConditionalCompilation.filterSourceObserved(source, unrelatedChange);
		assertTrue(unchanged.getObservation().getCanonicalIdentity() == enabled.getObservation().getCanonicalIdentity(),
			"unused and short-circuited definition changes should not change conditional observation");
		final presenceOnlyValueChange = new StringMap<String>();
		presenceOnlyValueChange.set("enabled", "different-private-value");
		final samePresence = HxConditionalCompilation.filterSourceObserved(source, presenceOnlyValueChange);
		assertTrue(samePresence.getObservation().getCanonicalIdentity() == enabled.getObservation().getCanonicalIdentity(),
			"a plain #if name check should depend on presence rather than over-invalidating on an unused value change");

		final fallbackDefines = new StringMap<String>();
		fallbackDefines.set("fallback", "1");
		fallbackDefines.set("mode", "debug");
		final fallback = HxConditionalCompilation.filterSourceObserved(source, fallbackDefines);
		assertTrue(fallback.getObservation().getObservedDefineNames().join(",") == "enabled,fallback",
			"evaluation should record the fallback definition after the first operand becomes false");
		assertTrue(fallback.getObservation().changedDefineNames(enabled.getObservation()).join(",") == "enabled,fallback",
			"comparison should name changed definition keys without exposing values");
		assertTrue(fallback.getObservation().getCanonicalIdentity() != enabled.getObservation().getCanonicalIdentity(),
			"a changed conditional input set should produce a new observation identity");
		final debugDefines = new StringMap<String>();
		debugDefines.set("mode", "debug");
		final releaseDefines = new StringMap<String>();
		releaseDefines.set("mode", "release");
		final debug = HxConditionalCompilation.filterSourceObserved(source, debugDefines);
		final release = HxConditionalCompilation.filterSourceObserved(source, releaseDefines);
		assertTrue(debug.getObservation().getCanonicalIdentity() != release.getObservation().getCanonicalIdentity()
			&& release.getObservation().changedDefineNames(debug.getObservation()).join(",") == "mode",
			"an equality check should retain a private value revision and report only its changed key");

		final restored = HxConditionalCompilation.filterSourceObserved(source, enabledDefines);
		assertTrue(restored.getObservation().getCanonicalIdentity() == enabled.getObservation().getCanonicalIdentity(),
			"exact A to B to A conditional input should reproduce the original observation");

		final plain = HxConditionalCompilation.filterSourceObserved("class Plain {}", unrelatedChange);
		assertTrue(plain.getObservation().getObservedDefineNames().length == 0, "source without conditional directives should observe no definitions");
		assertTrue(plain.getObservation()
			.getCanonicalIdentity() == HxConditionalCompilation.filterSourceObserved("class Plain {}", enabledDefines)
			.getObservation()
			.getCanonicalIdentity(),
			"unrelated definitions should not affect source without conditional directives");
	}

	static function main():Void {
		final inlineElseIf = 'if (#if flash Flash.path() #elseif php php.Global.method_exists(v, "hxSerialize") #else v.hxSerialize != null #end) keep();';
		final jsFiltered = HxConditionalCompilation.filterSource(inlineElseIf, defines(["js"]));
		assertContains(jsFiltered, "v.hxSerialize != null", "inline #elseif chain should keep the #else branch for js");
		assertNotContains(jsFiltered, "php.Global", "inline inactive php #elseif branch should be blanked for js");
		assertNotContains(jsFiltered, "#elseif", "inline conditional directives should be blanked");

		final phpFiltered = HxConditionalCompilation.filterSource(inlineElseIf, defines(["php"]));
		assertContains(phpFiltered, "php.Global.method_exists", "inline #elseif chain should keep the matching php branch");
		assertNotContains(phpFiltered, "Flash.path", "inline inactive flash #if branch should be blanked for php");
		assertNotContains(phpFiltered, "v.hxSerialize", "inline #else branch should be blanked after a matching #elseif");

		testInactiveTargetQualifiedDeps();
		testActiveTargetNativeExternImports();
		testActiveNativeLibraryExternImports();
		testInlineInactiveModifierKeepsSuffix();
		testBlockConditionalEndWithSemicolonAfterInlineGuard();
		testConditionalObservation();
	}
}
