import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds an interface-heavy program with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- An interface method has no body, and Stage3 used to emit an empty stub
	  for it that returned the placeholder `0`. Every call through an
	  interface-typed value bound to that stub: `final p:Named = new Person();
	  p.name()` printed `0`, and `p.name().toUpperCase()` crashed with SIGSEGV.
	- A method inherited from a parent interface (`interface Greeter extends
	  Named`) was not found at all, so `g.name()` fell back to a field read that
	  returned nothing.

	What
	- `stage3_interface_calls` calls interface methods on locals, a static
	  field, instance fields, array elements, parameters, and `this` passed as
	  an interface. It covers generic interfaces, an interface that extends a
	  generic interface, a method inherited from a parent interface, a class
	  that inherits its implementation from a superclass, subclasses that do
	  and do not override the implementation, a packaged interface, interface
	  method values, and String, Int, Float, and Bool results and arguments.
	  It also covers `StringBuf.toString` on a local, a field, and a call result,
	  and a call on a null interface value that `catch` must handle.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- Every interface module of the fixture must hold dispatchers, not stubs.
	- An interface method whose calling convention cannot be forwarded yet must
	  fail at emit time with a named error. That failed emit runs first, so the
	  passing emit after it also proves a failure leaves no emitter state behind.
	- A receiver whose class has no generated method table (an extern
	  `StringMap` seen as `IMap`) must stop the program with a named runtime
	  error, never continue with a placeholder.
**/
class M14Stage3InterfaceCallsTest {
	static final fixture = "test/fixtures/stage3_interface_calls";

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
		final root = ".tmp/m14_stage3_interface_calls_" + name;
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

	/** An unsupported calling convention is an emit-time error, never a placeholder. */
	static function rejectUnsupportedShapes():Void {
		final cases = [
			{
				name: "optional",
				expected: "has an optional or rest argument",
				source: "interface Named {\n\tfunction name(?suffix:String):String;\n}\n" +
				"class Person implements Named {\n\tpublic function new() {}\n\tpublic function name(?suffix:String):String\n\t\treturn \"ann\";\n}\n" +
				"class Main {\n\tstatic function main() {\n\t\tfinal p:Named = new Person();\n\t\tSys.println(p.name());\n\t}\n}\n"
			},
			{
				name: "dynamic",
				expected: "Person's implementation is a dynamic method",
				source: "interface Named {\n\tfunction name():String;\n}\n" +
				"class Person implements Named {\n\tpublic function new() {}\n\tpublic dynamic function name():String\n\t\treturn \"ann\";\n}\n" +
				"class Main {\n\tstatic function main() {\n\t\tfinal p:Named = new Person();\n\t\tSys.println(p.name());\n\t}\n}\n"
			},
			{ // Greeter redeclares Named.name. A call through the parent
				// interface must see the same rejection as one through Greeter.
				name: "redeclared",
				expected: "Person's implementation is a dynamic method",
				source: "interface Named {\n\tfunction name():String;\n}\n"
				+ "interface Greeter extends Named {\n\tfunction name():String;\n}\n"
				+ "class Person implements Greeter {\n\tpublic function new() {}\n\tpublic dynamic function name():String\n\t\treturn \"ann\";\n}\n"
				+ "class Main {\n\tstatic function main() {\n\t\tfinal p:Named = new Person();\n\t\tSys.println(p.name());\n\t}\n}\n"}
		];
		for (shape in cases) {
			final emitted = emitInline(shape.name, shape.source);
			deleteRecursive(emitted.root);
			if (!StringTools.startsWith(emitted.result, "error: ")
				|| emitted.result.indexOf("the interface call Main.Named.name has no native dispatch") < 0
				|| emitted.result.indexOf(shape.expected) < 0)
				throw "an interface call with a " + shape.name + " implementation must be rejected at emit time, got: " + emitted.result;
		}
		Sys.println("M14_STAGE3_INTERFACE_CALLS_UNSUPPORTED_SHAPE:PASS");
	}

	/** A class without a generated table stops at run time with a named error. */
	static function rejectUntabledReceiver():Void {
		final emitted = emitInline("untabled",
			"class Main {\n\tstatic function main() {\n" + "\t\tfinal m:haxe.Constraints.IMap<String, Int> = new haxe.ds.StringMap<Int>();\n" +
			"\t\tSys.println(m.exists(\"a\"));\n\t}\n}\n");
		if (StringTools.startsWith(emitted.result, "error: "))
			throw "an IMap call on an extern map must still emit, got: " + emitted.result;
		final process = new sys.io.Process(emitted.result, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		deleteRecursive(emitted.root);
		if (code == 0 || stdout != "" || stderr.indexOf("HxMethodDispatch: receiver is not a class instance: exists") < 0)
			throw "an IMap call on an extern map must stop with a named error: exit=" + code + " stdout=" + stdout + " stderr=" + stderr;
		Sys.println("M14_STAGE3_INTERFACE_CALLS_UNTABLED_RECEIVER:PASS");
	}

	static function compareWithUpstream():Void {
		final path = fixture + "/Main.hx";
		final expected = File.getContent(fixture + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", fixture, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_interface_calls";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: fixture});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_INTERFACE_CALLS_WHOLE_FILE:PASS");
		requireDispatchers(outDir);
		deleteRecursive(outDir);
	}

	/** Every interface method of the fixture must dispatch on its receiver instead of returning a placeholder. */
	static function requireDispatchers(outDir:String):Void {
		final methods = [
			"Main_Named" => ["name"],
			"Main_Greeter" => ["greet"],
			"Main_Box" => ["get", "put"],
			"Main_Store" => ["size"],
			"Main_Check" => ["test"],
			"Shapes_Shape" => ["area", "label"]
		];
		for (module => names in methods) {
			final source = File.getContent(outDir + "/" + module + ".ml");
			if (source.indexOf("Obj.magic 0") >= 0)
				throw module + " still contains a placeholder stub:\n" + source;
			for (name in names)
				if (source.indexOf("HxMethodDispatch.class_method (Obj.repr this_) \"" + name + "\"") < 0)
					throw module + "." + name + " does not dispatch on its receiver:\n" + source;
		}
		Sys.println("M14_STAGE3_INTERFACE_CALLS_DISPATCHERS:PASS");
	}

	static function main():Void {
		// The rejected emits run first: a failed emit must leave no typed
		// executable selected for the next emit in the same process.
		rejectUnsupportedShapes();
		compareWithUpstream();
		rejectUntabledReceiver();
	}
}
