import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/**
	`b[i] = null` through a declared indexed setter whose value parameter is a basic
	type (`set(i:Int, v:Int)`) follows upstream Haxe 4.3.7 per target.

	Why: upstream accepts the write on JavaScript, C++, HashLink, Java and the other
	targets it was checked on, and rejects it only on C# with "On static platforms,
	null can't be used as basic type Int". hxhx rejected it everywhere with "No
	compatible declared indexed setter", because setter selection scored a null
	literal against `Int` like an ordinary call argument.

	What: accepted cases share one program. Upstream JavaScript compiles it first,
	then hxhx types it for the JavaScript and OCaml targets. Each C# case runs alone,
	because typing stops at the first rejection. A JavaScript runtime observer checks
	the stored value and the setter result against upstream output.

	Native OCaml divergence (documented): the interpreter and JavaScript store null.
	A native `Int`, `Float` or `Bool` parameter is an unboxed OCaml value that cannot
	hold null, so the native setter call raises the catchable "Null Access" exception,
	exactly as passing a null `Null<Int>` already does. It never stores a
	reinterpreted pointer. A `Map<String,Int>` value is a generic slot and stores null
	natively too. The native observer checks both behaviours.
**/
class M14IndexedNullSetterTest {
	static final declarations = 'abstract B(Array<Int>){public inline function new(){this=[1];}'
		+ '@:arrayAccess public function get(i:Int):Int return this[i];'
		+ '@:arrayAccess public function set(i:Int,v:Int):Int{this[i]=v;return v;}}'
		+ 'abstract F(Array<Float>){public inline function new(){this=[1];}'
		+ '@:arrayAccess public function get(i:Int):Float return this[i];'
		+ '@:arrayAccess public function set(i:Int,v:Float):Float{this[i]=v;return v;}}'
		+ 'abstract S<T>(Array<T>){public inline function new(){this=[];}'
		+ '@:op([]) public static function read<T>(s:S<T>,i:Int):T return null;'
		+ '@:op([]) public static function write<T>(s:S<T>,i:Int,v:T):T return v;}';

	static final cases = [
		{name: "int_setter", body: 'var b=new B();b[0]=null;'},
		{name: "int_setter_result", body: 'var b=new B();var r:Int=b[0]=null;'},
		{name: "untyped_int_setter", body: 'var b=new B();untyped b[0]=null;'},
		{name: "float_setter", body: 'var f=new F();f[0]=null;'},
		{name: "generic_static_setter", body: 'var s=new S<Int>();s[0]=null;'},
		{name: "nullable_owner", body: 'var g:Null<B>=new B();g[0]=null;'},
		{name: "map_value", body: 'var m:Map<String,Int>=new Map();m["k"]=null;'}
	];

	static function main():Void {
		final methods = new StringBuf();
		for (index in 0...cases.length)
			methods.add('static function case' + index + '():Void{' + cases[index].body + '}');
		final batched = program(methods.toString());
		final upstreamError = upstream(batched, ["-js", "upstream.js"]);
		if (upstreamError != null)
			throw "upstream JavaScript rejects indexed null setter cases: " + upstreamError;
		for (target in ["js", "ocaml"]) {
			final local = typingError(batched, target);
			if (local != null)
				throw "hxhx " + target + " rejects indexed null setter cases: " + local;
		}
		for (entry in cases)
			Sys.println("INDEXED_NULL_SETTER:PASS " + entry.name);
		for (entry in cases) {
			final source = program('static function main():Void{' + entry.body + '}');
			final expected = upstream(source, ["-cs", "cs"]);
			if (expected == null || expected.indexOf("On static platforms, null can't be used as basic type") < 0)
				throw "upstream C# accepts indexed null setter: " + entry.name + " " + expected;
			final local = typingError(source, "cs");
			if (local == null || local.indexOf("On static platforms, null can't be used as basic type") < 0)
				throw "hxhx C# indexed null setter differs: " + entry.name + " " + local;
			Sys.println("INDEXED_NULL_SETTER:PASS cs_" + entry.name);
		}
		checkRuntime();
		checkNative();
		Sys.println("INDEXED_NULL_SETTER:PASS");
	}

	/** Upstream's interpreter stores null; native unboxed setter slots raise a catchable Null Access instead. */
	static function checkNative():Void {
		final source = declarations
			+ 'abstract Z(Array<Bool>){public inline function new(){this=[true];}'
			+ '@:arrayAccess public function get(i:Int):Bool return this[i];'
			+ '@:arrayAccess public function set(i:Int,v:Bool):Bool{this[i]=v;return v;}}'
			+ 'class Main{'
			+ 'static function intCase():Void{var b=new B();try{b[0]=null;Sys.println("int:stored");}catch(e:String){Sys.println("int:"+e);}}'
			+
			'static function resultCase():Void{var b=new B();try{var r:Int=b[0]=null;Sys.println("result:stored");}catch(e:String){Sys.println("result:"+e);}}'
			+ 'static function floatCase():Void{var f=new F();try{f[0]=null;Sys.println("float:stored");}catch(e:String){Sys.println("float:"+e);}}'
			+ 'static function boolCase():Void{var z=new Z();try{z[0]=null;Sys.println("bool:stored");}catch(e:String){Sys.println("bool:"+e);}}'
			+
			'static function mapCase():Void{var m:Map<String,Int>=new Map();try{m["k"]=null;Sys.println("map:stored:"+m.exists("k"));}catch(e:String){Sys.println("map:"+e);}}'
			+ 'static function main():Void{intCase();resultCase();floatCase();boolCase();mapCase();}}';
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-cp", root, "-main", "Main", "--interp"],
			expected: "int:stored\nresult:stored\nfloat:stored\nbool:stored\nmap:stored:true\n"
		});
		final prepared = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram(prepared, false), root + "/ocaml", true);
		M14Stage3RuntimeFixture.observe({
			command: artifact,
			arguments: [],
			expected: "int:Null Access\nresult:Null Access\nfloat:Null Access\nbool:Null Access\nmap:stored:true\n"
		});
		Sys.println("INDEXED_NULL_SETTER:PASS native_null_access");
	}

	static function program(members:String):String
		return declarations
			+ 'class Main{'
			+ members
			+ (members.indexOf("function main(") >= 0 ? "" : 'static function main():Void{}')
			+ '}';

	/** Null when upstream compiles the source for the given target without output; otherwise its diagnostic. */
	static function upstream(source:String, target:Array<String>):Null<String> {
		final root = JsRuntimeFixture.reserveOutput();
		sys.io.File.saveContent(root + "/Main.hx", source);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", target[0], root + "/" + target[1], "--no-output"]);
		final output = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return code == 0 ? null : output;
	}

	/** Type `Main` with one target's defines and class paths; null when typing succeeds. */
	static function typingError(source:String, target:String):Null<String> {
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final arguments = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: target
		});
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], target, target), index);
		loader.markResolvedAlready([module]);
		try {
			TyperStage.typeResolvedModule(module, index, loader, true);
			return null;
		} catch (error:TyperError) {
			return error.toString();
		}
	}

	/** The setter receives null: the stored value and the assignment result are both null on JavaScript. */
	static function checkRuntime():Void {
		final source = declarations
			+ 'class Main{static function main():Void{var b=new B();var r=b[0]=null;var stored:Null<Int>=b[0];'
			+ 'trace(Std.string(r)+":"+Std.string(stored));}}';
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		if (Sys.command("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]) != 0)
			throw "indexed null setter upstream observer did not compile";
		final expected = "null:null\n";
		M14Stage3RuntimeFixture.observe({command: "node", arguments: [root + "/upstream.js"], expected: path + ":1: " + expected});
		JsRuntimeFixture.assertRuntime(M14Stage3RuntimeFixture.prepareMain({source: source, path: path, root: root}), "Main", expected);
		Sys.println("INDEXED_NULL_SETTER:PASS runtime");
	}
}
