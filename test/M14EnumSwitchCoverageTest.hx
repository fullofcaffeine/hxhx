/** Complete enum switches preserve their selected value without an artificial default arm. */
class M14EnumSwitchCoverageTest {
	static function main():Void {
		final root = '.tmp/enum_switch_coverage';
		sys.FileSystem.createDirectory(root);
		final path = root + '/Main.hx';
		final source = 'enum Choice{North;Middle;South;}class Main{'
			+ 'static function output(value:Int):Void{Sys.println(value);}'
			+ 'static function read(value:Choice):Void{output(switch(value){case North:10;case Middle:20;case South:30;});}'
			+ 'static function main():Void{read(Choice.North);read(Choice.Middle);read(Choice.South);}}';
		sys.io.File.saveContent(path, source);
		if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
			throw 'upstream enum coverage compilation failed';
		assertOutput(root + '/upstream.n', '10\n20\n30\n');
		Sys.println('UPSTREAM_ENUM_COVERAGE:PASS');
		final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		#if enum_coverage_ocaml
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), root + '/ocaml', true);
		final process = new sys.io.Process('gtimeout', ['30', executable]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != '10\n20\n30\n')
			throw 'native enum coverage differs: ' + output + errors;
		Sys.println('OCAML_ENUM_COVERAGE:PASS');
		#else
		final context = new backend.BackendContext(root, root + '/local.n', 'Main', true, false, HxDefineMap.fromRawDefines(['neko=1']));
		final generated = @:privateAccess backend.vm.NekoTargetCore.renderProgram(new MacroExpandedProgram([typed], false), context);
		sys.io.File.saveContent(root + '/local.neko', generated);
		if (Sys.command('nekoc', [root + '/local.neko']) != 0)
			throw 'local enum coverage compilation failed';
		assertOutput(root + '/local.n', '10\n20\n30\n');
		Sys.println('NEKO_ENUM_COVERAGE:PASS');
		JsRuntimeFixture.assertRuntime(typed, 'Main', '10\n20\n30\n');
		Sys.println('JS_ENUM_COVERAGE:PASS');
		#end
	}

	/** Compare each native observer against the independently specified selected branch values. */
	static function assertOutput(path:String, expected:String):Void {
		final process = new sys.io.Process('gtimeout', ['30', 'neko', path]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw 'enum coverage output differs: ' + output + errors;
	}
}
