/**
	`untyped b[i] = v` must still select a declared abstract indexed setter.

	Why: the parser binds `untyped` to the indexed place (`(untyped b[i]) = v`)
	while upstream Haxe 4.3.7 applies it to the whole assignment. Either way the
	assignment writes through the abstract, so a getter-only abstract must be
	rejected, and index/value operands must match the declared setter. The
	`untyped` wrapper only gives the assignment an unconstrained result type.

	What: every typing case first runs upstream Haxe 4.3.7 as the expectation,
	then types and projects the same source locally. A JavaScript runtime
	observer compares receiver/index/value/setter effect order and the setter
	result with upstream output.
**/
class M14UntypedIndexedAssignmentTest {
	static final getter = '@:arrayAccess function get(i:Int):Int return this[i];';
	static final setter = '@:arrayAccess function set(i:Int,v:Int):Int return this[i]=v;';
	static final stringResultSetter = '@:arrayAccess function set(i:Int,v:Int):String{this[i]=v;return "s";}';

	static function main():Void {
		check("getter_only_return", getter, 'static function w(b:B):Int return untyped b[0]=9;', false);
		check("getter_only_statement", getter, 'static function w(b:B):Void{untyped b[0]=9;}', false);
		check("wrong_index", getter + setter, 'static function w(b:B):Int return untyped b["x"]=9;', false);
		check("wrong_value", getter + setter, 'static function w(b:B):Int return untyped b[0]="x";', false);
		check("declared_setter", getter + setter, 'static function w(b:B):Int return untyped b[0]=9;', true);
		check("setter_result_is_unconstrained", getter + stringResultSetter, 'static function w(b:B):Int return untyped b[0]=9;', true);
		check("setter_result_to_string", getter + setter, 'static function w(b:B):Void{var s:String=untyped b[0]=9;}', true);
		check("raw_untyped_storage", "", 'static function w(b:B):Int return untyped b[0]=9;', true);
		// The untyped result flows into declared setters, calls and locals.
		final take = 'static function take(v:Int):Void{}';
		check("chained_untyped_assignment", getter + setter, 'static function w(b:B):Void{untyped b[0]=untyped b[0]=1;}', true);
		check("result_local_to_setter", getter + setter, 'static function w(b:B):Void{var x=untyped b[0]=1;b[0]=x;}', true);
		check("result_local_to_call", getter + setter, take + 'static function w(b:B):Void{var x=untyped b[0]=1;take(x);}', true);
		check("result_to_call", getter + setter, take + 'static function w(b:B):Void{take(untyped b[0]=1);}', true);
		check("result_to_typed_setter", getter + setter, 'static function w(b:B):Void{b[1]=untyped b[0]=1;}', true);
		check("result_local_to_untyped_setter", getter + setter, 'static function w(b:B):Void{var x=untyped b[0]=1;untyped b[0]=x;}', true);
		// Update forms stay rejected for a getter-only abstract; real untyped update
		// support with a declared setter is owned by haxe_ocaml-2hkru.
		check("compound_getter_only", getter, 'static function w(b:B):Void{untyped b[0]+=1;}', false);
		check("null_coalescing_getter_only", getter, 'static function w(b:B):Void{untyped b[0]??=1;}', false);
		check("parenthesized_untyped_place", getter + setter, 'static function w(b:B):Void{(untyped b[0])=9;}', false);
		checkRuntime();
		Sys.println("UNTYPED_INDEXED_ASSIGNMENT:PASS");
	}

	static function program(members:String, body:String):String
		return 'abstract B(Array<Int>){public inline function new(){this=[1];}'
			+ members
			+ '}class Main{'
			+ body
			+ 'static function main():Void{}}';

	/** Upstream acceptance is checked before the same source reaches local typing and backend projection. */
	static function check(name:String, members:String, body:String, accepted:Bool):Void {
		final source = program(members, body);
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js", "--no-output"]);
		final output = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if ((code == 0) != accepted)
			throw "upstream untyped indexed expectation differs: " + name + " " + output;
		var localAccepted = true;
		try {
			M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root}).getBackendProjection();
		} catch (error:TyperError) {
			if (accepted)
				throw error;
			localAccepted = false;
		}
		if (localAccepted != accepted)
			throw "local untyped indexed expectation differs: " + name;
		Sys.println("UNTYPED_INDEXED_ASSIGNMENT:PASS " + name);
	}

	/** Receiver, index and value run once in source order before the setter, and the setter result is the assignment value. */
	static function checkRuntime():Void {
		final source = 'abstract B(Array<Int>){public inline function new(){this=[1];}'
			+ '@:arrayAccess public inline function get(i:Int):Int{Main.events+="G";return this[i];}'
			+ '@:arrayAccess public inline function set(i:Int,v:Int):Int{Main.events+="S";this[i]=v;return v+30;}}'
			+ 'class Main{public static var events:String="";static var box:B=new B();'
			+ 'static function owner():B{events+="R";return box;}'
			+ 'static function index():Int{events+="I";return 0;}'
			+ 'static function value():Int{events+="V";return 9;}'
			+ 'static function write():Int return untyped owner()[index()]=value();'
			+ 'static function main():Void{final written=write();final stored:Int=box[0];trace(events+":"+written+":"+stored);}}';
		final expected = "RIVSG:39:9\n";
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		if (Sys.command("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]) != 0)
			throw "untyped indexed assignment upstream observer did not compile";
		M14Stage3RuntimeFixture.observe({
			command: "node",
			arguments: [root + "/upstream.js"],
			expected: path + ":1: " + expected
		});
		JsRuntimeFixture.assertRuntime(M14Stage3RuntimeFixture.prepareMain({source: source, path: path, root: root}), "Main", expected);
		Sys.println("UNTYPED_INDEXED_ASSIGNMENT:PASS runtime");
	}
}
