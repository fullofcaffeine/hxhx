import backend.BackendContext;
import backend.ocaml.OcamlTargetCore;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.io.File;

/** Compare native array-call effects with upstream and reject copied call ownership. */
class M14Stage3ArrayCallOrderTest {
	static final root = "test/fixtures/stage3_array_call_order";

	static function observe(command:String, arguments:Array<String>, label:String):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != File.getContent(root + "/expected.stdout"))
			throw label + " array-call order differs: " + output + errors;
	}

	/** A second encoding of the same selected declaration is not the original typed occurrence. */
	static function assertCallOwnership(typed:TypedModule):Void {
		var checked = 0;
		for (owner in typed.getBackendProjection().getClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody())
					TypedBackendSourceWalk.statement(statement, expression -> {
						final selected = TypedExactCallSource.decodeInstance(expression);
						if (selected == null || selected.owner != "Array" || (selected.method != "map" && selected.method != "join"))
							return;
						if (fn.findInstanceCall(expression) == null)
							throw "original array call lost its typed owner";
						final copied = TypedExactCallSource.encodeInstance(selected.owner, selected.declaration, selected.method, selected.resultType,
							selected.receiver, selected.arguments);
						if (fn.findInstanceCall(copied) != null)
							throw "copied array call borrowed another occurrence";
						checked++;
					}, _ -> {});
		if (checked != 2)
			throw "array-call ownership observer did not check map and join";
	}

	public static function main():Void {
		observe("haxe", ["-cp", root, "--run", "Main"], "upstream");
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final arguments = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "ocaml"
		});
		final defines = Stage3SetupSupport.buildDefinesMap(["ocaml_profile=portable"], "ocaml", "ocaml");
		final index = TyperIndex.buildHeaders([resolved]);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready([resolved]);
		if (loader.ensureTypeAvailable("Array", "", []) == null)
			throw "array-call fixture requires the real Array declaration";
		final typed = TyperStage.typeResolvedModule(resolved, index, loader, true);
		assertCallOwnership(typed);
		final emitted = new OcamlTargetCore().emit(new MacroExpandedProgram([typed], false),
			new BackendContext(".tmp/stage3-array-call-order", null, "Main", true, defines));
		observe(emitted.entryPath, [], "native");
		Sys.println("ARRAY_CALL_ORDER_NATIVE:PASS");
	}
}
