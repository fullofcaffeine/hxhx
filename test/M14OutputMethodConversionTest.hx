/** Output conversions retain declaration priority, specialized results, and receiver effects. */
class M14OutputMethodConversionTest {
	static function main():Void {
		final cases = [
			{
				name: 'structure',
				source: 'typedef Record={value:String};abstract A(String){public function new(){this="raw";}@:to function out():Record{Sys.println("to");return {value:this};}}class Main{static function take(value:Record):Void{Sys.println(value.value);}static function main(){take(new A());}}',
				expected: 'to\nraw\n',
				selected: 'out'
			},
			{
				name: 'call',
				source: 'abstract A(String){public function new(){this="raw";}@:to function out():String{Sys.println("to");return this;}}class Main{static function make():A{Sys.println("produce");return new A();}static function take(value:String):Void{Sys.println(value);}static function main(){take(make());}}',
				expected: 'produce\nto\nraw\n',
				selected: 'out'
			},
			{
				name: 'both',
				source: 'abstract A(Int){public function new(){this=1;}@:to function out():B{Sys.println("to");return new B();}}abstract B(Int){public function new(){this=2;}@:from static function input(a:A):B{Sys.println("from");return new B();}}class Main{static function main(){var b:B=new A();}}',
				expected: 'to\n',
				selected: 'out'
			},
			{
				name: 'order',
				source: 'abstract A(String){public function new(){this="raw";}@:to function first():String{Sys.println("first");return this;}@:to function second():String{Sys.println("second");return this;}}class Main{static function main(){var value:String=new A();Sys.println(value);}}',
				expected: 'first\nraw\n',
				selected: 'first'
			},
			// This fixture deliberately exercises a generic conversion boundary. Its
			// only selected result is String, matching the known String backing value.
			{
				name: 'generic',
				source: 'abstract A(String){public function new(){this="raw";}@:to function out<T>():T{Sys.println("to");return cast this;}}class Main{static function main(){var value:String=new A();Sys.println(value);}}',
				expected: 'to\nraw\n',
				selected: 'out'
			},
			{
				name: 'owner',
				source: 'abstract A<T>(T){public function new(value:T){this=value;}@:to function out():T{Sys.println("to");return this;}}class Main{static function main(){var value:String=new A<String>("raw");Sys.println(value);}}',
				expected: 'to\nraw\n',
				selected: 'out'
			},
			{
				name: 'bound',
				source: 'abstract A(String){public function new(){this="raw";}@:to function bounded<T:Int>():T{Sys.println("wrong");return cast this;}@:to function fallback():String{Sys.println("fallback");return this;}}class Main{static function main(){var value:String=new A();Sys.println(value);}}',
				expected: 'fallback\nraw\n',
				selected: 'fallback'
			},
			{
				name: 'header',
				source: 'abstract A(String) to String{public function new(){this="raw";}@:to function out():String{Sys.println("wrong");return "changed";}}class Main{static function main(){var value:String=new A();Sys.println(value);}}',
				expected: 'raw\n',
				selected: ''
			}
		];
		for (entry in cases) {
			// The full command retains the failing JS header-cast contract. This
			// explicit subset isolates executable methods while p4qty owns that cast.
			#if output_method_only
			if (entry.name == 'header')
				continue;
			#end
			final root = '.tmp/output_method_conversion_' + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + '/Main.hx';
			sys.io.File.saveContent(path, entry.source);
			final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || output != entry.expected)
				throw 'upstream output conversion differs: ' + entry.name + output + errors;
			Sys.println('UPSTREAM_OUTPUT_CONVERSION:PASS ' + entry.name);
			final module = new ResolvedModule('Main', path, ParserStage.parse(entry.source, path));
			final index = TyperIndex.build([module]);
			final actual = TyType.nominal(new TyNominalTypeId('Main.A'), entry.name == 'owner' ? [TyType.fromHintText('String')] : []);
			final expected = entry.name == 'structure' ? index.getByFullName('Main')
				.staticMethodCandidates('take')[0].getArgs()[0] : entry.name == 'both' ? TyType.nominal(new TyNominalTypeId('Main.B'),
					[]) : TyType.fromHintText('String');
			final plan = TyAbstractMethodConversion.select(index, expected, actual);
			if (entry.selected == '') {
				if (plan != null)
					throw 'header conversion lost priority';
			} else {
				if (plan == null
					|| plan.getDeclaration().getIsStatic()
					|| plan.getDeclaration().getSignature().getName() != entry.selected)
					throw 'wrong output conversion declaration: ' + entry.name;
				final receiver = TypedExpr.nameRead('value', actual, HxPos.unknown());
				final call = plan.apply(receiver);
				if (call.getExpressions().length != 1
					|| call.getExpressions()[0].getExpressions()[0] != receiver
					|| call.getDeclaration() != plan.getDeclaration()
					|| call.getType().getSemanticKey() != expected.getSemanticKey())
					throw 'output conversion lost its receiver or specialized result';
				var rejected = false;
				try {
					plan.apply(TypedExpr.intLiteral(1, TyType.fromHintText('Int'), HxPos.unknown()));
				} catch (message:String) {
					if (message != 'abstract method conversion received a different source type')
						throw message;
					rejected = true;
				}
				if (!rejected)
					throw 'output conversion accepted a foreign receiver';
			}
			final typed = TyperStage.typeResolvedModule(module, index);
			JsRuntimeFixture.assertRuntime(typed, 'Main', entry.expected);
			Sys.println('LOCAL_OUTPUT_CONVERSION:PASS ' + entry.name);
		}
		Sys.println('OUTPUT_METHOD_CONVERSION:PASS');
	}
}
