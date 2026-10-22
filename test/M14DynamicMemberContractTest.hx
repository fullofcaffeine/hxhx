/** Compare extern dynamic-member contracts with upstream and observe a real host object. */
class M14DynamicMemberContractTest {
	static var standard:ResolvedModule;

	static function main():Void {
		final args = hxhx.Stage1Compiler.Stage1Args.parse(["-main", "Main"], true);
		final stdPath = hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(args) + "/StdTypes.hx";
		standard = new ResolvedModule("StdTypes", stdPath, ParserStage.parse(sys.io.File.getContent(stdPath), stdPath));
		for (entry in [
			{
				name: "direct",
				header: 'extern class Bag implements Dynamic<String>{}',
				receiver: 'Bag',
				field: 'title',
				result: 'String'
			},
			{
				name: "generic",
				header: 'extern class Bag<T> implements Dynamic<T>{}',
				receiver: 'Bag<String>',
				field: 'title',
				result: 'String'
			},
			{
				name: "inherited",
				header: 'extern class Base<A,B> implements Dynamic<B>{} extern class Bag extends Base<Int,String>{}',
				receiver: 'Bag',
				field: 'title',
				result: 'String'
			},
			{
				name: "override",
				header: 'extern class Base implements Dynamic<Int>{} extern class Bag extends Base implements Dynamic<String>{}',
				receiver: 'Bag',
				field: 'title',
				result: 'String'
			},
			{
				name: "declared",
				header: 'extern class Bag implements Dynamic<String>{public var known:Int;}',
				receiver: 'Bag',
				field: 'known',
				result: 'Int'
			},
			{
				name: "bare",
				header: 'extern class Bag implements Dynamic{}',
				receiver: 'Bag',
				field: 'title',
				result: 'Dynamic'
			},
			{
				name: "nullable_marker",
				header: 'extern class Bag implements Null<Dynamic<String>>{}',
				receiver: 'Bag',
				field: 'title',
				result: 'String'
			}
		]) {
			final source = entry.header + 'class Main{static function read(b:' + entry.receiver + '):' + entry.result + '{return b.' + entry.field
				+ ';}static function main():Void{}}';
			final root = writeSource(entry.name, source);
			upstream(root, true);
			final program = typeSource(root, source);
			final main = program[1];
			final revision = CompilerTypedModuleRevision.fromTypedModule(main).getCanonicalIdentity();
			final declarations = main.getTypedClasses();
			final read = declarations[declarations.length - 1].getFunctions()[0];
			final actual = read.getBody().getStatements()[0].getExpressions()[0].getType();
			if (actual.getSemanticKey() != TyType.fromHintText(entry.result).getSemanticKey())
				throw 'dynamic member read lost its type: ' + entry.name + ' ' + actual.getSemanticKey();
			final graph = classGraph(program);
			final bag = graph.findClassFacts('Main.Bag');
			if (bag == null || bag.getInterfaceTypes().length != 0)
				throw 'dynamic marker became an interface edge';
			emit(program, root);
			if (CompilerTypedModuleRevision.fromTypedModule(main).getCanonicalIdentity() != revision)
				throw 'dynamic member projection changed typed source';
			Sys.println('DYNAMIC_MEMBER_TYPES:PASS ' + entry.name);
		}
		for (entry in [
			{name: "write", source: 'extern class Bag implements Dynamic<String>{} class Main{static function f(b:Bag){b.title=7;}static function main(){}}'},
			{
				name: "read",
				source: 'extern class Bag implements Dynamic<String>{} class Main{static function f(b:Bag):Int{return b.title;}static function main(){}}'
			},
			{name: "nonextern", source: 'class Bag implements Dynamic<String>{public function new(){}} class Main{static function main(){}}'},
			{name: "interface", source: 'interface Bag extends Dynamic<String>{} class Main{static function main(){}}'},
			{name: "duplicate", source: 'extern class Bag implements Dynamic<String> implements Dynamic<Int>{} class Main{static function main(){}}'},
			{name: "arity", source: 'extern class Bag implements Dynamic<String,Int>{} class Main{static function main(){}}'},
			{name: "ordinary_parent", source: 'class Parent{} extern class Bag implements Parent{} class Main{static function main(){}}'}
		]) {
			final root = writeSource('invalid_' + entry.name, entry.source);
			upstream(root, false);
			var rejected = false;
			final oldStrict = Sys.getEnv('HXHX_TYPER_STRICT');
			Sys.putEnv('HXHX_TYPER_STRICT', entry.name == 'write' ? '0' : '1');
			try {
				classGraph(typeSource(root, entry.source));
			} catch (error:haxe.Exception) {
				final expected = switch entry.name {
					case 'write': 'assigned type Int is not compatible with field Main.Bag.title:String';
					case 'read': 'lambda result String is not compatible with Int';
					case 'nonextern', 'interface': 'implements Dynamic is only supported on extern classes';
					case 'duplicate': 'Cannot have several dynamics';
					case 'arity': 'Too many parameters for Dynamic';
					case 'ordinary_parent': 'interface parent is not an interface: Main.Parent';
					case _: throw 'unknown rejection case';
				};
				rejected = error.message.indexOf(expected) >= 0;
				if (!rejected)
					throw error;
			}
			Sys.putEnv('HXHX_TYPER_STRICT', oldStrict == null ? '' : oldStrict);
			if (!rejected)
				throw 'invalid dynamic-member program accepted: ' + entry.name;
			Sys.println('DYNAMIC_MEMBER_REJECTION:PASS ' + entry.name);
		}
		checkIdentity();
		checkLookalikeProvider();
		checkHostRuntime();
		checkHostConversion();
	}

	/** Load the real core provider so identity and graph validation use production declarations. */
	static function typeSource(root:String, source:String):Array<TypedModule> {
		final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
		final index = TyperIndex.build([standard, module]);
		return [
			TyperStage.typeResolvedModule(standard, index),
			TyperStage.typeResolvedModule(module, index)
		];
	}

	static function classGraph(program:Array<TypedModule>):TypedBackendClassGraph {
		return new TypedBackendClassGraph('dynamic-member-test', [
			for (module in program)
				for (owner in module.getBackendProjection().getClasses())
					owner.requireSemanticFacts()
		]);
	}

	static function writeSource(name:String, source:String):String {
		final root = '.tmp/dynamic_member_' + name;
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + '/Main.hx', source);
		return root;
	}

	static function upstream(root:String, accepted:Bool):Void {
		final result = run('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-js', root + '/upstream.js']);
		if ((result.code == 0) != accepted)
			throw 'upstream dynamic-member result differs: ' + root + result.stderr;
	}

	static function emit(program:Array<TypedModule>, root:String):Void {
		new backend.js.JsBackend().emit(new MacroExpandedProgram(program, false),
			new backend.BackendContext(root, root + '/candidate.js', 'Main', true, false, HxDefineMap.fromRawDefines(['js=1'])));
	}

	/** Marker payload edits must invalidate public and backend identities; lookalike providers remain ordinary parents. */
	static function checkIdentity():Void {
		final stringProgram = typeSource('.tmp', 'extern class Bag implements Dynamic<String>{} class Main{}');
		final intProgram = typeSource('.tmp', 'extern class Bag implements Dynamic<Int>{} class Main{}');
		if (CompilerTypedModuleRevision.fromTypedModule(stringProgram[1])
			.publicInterfaceRevision == CompilerTypedModuleRevision.fromTypedModule(intProgram[1])
			.publicInterfaceRevision || classGraph(stringProgram).getCanonicalIdentity() == classGraph(intProgram).getCanonicalIdentity())
			throw 'marker type edit did not change revision';
		final fake = TyType.nominal(new TyNominalTypeId('fake.Dynamic'), [TyType.fromHintText('String')]);
		final relationship = TyClassRelationships.resolve([fake], false, true);
		if (relationship.dynamicMemberType != null || relationship.interfaces.length != 1)
			throw 'short name was used as core provider identity';
		final projection = new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram(stringProgram, false));
		var rejected = false;
		try {
			new backend.cpp.CppManagedClassStorage(projection).requireType(TyType.nominal(new TyNominalTypeId('Main.Bag'), []));
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf('managed class storage requires an explicit interface or native adapter plan') >= 0;
		}
		if (!rejected)
			throw 'native storage silently accepted an extern without an adapter';
		final bag = stringProgram[1].getTypedClasses()[0];
		rejected = false;
		try {
			new TypedBackendClassSemanticFacts(bag.getSemanticInfo(), null, bag.getFunctions(), [
				TyType.nominal(new TyNominalTypeId('StdTypes.Dynamic'), [TyType.fromHintText('Int')])
			]);
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf('interface parent conflicts with indexed identity') >= 0;
		}
		if (!rejected)
			throw 'backend substituted a different marker payload';
		Sys.println('DYNAMIC_MEMBER_IDENTITY:PASS');
	}

	/** Actual package resolution must reject a user class whose short name resembles the core marker. */
	static function checkLookalikeProvider():Void {
		final source = 'extern class Bag implements fake.Dynamic<String>{} class Main{static function main(){}}';
		final root = writeSource('lookalike', source);
		sys.FileSystem.createDirectory(root + '/fake');
		final fakePath = root + '/fake/Dynamic.hx';
		final fakeSource = 'package fake; class Dynamic<T>{public function new(){}}';
		sys.io.File.saveContent(fakePath, fakeSource);
		upstream(root, false);
		final main = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
		final fake = new ResolvedModule('fake.Dynamic', fakePath, ParserStage.parse(fakeSource, fakePath));
		final index = TyperIndex.build([standard, fake, main]);
		var rejected = false;
		try {
			classGraph([
				for (module in [standard, fake, main])
					TyperStage.typeResolvedModule(module, index)
			]);
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf('interface parent is not an interface: fake.Dynamic') >= 0;
		}
		if (!rejected)
			throw 'a same-named user class became a core marker';
		Sys.println('DYNAMIC_MEMBER_LOOKALIKE:PASS');
	}

	/** The host observes exact reads and writes; no compiler-created field storage can satisfy this test. */
	static function checkHostRuntime():Void {
		final source = '@:native("FixtureBag") extern class Bag implements Dynamic<String>{public function new();public var known:Int;}'
			+ '@:native("console") extern class Console{public static function log(value:String):Void;}'
			+
			'class Main{static function main():Void{var b=new Bag();b.title="updated";if(b.title!="updated")throw "read";if(b.known!=7)throw "known";Console.log(b.title);}}';
		final root = writeSource('host', source);
		upstream(root, true);
		emit(typeSource(root, source), root);
		final harness = root + '/host.cjs';
		sys.io.File.saveContent(harness,
			'let reads=0,writes=0,value="initial";global.FixtureBag=function(){this.known=7;Object.defineProperty(this,"title",{get(){reads++;return value;},set(v){writes++;value=v;}});};' +
			'require(process.argv[2]);if(reads!==2||writes!==1||value!=="updated")throw Error("host access changed");');
		for (file in ['upstream.js', 'candidate.js']) {
			final result = run('node', [harness, sys.FileSystem.fullPath(root + '/' + file)]);
			if (result.code != 0 || result.stdout != 'updated\n')
				throw 'dynamic host runtime differs: ' + file + result.stdout + result.stderr;
		}
		Sys.println('DYNAMIC_MEMBER_HOST_RUNTIME:PASS');
	}

	/** A write must execute a selected abstract conversion even though the member has no field declaration. */
	static function checkHostConversion():Void {
		final source = 'abstract Title(String) from String to String{'
			+ '@:from public static function fromInt(v:Int):Title{return "item"+v;}}'
			+ '@:native("FixtureBag") extern class Bag implements Dynamic<Title>{public function new();}'
			+ 'class Main{static function main():Void{var b=new Bag();b.title=7;}}';
		final root = writeSource('conversion', source);
		upstream(root, true);
		emit(typeSource(root, source), root);
		final harness = root + '/host.cjs';
		sys.io.File.saveContent(harness,
			'let writes=0,value;global.FixtureBag=function(){Object.defineProperty(this,"title",{set(v){writes++;value=v;}});};' +
			'require(process.argv[2]);if(writes!==1||value!=="item7")throw Error("conversion missing or repeated: "+value);console.log(value);');
		for (file in ['upstream.js', 'candidate.js']) {
			final result = run('node', [harness, sys.FileSystem.fullPath(root + '/' + file)]);
			if (result.code != 0 || result.stdout != 'item7\n')
				throw 'dynamic conversion differs: ' + file + result.stdout + result.stderr;
		}
		Sys.println('DYNAMIC_MEMBER_CONVERSION:PASS');
	}

	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(Sys.systemName() == 'Mac' ? 'gtimeout' : 'timeout', ['30', command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}
}
