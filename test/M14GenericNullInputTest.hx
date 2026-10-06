/** Null supplies no generic type evidence, but can enter a declaration's boxed generic input. */
class M14GenericNullInputTest {
	static function main():Void {
		for (bounded in [false, true]) {
			final root = '.tmp/generic_null_input_contract_' + bounded;
			final source = 'class Box<T'
				+ (bounded ? ':Int' : '')
				+ '> {public function new(){} '
				+ 'function put(value:T):Void {if(value==null) Sys.println("null"); else Sys.println("value");} public function clear():Void {put(null);}} '
				+ 'class Main {static function main():Void {var box=new Box<Int>(); box.clear(); Sys.println("ok");}}';
			sys.FileSystem.createDirectory(root);
			sys.io.File.saveContent(root + '/Main.hx', source);
			if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
				throw 'upstream generic null compilation failed';
			check('neko', [root + '/upstream.n']);
			final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			JsRuntimeFixture.assertRuntime(typed, 'Main', 'null\nok\n');
			final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + '/ocaml', true);
			check('gtimeout', ['30', executable]);
			Sys.println('GENERIC_NULL_INPUT_CASE:PASS ' + bounded);
		}
		Sys.println('GENERIC_NULL_INPUT:PASS');
	}

	static function check(command:String, arguments:Array<String>):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != 'null\nok\n')
			throw 'generic null runtime differs: ' + output + errors;
	}
}
