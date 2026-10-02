import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Secondary types and member lookups must load their source module only once. */
class M14ModuleFallbackIdentityIntegrationTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function main():Void {
		final root = ".tmp/module_fallback_" + Date.now().getTime();
		FileSystem.createDirectory(root);
		File.saveContent(root + "/Library.hx", "class Library { public static var value:Int = 7; } class Child { public function new() {} }");
		File.saveContent(root + "/Main.hx",
			"import Library.Child; class Main { static function main() { var child = new Child(); Sys.println(Library.value); } }");
		final upstream = new sys.io.Process("haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		check(code == 0 && output == "7\n", "upstream contract failed: " + errors);

		for (first in ["Library", "Library.Child", "Library.value"]) {
			final index = TyperIndex.build([]);
			final prepared = new Array<String>();
			final loader = new ModuleLoader([root], new StringMap(), index, null, false, null, module -> {
				prepared.push(ResolvedModule.getModulePath(module));
				return module;
			});
			@:privateAccess loader.loadModuleByPath(first);
			for (request in ["Library", "Library.Child", "Library.value"])
				@:privateAccess loader.loadModuleByPath(request);
			final loaded = loader.drainNewModules();
			check(loaded.length == 1, "lookup " + first + " loaded " + loaded.length + " copies of Library");
			check(ResolvedModule.getModulePath(loaded[0]) == "Library", "fallback retained a member as module identity");
			final origin = ResolvedModule.getSourceOrigin(loaded[0]);
			check(origin.requestedModulePath == first && origin.sourceModulePath == "Library", "lookup provenance lost its selected source owner");
			check(origin.usedSecondaryTypeFallback == (first != "Library"), "fallback provenance changed");
			check(origin.getSourceIdentity() == CompilerModuleOrigin.direct("Library", 0).getSourceIdentity(),
				"equivalent lookups must produce the same source identity");
			check(prepared.join(",") == "Library", "preparation must receive one canonical module");
			check(index.getByFullName("Library.Child") != null, "secondary type must retain its module owner");
			final eager = ResolverStage.parseProjectRoots([root], [first], new StringMap());
			check(eager.length == 1 && ResolvedModule.getModulePath(eager[0]) == "Library", "eager and lazy module identities differ");
			final seeded = new ModuleLoader([root], new StringMap(), TyperIndex.build(eager), null, false);
			seeded.markResolvedAlready(eager);
			@:privateAccess seeded.loadModuleByPath("Library.value");
			check(seeded.drainNewModules().length == 0, "already resolved source was loaded again through a member");
		}

		// A direct module is distinct even when another class path offers a fallback.
		final higher = root + "/higher";
		FileSystem.createDirectory(higher);
		FileSystem.createDirectory(higher + "/Library");
		File.saveContent(higher + "/Library/Child.hx", "package Library; class Child {}");
		final direct = new ModuleLoader([higher, root], new StringMap(), TyperIndex.build([]), null, false);
		@:privateAccess direct.loadModuleByPath("Library");
		@:privateAccess direct.loadModuleByPath("Library.Child");
		final selected = direct.drainNewModules();
		check(selected.length == 2, "distinct direct module was suppressed by the fallback owner");
		check(Path.normalize(ResolvedModule.getFilePath(selected[1])) == Path.normalize(higher + "/Library/Child.hx"),
			"higher-priority direct module lost to fallback");
		Sys.println("MODULE_FALLBACK_IDENTITY:PASS");
	}
}
