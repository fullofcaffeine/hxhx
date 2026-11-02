import backend.BackendContext;
import backend.js.JsBackend;

/**
	`untyped b[i] += v`, `untyped b[i]++` and `untyped ++b[i]` on an abstract with a
	declared indexed getter and setter must run the getter, the step and the setter,
	exactly as upstream Haxe 4.3.7 JavaScript does.

	Why: the parser binds `untyped` to the indexed place of a compound assignment
	(`(untyped b[i]) += v`) and to the whole update of `++`/`--`. Upstream applies
	`untyped` to the whole expression in both cases. The update still reads and writes
	through the declared helpers; `untyped` only leaves the result unconstrained.

	What: every typing case runs upstream first, then types the same source through the
	real JavaScript providers and builds every `Main` body. A runtime case compares
	getter/setter events, operand order and results with upstream JavaScript output.
	Abstract indexed updates are JavaScript-only today (haxe_ocaml-rgmu4), and so is
	`??=` on a declared indexed place, typed or untyped.
**/
class M14UntypedIndexedUpdateTest {
	static final getter = '@:arrayAccess public inline function get(i:Int):Int{Main.events+="G";return this[i];}';
	static final setter = '@:arrayAccess public inline function set(i:Int,v:Int):Int{Main.events+="S";this[i]=v;return v+30;}';

	static function main():Void {
		final both = getter + setter;
		check("compound", both, 'var b=new B();untyped b[0]+=1;', true);
		check("compound_minus_local", both, 'var b=new B();var x=2;untyped b[0]-=x;', true);
		check("postfix", both, 'var b=new B();untyped b[0]++;', true);
		check("prefix", both, 'var b=new B();untyped ++b[0];', true);
		check("prefix_decrement", both, 'var b=new B();untyped --b[0];', true);
		check("compound_result_is_unconstrained", both, 'var b=new B();var s:String=untyped b[0]+=1;', true);
		check("postfix_result_is_unconstrained", both, 'var b=new B();var s:String=untyped b[0]++;', true);
		check("compound_result_to_call", both, 'var b=new B();take(untyped b[0]+=1);', true);
		check("map_compound", "", 'var m=["k"=>1];untyped m["k"]+=1;untyped m["k"]++;', true);
		check("vector_compound", "", 'var v=new haxe.ds.Vector<Int>(2);untyped v[0]+=1;untyped v[0]++;', true);
		check("raw_storage_compound", "", 'var b=new B();untyped b[0]+=1;', true);
		check("compound_getter_only", getter, 'var b=new B();untyped b[0]+=1;', false);
		check("postfix_getter_only", getter, 'var b=new B();untyped b[0]++;', false);
		check("prefix_getter_only", getter, 'var b=new B();untyped --b[0];', false);
		check("compound_setter_only", setter, 'var b=new B();untyped b[0]+=1;', false);
		check("compound_wrong_value", both, 'var b=new B();untyped b[0]+="x";', false);
		check("compound_wrong_index", both, 'var b=new B();untyped b["x"]+=1;', false);
		checkNullCoalescingDeferred(both);
		checkRuntime(both);
		Sys.println("UNTYPED_INDEXED_UPDATE:PASS");
	}

	static function program(members:String, body:String):String
		return 'abstract B(Array<Int>){public inline function new(){this=[1];}'
			+ members
			+ '}'
			+ 'class Main{public static var events:String="";static function take(v:Int):Void{}'
			+ 'static function main():Void{'
			+ body
			+ '}}';

	/** Upstream acceptance first; then hxhx types the program and builds every `Main` body. */
	static function check(name:String, members:String, body:String, accepted:Bool):Void {
		final source = program(members, body);
		final upstream = upstreamCompile(source);
		if ((upstream == null) != accepted)
			throw "upstream untyped indexed update expectation differs: " + name + " " + upstream;
		final local = localCompile(source);
		if ((local == null) != accepted)
			throw "local untyped indexed update expectation differs: " + name + " " + local;
		Sys.println("UNTYPED_INDEXED_UPDATE:PASS " + name);
	}

	/**
		Upstream accepts `untyped b[i] ??= v` with a getter and a setter. hxhx keeps the
		explicit diagnostic it already gives for the typed `b[i] ??= v`, because the
		declared-index `??=` schedule is not implemented yet (haxe_ocaml-rgmu4).
	**/
	static function checkNullCoalescingDeferred(both:String):Void {
		final source = program(both, 'var b=new B();untyped b[0]??=1;');
		if (upstreamCompile(source) != null)
			throw "upstream no longer accepts untyped indexed ??=";
		final local = localCompile(source);
		if (local == null || local.indexOf("null-coalescing assignment is not yet supported (haxe_ocaml-rgmu4)") < 0)
			throw "untyped indexed ??= lost its explicit diagnostic: " + local;
		if (localCompile(program(getter, 'var b=new B();untyped b[0]??=1;')) == null)
			throw "getter-only untyped indexed ??= was accepted";
		Sys.println("UNTYPED_INDEXED_UPDATE:PASS null_coalescing_deferred");
	}

	/** Null when upstream compiles the source to JavaScript; otherwise its diagnostic. */
	static function upstreamCompile(source:String):Null<String> {
		final root = JsRuntimeFixture.reserveOutput();
		sys.io.File.saveContent(root + "/Main.hx", source);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js", "--no-output"]);
		final output = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return code == 0 ? null : output;
	}

	/** Null when hxhx types the source and builds every `Main` body; otherwise the typer diagnostic. */
	static function localCompile(source:String):Null<String> {
		try {
			final loaded = JsSourceProgramFixture.load({sources: [{path: "Main.hx", source: source}], requiredModules: []});
			for (module in loaded.program.getTypedModules())
				for (owner in module.getTypedClasses())
					if (HxClassDecl.getName(owner.getSourceDeclaration()) == "Main")
						for (fn in owner.getFunctions())
							fn.getBody();
			return null;
		} catch (error:TyperError) {
			return error.toString();
		}
	}

	/** Getter/setter events, receiver/index/value order and results match upstream JavaScript. */
	static function checkRuntime(both:String):Void {
		final source = 'abstract B(Array<Int>){public inline function new(){this=[1];}'
			+ both
			+ '}'
			+ 'class Main{public static var events:String="";static var box:B=new B();'
			+ 'static function owner():B{events+="R";return box;}'
			+ 'static function index():Int{events+="I";return 0;}'
			+ 'static function value():Int{events+="V";return 5;}'
			+
			'static function show(label:String,result:Int):Void{final stored:Int=box[0];js.Syntax.code("console.log({0})",label+":"+events+":"+result+":"+stored);events="";}'
			+ 'static function main():Void{'
			+ 'final compound:Int=untyped owner()[index()]+=value();show("compound",compound);'
			+ 'final postfix:Int=untyped box[0]++;show("postfix",postfix);'
			+ 'final prefix:Int=untyped ++box[0];show("prefix",prefix);'
			+ 'final decrement:Int=untyped box[0]--;show("decrement",decrement);'
			+ 'var map=["k"=>1];final mapCompound:Int=untyped map["k"]+=2;final mapPostfix:Int=untyped map["k"]++;'
			+ 'js.Syntax.code("console.log({0})","map:"+mapCompound+":"+mapPostfix+":"+map["k"]);}}';
		final root = JsRuntimeFixture.reserveOutput();
		sys.io.File.saveContent(root + "/Main.hx", source);
		if (Sys.command("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]) != 0)
			throw "untyped indexed update upstream observer did not compile";
		final expected = run(root + "/upstream.js");
		final loaded = JsSourceProgramFixture.load({
			sources: [{path: "Main.hx", source: source}],
			requiredModules: ["haxe.ds.Map", "haxe.ds.StringMap"]
		});
		final script = root + "/main.js";
		new JsBackend().emit(JsSourceProgramFixture.retain(loaded, "full"),
			new BackendContext(root, script, "Main", false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		final actual = run(script);
		if (actual != expected)
			throw "untyped indexed update runtime differs\nupstream:\n" + expected + "hxhx:\n" + actual;
		Sys.println("UNTYPED_INDEXED_UPDATE:PASS runtime " + StringTools.replace(StringTools.trim(expected), "\n", " | "));
	}

	static function run(script:String):String {
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node", "--use-strict", script]);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stderr != "")
			throw "untyped indexed update runtime failed: " + script + " " + code + "\n" + stdout + stderr;
		return stdout;
	}
}
