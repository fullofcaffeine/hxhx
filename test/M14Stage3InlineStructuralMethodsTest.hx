import sys.FileSystem;

/**
	Builds a program that uses inline structural method types with the Stage3
	native emitter and compares its output with upstream Haxe.

	Why
	- `function provide():{ function value():Int; } return new Answer();` used
	  to type its return as an unresolved annotation, because the parser joined
	  `function value` into one word. After that was repaired, the native
	  program still crashed: a class instance keeps its methods as module-level
	  OCaml functions, not in its field storage, so reading `value` through the
	  structure type found nothing and the call jumped through a null value.

	What
	- `stage3_inline_structural_methods` calls, stores, and passes method fields
	  of inline structure types, filled by object literals and by class
	  instances (including an overriding subclass), plus a variable field that
	  holds a function and a named typedef for comparison.
	- It also reads a `dynamic` method, a stored function field, and a method
	  of a null receiver, which must raise the catchable "Null Access".
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- A method that a structural read cannot bind yet (an optional argument, or
	  a method of a runtime-provided String) must raise a catchable named error.
**/
class M14Stage3InlineStructuralMethodsTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	/**
		Methods that a structural read cannot bind yet must fail as catchable Haxe
		errors, never as an OCaml abort or a crash.

		Upstream accepts both programs, so only the native result is checked: a
		method with an optional argument (structural call sites do not pad an
		omitted argument yet), the same method when a subclass overrides it (the
		override's dispatch table holds it for ordinary calls), and a method of a
		runtime-provided String.
	**/
	static function unsupportedReadsAreCatchable():Void {
		final root = ".tmp/m14_stage3_inline_structural_methods_unsupported";
		deleteRecursive(root);
		FileSystem.createDirectory(root + "/src");
		final path = root + "/src/Main.hx";
		final source = "class Optional {\n"
			+ "\tpublic function new() {}\n"
			+ "\tpublic function pick(?x:Int):Int return x == null ? -1 : x;\n"
			+ "}\n"
			+ "class OptionalBase {\n"
			+ "\tpublic function new() {}\n"
			+ "\tpublic function pick(?x:Int):String return \"base:\" + (x == null ? \"null\" : Std.string(x));\n"
			+ "}\n"
			+ "class OptionalLate extends OptionalBase {\n"
			+ "\tpublic function new() super();\n"
			+ "\toverride public function pick(?x:Int):String return \"late:\" + (x == null ? \"null\" : Std.string(x));\n"
			+ "}\n"
			+ "class Main {\n"
			+ "\tstatic function main():Void {\n"
			+ "\t\tfinal picker:{ function pick(?x:Int):String; } = new OptionalLate();\n"
			+ "\t\ttry {\n"
			+ "\t\t\tSys.println(picker.pick());\n"
			+ "\t\t} catch (e:String) {\n"
			+ "\t\t\tSys.println(\"overridden: \" + e);\n"
			+ "\t\t}\n"
			+ "\t\tfinal optional:{ function pick(?x:Int):Int; } = new Optional();\n"
			+ "\t\ttry {\n"
			+ "\t\t\tSys.println(optional.pick());\n"
			+ "\t\t} catch (e:String) {\n"
			+ "\t\t\tSys.println(\"optional: \" + e);\n"
			+ "\t\t}\n"
			+ "\t\tfinal text:{ function charAt(i:Int):String; } = \"abc\";\n"
			+ "\t\ttry {\n"
			+ "\t\t\tSys.println(text.charAt(1));\n"
			+ "\t\t} catch (e:String) {\n"
			+ "\t\t\tSys.println(\"runtime-provided: \" + e);\n"
			+ "\t\t}\n"
			+ "\t}\n"
			+ "}\n";
		sys.io.File.saveContent(path, source);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root + "/src"});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
		M14Stage3RuntimeFixture.observe({command: executable,
			arguments: [],
			expected: "overridden: Stage3 cannot call method pick of class OptionalLate through a structure type"
			+ " (methods with type parameters, optional or rest arguments, or without a generated body are not supported)\n"
			+ "optional: Stage3 cannot call method pick of class Optional through a structure type"
			+ " (methods with type parameters, optional or rest arguments, or without a generated body are not supported)\n"
			+ "runtime-provided: Stage3 cannot call method charAt of a runtime-provided value through a structure type\n"});
		deleteRecursive(root);
		Sys.println("M14_STAGE3_INLINE_STRUCTURAL_METHODS_UNSUPPORTED_CATCHABLE:PASS");
	}

	static function main():Void {
		final source = "test/fixtures/stage3_inline_structural_methods";
		final path = source + "/Main.hx";
		final expected = sys.io.File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_inline_structural_methods";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: sys.io.File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_INLINE_STRUCTURAL_METHODS:PASS");
		unsupportedReadsAreCatchable();
	}
}
