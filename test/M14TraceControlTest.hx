/** Compare logging operand effects with upstream without replacing the default logger. */
function run():Void {
	for (entry in [
		{name: "block", body: 'trace({events+="a";"value";});trace(events);', output: "value\na\n"},
		{name: "nested", body: 'trace({trace(mark("inner"));"outer";});trace(events);', output: "inner\nouter\ninner\n"},
		{name: "order", body: 'trace(join(mark("a"),{events+="b";"b";}));trace(events);', output: "ab\nab\n"},
		{
			name: "shadow",
			body: 'final trace=function(value:String):Void{events+=value;};trace({events+="a";"value";});(trace)("b");trace(events);',
			output: "value\nab\n"
		}
	]) {
		final root = ".tmp/trace-control-" + entry.name;
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = 'class Main{static var events:String="";static function mark(value:String):String{events+=value;return value;}'
			+ 'static function join(left:String,right:String):String{return left+right;}static function main():Void{'
			+ entry.body
			+ '}}';
		sys.io.File.saveContent(path, source);
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		final expected = entry.output.split("\n")
			.filter(line -> line.length > 0)
			.map(line -> path + ":1: " + line + "\n")
			.join("");
		if (code != 0 || stdout != expected || stderr.length != 0)
			throw "upstream trace operands differ: " + entry.name + stdout + stderr;
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		JsRuntimeFixture.assertRuntime(typed, "Main", entry.output);
		M14TraceDisabledTest.assertNeko(typed, "Main", entry.output);
		Sys.println("TRACE_CONTROL:PASS " + entry.name);
	}
}
