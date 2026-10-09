/** Preserve already-Dynamic values across a block closure's local return exception. */
class M14NativeDynamicBlockReturnTest {
	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "Dynamic block-return observer failed: " + stderr;
		return stdout;
	}

	static function main():Void {
		final root = ".tmp/native_dynamic_block_return";
		sys.FileSystem.createDirectory(root);
		final source = 'class Main { static function main():Void {'
			+ 'var effects = 0; var value:Dynamic = true;'
			+ 'final read = function():Dynamic { effects++; return value; };'
			+ 'Sys.println(read()); value = 7; Sys.println(read());'
			+ 'value = "text"; Sys.println(read());'
			+ 'var items:Dynamic = [1, 2]; value = items;'
			+ 'Sys.println(read() == items); Sys.println(effects);'
			+ '} }';
		final expected = "true\n7\ntext\ntrue\n4\n";
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		if (run("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]) != expected)
			throw "upstream Dynamic block-return contract differs";
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true);
		if (run(executable, []) != expected)
			throw "native Dynamic block-return values, identity, or effects differ";
		Sys.println("NATIVE_DYNAMIC_BLOCK_RETURN:PASS");
	}
}
