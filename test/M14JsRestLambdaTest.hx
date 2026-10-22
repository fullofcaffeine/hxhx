/** Source callbacks collect rest operands while retaining their own closure and initializer scope. */
class M14JsRestLambdaTest {
	static function main():Void {
		for (entry in [
			{name: "locals",
				source: 'class Main{static function main():Void{'
				+ 'var count=function(...values:Int):Int{return values.length;};'
				+ 'trace(count());trace(count(2,3));'
				+ 'var sum=function(arguments:Int,...values:Int):Int{return arguments+values[0]+values[1];};'
				+ 'trace(sum(10,2,3));}}',
				expected: "0\n2\n15\n"
			},
			{name: "nested",
				source: 'class Main{var base:Int;function new(){base=10;}'
				+ 'function run():Int{var make=function(offset:Int){return function(...values:Int):Int{return this.base+offset+values[0];};};'
				+ 'var callback=make(2);return callback(3);}'
				+ 'static function main():Void{trace(new Main().run());}}',
				expected: "15\n"
			},
			{name: "initializers",
				source: 'class Main{static var count=function(...values:Int):Int{return values.length;};'
				+ 'var pick=function(prefix:Int,...values:Int):Int{return prefix+values[0];};'
				+ 'function new(){}static function main():Void{trace(count());trace(count(2,3));'
				+ 'trace(new Main().pick(10,5));}}',
				expected: "0\n2\n15\n"
			}
		]) {
			final root = ".tmp/js-rest-lambda-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, entry.source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			run(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--js", root + "/upstream.js"], "");
			final upstreamExpected = [
				for (line in entry.expected.split("\n"))
					if (line.length > 0) path + ":1: " + line
			].join("\n") + "\n";
			run("node", [root + "/upstream.js"], upstreamExpected);
			Sys.println("JS_REST_LAMBDA_UPSTREAM:PASS " + entry.name);
			final typed = @:privateAccess M14GenericDynamicInferenceTest.typeSource(entry.source, root, path);
			JsRuntimeFixture.assertRuntime(typed, "Main", entry.expected);
			Sys.println("JS_REST_LAMBDA:PASS " + entry.name);
		}
	}

	/** Keep compile failures distinct from execution failures and compare the independently specified output. */
	static function run(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw command + " differs: " + stdout + stderr;
	}
}
