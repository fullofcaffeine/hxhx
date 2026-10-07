/** Explicit Dynamic destinations must not erase constraints on shared untyped results. */
class M14UntypedDynamicContextTest {
	static function main():Void {
		final cases = [
			{
				name: "assigned",
				body: "var value;value=untyped text.foreign();take(value);",
				parameter: "text:String",
				accepted: true,
				argument: "Dynamic"
			},
			{
				name: "assigned_try",
				body: "var value;try {value=untyped text.foreign();} catch(error:Dynamic) {return;}take(value);",
				parameter: "text:String",
				accepted: true,
				argument: "Dynamic"
			},
			{
				name: "assigned_constrained",
				body: "var value;value=untyped text.foreign();take(value);var concrete:Int=value;",
				parameter: "text:String",
				accepted: true,
				argument: "Int"
			},
			{
				name: "assigned_conflict",
				body: "var value;value=untyped text.foreign();take(value);var first:Int=value;var second:String=value;",
				parameter: "text:String",
				accepted: false,
				argument: ""
			},
			{
				name: "assigned_again",
				body: "var value;value=untyped text.foreign();value=7;take(value);",
				parameter: "text:String",
				accepted: true,
				argument: "Int"
			},
			{
				name: "assigned_again_conflict",
				body: "var value;value=untyped text.foreign();value=7;value=\"bad\";take(value);",
				parameter: "text:String",
				accepted: false,
				argument: ""
			},
			{
				name: "direct",
				body: "take(untyped text.foreign());",
				parameter: "text:String",
				accepted: true,
				argument: "Dynamic"
			},
			{
				name: "alias",
				body: "var value=untyped text.foreign();take(value);",
				parameter: "text:String",
				accepted: true,
				argument: "Dynamic"
			},
			{
				name: "constrained",
				body: "var value=untyped text.foreign();take(value);var concrete:Int=value;",
				parameter: "text:String",
				accepted: true,
				argument: "Int"
			},
			{
				name: "conflict",
				body: "var value=untyped text.foreign();take(value);var first:Int=value;var second:String=value;",
				parameter: "text:String",
				accepted: false,
				argument: ""
			},
			{
				name: "ordinary",
				body: "take(text.foreign());",
				parameter: "text:String",
				accepted: false,
				argument: ""
			},
			{
				name: "omitted_parameter",
				body: "take(text);",
				parameter: "text",
				accepted: true,
				argument: "Dynamic"
			}
		];
		for (entry in cases) {
			final source = 'class Main { static function take(value:Dynamic):Void {} static function run('
				+ entry.parameter
				+ '):Void {'
				+ entry.body
				+ '} static function main():Void {} }';
			final root = ".tmp/untyped-dynamic-context-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if ((code == 0) != entry.accepted)
				throw "upstream Dynamic-context acceptance differs: " + entry.name + output + errors;
			var typed:Null<TypedModule> = null;
			try {
				final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
				typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
				typed.getBackendProjection();
			} catch (error:haxe.Exception) {
				if (entry.accepted)
					throw error;
				typed = null;
			}
			if ((typed != null) != entry.accepted)
				throw "local Dynamic-context acceptance differs: " + entry.name;
			if (typed != null) {
				var calls = 0;
				function expression(value:TypedExpr):Void {
					final declaration = value.getDeclaration();
					if (value.getTag() == Call && declaration != null && declaration.getSignature().getName() == "take") {
						final binding = value.getNamedArguments();
						if (binding == null
							|| value.getExpressions()[1].getType().getSemanticKey() != TyType.fromHintText(entry.argument).getSemanticKey())
							throw "Dynamic context erased or lost later type evidence: " + entry.name;
						value.assertArgumentBinding();
						calls++;
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
				if (calls != 1)
					throw "Dynamic-context fixture lost its call";
			}
			Sys.println("UNTYPED_DYNAMIC_CONTEXT:PASS " + entry.name);
		}
		assignedRuntime();
	}

	/** Both a successful first write and a throwing path keep their original effects. */
	static function assignedRuntime():Void {
		final source = 'class Main {static function take(value:Dynamic):Void {Sys.println(value);} '
			+ 'static function read(handle:{},fail:Bool):Void {var value;try {if(fail) throw "skip";value=untyped handle.value;}'
			+ 'catch(error:Dynamic) {Sys.println("caught");return;}take(value);} '
			+ 'static function main():Void {read({value:7},false);read({value:true},false);read({value:"ok"},false);'
			+ 'var nothing:Dynamic=null;read({value:nothing},false);read({value:9},true);}}';
		final root = '.tmp/untyped-assigned-runtime';
		sys.FileSystem.createDirectory(root);
		final path = root + '/Main.hx';
		sys.io.File.saveContent(path, source);
		final expected = '7\ntrue\nok\nnull\ncaught\n';
		final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || output != expected)
			throw 'upstream assigned untyped result differs: ' + output + errors;
		final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, 'Main', expected);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + '/ocaml', true);
		final timeout = Sys.systemName() == 'Mac' ? 'gtimeout' : 'timeout';
		final native = new sys.io.Process(timeout, ['30', executable]);
		final nativeOutput = native.stdout.readAll().toString();
		final nativeErrors = native.stderr.readAll().toString();
		final nativeCode = native.exitCode();
		native.close();
		if (nativeCode != 0 || nativeOutput != expected)
			throw 'native assigned untyped result differs: ' + nativeOutput + nativeErrors;
		Sys.println('UNTYPED_ASSIGNED_RUNTIME:PASS');
	}
}
