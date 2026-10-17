import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.io.File;
import sys.FileSystem;

/** Compile type-only and mixed modules without dropping executable declarations. */
class M14OcamlModuleInventoryTest {
	static function main():Void {
		final root = FileSystem.fullPath("test/fixtures/ocaml_module_inventory");
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final arguments = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "ocaml"
		});
		final resolved = [
			for (name in ["Main", "Record", "Mixed", "Unknown", "Entry"])
				new ResolvedModule(name, root + "/" + name + ".hx", ParserStage.parse(File.getContent(root + "/" + name + ".hx"), root + "/" + name + ".hx"))
		];
		final index = TyperIndex.buildHeaders(resolved);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "ocaml", "ocaml"), index);
		loader.markResolvedAlready(resolved);
		final modules = [
			for (module in resolved)
				TyperStage.typeResolvedModule(module, index, loader, true)
		];
		if (modules[1].getBackendProjection().getClasses().length != 0 || modules[2].getBackendProjection().getClasses().length != 1)
			throw "module fixture lost its exact declaration inventory";
		final output = ".tmp/ocaml_module_inventory";
		final result = new backend.ocaml.OcamlTargetCore().emit(MacroStage.expandProgram(modules, []),
			new backend.BackendContext(output, null, "Main", true, true, HxDefineMap.fromRawDefines(["ocaml_profile=portable"])));
		if (!result.builtExecutable
			|| FileSystem.exists(output + "/Record.ml")
			|| FileSystem.exists(output + "/Mixed.ml")
			|| !FileSystem.exists(output + "/Mixed_Helper.ml")
			|| !FileSystem.exists(output + "/Unknown.ml"))
			throw "native module inventory invented a class or omitted an executable provider";
		M14Stage3RuntimeFixture.observe({command: result.entryPath, arguments: [], expected: expected});
		final entryExpected = "entry\nhelper\n7\n";
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Entry"], expected: entryExpected});
		final entry = new backend.ocaml.OcamlTargetCore().emit(MacroStage.expandProgram(modules, []),
			new backend.BackendContext(".tmp/ocaml_module_entry", null, "Entry", true, true, HxDefineMap.fromRawDefines(["ocaml_profile=portable"])));
		if (!entry.builtExecutable)
			throw "module-level entrypoint did not build";
		M14Stage3RuntimeFixture.observe({command: entry.entryPath, arguments: [], expected: entryExpected});
		Sys.println("OCAML_MODULE_INVENTORY_RUNTIME:PASS");
	}
}
