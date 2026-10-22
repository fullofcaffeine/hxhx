/** Dynamic calls supply argument context without erasing later constraints or evaluation order. */
class M14DynamicArgumentContextTest {
	static function main():Void {
		final typed = "static var invoke:(Dynamic,Int)->Int=consume;";
		final dynamicField = "static var invoke:Dynamic=consume;";
		for (entry in [
			{
				name: "typed",
				field: typed,
				hint: "{value:Int}",
				body: "return invoke(handle.value,if(flag)2 else 3);",
				argument: "primitive:Int",
				events: "v"
			},
			{
				name: "known",
				field: dynamicField,
				hint: "{value:Int}",
				body: "return invoke(handle.value,if(flag)2 else 3);",
				argument: "primitive:Int",
				events: "v"
			},
			{
				name: "direct",
				field: dynamicField,
				hint: "{}",
				body: "return invoke(untyped handle.value,if(flag)2 else 3);",
				argument: "dynamic",
				events: "v"
			},
			{
				name: "alias",
				field: dynamicField,
				hint: "{}",
				body: "var value=untyped handle.value;var alias=value;return invoke(alias,if(flag)2 else 3);",
				argument: "dynamic",
				events: "v"
			},
			{
				name: "later",
				field: dynamicField,
				hint: "{}",
				body: "var value=untyped handle.value;var result=invoke(value,if(flag)2 else 3);var concrete:Int=value;return result;",
				argument: "primitive:Int",
				events: "v"
			},
			{
				name: "unused",
				field: dynamicField,
				hint: "{}",
				body: "untyped handle.unused;return invoke(untyped handle.value,if(flag)2 else 3);",
				argument: "dynamic",
				events: "v"
			},
			{
				name: "effects",
				field: dynamicField,
				hint: "{}",
				body: "return acquire()(untyped receiver(handle).value,if(flag)mark(2) else mark(3));",
				argument: "dynamic",
				events: "crav"
			}
		]) {
			final source = 'class Main{static var events:String="";static function consume(value:Dynamic,other:Int):Int{events+="v";return other;}'
				+ entry.field
				+ 'static function acquire():Dynamic{events+="c";return invoke;}'
				+ 'static function receiver(value:{}):{}{events+="r";return value;}static function mark(value:Int):Int{events+="a";return value;}'
				+ 'static function run(handle:'
				+ entry.hint
				+ ',flag:Bool):Dynamic{'
				+ entry.body
				+ '}'
				+ 'static function main():Void{var answer=run({value:7},true);Sys.println(answer);Sys.println(events);}}';
			final root = '.tmp/dynamic-argument-contract-' + entry.name;
			final expected = '2\n' + entry.events + '\n';
			upstream(root, source, expected);
			final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
			final typedModule = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			var calls = 0;
			function expression(value:TypedExpr):Void {
				final operands = value.getExpressions();
				if (value.getTag() == Call && operands[0].getType().isDynamic()) {
					if (operands.length != 3 || operands[1].getType().getSemanticKey() != entry.argument || !value.getType().isDynamic())
						throw 'Dynamic call lost its argument or result contract: ' + entry.name;
					calls++;
				}
				if (value.getTag() == FieldRead && value.getTexts()[0] == 'unused' && !value.getType().isUnknown())
					throw 'Dynamic call context leaked into an unrelated unused field';
				for (child in operands)
					expression(child);
			}
			function statement(value:TypedStmt):Void {
				for (child in value.getExpressions())
					expression(child);
				for (child in value.getStatements())
					statement(child);
			}
			for (owner in typedModule.getTypedClasses())
				for (fn in owner.getFunctions())
					if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == 'run')
						for (body in fn.getBody().getStatements())
							statement(body);
			if (calls != (entry.name == 'typed' ? 0 : 1))
				throw 'Dynamic argument observer missed its call';
			JsRuntimeFixture.assertRuntime(typedModule, 'Main', expected);
			if (entry.name == 'effects')
				@:privateAccess M14NekoClosureControlTest.assertSource('dynamic_argument_context', source, expected);
			Sys.println('DYNAMIC_ARGUMENT_CONTEXT:PASS ' + entry.name);
		}
		rejected('conflict',
			'static function run(handle:{}):Void{var value=untyped handle.value;invoke(value,2);var first:Int=value;var second:String=value;}');
		rejected('ordinary', 'static function run(handle:{},flag:Bool):Void{invoke(handle.value,if(flag)2 else 3);}');
	}

	/** Upstream behavior is authored independently of the local inference implementation. */
	static function upstream(root:String, source:String, expected:Null<String>):Void {
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + '/Main.hx', source);
		final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
		final out = process.stdout.readAll().toString();
		final err = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (expected == null ? code == 0
			|| (err.indexOf('should be') < 0 && err.indexOf('has no field') < 0) : code != 0 || out != expected)
			throw 'upstream Dynamic argument differs: ' + root + out + err;
		Sys.println('UPSTREAM_DYNAMIC_ARGUMENT_CONTEXT:PASS ' + root);
	}

	/** Dynamic use neither erases incompatible alias constraints nor grants unchecked access. */
	static function rejected(name:String, body:String):Void {
		final source = 'class Main{static var invoke:Dynamic;' + body + 'static function main():Void{}}';
		final root = '.tmp/dynamic-argument-rejection-' + name;
		upstream(root, source, null);
		var failure = '';
		try {
			final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			typed.getBackendProjection();
			JsRuntimeFixture.assertRuntime(typed, 'Main', '');
		} catch (error:haxe.Exception)
			failure = error.message;
		if (failure.indexOf('not compatible') < 0
			&& failure.indexOf('conflict') < 0
			&& failure.indexOf('cannot materialize an unresolved operand') < 0)
			throw 'Dynamic argument rejection differs: ' + name + ' ' + failure;
		Sys.println('DYNAMIC_ARGUMENT_REJECTION:PASS ' + name);
	}
}
