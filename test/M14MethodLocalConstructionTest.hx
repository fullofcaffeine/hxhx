import sys.io.File;
import hxhx.Stage1Compiler.Stage1Args;

/** Prove the parser's local ownership on real Vector source and native constructor execution. */
class M14MethodLocalConstructionTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Require the real source to contain the regression's locals, then prove they are not fields. */
	static function vectorLocals():Void {
		final root = Stage1Args.getStandardLibraryRoot(Stage1Args.parse([], true));
		final path = root + "/haxe/ds/Vector.hx";
		final source = File.getContent(path);
		final defines = new haxe.ds.StringMap<String>();
		defines.set("ocaml", "1");
		final filtered = HxConditionalCompilation.filterSource(source, defines);
		final parsed = ParserStage.parseFilteredSource({originalSource: source, filteredSource: filtered, filePath: path});
		final vector = HxModuleDecl.getMainClass(parsed.getDecl());
		require(HxClassDecl.getName(vector) == "Vector", "real Vector declaration missing");
		for (field in HxClassDecl.getFields(vector))
			require(HxFieldDecl.getName(field) != "r" && HxFieldDecl.getName(field) != "len", "Vector method local became a field");
		for (entry in [{method: "copy", names: ["r"]}, {method: "map", names: ["r", "len"]}]) {
			final methods = HxClassDecl.getFunctions(vector).filter(fn -> HxFunctionDecl.getName(fn) == entry.method);
			require(methods.length == 1, "Vector method missing: " + entry.method);
			final locals:Array<String> = [];
			for (statement in HxFunctionDecl.getBody(methods[0]))
				switch statement {
					case SVar(name, _, _, _, _):
						locals.push(name);
					case _:
				}
			for (name in entry.names)
				require(locals.indexOf(name) >= 0, "Vector local missing from method body: " + entry.method + "." + name);
		}
		Sys.println("VECTOR_PARSER_LOCAL_OWNERSHIP:PASS");
	}

	public static function main():Void {
		vectorLocals();
		final root = "test/fixtures/method_local_construction";
		final path = root + "/Main.hx";
		final source = File.getContent(path);
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		final projection = typed.getBackendProjection();
		final fields = HxClassDecl.getFields(HxModuleDecl.getMainClass(projection.getDeclaration())).map(field -> HxFieldDecl.getName(field));
		require(fields.length == 1 && fields[0] == "length", "method locals leaked into projected fields: " + fields.join(","));
		final output = ".tmp/method_local_construction";
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), output);
		// Native compilation rejects an unbound constructor receiver. A textual
		// ban on new_ (__hx_obj) also rejects valid calls with a bound receiver.
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("METHOD_LOCAL_CONSTRUCTION_NATIVE:PASS");
	}
}
