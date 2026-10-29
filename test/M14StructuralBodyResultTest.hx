/** Structural compatibility must use checked body results without rewriting method declarations. */
class M14StructuralBodyResultTest {
	static function main():Void {
		collidingSourceEdit();
		for (entry in [
			{
				name: "explicit",
				annotated: true,
				valid: true,
				forwarded: false
			},
			{
				name: "inferred",
				annotated: false,
				valid: true,
				forwarded: false
			},
			{
				name: "incompatible",
				annotated: false,
				valid: false,
				forwarded: false
			},
			{
				name: "forwarded",
				annotated: false,
				valid: true,
				forwarded: true
			},
			{
				name: "recursive",
				annotated: false,
				valid: true,
				forwarded: false
			},
			{
				name: "mutual",
				annotated: false,
				valid: true,
				forwarded: false
			},
			{
				name: "inherited",
				annotated: false,
				valid: true,
				forwarded: true
			}
		]) {
			final source = 'typedef Reader<T> = {function hasNext():Bool; function next():T;}\n'
				+ 'class Cursor<T> {var value:T; public function new(value:T) {this.value=value;} '
				+ 'public function hasNext()'
				+ (entry.annotated ? ':Bool' : '')
				+ ' {'
				+ (entry.name == "recursive" ? 'if (false) return hasNext(); ' : entry.name == "mutual" ? 'if (false) return again(); ' : '')
				+ 'return '
				+ (entry.valid ? 'true' : '"wrong"')
				+ ';} '
				+ 'public function next()'
				+ (entry.annotated ? ':T' : '')
				+ ' {return '
				+ (entry.forwarded ? 'read()' : 'value')
				+ ';} function read() {return value;}'
				+ (entry.name == "mutual" ? 'function again() {return hasNext();}' : '')
				+ '}\n'
				+ (entry.name == "inherited" ? 'class Child<T> extends Cursor<T> {public function new(value:T){super(value);}}' : '')
				+ 'class Main {static function make<T>(value:T):Reader<T> {return new '
				+ (entry.name == "inherited" ? 'Child' : 'Cursor')
				+ '<T>(value);} '
				+ 'static function main():Void {var reader=make(7); Sys.println(reader.next());}}';
			final root = '.tmp/structural_body_result_' + entry.name;
			sys.FileSystem.createDirectory(root);
			sys.io.File.saveContent(root + '/Main.hx', source);
			final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
			final output = upstream.stdout.readAll().toString();
			final errors = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if ((code == 0) != entry.valid || (entry.valid && output != '7\n'))
				throw 'upstream structural body result differs: ' + entry.name + output + errors;
			final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
			final index = TyperIndex.build([module]);
			final owners = index.getByShortName('Cursor');
			if (owners.length != 1)
				throw 'fixture requires one Cursor declaration';
			final signature = owners[0].instanceMethodCandidates('next')[0];
			final declaration = owners[0].declarationForSignature(signature);
			final identity = declaration.getIdentity().getCanonicalKey();
			final indexedResult = signature.getReturnType().getSemanticKey();
			var accepted = true;
			try {
				final typed = TyperStage.typeResolvedModule(module, index);
				if (entry.valid)
					JsRuntimeFixture.assertRuntime(typed, 'Main', '7\n');
			} catch (error:TyperError) {
				accepted = false;
			}
			if (accepted != entry.valid)
				throw 'structural body result acceptance differs: ' + entry.name;
			if (declaration.getIdentity().getCanonicalKey() != identity || signature.getReturnType().getSemanticKey() != indexedResult)
				throw 'body inference rewrote a declaration header';
			if (entry.valid && !entry.annotated) {
				final body = HxFunctionDecl.getBody(declaration.getSourceDeclaration());
				body.push(SExpr(EInt(0), HxPos.unknown()));
				var staleRejected = false;
				try {
					index.getMethodBodyResults().result(declaration);
				} catch (message:String) {
					if (message != "method body result belongs to a changed declaration")
						throw message;
					staleRejected = true;
				}
				body.pop();
				if (!staleRejected)
					throw 'method result survived a changed source body';
			}
		}
		crossModule();
		Sys.println('STRUCTURAL_BODY_RESULT:PASS');
	}

	/** Equal compact hashes must not authorize checked results after an exact source edit. */
	static function collidingSourceEdit():Void {
		final source = 'class Main {static function value() {return "Aa";} static function main():Void {value();}}';
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([module]);
		TyperStage.typeResolvedModule(module, index);
		final owner = index.getByFullName("Main");
		final declaration = owner.declarationForSignature(owner.staticMethod("value"));
		final results = index.getMethodBodyResults();
		if (results.result(declaration).getSemanticKey() != "primitive:String")
			throw "collision fixture did not publish its original checked result";
		final body = HxFunctionDecl.getBody(declaration.getSourceDeclaration());
		final original = body[0];
		final compact = TypedBodyFingerprint.forStatements(body);
		final exact = TypedBodyFingerprint.exactStatements(body);
		body[0] = switch original {
			case SReturn(EString("Aa"), position): SReturn(EString("BB"), position);
			case _: throw "collision fixture lost its literal return";
		};
		if (TypedBodyFingerprint.forStatements(body) != compact || TypedBodyFingerprint.exactStatements(body) == exact)
			throw "method-result fixture did not independently establish a compact hash collision";
		var rejected = false;
		try
			results.result(declaration)
		catch (message:String)
			rejected = message == "method body result belongs to a changed declaration";
		body[0] = original;
		if (!rejected)
			throw "checked method result survived a colliding source edit";
		if (results.result(declaration).getSemanticKey() != "primitive:String")
			throw "restored exact source lost its checked result";
		Sys.println("METHOD_RESULT_COLLISION:PASS");
	}

	/** A consumer's same-spelled class cannot replace a provider's imported result owner. */
	static function crossModule():Void {
		final root = '.tmp/structural_body_result_modules';
		sys.FileSystem.createDirectory(root);
		sys.FileSystem.createDirectory(root + '/library');
		final sources = [
			{name: 'Main',
				file: 'Main.hx',
				source: 'import library.Provider; import library.Value as LibraryValue; '
				+ 'typedef Reader<T>={function get():T;} class Value {public var n:String; public function new(){n="wrong";}} '
				+ 'class Main {static function make():Reader<LibraryValue> {return new Provider();} '
				+ 'static function main():Void {Sys.println(make().get().n);}}'},
			{
				name: 'library.Provider',
				file: 'library/Provider.hx',
				source: 'package library; import library.Value; ' + 'class Provider {public function new(){} public function get(){return new Value();}}'
			},
			{
				name: 'library.Value',
				file: 'library/Value.hx',
				source: 'package library; ' + 'class Value {public var n:Int; public function new(){n=7;}}'
			}
		];
		for (source in sources)
			sys.io.File.saveContent(root + '/' + source.file, source.source);
		final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != '7\n')
			throw 'upstream module inference differs: ' + output + errors;
		for (reverse in [false, true]) {
			final modules = [
				for (source in sources)
					new ResolvedModule(source.name, root + '/' + source.file, ParserStage.parse(source.source, root + '/' + source.file))
			];
			if (reverse)
				modules.reverse();
			final index = TyperIndex.build(modules);
			for (module in modules)
				TyperStage.typeResolvedModule(module, index);
			final provider = index.getByFullName('library.Provider');
			final declaration = provider.declarationForSignature(provider.instanceMethodCandidates('get')[0]);
			final result = index.getMethodBodyResults().result(declaration).getNominalIdentity();
			if (result == null || result.getCanonicalName() != 'library.Value')
				throw 'method body used the consumer module context';
		}
	}
}
