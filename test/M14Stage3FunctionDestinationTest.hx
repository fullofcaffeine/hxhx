import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Every `haxe.Constraints.Function` destination that Stage3 does not adapt must
	stop native emission with a named error.

	Why
	- A `Function` value is called through the Dynamic convention. Stage3 adapts
	  a function at call arguments, `Function` locals and `Array<Function>`
	  literal elements. A raw typed closure anywhere else crashes the native
	  program (SIGSEGV or SIGBUS) when `Reflect.callMethod` calls it with
	  arguments of another category or count (haxe_ocaml-h9dw9).

	What
	- Each program below is valid upstream Haxe 4.3.7. Stage3 must refuse it at
	  emit time and name the destination. Adapted destinations are covered by
	  `M14Stage3ReflectCallMethodTest`.
**/
class M14Stage3FunctionDestinationTest {
	static final FN = "function(s:String) Sys.println(s)";
	static final T = "haxe.Constraints.Function";

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

	static function requireRejected(name:String, source:String, site:String, ?exact:String):Void {
		final root = ".tmp/m14_stage3_function_destination_" + name;
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
		process.stdout.readAll();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0)
			throw name + ": upstream Haxe must accept the program, got: " + stderr;
		final message = try {
			final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
			EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
			null;
		} catch (error:haxe.Exception) {
			error.message;
		}
		deleteRecursive(root);
		final expected = exact != null ? exact : "cannot be " + site;
		if (message == null || message.indexOf(expected) < 0 || (exact == null && message.indexOf("haxe.Constraints.Function") < 0))
			throw name + ": Stage3 must stop with a named error containing <" + expected + ">, got: " + message;
		Sys.println("M14_STAGE3_FUNCTION_DESTINATION_REJECT_" + name.toUpperCase() + ":PASS");
	}

	static function main():Void {
		final holder = 'class Holder {\n\tpublic var f:$T;\n\tpublic static var s:$T;\n\tpublic function new(?g:$T) {}\n}\n';
		final box = 'enum Box {\n\tFilled(f:$T);\n}\n';
		function program(body:String, members:String = ""):String
			return holder + 'class Main {\n$members\n\tstatic function main() {\n\t\t$body\n\t}\n}\n';
		final stored = "stored as haxe.Constraints.Function in this ";
		requireRejected("instance_field", program('final h = new Holder();\n\t\th.f = $FN;'), stored + "field");
		requireRejected("static_field", program('Holder.s = $FN;'), stored + "field");
		requireRejected("static_initializer", 'class Main {\n\tstatic var f:$T = $FN;\n\n\tstatic function main() {}\n}\n', stored + "field initializer");
		requireRejected("function_result", program("make();", '\tstatic function make():$T\n\t\treturn $FN;\n'), stored + "function result");
		requireRejected("lambda_result", program('final g:Void->$T = () -> $FN;'), stored + "function result");
		requireRejected("structure_field", program('final o:{f:$T} = {f: $FN};'), stored);
		requireRejected("array_index", program('final a:Array<$T> = [];\n\t\ta[0] = $FN;'), stored + "array element");
		requireRejected("type_check", program('final g = ($FN : $T);'), stored + "expression result");
		// The stored value's type is Null<function>, which must count as a function value.
		requireRejected("optional_callback_field",
			program('set(new Holder(), function(s:String) Sys.println(s));', '\tstatic function set(h:Holder, ?cb:String->Void) {\n\t\th.f = cb;\n\t}\n'),
			stored + "field");
		requireRejected("nullable_conditional_field", program('final h = new Holder();\n\t\th.f = Sys.args().length == 0 ? $FN : null;'), stored + "field");
		requireRejected("nullable_function_result", program('get();', '\tstatic function get(?cb:String->Void):$T\n\t\treturn cb;\n'),
			stored + "function result");
		requireRejected("null_coalescing", program('final g:Null<$T> = null;\n\t\tfinal f:$T = g ?? $FN;'), stored);
		requireRejected("conditional_mixed_function", program('final g:Null<$T> = null;\n\t\tfinal f:$T = g != null ? g : $FN;'), stored
			+ "expression result");
		// A `using` call keeps its receiver under the callee.
		requireRejected("using_extension",
			'using Main.Ex;\n\nclass Ex {\n\tpublic static function keep(f:$T):$T\n\t\treturn f;\n}\n\nclass Main {\n\tstatic function main() {\n\t\tfinal fn = $FN;\n\t\tfn.keep();\n\t}\n}\n',
			stored + "extension method argument");
		// `super(...)` is a constructor occurrence with no call-argument facts.
		final base = 'class K {\n\tpublic function new(f:$T) {}\n}\n\nclass L extends K {\n\tpublic function new()\n\t\tsuper($FN);\n}\n';
		requireRejected("super_argument", base + 'class Main {\n\tstatic function main() {\n\t\tnew L();\n\t}\n}\n', stored + "constructor argument");
		final generic = 'class Box<T> {\n\tpublic var v:T;\n\n\tpublic function new(v:T)\n\t\tthis.v = v;\n}\n\nclass B extends Box<$T> {\n\tpublic function new()\n\t\tsuper($FN);\n}\n';
		requireRejected("generic_super_argument", generic + 'class Main {\n\tstatic function main() {\n\t\tnew B();\n\t}\n}\n',
			stored + "constructor argument");
		final passed = "passed as haxe.Constraints.Function";
		requireRejected("array_push", program('final a:Array<$T> = [];\n\t\ta.push($FN);'), passed);
		requireRejected("map_set", program('final m = new Map<String, $T>();\n\t\tm.set("a", $FN);'), passed);
		// A Function enum payload has no native representation, so the enum itself is refused.
		requireRejected("enum_argument", box + 'class Main {\n\tstatic function main() {\n\t\tFilled($FN);\n\t}\n}\n', "",
			"OCaml enum payload representation is not implemented");
		requireRejected("constructor_argument", program('new Holder($FN);'), stored + "constructor argument");
		Sys.println("M14_STAGE3_FUNCTION_DESTINATION:PASS");
	}
}
