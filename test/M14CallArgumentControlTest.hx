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

	/** Check the exact observation; ordinary assertion fixtures produce no output. */
	static function assertProcess(process:sys.io.Process, context:String, expected:String = ""):Void {
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = try {
			process.exitCode();
		} catch (error:haxe.Exception) {
			process.close();
			throw new haxe.Exception(context + " did not exit normally: " + stdout + stderr, error);
		}
		process.close();
		if (code != 0 || stdout != expected)
			throw context + " failed: " + stdout + stderr;
	}

	/**
		Upstream captures null and rejects its invocation. Until native nullable
		method storage is supported, reject capture explicitly instead of binding
		a callable that can return a normal result without using its null receiver.
		This checks an unsupported boundary, not native parity for null captures.
	 */
	static function checkNullReceiver():Void {
		final root = ".tmp/call_argument_control_null_receiver";
		final source = "class Sink { public function new() {} public function put(value:Int):Int return value; } "
			+ "class Main { static function main():Void { var sink:Sink=null; try { final captured=sink.put; "
			+ "Sys.println(captured==null ? 'captured-null' : 'captured-non-null'); Sys.println('capture-ok:'+captured(7)); "
			+ "} catch(error:Dynamic) { Sys.println('capture-error:'+Std.string(error)); } } }";
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Main.hx", source);
		assertProcess(new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]), "upstream null receiver",
			"captured-null\ncapture-error:Cannot call null\n");
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true);
		assertProcess(new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable]), "native null receiver",
			"capture-error:Capturing a method from a null receiver is not supported\n");
		Sys.println("CALL_ARGUMENT_CONTROL:PASS null_receiver_rejected");
	}

	static function main():Void {
		check("nullable",
			"class Sink { public function new() {} public function put(value:Null<Int>):Int return value==null ? 9 : value; } " +
			"class Main { static function main():Void { final sink=new Sink(); if(sink.put(true ? 3 : null)!=3 || sink.put(false ? 3 : null)!=9) throw 'nullable call'; } }",
			true);
		check("native_capture_order",
			"class Sink { public function new() {} public function put(value:Null<Int>):Int return value==null ? 9 : value; } "
			+ "class State { public var order:Int; public function new() {} } "
			+ "class Main { static function mark(state:State, digit:Int):Int { state.order=state.order*10+digit; return digit; } "
			+ "static function receiver(state:State):Sink { mark(state,1); return new Sink(); } static function main():Void { "
			+ "final state=new State(); state.order=0; "
			+ "final result=receiver(state).put({ mark(state,2); var value:Null<Int>=true ? mark(state,3) : null; mark(state,4); value; }); "
			+ "if(result!=3 || state.order!=1234) throw 'native receiver capture order'; } }",
			true);
		check("native_zero_argument_capture",
			"class Sink { public var calls:Int; public function new() {} public function read():Int { calls=calls+1; return calls; } } " +
			"class Main { static function main():Void { final sink=new Sink(); sink.calls=0; final call=sink.read; " +
			"if(sink.calls!=0) throw 'eager method capture'; if(call()!=1 || call()!=2 || sink.calls!=2) throw 'captured receiver state'; } }",
			true);
		check("native_generic_capture",
			"class State { public var order:Int; public function new() {} } "
			+ "class Sink { var state:State; public function new(state:State) { this.state=state; } "
			+ "public function echo<T>(value:T):T { state.order=state.order*10+3; return value; } } "
			+ "class Main { static function receiver(state:State):Sink { state.order=state.order*10+1; return new Sink(state); } "
			+ "static function main():Void { final state=new State(); state.order=0; "
			+ "final text=receiver(state).echo({ state.order=state.order*10+2; true ? 'text' : 'wrong'; }); "
			+ "if(text!='text' || state.order!=123) throw 'generic argument order'; "
			+ "state.order=0; var number:Int->Int=receiver(state).echo; if(state.order!=1) throw 'eager generic invocation'; "
			+ "if(number(7)!=7 || number(8)!=8 || state.order!=133) throw 'generic integer capture'; "
			+ "var truth:Bool->Bool=receiver(state).echo; if(!truth(true) || truth(false)) throw 'generic boolean capture'; "
			+ "var decimal:Float->Float=receiver(state).echo; if(decimal(1.5)!=1.5) throw 'generic float capture'; } }",
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
		check("static_dynamic",
			"class Main { static dynamic function run(value:Int):Int return 1; static function main():Void { " +
			"final result=run({run=function(value:Int):Int return 2; 7;}); if(result!=1 || run(7)!=2) throw 'static method lookup moved'; } }");
		check("static_effects",
			"class Main { static var order:Int=0; static function accept(value:Int):Int { order=order*10+3; return value; } " +
			"static function main():Void { final result=Main.accept({order=1; order=order*10+2; 7;}); if(result!=7 || order!=123) throw 'static argument order'; } }");
		check("parent",
			"class Base { public var value:Null<Int>; public function new(value:Null<Int>) { this.value=value; } } " +
			"class Child extends Base { public function new() { super(true?3:null); } } " +
			"class Main { static function main():Void { if(new Child().value!=3) throw 'parent constructor'; } }");
		if (failures != 0)
			throw "call argument control failures=" + failures;
		checkNullReceiver();
		Sys.println("CALL_ARGUMENT_CONTROL:PASS");
	}
}
