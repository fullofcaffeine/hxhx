import backend.BackendContext;
import backend.js.JsBackend;

/** Real host objects keep their identity, methods, and frozen property sets. */
class M14JsExternNativeBindingTest {
	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function run(arguments:Array<String>):String {
		final process = new sys.io.Process("node", arguments);
		final output = process.stdout.readAll().toString();
		final error = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		check(code == 0, error);
		return output;
	}

	static function main():Void {
		M14JsNativeExternLookupTest.check();
		M14JsPlainExternBindingTest.check();
		final root = ".tmp/js_extern_native_binding";
		sys.FileSystem.createDirectory(root);
		final source = '@:native("fixture.Host") extern class Host { public function new(value:Int); public function read():Int; public static function label():String; }'
			+ '@:native("console") extern class Console { public static function log(value:String):Void; }'
			+ 'class Main { static function main():Void { final host = new Host(7); Console.log(Host.label()); Console.log("value=" + host.read()); }}';
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		check(code == 0, errors);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		new JsBackend().emit(new MacroExpandedProgram([typed], false),
			new BackendContext(root, root + "/native.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
		final harness = root + "/host.cjs";
		sys.io.File.saveContent(harness,
			'class Host {constructor(value){this.value=value;} read(){return this.value;} static label(){return "host";}}'
			+ 'Object.freeze(Host.prototype); Object.freeze(Host); global.fixture=Object.freeze({Host});'
			+ 'const before=Object.getOwnPropertyNames(Host).join(); require(process.argv[2]);'
			+ 'if(fixture.Host!==Host || Object.getOwnPropertyNames(Host).join()!==before) throw Error("host mutated");');
		final expected = "host\nvalue=7\n";
		for (output in ["upstream.js", "native.js"])
			check(run([harness, sys.FileSystem.fullPath(root + "/" + output)]) == expected, "host binding behavior differs");
		for (metadata in [
			'@:native("fixture.Host;throw 1")',
			'@:native("fixture..Host")',
			'@:native(7)',
			'@:native("return")',
			'@:native("fixture.Host", "extra")'
		]) {
			var rejected = false;
			try {
				backend.js.JsExternBinding.reference(new HxClassDecl("Bad", false, [], [], "", [metadata], false, [], HxVisibility.Public, [], true));
			} catch (_:String) {
				rejected = true;
			}
			check(rejected, "malformed native path accepted");
		}
		Sys.println("JS_EXTERN_NATIVE_BINDING:PASS");
	}
}
