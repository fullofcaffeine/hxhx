import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program with overridden methods and `super` calls with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- Stage3 writes each Haxe class as one OCaml module, and an instance call
	  named the declaring class's function. A call on a value typed as the
	  superclass ran the superclass method: `final p:Person = new Teacher();
	  p.name()` printed Person's result (haxe_ocaml-tcf2h).
	- `super.name()` rendered its receiver as the placeholder `(Obj.magic 0)`,
	  and the emitter then replaced the whole enclosing expression with it
	  (haxe_ocaml-37rs6).

	What
	- `stage3_virtual_calls` calls overridden methods through a four-level
	  chain with a class that overrides nothing in the middle, on locals,
	  a static field, an instance field, parameters, array elements, `this`,
	  method values, and an interface. It covers String, Int, Float, Bool,
	  and Void results, optional arguments whose default differs per class,
	  a method with its own type parameter,
	  and `super` calls with and without arguments, in value and statement
	  position, as an unbraced expression body, to a direct parent, to an ancestor through a class that does
	  not override, and to a method no class overrides.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- The generated modules must keep calls direct where no override can
	  apply: a method no class overrides, a `final` class, and the most derived
	  class. Overridden methods must dispatch.
	- Overridden methods whose calling convention cannot be forwarded yet, and
	  `super` used other than in a call, must fail at emit time with a named
	  error. The failed emits run first, so the passing emit after them also
	  proves a failure leaves no emitter state behind.
**/
class M14Stage3VirtualCallsTest {
	static final fixture = "test/fixtures/stage3_virtual_calls";

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

	static function emitInline(name:String, source:String):{root:String, result:String} {
		final root = ".tmp/m14_stage3_virtual_calls_" + name;
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
		final result = try {
			EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
		} catch (error:haxe.Exception) {
			"error: " + error.message;
		}
		return {root: root, result: result};
	}

	static function hierarchy(baseMethod:String, overrideMethod:String, main:String):String {
		return "class Base {\n\tpublic function new() {}\n\t"
			+ baseMethod
			+ "\n}\n"
			+ "class Sub extends Base {\n\tpublic function new()\n\t\tsuper();\n\t"
			+ overrideMethod
			+ "\n}\n"
			+ "class Main {\n\tstatic function main() {\n\t\t"
			+ main
			+ "\n\t}\n}\n";
	}

	/** An unsupported calling convention or `super` use is an emit-time error, never a placeholder. */
	static function rejectUnsupportedShapes():Void {
		final cases = [
			{
				name: "dynamic",
				expected: "the call Main.Base.name has no native virtual dispatch: Main.Base.name is a dynamic method",
				source: hierarchy("public dynamic function name():String\n\t\treturn \"base\";",
					"override public dynamic function name():String\n\t\treturn \"sub\";", "final b:Base = new Sub();\n\t\tSys.println(b.name());")
			},
			{
				name: "rest",
				expected: "the call Main.Base.count has no native virtual dispatch: Main.Base.count has a rest argument",
				source: hierarchy("public function count(...values:Int):Int\n\t\treturn values.length;",
					"override public function count(...values:Int):Int\n\t\treturn 0;", "final b:Base = new Sub();\n\t\tSys.println(b.count(1, 2));")
			},
			{ // Upstream rejects this while typing (haxe_ocaml-rmknt); until hxhx does,
				// the emitter must still refuse it by name.
				name: "super_value",
				expected: "super is supported only in super(...) and super.method(...) calls",
				source: hierarchy("public function name():String\n\t\treturn \"base\";",
					"override public function name():String {\n\t\tfinal read = super.name;\n\t\treturn read();\n\t}",
					"final b:Base = new Sub();\n\t\tSys.println(b.name());")
			}
		];
		for (shape in cases) {
			final emitted = emitInline(shape.name, shape.source);
			deleteRecursive(emitted.root);
			if (!StringTools.startsWith(emitted.result, "error: ") || emitted.result.indexOf(shape.expected) < 0)
				throw "an overridden method with a " + shape.name + " shape must be rejected at emit time, got: " + emitted.result;
		}
		Sys.println("M14_STAGE3_VIRTUAL_CALLS_UNSUPPORTED_SHAPE:PASS");
	}

	/** A call that no override can reach stays direct, so an unsupported shape there still compiles. */
	static function acceptExactUnsupportedShape():Void {
		final emitted = emitInline("exact_dynamic",
			hierarchy("public dynamic function name():String\n\t\treturn \"base\";", "override public dynamic function name():String\n\t\treturn \"sub\";",
				"final s:Sub = new Sub();\n\t\tSys.println(s.name());"));
		if (StringTools.startsWith(emitted.result, "error: "))
			throw "a dynamic method called on its most derived class must still emit, got: " + emitted.result;
		M14Stage3RuntimeFixture.observe({command: emitted.result, arguments: [], expected: "sub\n"});
		deleteRecursive(emitted.root);
		Sys.println("M14_STAGE3_VIRTUAL_CALLS_EXACT_UNSUPPORTED_SHAPE:PASS");
	}

	static function compareWithUpstream():Void {
		final path = fixture + "/Main.hx";
		final expected = File.getContent(fixture + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", fixture, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_virtual_calls";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: fixture});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_VIRTUAL_CALLS_WHOLE_FILE:PASS");
		requireCallShapes(outDir);
		deleteRecursive(outDir);
	}

	static function requireText(outDir:String, module:String, text:String, why:String):Void {
		final source = File.getContent(outDir + "/" + module + ".ml");
		if (source.indexOf(text) < 0)
			throw module + " must contain `" + text + "` (" + why + "):\n" + source;
	}

	static function rejectText(outDir:String, module:String, text:String, why:String):Void {
		final source = File.getContent(outDir + "/" + module + ".ml");
		if (source.indexOf(text) >= 0)
			throw module + " must not contain `" + text + "` (" + why + "):\n" + source;
	}

	/** Overridden methods dispatch, and calls that no override can reach stay direct. */
	static function requireCallShapes(outDir:String):Void {
		for (method in [
			"name",
			"rank",
			"weight",
			"senior",
			"greet",
			"shout",
			"label",
			"score",
			"describe",
			"echo"
		])
			requireText(outDir, "Main_Person", "and " + method + " (this_ : _)", "Person." + method + " is overridden and needs a dispatcher");
		requireText(outDir, "Main_Person", "HxMethodDispatch.class_method (Obj.repr this_) \"name\"", "the dispatcher looks up the receiver's class");
		rejectText(outDir, "Main_Person", "tag'direct", "no class overrides tag");
		rejectText(outDir, "Main_Professor", "'direct (", "no class overrides Professor's methods");
		// Super calls reach the nearest ancestor's direct function.
		requireText(outDir, "Main_Teacher", "Main_Person.name'direct)", "super.name() in Teacher");
		requireText(outDir, "Main_Teacher", "Main_Person.shout'direct)", "super.shout() in statement position");
		requireText(outDir, "Main_Teacher", "Main_Person.record'direct)", "super.record() as an unbraced expression body");
		requireText(outDir, "Main_Professor", "Main_Teacher.name'direct)", "super.name() reaches Teacher through Assistant");
		requireText(outDir, "Main_Professor", "Main_Person.describe'direct)", "super.describe() reaches Person through two classes");
		requireText(outDir, "Main_Professor", "(Main_Person.tag)", "super.tag() reaches a method no class overrides");
		// Calls whose receiver type no override can reach stay direct.
		requireText(outDir, "Main", "(Main_Person.tag)", "no class overrides tag");
		requireText(outDir, "Main", "(Main_Person.name'direct)", "Visitor is final and overrides nothing");
		requireText(outDir, "Main", "(Main_Professor.name)", "Professor is the most derived class");
		// Calls on superclass-typed values dispatch.
		requireText(outDir, "Main", "(Main_Person.name)", "a Person value may hold any subclass");
		requireText(outDir, "Main", "(Main_Teacher.name)", "a Teacher value may hold a Professor");
		Sys.println("M14_STAGE3_VIRTUAL_CALLS_SHAPES:PASS");
	}

	static function main():Void {
		// The rejected emits run first: a failed emit must leave no typed
		// executable selected for the next emit in the same process.
		rejectUnsupportedShapes();
		acceptExactUnsupportedShape();
		compareWithUpstream();
	}
}
