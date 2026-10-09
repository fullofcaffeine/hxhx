/** Plain extern values belong to the host; type-only declarations cause no startup reads. */
class M14JsPlainExternBindingTest {
	public static function check():Void {
		for (packageName in ["", "fixture"]) {
			final root = ".tmp/js_plain_extern_" + (packageName == "" ? "root" : packageName);
			final sourceRoot = root + (packageName == "" ? "" : "/" + packageName);
			sys.FileSystem.createDirectory(sourceRoot);
			final main = packageName == "" ? "Main" : packageName + ".Main";
			final path = sourceRoot + "/Main.hx";
			final source = (packageName == "" ? "" : "package " + packageName + ";")
				+ 'extern class Missing {public function read():Int;}'
				+ 'extern class Host {public function new(value:Int);public function read():Int;public static var count:Int;}'
				+ 'class Child extends Host {public function new(value:Int){super(value);}}'
				+ '@:native("console") extern class Console {public static function log(value:Int):Void;}'
				+ 'class Main {static function unused(value:Missing):Int{return value.read();}'
				+ 'static function main():Void{var value=new Child(7);Console.log(value.read());Console.log(Host.count);}}';
			sys.io.File.saveContent(path, source);
			final upstream = run("node_modules/.bin/haxe", ["-cp", root, "-main", main, "-js", root + "/upstream.js"]);
			if (upstream.code != 0)
				throw "plain extern upstream failed: " + upstream.stderr;
			final module = new ResolvedModule(main, path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
				new backend.BackendContext(root, root + "/native.js", main, true, false, HxDefineMap.fromRawDefines(["js=1"])));
			final harness = root + "/host.cjs";
			sys.io.File.saveContent(harness,
				'function Host(value){this.value=value;global.created=this;}Host.prototype.read=function(){return this.value;};Host.count=3;'
				+ 'Object.freeze(Host.prototype);Object.freeze(Host);'
				+ (packageName == "" ? 'global.Host=Host;const namespace=global;' : 'global.fixture={Host};const namespace=fixture;')
				+ 'Object.defineProperty(namespace,"Missing",{get(){throw Error("type-only extern was read");}});'
				+ 'const fields=Object.getOwnPropertyNames(Host).join();require(process.argv[2]);'
				+
				'if(!(created instanceof Host)||namespace.Host!==Host||Object.getOwnPropertyNames(Host).join()!==fields)throw Error("host ownership changed");');
			for (file in ["upstream.js", "native.js"]) {
				final result = run("node", [harness, sys.FileSystem.fullPath(root + "/" + file)]);
				if (result.code != 0 || result.stdout != "7\n3\n")
					throw "plain extern runtime differs: " + file + result.stdout + result.stderr;
			}
			Sys.println("JS_PLAIN_EXTERN_BINDING:PASS " + main);
		}
	}

	/** Retain separate compilation and process results so runtime success cannot hide a compiler failure. */
	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}
}
