import sys.io.File;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/**
	Exercise authored function expressions through typing and control lowering.
	Runtime assertions replace assumptions about the obsolete parser-generated
	continuation functions. Each source also runs through upstream Haxe first.
 */
class M14JsFunctionLiteralRuntimeTest {
	static function main():Void {
		run();
	}

	public static function run():Void {
		final cases:Array<{name:String, body:String, ?declarations:String}> = [
			{name: "returns",
				body: 'var unary = function(x:Int) return x + 1; if (unary(4) != 5) throw "unary";'
				+ 'var typed = function(value:Int) return value; if (typed(9) != 9) throw "typed";'
				+ 'var reserved = function(arguments:Int) return arguments; if (reserved(11) != 11) throw "arguments";'
				+ 'var evaluated = function(eval:Int) return eval; if (evaluated(13) != 13) throw "eval";'
				+ 'var empty = function() return 7; if (empty() != 7) throw "empty";'},
			{name: "arrows",
				body: 'var maybe:()->Bool; maybe = () -> Math.random() > 0.5;'
				+ 'var answer = maybe(); if (answer != true && answer != false) throw "comparison";'
				+ 'var f:(?a:Int, b:String)->Int; f = (?a:Int=1, b:String) -> a + b.length;'
				+ 'if (f(null, "xx") != 3 || f(4, "xxx") != 7) throw "default";'
				+ 'var f0:()->Int; f0 = (() -> 1:()->Int); if (f0() != 1) throw "ascription";'},
			{name: "blocks",
				body: 'var block = function(x:Int) { var y = x + 1; return y; };'
				+ 'if (block(8) != 9) throw "block";'
				+ 'var count = function(xs:Array<Int>) { var i = 0; while (i < xs.length) { i += 1; } return i; };'
				+ 'if (count([]) != 0 || count([4, 5, 6]) != 3) throw "while";'
				+ 'var copy = function(xs:Array<Int>) { var out:Array<Int> = []; for (x in xs) { out.push(x); } return out; };'
				+ 'var result = copy([8, 3]); if (result.length != 2 || result[0] != 8 || result[1] != 3 || copy([]).length != 0) throw "for";'
				+ 'var choose = function(kind:String) { var out = ""; switch (kind) { case "a": out = "A"; default: out = "X"; } return out; };'
				+ 'if (choose("a") != "A" || choose("other") != "X") throw "switch";'},
			{name: "nested",
				body: 'var xml = [1, 2]; var visit = function() for (x in xml) null; visit();'
				+ 'for (flag in [true, false]) {'
				+ 'var maybe = () -> flag; var f7:(Int->Int)->(Int->Int);'
				+ 'f7 = switch maybe() { case true: f -> f; case false: f -> g -> f(g); };'
				+ 'var selected = f7(value -> value + 3); if (selected(4) != 7) throw "nested arrow";}'},
			{
				name: "map_arrows",
				body: 'var map:Map<Int,Int->Int>; map = [1 => a -> a + a, 2 => b -> b + b];' + 'if (map[1](3) != 6 || map[2](4) != 8) throw "map callbacks";'
			},
			{
				name: "block_context",
				body: 'var callback:Int->Int = { ((s:String) -> s)("ignored"); { value -> value + 1; } };' +
				'if (callback(8) != 9) throw "nested block context";'
			},
			{name: "unicode_filter",
				declarations: 'enum Filter { Only(values:Array<Int>); All; }',
				body: 'for (windows in [false, true]) {'
				+ 'var valid:Array<Filter> = [Only([0x0001]), Only([0xD7FF]), Only([0x1FFFF]), Only([65]), Only([65,66]), All];'
				+ 'var result = { var valid = valid.copy(); if (windows) valid = valid.filter(f -> !f.match(Only([0x0001])));'
				+ 'valid = valid.filter(f -> !f.match(Only([0xD7FF])) && !f.match(Only([0x1FFFF]))); valid; };'
				+ 'if (valid.length != 6 || result.length != (windows ? 3 : 4)) throw "filter length";'
				+ 'if (!result[result.length-3].match(Only([65])) || !result[result.length-2].match(Only([65,66]))'
				+ '|| result[result.length-1] != All) throw "filter order";}'},
		];
		for (entry in cases) {
			final source = (entry.declarations == null ? "" : entry.declarations)
				+ 'class Main { static function main():Void {'
				+ entry.body
				+ '} }';
			final root = JsRuntimeFixture.reserveOutput();
			final path = root + "/Main.hx";
			File.saveContent(path, source);
			final configured = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			command(configured == null ? "node_modules/.bin/haxe" : configured, ["-cp", root, "-main", "Main", "--js", root + "/upstream.js"]);
			command("node", ["--use-strict", root + "/upstream.js"]);
			Sys.println("JS_FUNCTION_LITERAL_UPSTREAM:PASS " + entry.name);
			final typed = typeSource(root);
			JsRuntimeFixture.assertRuntime(typed, "Main", "", ["--use-strict"]);
			sys.FileSystem.deleteFile(path);
			sys.FileSystem.deleteFile(root + "/upstream.js");
			sys.FileSystem.deleteDirectory(root);
			Sys.println("JS_FUNCTION_LITERAL_RUNTIME:PASS " + entry.name);
		}
	}

	/** Load real member declarations before typing primitive String and collection calls. */
	static function typeSource(root:String):TypedModule {
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final modules = ResolverStage.parseProjectRootsShallow(paths, ["Main", "String", "Array", "haxe.ds.Map"], defines);
		final index = TyperIndex.buildHeaders(modules);
		final loader = new ModuleLoader(paths, defines, index, null, false);
		loader.markResolvedAlready(modules);
		final main = modules.filter(module -> ResolvedModule.getModulePath(module) == "Main");
		if (main.length != 1)
			throw "function-literal fixture requires one Main module";
		return TyperStage.typeResolvedModule(main[0], index, loader, true);
	}

	/** Bound both compiler and runtime children; successful assertions produce no output. */
	static function command(executable:String, arguments:Array<String>):Void {
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable].concat(arguments));
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "function literal observer failed: " + executable + ": " + code + "\n" + stdout + stderr;
	}
}
