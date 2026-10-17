/** Native extern declarations do not read hosts until used, and each use observes the current host. */
class M14JsNativeExternLookupTest {
	public static function check():Void {
		final console = '@:native("console") extern class Console {public static function log(value:Int):Void;}';
		final missing = '@:native("MissingNativeHost") extern class Missing {public static var value:Int;}';
		final host = '@:native("fixture.Host") extern class Host {public function new(value:Int);public function read():Int;public static var value:Int;public static function consume(value:Int):Int;}'
			+ '@:native("fixture.Host") extern class Alias {public static var value:Int;}'
			+ '@:native("fixture.control") extern class Control {public static function replace():Void;public static function argument():Int;}';
		// Host JavaScript is the independent observer at this explicit extern boundary.
		// Its getter reports every host read; replacement must be visible on the next use.
		final observer = 'function First(value){this.number=value;}First.prototype.read=function(){return this.number;};First.value=7;'
			+ 'First.consume=function(value){return this.value+value;};'
			+ 'function Second(value){this.number=value+1;}Second.prototype.read=First.prototype.read;Second.value=9;'
			+ 'Object.freeze(First.prototype);Object.freeze(First);Object.freeze(Second.prototype);Object.freeze(Second);'
			+ 'let current=First;global.fixture={control:{replace(){current=Second;},argument(){console.log(102);current=Second;return 2;}}};'
			+ 'Object.defineProperty(fixture,"Host",{get(){console.log(101);return current;}});';
		for (entry in [
			{
				name: "unused_absent",
				declarations: missing,
				members: 'static var unused:Null<Missing>;',
				body: 'Console.log(7);',
				setup: '',
				expected: "7\n",
				error: ""
			},
			{
				name: "unused_getter",
				declarations: '@:native("fixture.Missing") extern class Missing {public static var value:Int;}',
				members: 'static var unused:Null<Missing>;',
				body: 'Console.log(7);',
				setup: 'global.fixture={};Object.defineProperty(fixture,"Missing",{get(){throw Error("unused host was read");}});',
				expected: "7\n",
				error: ""
			},
			{
				name: "used_absent",
				declarations: missing,
				members: '',
				body: 'Console.log(1);Console.log(Missing.value);',
				setup: '',
				expected: "1\n",
				error: "ReferenceError"
			},
			{
				name: "getter_alias_rebinding",
				declarations: host,
				members: '',
				body: 'Console.log(1);Console.log(Host.value);Control.replace();Console.log(Alias.value);',
				setup: observer,
				expected: "1\n101\n7\n101\n9\n",
				error: ""
			},
			{
				name: "call_order",
				declarations: host,
				members: '',
				body: 'Console.log(1);Console.log(Host.consume(Control.argument()));Console.log(Alias.value);',
				setup: observer,
				expected: "1\n101\n102\n9\n101\n9\n",
				error: ""
			},
			{
				name: "local_shadow",
				declarations: host,
				members: 'static function observe(fixture:Int):Void{Console.log(fixture);Console.log(Host.value);}',
				body: 'observe(3);',
				setup: observer,
				expected: "3\n",
				error: "TypeError"
			},
			{
				name: "constructor_rebinding",
				declarations: host,
				members: '',
				body: 'Console.log(1);var first=new Host(4);Console.log(first.read());Control.replace();var second=new Host(4);Console.log(second.read());',
				setup: observer,
				expected: "1\n101\n4\n101\n5\n",
				error: ""
			}
		]) {
			final root = ".tmp/js_native_extern_lookup_" + entry.name;
			sys.FileSystem.createDirectory(root);
			final source = console + entry.declarations + 'class Main{' + entry.members + 'static function main():Void{' + entry.body + '}}';
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final compile = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-dce", "no", "-js", root + "/upstream.js"]);
			if (compile.code != 0)
				throw "native extern upstream compilation failed: " + compile.stderr;
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
			new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
				new backend.BackendContext(root, root + "/candidate.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
			final harness = root + "/host.cjs";
			sys.io.File.saveContent(harness, entry.setup + 'require(process.argv[2]);');
			for (file in ["upstream.js", "candidate.js"]) {
				final result = run("node", [harness, sys.FileSystem.fullPath(root + "/" + file)]);
				if (result.stdout != entry.expected
					|| (entry.error != "" ? result.code == 0 || result.stderr.indexOf(entry.error) < 0 : result.code != 0))
					throw "native extern lookup differs for " + entry.name + " " + file + ": " + result.stdout + result.stderr;
				Sys.println("JS_NATIVE_EXTERN_LOOKUP:PASS " + entry.name + " " + file);
			}
			if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
				throw "native extern emission changed typed source";
		}
	}

	/** Bound compiler/runtime observers and keep exit status separate from their output. */
	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void
		check();
}
