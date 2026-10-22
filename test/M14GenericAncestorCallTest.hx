/** Inherited generic arguments must constrain calls and results without erasing the operand type. */
class M14GenericAncestorCallTest {
	static function main():Void {
		M14InheritedArrayReadTest.check();
		final prefix = "class Base<T> {public function new(){}} class Child<T> extends Base<T> {} class Box<T> {public function new(){}} ";
		final cases:Array<{
			name:String,
			source:String,
			accepts:Bool,
			result:String
		}> = [
			{
				name: "overload",
				source: prefix +
				'extern class Api {overload static function accept<T>(value:Base<T>):String; overload static function accept<T>(value:Child<T>):Int;} class Main {static function main():Void {var result:Int=Api.accept(new Child<Int>());}}',
				accepts: true,
				result: "primitive:Int"
			},
			{
				name: "direct",
				source: prefix +
				"class Main {static function accept<T>(a:Box<T>,b:Base<T>):Void {} static function main():Void {accept(new Box<Int>(),new Child<Int>());}}",
				accepts: true,
				result: ""
			},
			{
				name: "forward",
				source: prefix +
				"class Main {static function accept<T>(a:Box<T>,b:Base<T>):Void {} static function forward<U>(a:Box<U>,b:Child<U>):Void {accept(a,b);} static function main():Void {forward(new Box<Int>(),new Child<Int>());}}",
				accepts: true,
				result: ""
			},
			{
				name: "result",
				source: prefix +
				"class Main {static function accept<T>(b:Base<T>):T {return cast null;} static function main():Void {var result=accept(new Child<Int>());}}",
				accepts: true,
				result: "primitive:Int"
			},
			{
				name: "wrong",
				source: prefix +
				"class Main {static function accept<T>(a:Box<T>,b:Base<T>):Void {} static function main():Void {accept(new Box<Int>(),new Child<String>());}}",
				accepts: false,
				result: ""
			},
			{
				name: "reverse",
				source: prefix + "class Main {static function accept<T>(b:Child<T>):Void {} static function main():Void {accept(new Base<Int>());}}",
				accepts: false,
				result: ""
			},
			{
				name: "unrelated",
				source: prefix + "class Main {static function accept<T>(b:Base<T>):Void {} static function main():Void {accept(new Box<Int>());}}",
				accepts: false,
				result: ""
			},
			{
				name: "bounded",
				source: prefix +
				"class Main {static function accept<T:String>(b:Base<T>):T {return cast null;} static function main():Void {var result=accept(new Child<String>());}}",
				accepts: true,
				result: "primitive:String"
			},
			{
				name: "wrong_bound",
				source: prefix +
				"class Main {static function accept<T:String>(b:Base<T>):T {return cast null;} static function main():Void {var result=accept(new Child<Int>());}}",
				accepts: false,
				result: ""
			},
			{
				name: "transitive",
				source: "class Base<A,B> {public function new(){}} class Middle<X,Y> extends Base<Y,X> {} class Child<T> extends Middle<String,T> {} class Main {static function accept<A,B>(b:Base<A,B>):A {return cast null;} static function main():Void {var result=accept(new Child<Int>());}}",
				accepts: true,
				result: "primitive:Int"
			},
			{
				name: "interface",
				source: "interface Carrier<T> {} class Item<T> implements Carrier<T> {public function new(){}} class Main {static function accept<T>(b:Carrier<T>):T {return cast null;} static function main():Void {var result=accept(new Item<Int>());}}",
				accepts: true,
				result: "primitive:Int"
			}
		];
		for (entry in cases) {
			final root = ".tmp/generic_ancestor_call/" + entry.name;
			sys.FileSystem.createDirectory(root);
			sys.io.File.saveContent(root + "/Main.hx", entry.source);
			final process = new sys.io.Process("haxe", ["-cp", root, "-main", "Main", "--no-output"]);
			final diagnostic = process.stderr.readAll().toString();
			final upstream = process.exitCode() == 0;
			process.close();
			if (upstream != entry.accepts)
				throw "upstream ancestor expectation differs: " + entry.name + " " + diagnostic;
			final resolved = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(entry.source, root + "/Main.hx"));
			final index = TyperIndex.build([resolved]);
			final owner = index.getByFullName(entry.name == "overload" ? "Main.Api" : "Main");
			if (entry.name == "overload" && owner.staticMethodCandidates("accept").length != 2)
				throw "ancestor overload fixture lost a candidate";
			final signature = owner.staticMethod("accept");
			final original = signature.getReturnType().getSemanticKey();
			var typed:Null<TypedModule> = null;
			var failure = "";
			try
				typed = TyperStage.typeResolvedModule(resolved, index)
			catch (error:haxe.Exception)
				failure = error.message;
			sys.io.File.saveContent(root
				+ "/diagnostics.txt",
				"upstream="
				+ upstream
				+ "\n"
				+ diagnostic
				+ "native="
				+ (typed != null)
				+ "\n"
				+ failure
				+ "\n");
			if ((typed != null) != entry.accepts)
				throw "ancestor acceptance differs: " + entry.name + " " + failure;
			if (signature.getReturnType().getSemanticKey() != original)
				throw "ancestor inference mutated a shared signature";
			if (typed != null && entry.result != "") {
				var seen = false;
				for (cls in typed.getTypedClasses())
					for (fn in cls.getFunctions())
						for (local in fn.getEnvironment().getLocals())
							if (local.getName() == "result") {
								seen = true;
								if (local.getType().getSemanticKey() != entry.result)
									throw "ancestor result differs: " + entry.name + " " + local.getType().getSemanticKey();
							}
				if (!seen)
					throw "missing ancestor result local";
			}
			Sys.println("GENERIC_ANCESTOR_CALL:PASS " + entry.name);
		}
		#if generic_ancestor_neko
		@:privateAccess M14NekoClosureControlTest.assertSource("generic_ancestor_call",
			'class Base<T> {public var value:T;public function new(value:T){this.value=value;}} class Child<T> extends Base<T> {} class Main {static function read<T>(value:Base<T>):T {return value.value;} static function main():Void {Sys.println(read(new Child<Int>(7)));Sys.println(read(new Child<String>("text")));}}',
			"7\ntext\n");
		#else
		runtime();
		#end
	}

	/** Execute inherited generic results after both upstream and local compilation. */
	static function runtime():Void {
		final root = ".tmp/generic_ancestor_runtime";
		sys.FileSystem.createDirectory(root);
		final source = 'class Base<T> {public var value:T;public function new(value:T){this.value=value;}} class Child<T> extends Base<T> {} class Main {static function read<T>(value:Base<T>):T {return value.value;} static function main():Void {if(read(new Child<Int>(7))!=7) throw "integer result";if(read(new Child<String>("text"))!="text") throw "string result";}}';
		sys.io.File.saveContent(root + "/Main.hx", source);
		observe("haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final resolved = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final script = root + "/main.js";
		new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(root, script, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		observe("node", ["--check", script]);
		observe("node", [script]);
		Sys.println("GENERIC_ANCESTOR_JS_RUNTIME:PASS");
	}

	static function observe(command:String, arguments:Array<String>):Void {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "")
			throw command + " ancestor observer failed: " + stdout + stderr;
	}
}
