import haxe.io.Path;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.FileSystem;
import sys.io.File;

/** Lua uses its real target declarations while explicit user sources retain priority. */
class M14LuaStandardLibraryPathsIntegrationTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Remove only files created in this test's isolated directory. */
	static function removeTree(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/.tmp/lua_std_paths_" + Date.now().getTime());
		FileSystem.createDirectory(root);
		final parsed = Stage1Args.parse(["-main", "Main"], true);
		require(parsed != null, "Lua provider fixture arguments must parse");
		final standard = Path.normalize(Stage1Args.getStandardLibraryRoot(parsed));
		final target = Path.join([standard, "lua", "_std"]);
		function paths(explicit:Array<String>, define:String = "lua", ?standardRoot:String):Array<String> {
			return Stage3SetupSupport.projectClassPaths({
				explicitPaths: explicit,
				libraries: [],
				cwd: root,
				standardRoot: standardRoot == null ? standard : standardRoot,
				targetDefine: define
			});
		}
		final sources = new CompilerSourceProvider();
		final mapPath = target + "/haxe/ds/ObjectMap.hx";
		require(sources.resolveModuleFile(paths([]), "haxe.ds.ObjectMap") == mapPath,
			"Lua must select its actual ObjectMap provider before the constrained common declaration");
		final defines = Stage3SetupSupport.buildDefinesMap([], "lua", "lua-native");
		final modules = ResolverStage.parseProjectRoots(paths([]), ["haxe.ds.ObjectMap"], defines);
		final maps = modules.filter(module -> ResolvedModule.getModulePath(module) == "haxe.ds.ObjectMap");
		require(maps.length == 1
			&& ResolvedModule.getFilePath(maps[0]) == mapPath, "resolved module lost the Lua provider source identity");
		final declarations = HxModuleDecl.getClasses(ResolvedModule.getParsed(maps[0]).getDecl());
		final owners = declarations.filter(owner -> HxClassDecl.getName(owner) == "ObjectMap");
		require(owners.length == 1, "Lua provider must declare exactly one ObjectMap");
		final parameters = HxClassDecl.getTypeParameters(owners[0]);
		require(parameters.length == 2 && parameters[0].constraints.length == 0 && parameters[1].constraints.length == 0,
			"Lua ObjectMap must retain its actual unconstrained key and value parameters");
		require(sources.resolveModuleFile(paths([]), "haxe.io.Eof") == standard + "/haxe/io/Eof.hx", "missing Lua overrides must use common providers");
		for (other in ["js", "neko", "ocaml", "cpp"])
			require(paths([], other).indexOf(target) == -1, "Lua providers leaked into " + other);
		// These empty files test source precedence only. The provider assertion above uses the real library.
		final project = root + "/project";
		FileSystem.createDirectory(project + "/haxe/ds");
		File.saveContent(project + "/haxe/ds/ObjectMap.hx", "package haxe.ds; class ObjectMap {}\n");
		require(sources.resolveModuleFile(paths([project]), "haxe.ds.ObjectMap") == project + "/haxe/ds/ObjectMap.hx", "explicit project provider must win");
		FileSystem.createDirectory(root + "/haxe/ds");
		File.saveContent(root + "/haxe/ds/ObjectMap.hx", "package haxe.ds; class ObjectMap {}\n");
		require(sources.resolveModuleFile(paths([]), "haxe.ds.ObjectMap") == root + "/haxe/ds/ObjectMap.hx", "implicit working directory must win");
		final explicitCommon = paths([standard + "/."]);
		require(sources.resolveModuleFile(explicitCommon, "haxe.ds.ObjectMap") == standard + "/haxe/ds/ObjectMap.hx",
			"explicit common root must retain user priority");
		require([for (path in explicitCommon) if (path == standard) path].length == 1, "equivalent common roots must not duplicate");
		final noOverrides = root + "/standard";
		FileSystem.createDirectory(noOverrides);
		File.saveContent(noOverrides + "/Probe.hx", "class Probe {}\n");
		require(sources.resolveModuleFile(paths([], "lua", noOverrides), "Probe") == noOverrides + "/Probe.hx",
			"absent Lua directory must retain common lookup");
		removeTree(root);
		Sys.println("LUA_STANDARD_LIBRARY_PATHS:PASS");
	}
}
