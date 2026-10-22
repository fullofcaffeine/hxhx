import backend.BackendContext;
import backend.js.JsBackend;
import sys.io.File;
import sys.FileSystem;

/** Constructor inference must survive exact typed publication and generated JavaScript execution. */
class M14GenericConstructorArgumentTest {
	/** Remove only the directory allocated by this test, including backend metadata. */
	static function removeOutput(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeOutput(path + "/" + entry);
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function run(command:String, arguments:Array<String>):String {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "constructor runtime failed: " + command + ": " + stdout + stderr;
		return stdout;
	}

	static function main():Void {
		final root = "test/fixtures/generic_constructor_context";
		final expected = File.getContent(root + "/constructor.expected.stdout");
		if (run("node_modules/.bin/haxe", ["-cp", root, "--run", "ConstructorCases"]) != expected)
			throw "upstream constructor inference behavior changed";
		final path = root + "/ConstructorCases.hx";
		final resolved = new ResolvedModule("ConstructorCases", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final actual = new Array<String>();
		function inspect(node:TypedExpr):Void {
			if (node.getTag() == NewValue) {
				actual.push(node.getType().getSemanticKey());
				final application = node.getConstructorApplication();
				if (application == null
					|| node.getDeclaration() != application.getDeclaration()
					|| application.getParameterTypes()[0].getSemanticKey() != node.getType().getTypeArguments()[0].getSemanticKey())
					throw "constructor inference lost its exact applied declaration";
			}
			for (child in node.getExpressions())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody().getStatements())
					for (expression in statement.getExpressions())
						inspect(expression);
		final types = [
			"nominal:ConstructorCases.Box<primitive:String>",
			"nominal:ConstructorCases.Box<primitive:Int>",
			"nominal:ConstructorCases.Box<primitive:String>",
			"nominal:ConstructorCases.Box<primitive:Float>",
			"nominal:ConstructorCases.Box<nominal:ConstructorCases.Box<primitive:String>>",
			"nominal:ConstructorCases.Box<primitive:String>"
		];
		if (actual.join(";") != types.join(";"))
			throw "constructor arguments did not infer exact independent types: " + actual.join(";");
		for (owner in typed.getBackendProjection().getClasses())
			for (fn in owner.getFunctions())
				fn.requireCaptureCatalog();
		Sys.println("GENERIC_CONSTRUCTOR_ARGUMENT_TYPES:PASS");
		assertRuntime(typed, "ConstructorCases", expected);
		Sys.println("GENERIC_CONSTRUCTOR_ARGUMENT_RUNTIME:PASS");
	}

	/** Execute the exact shared typed module through the ordinary JavaScript backend. */
	public static function assertRuntime(typed:TypedModule, module:String, expected:String):Void {
		final output = ".tmp/generic_constructor_arguments_" + Std.string(Date.now().getTime());
		FileSystem.createDirectory(output);
		final script = output + "/main.js";
		new JsBackend().emit(MacroStage.expandProgram([typed], []),
			new BackendContext(output, script, module, true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		if (run("node", [script]) != expected)
			throw "generated constructor behavior differs; retained output: " + script;
		removeOutput(output);
	}
}
