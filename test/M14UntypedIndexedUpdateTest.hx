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

	What: every typing case runs upstream first. Accepted cases are then typed together
	in one program through the real JavaScript providers, with every `Main` body built.
	Rejected and deferred cases only need typing, so they skip the JavaScript standard
	library. A runtime case compares
	getter/setter events, operand order and results with upstream JavaScript output.
	Abstract indexed updates are JavaScript-only today (haxe_ocaml-rgmu4), and so is
	`??=` on a declared indexed place, typed or untyped.
**/
class M14UntypedIndexedUpdateTest {
	static final getter = '@:arrayAccess public inline function get(i:Int):Int{Main.events+="G";return this[i];}';
	static final setter = '@:arrayAccess public inline function set(i:Int,v:Int):Int{Main.events+="S";this[i]=v;return v+30;}';

	static function main():Void {
		final both = getter + setter;
		checkAccepted([
			{name: "compound", members: both, body: 'var b=new B();untyped b[0]+=1;'},
			{name: "compound_minus_local", members: both, body: 'var b=new B();var x=2;untyped b[0]-=x;'},
			{name: "postfix", members: both, body: 'var b=new B();untyped b[0]++;'},
			{name: "prefix", members: both, body: 'var b=new B();untyped ++b[0];'},
			{name: "prefix_decrement", members: both, body: 'var b=new B();untyped --b[0];'},
			{name: "compound_result_is_unconstrained", members: both, body: 'var b=new B();var s:String=untyped b[0]+=1;'},
			{name: "postfix_result_is_unconstrained", members: both, body: 'var b=new B();var s:String=untyped b[0]++;'},
			{name: "compound_result_to_call", members: both, body: 'var b=new B();take(untyped b[0]+=1);'},
			{name: "map_compound", members: "", body: 'var m=["k"=>1];untyped m["k"]+=1;untyped m["k"]++;'},
			{name: "vector_compound", members: "", body: 'var v=new haxe.ds.Vector<Int>(2);untyped v[0]+=1;untyped v[0]++;'},
			{name: "raw_storage_compound", members: "", body: 'var b=new B();untyped b[0]+=1;'}
		]);
		reject("compound_getter_only", getter, 'var b=new B();untyped b[0]+=1;');
		reject("postfix_getter_only", getter, 'var b=new B();untyped b[0]++;');
		reject("prefix_getter_only", getter, 'var b=new B();untyped --b[0];');
		reject("compound_setter_only", setter, 'var b=new B();untyped b[0]+=1;');
		reject("compound_wrong_value", both, 'var b=new B();untyped b[0]+="x";');
		reject("compound_wrong_index", both, 'var b=new B();untyped b["x"]+=1;');
		// Upstream accepts `untyped b[i] ??= v` with a getter and a setter. hxhx keeps
		// the diagnostic that typed `b[i] ??= v` already gives: the declared-index
		// `??=` schedule is not implemented yet (haxe_ocaml-rgmu4).
		final coalescing = "null-coalescing assignment is not yet supported (haxe_ocaml-rgmu4)";
		deferred("null_coalescing", both, 'var b=new B();untyped b[0]??=1;', coalescing);
		reject("null_coalescing_getter_only", getter, 'var b=new B();untyped b[0]??=1;');
		// `++untyped b[i]` updates an untyped place. Upstream increments the inlined
		// getter body in place, without a setter call. That works only when the inlined
		// getter is itself a plain place (`return this[i]`); an effectful getter body is
		// "Invalid assign". hxhx does not model the in-place form yet (haxe_ocaml-9f5qd).
		final prefixUntyped = "Untyped prefix indexed increment/decrement is not yet supported (haxe_ocaml-9f5qd)";
		final placeGetter = '@:arrayAccess public inline function get(i:Int):Int return this[i];';
		reject("prefix_untyped_place_effectful_getter", both, 'var b=new B();++untyped b[0];');
		deferred("prefix_untyped_place", placeGetter + setter, 'var b=new B();++untyped b[0];', prefixUntyped);
		deferred("prefix_decrement_untyped_place_getter_only", placeGetter, 'var b=new B();--untyped b[0];', prefixUntyped);
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

	/**
		Accepted cases share one program, so hxhx loads the JavaScript standard library
		once. Each case gets its own abstract (`B0`, `B1`, ...) and its own method.
		If the batch disagrees with upstream, each case is retried alone to name it.
	**/
	static function checkAccepted(cases:Array<{name:String, members:String, body:String}>):Void {
		final abstracts = new StringBuf();
		final methods = new StringBuf();
		final calls = new StringBuf();
		for (index in 0...cases.length) {
			final entry = cases[index];
			final owner = "B" + index;
			abstracts.add('abstract ' + owner + '(Array<Int>){public inline function new(){this=[1];}' + entry.members + '}');
			methods.add('static function case' + index + '():Void{' + StringTools.replace(entry.body, "new B()", "new " + owner + "()") + '}');
			calls.add('case' + index + '();');
		}
		final source = abstracts.toString()
			+ 'class Main{public static var events:String="";static function take(v:Int):Void{}'
			+ methods.toString()
			+ 'static function main():Void{'
			+ calls.toString()
			+ '}}';
		final upstream = upstreamCompile(source);
		final local = upstream == null ? localCompile(source) : null;
		if (upstream != null || local != null) {
			for (entry in cases) {
				final single = program(entry.members, entry.body);
				final singleUpstream = upstreamCompile(single);
				if (singleUpstream != null)
					throw "upstream rejects accepted untyped indexed update: " + entry.name + " " + singleUpstream;
				final singleLocal = localCompile(single);
				if (singleLocal != null)
					throw "local rejects accepted untyped indexed update: " + entry.name + " " + singleLocal;
			}
			throw "batched untyped indexed updates disagree while every case passes alone: " + upstream + local;
		}
		for (entry in cases)
			Sys.println("UNTYPED_INDEXED_UPDATE:PASS " + entry.name);
	}

	/** Upstream rejects; hxhx rejects while typing, before any JavaScript-only projection. */
	static function reject(name:String, members:String, body:String):Void {
		final source = program(members, body);
		final upstream = upstreamCompile(source);
		if (upstream == null)
			throw "upstream accepts rejected untyped indexed update: " + name;
		final local = typingError(source);
		if (local == null || local.indexOf("JavaScript target only") >= 0)
			throw "local untyped indexed update expectation differs: " + name + " " + local;
		Sys.println("UNTYPED_INDEXED_UPDATE:PASS " + name);
	}

	/** Upstream accepts; hxhx gives the named explicit diagnostic for a tracked gap. */
	static function deferred(name:String, members:String, body:String, diagnostic:String):Void {
		final source = program(members, body);
		if (upstreamCompile(source) != null)
			throw "upstream no longer accepts deferred untyped indexed update: " + name;
		final local = typingError(source);
		if (local == null || local.indexOf(diagnostic) < 0)
			throw "deferred untyped indexed update lost its explicit diagnostic: " + name + " " + local;
		Sys.println("UNTYPED_INDEXED_UPDATE:PASS " + name + "_deferred");
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

	/** Typing-only check without the JavaScript standard library; null when typing succeeds. */
	static function typingError(source:String):Null<String> {
		final root = JsRuntimeFixture.reserveOutput();
		try {
			M14Stage3RuntimeFixture.typeMain({source: source, path: root + "/Main.hx", root: root});
			return null;
		} catch (error:TyperError) {
			return error.toString();
		}
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
