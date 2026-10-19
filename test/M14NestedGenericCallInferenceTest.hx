/** Nested generic calls share result constraints through aliases before immutable body replay. */
class M14NestedGenericCallInferenceTest {
	static final helpers = 'class Box<T>{public function new(){}}class Main{'
		+ 'static function create<T>():Box<T>{return new Box<T>();}'
		+ 'static function forward<U>(value:Box<U>):Box<U>{return value;}'
		+ 'static function optional<U>(value:Box<U>,?unused:Int):Box<U>{return value;}'
		+ 'static function middle<U>(?unused:Int,value:Box<U>):Box<U>{return value;}'
		+ 'static function rest<U>(value:Box<U>,...tail:Box<U>):Box<U>{return value;}';

	static function main():Void {
		dynamicResultContexts();
		nullableContexts();
		final cases = [
			{name: 'nested', body: 'var value=forward(create());return value;', calls: 2},
			{name: 'alias', body: 'var inner=create();var alias=inner;var value=forward(alias);return value;', calls: 2},
			{name: 'deep', body: 'var value=forward(forward(create()));return value;', calls: 3},
			{name: 'return_context', body: 'return forward(create());', calls: 2},
			{name: 'omitted', body: 'var value=optional(create());return value;', calls: 2},
			{name: 'middle_omitted', body: 'var value=middle(create());return value;', calls: 2},
			{name: 'middle_alias', body: 'var inner=create();var value=middle(inner);return value;', calls: 2},
			{name: 'middle_supplied', body: 'var value=middle(3,create());return value;', calls: 2},
			{name: 'explicit_null', body: 'var value=optional(create(),null);return value;', calls: 2},
			{name: 'rest', body: 'var value=rest(create(),create(),create());return value;', calls: 4}
		];
		for (entry in cases) {
			final source = helpers
				+ 'static function run<S>(sample:S):Box<S>{'
				+ entry.body
				+ '}static function main():Void{Sys.println(run(1)!=null);}}';
			final path = writeSource(entry.name, source);
			assertUpstream(path, true);
			final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			var checked = 0;
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions()) {
					if (fn.getDeclaration().getSignature().getName() != 'run')
						continue;
					final expected = fn.getDeclaration().getSignature().getReturnType().getSemanticKey();
					function expression(value:TypedExpr):Void {
						final declaration = value.getDeclaration();
						if (value.getTag() == Call
							&& declaration != null
							&& ['create', 'forward', 'optional', 'middle', 'rest'].indexOf(declaration.getSignature().getName()) >= 0) {
							if (value.getType().getSemanticKey() != expected || value.getType().hasOpenMethodParameter())
								throw 'nested call lost its enclosing method parameter: ' + value.getType().getSemanticKey();
							checked++;
						}
						for (child in value.getExpressions())
							expression(child);
					}
					function statement(value:TypedStmt):Void {
						for (child in value.getExpressions())
							expression(child);
						for (child in value.getStatements())
							statement(child);
					}
					for (value in fn.getBody().getStatements())
						statement(value);
					final revision = CompilerTypedTreeRevision.functionBody(fn);
					typed.getBackendProjection();
					if (CompilerTypedTreeRevision.functionBody(fn) != revision)
						throw 'projection changed nested call inference';
				}
			if (checked != entry.calls)
				throw 'nested call test missed typed calls for ' + entry.name + ': ' + checked;
			JsRuntimeFixture.assertRuntime(typed, 'Main', 'true\n');
			Sys.println('NESTED_GENERIC_CALL:PASS ' + entry.name);
		}
		final negative = helpers + 'static function main():Void{var value=create();var first:Box<Int>=forward(value);var second:Box<String>=forward(value);}}';
		final path = writeSource('conflict', negative);
		assertUpstream(path, false);
		var diagnostic = '';
		try {
			final module = new ResolvedModule('Main', path, ParserStage.parse(negative, path));
			TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getBackendProjection();
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		if (diagnostic.indexOf('conflict') < 0 && diagnostic.indexOf('not compatible') < 0)
			throw 'nested alias conflict was not rejected by typing: ' + diagnostic;
		Sys.println('NESTED_GENERIC_CALL:PASS conflict');
	}

	/** A written Dynamic return stays Dynamic when an inferred generic call feeds a concrete argument. */
	static function dynamicResultContexts():Void {
		for (rest in [false, true]) {
			final consume = rest ? 'static function consume(...values:Int):Int{return values[0]+1;}' : 'static function consume(value:Int):Int{return value+1;}';
			// The authored untyped boundary models a native API input. Its unknown
			// value parameter triggers direct-call inference without erasing read's
			// explicitly declared Dynamic result or weakening later typed calls.
			final source = 'class Box<K,V>{}class Main{static var calls:Int=0;'
				+ 'static function read<K,V>(value:Box<K,V>,start:K):Dynamic{calls=calls+1;return 7;}'
				+ consume
				+ 'static function run(value:Int):Int{return consume(read(untyped value,0));}'
				+ 'static function main():Void{Sys.println(run(1)==8 && calls==1);}}';
			final path = writeSource(rest ? 'dynamic_result_rest' : 'dynamic_result', source);
			assertUpstream(path, true);
			final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			var checked = 0;
			function expression(value:TypedExpr):Void {
				if (value.getTag() == Call && value.getDeclaration() != null) {
					value.assertArgumentBinding();
					if (value.getDeclaration().getSignature().getName() == 'read') {
						if (!value.getType().isDynamic())
							throw 'concrete destination changed the declared Dynamic result';
						checked++;
					}
				}
				for (child in value.getExpressions())
					expression(child);
			}
			function statement(value:TypedStmt):Void {
				for (child in value.getExpressions())
					expression(child);
				for (child in value.getStatements())
					statement(child);
			}
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					for (body in fn.getBody().getStatements())
						statement(body);
			if (checked != 1)
				throw 'Dynamic result regression missed its exact generic call';
			JsRuntimeFixture.assertRuntime(typed, 'Main', 'true\n');
			final negative = StringTools.replace(source, ':Dynamic{calls=calls+1;return 7;}', ':String{calls=calls+1;return "wrong";}');
			final negativePath = writeSource(rest ? 'concrete_result_rest_conflict' : 'concrete_result_conflict', negative);
			final oracle = new sys.io.Process('node_modules/.bin/haxe', ['-cp', haxe.io.Path.directory(negativePath), '-main', 'Main', '--interp']);
			final output = oracle.stdout.readAll().toString();
			final errors = oracle.stderr.readAll().toString();
			final code = oracle.exitCode();
			oracle.close();
			if (code == 0 || errors.indexOf('String should be Int') < 0)
				throw 'upstream concrete call result did not reject: ' + output + errors;
			var rejected = false;
			try {
				final invalid = new ResolvedModule('Main', negativePath, ParserStage.parse(negative, negativePath));
				TyperStage.typeResolvedModule(invalid, TyperIndex.build([invalid])).getBackendProjection();
			} catch (error:haxe.Exception) {
				rejected = error.message.indexOf('No compatible method signature') >= 0 || error.message.indexOf('not compatible') >= 0;
			}
			if (!rejected)
				throw 'declared concrete result bypassed its argument constraint';
			Sys.println('NESTED_GENERIC_CALL:PASS declared Dynamic result ' + (rest ? 'rest' : 'ordinary'));
		}
	}

	/** Matching nullable generic destinations accept T without accepting an unrelated concrete result. */
	static function nullableContexts():Void {
		final source = 'class Main{static function identity<T>(value:T):T{return value;}static function plain<T>(value:T):Null<T>{return identity(value);}static function unchecked<T>(value:T):Null<T>{return untyped value;}static function main():Void{Sys.println(plain(3)==3 && unchecked(4)==4);}}';
		final path = writeSource('nullable', source);
		assertUpstream(path, true);
		final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
		JsRuntimeFixture.assertRuntime(TyperStage.typeResolvedModule(module, TyperIndex.build([module])), 'Main', 'true\n');
		final negative = StringTools.replace(StringTools.replace(source, 'plain<T>(value:T):Null<T>', 'plain<T>(value:T):Null<String>'),
			'Sys.println(plain(3)==3 && unchecked(4)==4);', 'plain(3);');
		final negativePath = writeSource('nullable_conflict', negative);
		final oracle = new sys.io.Process('node_modules/.bin/haxe', ['-cp', haxe.io.Path.directory(negativePath), '-main', 'Main', '--interp']);
		final output = oracle.stdout.readAll().toString();
		final errors = oracle.stderr.readAll().toString();
		final code = oracle.exitCode();
		oracle.close();
		if (code == 0 || errors.indexOf('String') < 0)
			throw 'upstream nullable conflict did not reject: ' + output + errors;
		var diagnostic = '';
		try {
			final rejected = new ResolvedModule('Main', negativePath, ParserStage.parse(negative, negativePath));
			TyperStage.typeResolvedModule(rejected, TyperIndex.build([rejected])).getBackendProjection();
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		if (diagnostic.indexOf('not compatible') < 0)
			throw 'nullable generic destination erased its concrete constraint: ' + diagnostic;
		Sys.println('NESTED_GENERIC_CALL:PASS nullable and nullable_conflict');
	}

	/** Keep each upstream source and artifact separate so a previous case cannot satisfy a later check. */
	static function writeSource(name:String, source:String):String {
		final root = '.tmp/nested_generic_call_' + name;
		sys.FileSystem.createDirectory(root);
		final path = root + '/Main.hx';
		sys.io.File.saveContent(path, source);
		return path;
	}

	/** Independent upstream execution defines acceptance and the conflicting alias's rejection. */
	static function assertUpstream(path:String, accepted:Bool):Void {
		final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', haxe.io.Path.directory(path), '-main', 'Main', '--interp']);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (accepted ? code != 0 || output != 'true\n' : code == 0 || errors.indexOf('Int should be String') < 0)
			throw 'upstream nested-call contract differs: ' + output + errors;
	}
}
