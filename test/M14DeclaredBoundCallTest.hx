/** Declared bounds prove call compatibility without erasing or borrowing parameter identities. */
class M14DeclaredBoundCallTest {
	static function main():Void {
		final cases = [
			{
				name: 'record',
				parameters: 'K:{value:String}',
				argument: 'K',
				target: '{value:String}',
				methodParameters: '',
				applied: 'Item',
				accepted: true
			},
			{
				name: 'compound',
				parameters: 'K:First & Second',
				argument: 'K',
				target: 'Second',
				methodParameters: '',
				applied: 'Item',
				accepted: true
			},
			{
				name: 'object',
				parameters: 'K:{}',
				argument: 'K',
				target: '{}',
				methodParameters: '',
				applied: 'Item',
				accepted: true
			},
			{
				name: 'chain',
				parameters: 'U:{},K:U',
				argument: 'K',
				target: '{}',
				methodParameters: '',
				applied: 'Item,Item',
				accepted: true
			},
			{
				name: 'nominal',
				parameters: 'K:Item',
				argument: 'K',
				target: 'Item',
				methodParameters: '',
				applied: 'Item',
				accepted: true
			},
			{
				name: 'dynamic',
				parameters: 'K',
				argument: 'K',
				target: 'Dynamic',
				methodParameters: '',
				applied: 'Item',
				accepted: true
			},
			{
				name: 'method',
				parameters: 'X',
				argument: 'K',
				target: '{}',
				methodParameters: '<K:{}>',
				applied: 'Item',
				accepted: true
			},
			{
				name: 'unbounded',
				parameters: 'K',
				argument: 'K',
				target: '{}',
				methodParameters: '',
				applied: 'Item',
				accepted: false
			},
			{
				name: 'shadow',
				parameters: 'K:{}',
				argument: 'K',
				target: '{}',
				methodParameters: '<K>',
				applied: 'Item',
				accepted: false
			},
			{
				name: 'foreign',
				parameters: 'K',
				argument: 'K',
				target: '{}',
				methodParameters: '',
				applied: 'Item',
				accepted: false
			}
		];
		for (entry in cases) {
			final source = 'interface First{public var value:String;}interface Second{public var other:Int;}class Item implements First implements Second{public var value:String="item";public var other:Int=1;public function new(){}}'
				+ (entry.name == 'foreign' ? 'class Other<K:{}>{public function new(){}}' : '')
				+ 'class Box<'
				+ entry.parameters
				+ '>{public function new(){Sys.println("construct");}static function take(value:'
				+ entry.target
				+ '):Void {Sys.println("ok");}'
				+ 'public function run'
				+ entry.methodParameters
				+ '(value:'
				+ entry.argument
				+ '):Void {take(value);}}'
				+ 'class Main{static function main(){var box=new Box<'
				+ entry.applied
				+ '>();box.run(new Item());}}';
			final root = '.tmp/declared_bound_call_' + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + '/Main.hx';
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
			final output = upstream.stdout.readAll().toString();
			final errors = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if (entry.accepted ? code != 0 || output != 'construct\nok\n' : code == 0)
				throw 'upstream declared bound differs: ' + entry.name + output + errors;
			Sys.println('UPSTREAM_DECLARED_BOUND:PASS ' + entry.name);
			final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
			final index = TyperIndex.build([module]);
			if (entry.name == 'object') {
				final parameter = TyNominalApplication.parameterIds(index.getByFullName('Main.Box'))[0];
				final bounds = index.getParameterBounds(parameter);
				if (bounds.length != 1 || !bounds[0].isAnonymous())
					throw 'class bound was not resolved';
				bounds.pop();
				if (index.getParameterBounds(parameter).length != 1)
					throw 'returned bounds mutate indexed facts';
			}
			var typed:Null<TypedModule> = null;
			try {
				typed = TyperStage.typeResolvedModule(module, index);
			} catch (error:TyperError) {
				if (entry.accepted || error.getMessage().indexOf('No compatible method signature for take') < 0)
					throw error;
			}
			if (entry.accepted) {
				if (typed == null)
					throw 'accepted bounded program has no typed result';
				if (!index.getByFullName('Main.Box').instanceMethodCandidates('run')[0].getArgs()[0].isTypeParameter())
					throw 'call checking replaced the declared parameter';
				JsRuntimeFixture.assertRuntime(typed, 'Main', 'construct\nok\n');
				#if declared_bound_native
				if (entry.name == 'object') {
					final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + '/native', true);
					final native = new sys.io.Process('gtimeout', ['30', executable]);
					final actual = native.stdout.readAll().toString();
					final stderr = native.stderr.readAll().toString();
					final exit = native.exitCode();
					native.close();
					if (exit != 0 || actual != 'construct\nok\n')
						throw 'native declared bound differs: ' + actual + stderr;
				}
				#end
			} else if (typed != null)
				throw 'unproved caller bound was accepted: ' + entry.name;
			Sys.println('LOCAL_DECLARED_BOUND:PASS ' + entry.name);
		}
		Sys.println('DECLARED_BOUND_CALL:PASS');
	}
}
