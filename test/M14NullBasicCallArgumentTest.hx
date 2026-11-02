import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/**
	`f(null)` to a required `Int`, `Float`, `Bool` or basic-abstract parameter follows
	upstream Haxe 4.3.7 per target.

	Why: upstream accepts the call on its dynamic targets (JavaScript, Neko, Python,
	Lua, PHP and the interpreter) and rejects it on its static targets (C++,
	HashLink, Java, C#) with "On static platforms, null can't be used as basic type
	Int". This holds for static and instance methods, constructors and function
	values. An optional `?v:Int` parameter accepts null on every target. hxhx
	rejected declared-method calls on every target and accepted constructors and
	function values on every target.

	What: each target compiles one batched program with upstream first, then hxhx
	types the same program with that target's defines. Static-target rejections run
	one case at a time, because typing stops at the first error.

	Native OCaml (documented divergence): hxhx accepts the call, like upstream's
	dynamic targets, but a native unboxed `int`, `float` or `bool` parameter cannot
	hold null. The call raises the catchable "Null Access" at the argument instead,
	as passing a null `Null<Int>` already does. The upstream interpreter passes null
	through. The native observer checks both, after an optional `o(null)` in the
	same function. A parameter written as an abstract or typedef over a basic type
	(`q(v:Abs)`), and any call through a function value, stops with a named native
	error instead, because the backend cannot convert its written null yet
	(haxe_ocaml-8gouw).
**/
class M14NullBasicCallArgumentTest {
	static final declarations = 'abstract Abs(Int) from Int to Int{}typedef MyInt = Int;'
		+ 'class C{public function new(v:Int){} public function m(v:Int):Void{}}'
		+ 'class CA{public function new(v:Abs){}}'
		+ 'class O{public function new(?v:Int){}}'
		+ 'abstract SA(Array<Int>){public inline function new(){this=[1];}'
		+ '@:arrayAccess public function get(i:Int):Abs return this[i];'
		+ '@:arrayAccess public function set(i:Int,v:Abs):Abs{this[i]=v;return v;}}';
	static final helpers = 'static function f(v:Int):Int return 0;static function g(v:Float):Float return 0;static function h(v:Bool):Bool return true;'
		+ 'static function q(v:Abs):Void{}static function a(v:MyInt):Void{}static function o(?v:Int):Int return 0;';

	/** Each case is accepted on dynamic targets and rejected on static targets. */
	static final required = [
		{name: "static_int", body: 'f(null);'},
		{name: "static_float", body: 'g(null);'},
		{name: "static_bool", body: 'h(null);'},
		{name: "instance_method", body: 'var c=new C(1);c.m(null);'},
		{name: "constructor", body: 'new C(null);'}
	];

	/**
		Calls whose written null the native OCaml backend cannot convert yet: parameters
		written as an abstract or typedef over a basic type, and every call through a
		function value (a local, a method value, an object field or an array element),
		which reaches the native call without a trustworthy parameter type. Upstream
		treats them like any basic parameter. hxhx stops with a named error on native
		OCaml (haxe_ocaml-8gouw) instead of passing a reinterpreted null into an unboxed
		slot. `staticRejects` is false for the indexed setter, which upstream rejects
		only on C# (see M14IndexedNullSetterTest).
	**/
	static final indirect = [
		{name: "basic_abstract", body: 'q(null);', staticRejects: true},
		{name: "basic_typedef", body: 'a(null);', staticRejects: true},
		{name: "abstract_constructor", body: 'new CA(null);', staticRejects: true},
		{name: "abstract_function_value", body: 'var fn=q;fn(null);', staticRejects: true},
		{name: "abstract_indexed_setter", body: 'var s=new SA();s[0]=null;', staticRejects: false},
		{name: "function_value", body: 'var fn=f;fn(null);', staticRejects: true},
		{name: "method_value", body: 'var c=new C(1);var m=c.m;m(null);', staticRejects: true},
		{name: "object_field_function", body: 'var ob={fn:f};ob.fn(null);', staticRejects: true},
		{name: "array_element_function", body: 'var arr=[f];arr[0](null);', staticRejects: true}
	];

	static final nativeUnsupported = "is not yet supported on the native OCaml target (haxe_ocaml-8gouw)";

	/** Accepted on every target. */
	static final optional = 'o(null);o();new O(null);';

	static final dynamicTargets = [
		{upstream: ["-js", "o.js"], local: "js"},
		{upstream: ["-neko", "o.n"], local: "neko"},
		{upstream: ["-python", "o.py"], local: "python"},
		{upstream: ["-lua", "o.lua"], local: "lua"},
		{upstream: ["-php", "php"], local: "php"}
	];

	static final staticTargets = [
		{upstream: ["-cpp", "cpp"], local: "cpp"},
		{upstream: ["-hl", "o.hl"], local: "hl"},
		{upstream: ["-java", "java"], local: "java"},
		{upstream: ["-cs", "cs"], local: "cs"}
	];

	static function main():Void {
		final methods = new StringBuf();
		for (index in 0...required.length)
			methods.add('static function case' + index + '():Void{' + required[index].body + '}');
		final direct = program(methods.toString() + 'static function optional():Void{' + optional + '}');
		for (index in 0...indirect.length)
			methods.add('static function indirect' + index + '():Void{' + indirect[index].body + '}');
		final accepted = program(methods.toString() + 'static function optional():Void{' + optional + '}');
		requireUpstream(accepted, ["--interp"], true, "interp");
		for (target in dynamicTargets) {
			requireUpstream(accepted, target.upstream, true, target.local);
			requireLocal(accepted, target.local, null, target.local);
			Sys.println("NULL_BASIC_CALL_ARGUMENT:PASS dynamic_" + target.local);
		}
		requireLocal(direct, "ocaml", null, "ocaml");
		Sys.println("NULL_BASIC_CALL_ARGUMENT:PASS ocaml_accepts");
		for (entry in indirect)
			requireLocal(program('static function single():Void{' + entry.body + '}'), "ocaml", nativeUnsupported, "ocaml " + entry.name);
		Sys.println("NULL_BASIC_CALL_ARGUMENT:PASS ocaml_indirect_rejected");
		final optionalOnly = program('static function optional():Void{' + optional + '}');
		for (target in staticTargets) {
			requireUpstream(optionalOnly, target.upstream, true, target.local + " optional");
			requireLocal(optionalOnly, target.local, null, target.local + " optional");
			for (entry in required.concat(indirect.filter(entry -> entry.staticRejects).map(entry -> {name: entry.name, body: entry.body}))) {
				final source = program('static function single():Void{' + entry.body + '}');
				requireUpstream(source, target.upstream, false, target.local + " " + entry.name);
				requireLocal(source, target.local, "On static platforms, null can't be used as basic type", target.local + " " + entry.name);
			}
			Sys.println("NULL_BASIC_CALL_ARGUMENT:PASS static_" + target.local);
		}
		checkNative();
		Sys.println("NULL_BASIC_CALL_ARGUMENT:PASS");
	}

	static function program(members:String):String
		return declarations + 'class Main{' + helpers + members + 'static function main():Void{}}';

	/** Upstream must accept, or reject with the static-platform diagnostic. */
	static function requireUpstream(source:String, target:Array<String>, accepted:Bool, label:String):Void {
		final root = JsRuntimeFixture.reserveOutput();
		sys.io.File.saveContent(root + "/Main.hx", source);
		final arguments = ["-cp", root, "-main", "Main", target[0]];
		if (target.length > 1)
			arguments.push(root + "/" + target[1]);
		arguments.push("--no-output");
		final process = new sys.io.Process("node_modules/.bin/haxe", arguments);
		final output = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (accepted ? code != 0 : (code == 0 || output.indexOf("On static platforms, null can't be used as basic type") < 0))
			throw "upstream null basic argument expectation differs: " + label + " " + output;
	}

	/** hxhx typing with one target's defines; `diagnostic` null means it must succeed. */
	static function requireLocal(source:String, target:String, diagnostic:Null<String>, label:String):Void {
		final error = typingError(source, target);
		if (diagnostic == null ? error != null : (error == null || error.indexOf(diagnostic) < 0))
			throw "hxhx null basic argument expectation differs: " + label + " " + error;
	}

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

	/** The interpreter passes null through; native unboxed parameters raise a catchable Null Access at the call. */
	static function checkNative():Void {
		final attempts = [
			{label: "int", call: 'Main.show(f(null));'},
			{label: "float", call: 'Main.show(g(null));'},
			{label: "bool", call: 'Main.show(h(null));'},
			{label: "method", call: 'var c=new C(1);c.m(null);Main.show(0);'},
			{label: "constructor", call: 'new C(null);Main.show(0);'}
		];
		final body = new StringBuf();
		// An optional `o(null)` comes first in the same function: its null must not lend
		// its carrier to the later required Int and Float nulls.
		body.add('Sys.println("optional:"+o(null)+":"+o());');
		for (attempt in attempts)
			body.add('Sys.print("' + attempt.label + ':");try{' + attempt.call + '}catch(e:String){Sys.println(e);}');
		final source = declarations
			+ 'class Main{'
			+ helpers
			+ 'public static function show(v:Dynamic):Void Sys.println("value");'
			+ 'static function main():Void{'
			+ body.toString()
			+ '}}';
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		// Every attempt reaches `show`, which prints "value" whatever it receives.
		final passed = [for (attempt in attempts) attempt.label + ":value"].join("\n");
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-cp", root, "-main", "Main", "--interp"],
			expected: "optional:0:0\n" + passed + "\n"
		});
		final raised = [for (attempt in attempts) attempt.label + ":Null Access"].join("\n");
		final prepared = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram(prepared, false), root + "/ocaml", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: "optional:0:0\n" + raised + "\n"});
		Sys.println("NULL_BASIC_CALL_ARGUMENT:PASS native_null_access");
	}
}
