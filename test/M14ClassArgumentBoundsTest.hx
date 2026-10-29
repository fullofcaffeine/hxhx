/** Invalid class applications must fail before a method can rely on its declared bound. */
class M14ClassArgumentBoundsTest {
	static function main():Void {
		final cases = [
			{
				name: 'unused_alias',
				extra: 'typedef Invalid=Box<Int>;',
				body: '',
				accepted: false
			},
			{
				name: 'invalid_bound',
				extra: 'class Holder<K:Box<Int>>{public function new(){}}',
				body: '',
				accepted: false
			},
			{
				name: 'shadowed_method',
				extra: 'class Holder<K>{public static function build<K:{}>(value:K):Box<K>{return new Box<K>();}}',
				body: 'var value=Holder.build("ok");',
				accepted: true
			},
			{
				name: 'constructed',
				extra: '',
				body: 'var box=new Box<Int>();',
				accepted: false
			},
			{
				name: 'local',
				extra: '',
				body: 'var box:Box<Int>=null;',
				accepted: false
			},
			{
				name: 'nested',
				extra: '',
				body: 'var box:Array<Box<Int>>=[];',
				accepted: false
			},
			{
				name: 'field',
				extra: 'class Stored{public var box:Box<Int>;}',
				body: '',
				accepted: false
			},
			{
				name: 'parameter',
				extra: 'class Stored{public static function take(box:Box<Int>):Void{}}',
				body: '',
				accepted: false
			},
			{
				name: 'return',
				extra: 'class Stored{public static function get():Box<Int>{return null;}}',
				body: '',
				accepted: false
			},
			{
				name: 'alias',
				extra: 'typedef Alias=Box<Int>;',
				body: 'var box:Alias=null;',
				accepted: false
			},
			{
				name: 'forwarded_invalid',
				extra: 'class Forward<K>{public var box:Box<K>;}',
				body: '',
				accepted: false
			},
			{
				name: 'forwarded_valid',
				extra: 'class Forward<K:{}>{public var box:Box<K>;}',
				body: '',
				accepted: true
			},
			{
				name: 'string',
				extra: '',
				body: 'var box=new Box<String>();',
				accepted: true
			},
			{
				name: 'dynamic',
				extra: '',
				body: 'var box:Box<Dynamic>=null;',
				accepted: true
			},
			{
				name: 'inferred_invalid',
				extra: 'class Inferred<K:{}>{public function new(value:K){}}',
				body: 'var box=new Inferred(1);',
				accepted: false
			},
			{
				name: 'inferred_valid',
				extra: 'class Inferred<K:{}>{public function new(value:K){}}',
				body: 'var box=new Inferred("ok");',
				accepted: true
			},
			{
				name: 'dependent_invalid',
				extra: 'class Pair<U,K:U>{public function new(){}}',
				body: 'var pair=new Pair<String,Int>();',
				accepted: false
			},
			{
				name: 'dependent_valid',
				extra: 'class Pair<U,K:U>{public function new(){}}',
				body: 'var pair=new Pair<String,String>();',
				accepted: true
			}
		];
		for (entry in cases) {
			final source = 'class Box<K:{}>{public function new(){}}' + entry.extra + 'class Main{static function main(){' + entry.body + '}}';
			final root = '.tmp/class_argument_bounds_' + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + '/Main.hx';
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '--no-output']);
			final output = upstream.stdout.readAll().toString();
			final errors = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if ((code == 0) != entry.accepted)
				throw 'upstream class application differs: ' + entry.name + output + errors;
			var accepted = true;
			try {
				final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
				TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			} catch (error:TyperError) {
				if (error.getMessage().indexOf('Constraint check failure for ') < 0)
					throw error;
				accepted = false;
			}
			if (accepted != entry.accepted)
				throw 'local class application differs: ' + entry.name;
			Sys.println('CLASS_ARGUMENT_BOUND:PASS ' + entry.name);
		}
	}
}
