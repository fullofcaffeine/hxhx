import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.FileSystem;
import sys.io.File;

/** Built-in declarations must enter both project resolution paths before signatures are indexed. */
class M14StandardTypesLoadingIntegrationTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		check(code == 0, command + " failed: " + errors);
		return output;
	}

	static function main():Void {
		final root = ".tmp/standard_types_" + Date.now().getTime();
		FileSystem.createDirectory(root);
		FileSystem.createDirectory(root + "/model");
		FileSystem.createDirectory(root + "/pkg");
		File.saveContent(root + "/model/ArrayAccess.hx", "package model; class ArrayAccess<T> {}");
		final cases = [
			{
				name: "Plain",
				prefix: "",
				expected: "null",
				identity: "StdTypes.ArrayAccess"
			},
			{
				name: "Aliased",
				prefix: "import model.ArrayAccess as Custom;",
				expected: "null",
				identity: "StdTypes.ArrayAccess"
			},
			{
				name: "Imported",
				prefix: "import model.ArrayAccess;",
				expected: "model.ArrayAccess",
				identity: "model.ArrayAccess"
			},
			{
				name: "pkg.Local",
				prefix: "package pkg; class ArrayAccess<T> {}",
				expected: "pkg.ArrayAccess",
				identity: "pkg.Local.ArrayAccess"
			}
		];
		for (scenario in cases) {
			final shortName = scenario.name.split(".").pop();
			File.saveContent(root
				+ "/"
				+ scenario.name.split(".").join("/")
				+ ".hx",
				scenario.prefix
				+ " class "
				+ shortName
				+ " { static var target:ArrayAccess<Int>; static function main() { Sys.println(Type.getClassName(ArrayAccess)); } }");
			final binary = root + "/" + shortName + ".n";
			run("haxe", ["-cp", root, "-main", scenario.name, "-neko", binary]);
			check(run("neko", [binary]) == scenario.expected + "\n", "upstream namespace contract changed: " + scenario.name);
		}

		final arguments = Stage1Args.parse(["-cp", root, "-main", "Plain"], true);
		check(arguments != null, "fixture arguments did not parse");
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(arguments),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "neko"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "neko", "neko-native");
		// Index the unrelated namesake too: a global short-name guess cannot prove visibility.
		final roots = [for (scenario in cases) scenario.name].concat(["model.ArrayAccess"]);
		for (shallow in [true, false]) {
			final modules = shallow ? ResolverStage.parseProjectRootsShallow(paths, roots, defines) : ResolverStage.parseProjectRoots(paths, roots, defines);
			final standardModules = [
				for (module in modules)
					if (ResolvedModule.getModulePath(module) == "StdTypes") module
			];
			check(standardModules.length == 1, "project must load StdTypes once before indexing; shallow=" + shallow);
			final index = TyperIndex.build(modules);
			final loader = new ModuleLoader(paths, defines, index, null, false);
			loader.markResolvedAlready(modules);
			for (scenario in cases) {
				final module = [
					for (module in modules)
						if (ResolvedModule.getModulePath(module) == scenario.name) module
				][0];
				final declaration = ResolvedModule.getParsed(module).getDecl();
				final directives = HxModuleDecl.getDirectives(declaration);
				final selected = index.resolveTypePath("ArrayAccess", HxModuleDecl.getPackagePath(declaration), directives, null, scenario.name);
				check(selected != null
					&& selected.getFullName() == scenario.identity, "wrong default/import/local type: " + scenario.name);
				final owner = index.getByFullName(scenario.name);
				final resolvedDirectives = @:privateAccess TyperStage.resolveModuleDirectives(directives, HxModuleDecl.getPackagePath(declaration),
					scenario.name, index, loader);
				final resolved = index.resolveTypePath("ArrayAccess", HxModuleDecl.getPackagePath(declaration), directives, resolvedDirectives, scenario.name);
				check(resolved != null
					&& resolved.getFullName() == scenario.identity, "resolved imports changed default scope: " + scenario.name);
				final fields = [for (field in owner.getFieldInfos()) if (field.getName() == "target") field];
				check(fields.length == 1 && fields[0].getType().getSemanticKey() == "nominal:" + scenario.identity + "<primitive:Int>",
					"initial signature lost the selected standard type: " + scenario.name);
				if (scenario.name == "Aliased") {
					final alias = index.resolveTypePath("Custom", "", directives, null, scenario.name);
					check(alias != null && alias.getFullName() == "model.ArrayAccess", "alias lost its ordinary provider");
				}
			}
			check(loader.ensureTypeAvailable("StdTypes.ArrayAccess", "", []) != null, "qualified standard type disappeared");
			check(loader.drainNewModules().length == 0, "lazy lookup duplicated the default module");
			Sys.println("STANDARD_TYPES_LOADING:PASS shallow=" + shallow);
		}
	}
}
