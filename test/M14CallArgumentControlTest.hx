/** Calls must capture their callable before a later argument executes a statement region. */
class M14CallArgumentControlTest {
	static var failures:Int = 0;

	static function check(name:String, source:String, native:Bool = false):Void {
		try {
			exercise(name, source, native);
		} catch (error:haxe.Exception) {
			failures++;
			Sys.println("CALL_ARGUMENT_CONTROL:FAIL " + name + " " + error.message);
		}
	}

	/** Keep independent cases running after a target failure, but fail the complete contract. */
	static function exercise(name:String, source:String, native:Bool):Void {
		final root = ".tmp/call_argument_control_" + name;
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Main.hx", source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
		assertProcess(upstream, "upstream " + name);
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final functions = [for (cls in typed.getTypedClasses()) for (fn in cls.getFunctions()) fn];
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		typed.getBackendProjection();
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		Sys.println("CALL_ARGUMENT_CONTROL:JS_PASS " + name);
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "call lowering changed authored typed facts: " + name;
		if (native) {
			final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true);
			assertProcess(new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable]), "native " + name);
		}
		Sys.println("CALL_ARGUMENT_CONTROL:PASS " + name);
	}

	/** Each authored assertion is also checked upstream; successful fixtures produce no output. */
	static function assertProcess(process:sys.io.Process, context:String):Void {
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = try {
			process.exitCode();
		} catch (error:haxe.Exception) {
			process.close();
			throw new haxe.Exception(context + " did not exit normally: " + stdout + stderr, error);
		}
		process.close();
		if (code != 0 || stdout != "")
			throw context + " failed: " + stdout + stderr;
	}

	static function main():Void {
		check("nullable",
			"class Sink { public function new() {} public function put(value:Null<Int>):Int return value==null ? 9 : value; } " +
			"class Main { static function main():Void { final sink=new Sink(); if(sink.put(true ? 3 : null)!=3 || sink.put(false ? 3 : null)!=9) throw 'nullable call'; } }",
			true);
		for (selected in [true, false]) {
			final source = "class Sink { public function new() {} public function run(first:Int, second:Null<Int>):Int { Main.mark(6); return first+(second==null ? 0 : second)+10; } } "
				+ "class Main { static var order:Int=0; public static function mark(digit:Int):Int { order=order*10+digit; return digit; } "
				+ "static function receiver():Sink { mark(1); return new Sink(); } "
				+ "static function main():Void { final result=receiver().run(mark(2), { mark(3); var value:Null<Int>="
				+ selected
				+ " ? mark(4) : null; mark(5); value; }); if(result!="
				+ (selected ? 16 : 12)
				+ " || order!="
				+ (selected ? 123456 : 12356)
				+ ") throw 'call order'; } }";
			check("order_" + selected, source);
		}
		check("dynamic",
			"class Sink { public function new() {} public dynamic function put(value:Int):Int return 1; } " +
			"class Main { static function main():Void { final sink=new Sink(); final result=sink.put({sink.put=function(value:Int):Int return 2; 7;}); if(result!=1) throw 'method lookup moved'; } }");
		check("bare",
			"class Sink { var offset:Int=10; public function new() {} function add(value:Null<Int>):Int return offset+(value==null?0:value); " +
			"public function run():Int return add(true?3:null); } class Main { static function main():Void { if(new Sink().run()!=13) throw 'bare receiver'; } }");
		check("captured",
			"class Sink { var offset:Int=10; public function new() {} public function add(value:Null<Int>):Int return offset+(value==null?0:value); } " +
			"class Main { static function main():Void { final sink=new Sink(); final call=sink.add; if(call(true?3:null)!=13) throw 'captured receiver'; } }");
		check("static",
			"class Main { static function add(value:Null<Int>):Int return value==null?0:value; " +
			"static function main():Void { if(add(true?3:null)!=3 || Main.add(false?3:null)!=0) throw 'static call'; } }");
		check("extension",
			"using Main.Extensions; class Sink { public var value:Int=10; public function new() {} } " +
			"class Extensions { public static function add(sink:Sink, value:Null<Int>):Int return sink.value+(value==null?0:value); } " +
			"class Main { static function main():Void { final sink=new Sink(); if(sink.add(true?3:null)!=13) throw 'extension call'; } }");
		check("parent",
			"class Base { public var value:Null<Int>; public function new(value:Null<Int>) { this.value=value; } } " +
			"class Child extends Base { public function new() { super(true?3:null); } } " +
			"class Main { static function main():Void { if(new Child().value!=3) throw 'parent constructor'; } }");
		if (failures != 0)
			throw "call argument control failures=" + failures;
		Sys.println("CALL_ARGUMENT_CONTROL:PASS");
	}
}
