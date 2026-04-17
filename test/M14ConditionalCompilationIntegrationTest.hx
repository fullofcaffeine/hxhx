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
	}
}
