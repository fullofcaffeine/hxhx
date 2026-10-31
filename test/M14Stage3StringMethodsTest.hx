import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a String-method program with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- `String` is an `extern` class, so none of its methods has a Haxe body.
	  Stage3 still writes a `String` OCaml module for it, and each method there
	  is an empty stub that returns `0`. A typed call that the emitter did not
	  route to the `HxString` runtime bound to that stub. `toUpperCase`,
	  `toLowerCase`, and `toString` had no route, so `box.text.toUpperCase()`
	  and `parts[1].toUpperCase()` printed `0` where upstream prints the text.
	- `(cast value : String)` produced the untyped `Dynamic` value, so a
	  routed method on that receiver did not compile.

	What
	- `stage3_string_methods` calls every String instance method on a local, an
	  instance field, a static field, an array index, static and instance call
	  results, a chained split and index, a type check, an unchecked cast, a
	  `Null<String>` local, and a function parameter.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- Every instance method of the `String` declaration that Stage3 emits must
	  have a native adapter. The emitter rejects a typed String call without one
	  instead of calling the stub, so this check keeps that rejection
	  unreachable for valid programs.
**/
class M14Stage3StringMethodsTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function compareWithUpstream(label:String, source:String, expectedPath:String):Array<TypedModule> {
		final path = source + "/Main.hx";
		final expected = File.getContent(expectedPath);
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_string_methods_" + label;
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_STRING_METHODS_" + label.toUpperCase() + ":PASS");
		return program;
	}

	/** Every instance method of the emitted `String` declaration must have a native adapter. */
	static function requireAdapterForEveryStringMethod(program:Array<TypedModule>):Void {
		final declarations = [
			for (module in program.filter(module -> module.getSourceOrigin().sourceModulePath == "String"))
				for (declaration in HxModuleDecl.getClasses(module.getBackendDeclaration()))
					if (HxClassDecl.getName(declaration) == "String")
						declaration
		];
		if (declarations.length != 1)
			throw "expected the emitted String declaration, found " + declarations.length;
		final methods:Array<String> = [];
		for (method in HxClassDecl.getFunctions(declarations[0])) {
			final name = HxFunctionDecl.getName(method);
			if (HxFunctionDecl.getIsStatic(method) || name == "new")
				continue;
			if (HxFunctionDecl.getHasBody(method))
				throw "String." + name + " has a Haxe body; this check assumes the extern String class";
			if (!backend.ocaml.Stage3OcamlStringCalls.supports(name))
				throw "String." + name + " has no native adapter in Stage3OcamlStringCalls";
			methods.push(name);
		}
		methods.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		final expected = "charAt,charCodeAt,indexOf,lastIndexOf,split,substr,substring,toLowerCase,toString,toUpperCase";
		if (methods.join(",") != expected)
			throw "expected String instance methods <" + expected + ">, got <" + methods.join(",") + ">";
		Sys.println("M14_STAGE3_STRING_METHODS_ADAPTER_COVERAGE:PASS");
	}

	static function main():Void {
		final program = compareWithUpstream("whole_file", "test/fixtures/stage3_string_methods", "test/fixtures/stage3_string_methods/expected.stdout");
		requireAdapterForEveryStringMethod(program);
	}
}
