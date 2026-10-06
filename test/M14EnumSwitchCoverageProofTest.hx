/** Compare finite enum coverage decisions with upstream; runtime evidence remains in the separate target test. */
class M14EnumSwitchCoverageProofTest {
	static function main():Void {
		final simple = 'enum Choice{North;Middle;South;}';
		final cases = [
			{
				name: 'singletons',
				decl: simple,
				type: 'Choice',
				arms: 'case North:1;case Middle:2;case South:3;',
				accepted: true
			},
			{
				name: 'alternatives',
				decl: simple,
				type: 'Choice',
				arms: 'case North | Middle:1;case South:3;',
				accepted: true
			},
			{
				name: 'qualified',
				decl: simple,
				type: 'Choice',
				arms: 'case Choice.North:1;case Choice.Middle:2;case Choice.South:3;',
				accepted: true
			},
			{
				name: 'payload',
				decl: 'enum Choice{Empty;Item(n:Int);}',
				type: 'Choice',
				arms: 'case Empty:0;case Item(n):n;',
				accepted: true
			},
			{
				name: 'generic_payload',
				decl: 'enum Choice<T>{Empty;Item(value:T);}',
				type: 'Choice<Int>',
				arms: 'case Empty:0;case Item(n):n;',
				accepted: true
			},
			{
				name: 'record_payload',
				decl: 'enum Choice{Empty;Item(value:{n:Int});}',
				type: 'Choice',
				arms: 'case Empty:0;case Item({n:n}):n;',
				accepted: true
			},
			{
				name: 'null_case',
				decl: simple,
				type: 'Null<Choice>',
				arms: 'case null:0;case North:1;case Middle:2;case South:3;',
				accepted: true
			},
			{
				name: 'missing',
				decl: simple,
				type: 'Choice',
				arms: 'case North:1;case Middle:2;',
				accepted: false
			},
			{
				name: 'duplicate',
				decl: simple,
				type: 'Choice',
				arms: 'case North | North:1;case Middle:2;',
				accepted: false
			},
			{
				name: 'guard',
				decl: simple,
				type: 'Choice',
				arms: 'case North if(false):1;case Middle:2;case South:3;',
				accepted: false
			},
			{
				name: 'literal_payload',
				decl: 'enum Choice{Empty;Item(n:Int);}',
				type: 'Choice',
				arms: 'case Empty:0;case Item(1):1;',
				accepted: false
			},
			{
				name: 'array_payload',
				decl: 'enum Choice{Empty;Item(values:Array<Int>);}',
				type: 'Choice',
				arms: 'case Empty:0;case Item([n]):n;',
				accepted: false
			},
			{
				name: 'foreign',
				decl: simple + 'enum Other{North;Middle;South;}',
				type: 'Choice',
				arms: 'case Other.North:1;case Other.Middle:2;case Other.South:3;',
				accepted: false
			}
		];
		for (entry in cases) {
			final root = '.tmp/enum-coverage-boundaries/' + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + '/Main.hx';
			final source = entry.decl + 'class Main{static function read(v:' + entry.type + '):Int return switch(v){' + entry.arms
				+ '};static function main():Void{}}';
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']);
			final output = upstream.stdout.readAll().toString();
			final error = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if ((code == 0) != entry.accepted)
				throw entry.name + ' upstream decision differs: ' + output + error;
			var localAccepted = false;
			var diagnostic = '';
			try {
				final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
				final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
				final functions = [for (owner in typed.getTypedClasses()) for (fn in owner.getFunctions()) fn];
				final revisions = functions.map(CompilerTypedTreeRevision.functionBody);
				typed.getBackendProjection();
				for (i in 0...functions.length) {
					if (revisions[i] != CompilerTypedTreeRevision.functionBody(functions[i]))
						throw 'authored switch changed';
					final lowered = TypedControlLowering.functionBody(functions[i]);
					if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
						throw 'switch lowering changed on repeated application';
				}
				localAccepted = true;
			} catch (error:haxe.Exception) {
				diagnostic = error.message;
			}
			if (localAccepted != entry.accepted)
				throw entry.name + ' local decision differs: ' + diagnostic;
			if (!localAccepted
				&& diagnostic.indexOf('exact exhaustive coverage') < 0
				&& diagnostic.indexOf('constructor belongs to another enum') < 0)
				throw entry.name + ' failed for an unrelated reason: ' + diagnostic;
			Sys.println('ENUM_COVERAGE_BOUNDARY:PASS ' + entry.name);
		}
	}
}
