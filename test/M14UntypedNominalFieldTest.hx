/** Later class constraints must validate earlier field reads on untyped results, including inherited generic fields. */
class M14UntypedNominalFieldTest {
	static function main():Void {
		final cases = [
			{
				name: 'plain',
				declaration: 'class Box{public var item:Int;public function new(value:Int){item=value;}}',
				type: 'Box',
				member: 'item',
				accepted: true
			},
			{
				name: 'generic',
				declaration: 'class Box<T>{public var item:T;public function new(value:T){item=value;}}',
				type: 'Box<Int>',
				member: 'item',
				accepted: true
			},
			{
				name: 'inherited',
				declaration: 'class Parent<T>{public var item:T;public function new(value:T){item=value;}}class Box extends Parent<Int>{public function new(value:Int){super(value);}}',
				type: 'Box',
				member: 'item',
				accepted: true
			},
			{
				name: 'wrong_type',
				declaration: 'class Box{public var item:String;public function new(value:Int){item="wrong";}}',
				type: 'Box',
				member: 'item',
				accepted: false
			},
			{
				name: 'missing',
				declaration: 'class Box{public function new(value:Int){}}',
				type: 'Box',
				member: 'item',
				accepted: false
			},
			{
				name: 'private',
				declaration: 'class Box{private var item:Int;public function new(value:Int){item=value;}}',
				type: 'Box',
				member: 'item',
				accepted: false
			}
		];
		for (entry in cases) {
			final root = '.tmp/untyped_nominal_field_' + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + '/Main.hx';
			final source = entry.declaration
				+ 'class Main{static function consume(value:'
				+ entry.type
				+ ',item:Int):Void{Sys.println(item);}static function main():Void{var value=untyped new '
				+ entry.type
				+ '(3);consume(value,value.'
				+ entry.member
				+ ');}}';
			sys.io.File.saveContent(path, source);
			final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '--interp']);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (entry.accepted ? code != 0 || output != '3\n' : code == 0)
				throw 'upstream nominal member contract differs for ' + entry.name + ': ' + output + errors;
			var diagnostic = '';
			try {
				final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
				final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
				typed.getBackendProjection();
				if (entry.accepted)
					JsRuntimeFixture.assertRuntime(typed, 'Main', '3\n');
			} catch (error:haxe.Exception) {
				diagnostic = error.message;
			}
			if (entry.accepted ? diagnostic.length != 0 : diagnostic.indexOf('selected call conflicts with generic constructor constraints') < 0)
				throw 'local nominal member contract differs for ' + entry.name + ': ' + diagnostic;
			Sys.println('UNTYPED_NOMINAL_MEMBER:PASS ' + entry.name);
		}
	}
}
