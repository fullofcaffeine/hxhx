/** Calls must execute selected abstract conversions once, in argument evaluation order. */
class M14CallMethodConversionTest {
	static function main():Void {
		#if call_conversion_native
		run('direct');
		#else
		for (kind in ['direct', 'optional', 'rest', 'generic', 'extension', 'nullable'])
			run(kind);
		for (kind in ['missing', 'input', 'bound'])
			reject(kind);
		#end
		Sys.println('CALL_METHOD_CONVERSION:PASS');
	}

	/** Backing storage and rejected method bounds do not authorize argument conversion. */
	static function reject(kind:String):Void {
		final method = switch kind {
			case 'input': '@:from static function convert(value:String):Token {return new Token(1);}';
			case 'bound': '@:from static function convert<T:Int>(value:T):Token {return new Token(1);}';
			case _: '';
		};
		final source = 'abstract Token(Int) {public function new(value:Int){this=value;}'
			+ method
			+ '}'
			+ 'class Main {static function take(value:Token):Void {} static function main():Void {take('
			+ (kind == 'missing' ? '1' : 'true')
			+ ');}}';
		final root = '.tmp/call_method_conversion_reject_' + kind;
		sys.FileSystem.createDirectory(root);
		final path = root + '/Main.hx';
		sys.io.File.saveContent(path, source);
		final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '--no-output']);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code == 0 || errors.indexOf('Token') < 0)
			throw 'upstream accepted invalid conversion: ' + output + errors;
		final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
		var rejected = false;
		try {
			TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		} catch (error:TyperError) {
			if (Std.string(error).indexOf('No compatible method signature for take') < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw 'local call accepted invalid conversion: ' + kind;
		Sys.println('CALL_METHOD_CONVERSION_REJECT:PASS ' + kind);
	}

	static function run(kind:String):Void {
		final consume = switch kind {
			case 'nullable': 'static function consume(left:Null<Token>,right:Token):Void {Sys.println("body");Sys.println(left.value());Sys.println(right.value());}';
			case 'optional': 'static function consume(left:Token,?right:Token):Void {Sys.println("body");Sys.println(left.value());Sys.println(right.value());}';
			case 'rest': 'static function consume(...values:Token):Void {Sys.println("body");Sys.println(values[0].value());Sys.println(values[1].value());}';
			case 'generic': 'static function consume<T>(left:Token,right:Token,extra:T):Void {Sys.println("body");Sys.println(left.value());Sys.println(right.value());}';
			case _: 'static function consume(left:Token,right:Token):Void {Sys.println("body");Sys.println(left.value());Sys.println(right.value());}';
		};
		final source = (kind == 'extension' ? 'using Main.Extensions;' : '')
			+ 'abstract Token(String) {'
			+ 'public function new(value:String) {this=value;}'
			+ '@:from static function fromInt(value:Int):Token {Sys.println("convert");return new Token("converted");}'
			+ (kind == 'nullable' ? '@:from static function fromDynamic(value:Dynamic):Token {Sys.println("unexpected");return new Token("dynamic");}' : '')
			+ 'public function value():String {return this;}}'
			+
			(kind == 'extension' ? 'class Extensions {public static function consume(receiver:String,left:Token,right:Token):Void {Sys.println(receiver);Sys.println(left.value());Sys.println(right.value());}}' : '')
			+ 'class Main {'
			+ 'static function produce(label:String):Int {Sys.println(label);return 1;}'
			+ consume
			+ (kind == 'nullable' ? 'static function checkNull(value:Null<Token>):Void {Sys.println(value==null ? "null" : "value");}' : '')
			+ 'static function main():Void {'
			+ (kind == 'extension' ? '"body".' : '')
			+ 'consume(produce("first"),produce("second")'
			+ (kind == 'generic' ? ',true' : '')
			+ ');'
			+ (kind == 'nullable' ? 'checkNull(null);' : '')
			+ '}}';
		final expected = 'first\nconvert\nsecond\nconvert\nbody\nconverted\nconverted\n' + (kind == 'nullable' ? 'null\n' : '');
		final root = '.tmp/call_method_conversion_' + kind;
		sys.FileSystem.createDirectory(root);
		final path = root + '/Main.hx';
		sys.io.File.saveContent(path, source);
		final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw 'upstream call conversion differs: ' + output + errors;
		Sys.println('UPSTREAM_CALL_METHOD_CONVERSION:PASS ' + kind);
		final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		var selected = 0;
		function expression(node:TypedExpr):Void {
			final declaration = node.getDeclaration();
			if (node.getTag() == Call
				&& declaration != null
				&& declaration.getOwner().getCanonicalName() == 'Main.Token'
				&& declaration.getSignature().getName() == 'fromInt') {
				selected++;
				if (node.getExpressions().length != 2
					|| node.getExpressions()[1].getType().getSemanticKey() != 'primitive:Int'
					|| node.getType().getSemanticKey() != 'nominal:Main.Token')
					throw 'call conversion lost its operand or applied result';
			}
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (value in node.getExpressions())
				expression(value);
			for (child in node.getStatements())
				statement(child);
		}
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				for (entry in fn.getBody().getStatements())
					statement(entry);
		if (selected != 2)
			throw 'call operands must retain exactly two conversion calls';
		JsRuntimeFixture.assertRuntime(typed, 'Main', expected);
		#if call_conversion_native
		{
			final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + '/ocaml', true);
			final native = new sys.io.Process('gtimeout', ['30', executable]);
			final nativeOutput = native.stdout.readAll().toString();
			final nativeErrors = native.stderr.readAll().toString();
			final nativeCode = native.exitCode();
			native.close();
			if (nativeCode != 0 || nativeOutput != expected)
				throw 'native call conversion differs: ' + nativeOutput + nativeErrors;
		}
		#end
		Sys.println('LOCAL_CALL_METHOD_CONVERSION:PASS ' + kind);
	}
}
