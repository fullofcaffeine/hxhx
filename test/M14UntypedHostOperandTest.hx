import backend.BackendContext;
import backend.js.JsBackend;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Explicit untyped host reads retain evidence through call typing and executable publication. */
class M14UntypedHostOperandTest {
	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function run(command:String, args:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, args);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function typeSource(source:String, path:String):TypedModule {
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function prove(caseName:String, body:String, expected:String, expectedReads:Int = 1):Void {
		final root = ".tmp/untyped_host_operand_" + caseName;
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = '@:native("console") extern class Console {public static function log(value:String):Void;}'
			+ 'class Main {static function read(value:Dynamic):Int {return value.answer;}'
			+ 'static function main():Void {var result = untyped '
			+ body
			+ '; Console.log(""+result);}}';
		sys.io.File.saveContent(path, source);
		final upstream = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		check(upstream.code == 0, upstream.stderr);
		final harness = root + "/host.cjs";
		sys.io.File.saveContent(harness,
			'let reads=0; Object.defineProperty(global,"hostPayload",{get(){reads++;return Object.freeze({answer:7,nested:Object.freeze({answer:7}),method(){return {answer:this.answer};}});}}); require(process.argv[2]); if(reads!==' +
			expectedReads + ')throw Error("host operand evaluated more than once");');
		check(run("node", [harness, sys.FileSystem.fullPath(root + "/upstream.js")]).stdout == expected, "upstream host operand differs");
		final typed = typeSource(source, path);
		var calls = 0;
		function inspect(expression:TypedExpr):Void {
			if (expression.getTag() == LocalRead && expression.getTexts()[0] == "known")
				check(expression.getType().getSemanticKey() == "primitive:Int", "known local lost its written type");
			final declaration = expression.getDeclaration();
			if (expression.getTag() == Call && declaration != null && declaration.getSignature().getName() == "read") {
				calls++;
				check(expression.getType().getSemanticKey() == "primitive:Int", "known result lost its type");
				final children = expression.getExpressions();
				check(children[children.length - 1].getType().isDynamic(), "host argument lost its explicit boundary type");
			}
			for (child in expression.getExpressions())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (method in owner.getFunctions())
				for (statement in method.getBody().getStatements())
					for (expression in statement.getExpressions())
						inspect(expression);
		check(calls == 1, "host call lost its selected declaration");
		new JsBackend().emit(new MacroExpandedProgram([typed], false),
			new BackendContext(root, root + "/native.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
		final native = run("node", [harness, sys.FileSystem.fullPath(root + "/native.js")]);
		check(native.code == 0 && native.stdout == expected, "native host operand differs: " + native.stderr);
		final strict = StringTools.replace(source, "untyped ", "");
		sys.io.File.saveContent(path, strict);
		check(run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/invalid.js"]).code != 0, "upstream accepted undeclared typed name");
		var rejected = false;
		try {
			typeSource(strict, path);
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		check(rejected, "ordinary typed host access was admitted");
		Sys.println("UNTYPED_HOST_OPERAND:PASS " + caseName);
	}

	static function main():Void {
		prove("direct", "read(hostPayload)", "7\n");
		prove("field", "read(hostPayload.nested)", "7\n");
		prove("bound", "read(hostPayload.method.bind(hostPayload)())", "7\n", 2);
		prove("alias", "{var known:Int=3; var alias=hostPayload; read(alias)+known;}", "10\n");
		proveReceiver("return", 'var values=[];untyped values.push(hostName);return values;');
		proveReceiver("alias", 'var values=[];var alias=values;untyped alias.push(hostName);return values;');
		proveReceiver("stored", 'var values=[];var item=untyped hostName;values.push(item);return values;');
		proveReceiver("written", 'var values:Array<String>=[];untyped values.push(hostName);return values;');
		proveReceiver("conflict", 'var values=[];untyped values.push(hostName);values.push(7);return values;', false);
		proveReceiver("scope", 'var values=[];untyped {values.push(hostName);}values.push(missingName);return values;', false);
	}

	/** A return annotation solves the earlier receiver and operand together; explicit untyped scope stays local. */
	static function proveReceiver(caseName:String, body:String, accepted:Bool = true):Void {
		final root = ".tmp/untyped_receiver_" + caseName;
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = '@:native("console") extern class Console {public static function log(value:String):Void;}'
			+ 'class Main {static function values():Array<String>{'
			+ body
			+ '}static function main():Void{Console.log(values()[0]);}}';
		sys.io.File.saveContent(path, source);
		final upstream = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		check((upstream.code == 0) == accepted, "upstream receiver acceptance differs: " + caseName + upstream.stderr);
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "js", "js-native"), index, null, true);
		loader.markResolvedAlready([module]);
		check(loader.ensureTypeAvailable("Array", "", []) != null, "missing real Array declaration");
		var typed:Null<TypedModule> = null;
		try {
			typed = TyperStage.typeResolvedModule(module, index, loader, true);
			typed.getBackendProjection();
		} catch (error:haxe.Exception) {
			if (accepted)
				throw error;
			typed = null;
		}
		check((typed != null) == accepted, "receiver acceptance differs: " + caseName);
		if (typed != null) {
			var pushes = 0;
			function inspect(expression:TypedExpr):Void {
				final declaration = expression.getDeclaration();
				if (expression.getTag() == Call && declaration != null && declaration.getSignature().getName() == "push") {
					pushes++;
					final values = expression.getExpressions();
					check(expression.getNamedArguments() != null, "receiver call lost its selected binding");
					check(values[values.length - 1].getType().getSemanticKey() == "primitive:String", "receiver operand was not solved");
				}
				for (child in expression.getExpressions())
					inspect(child);
			}
			for (owner in typed.getTypedClasses())
				for (method in owner.getFunctions())
					for (statement in method.getBody().getStatements())
						for (expression in statement.getExpressions())
							inspect(expression);
			check(pushes == 1, "receiver regression missed its call");
			final harness = root + "/host.cjs";
			sys.io.File.saveContent(harness,
				'let reads=0;Object.defineProperty(global,"hostName",{get(){reads++;return "word";}});' +
				'require(process.argv[2]);if(reads!==1)throw Error("host read count differs");');
			new JsBackend().emit(new MacroExpandedProgram([typed], false),
				new BackendContext(root, root + "/native.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
			for (file in ["upstream.js", "native.js"]) {
				final result = run("node", [harness, sys.FileSystem.fullPath(root + "/" + file)]);
				check(result.code == 0 && result.stdout == "word\n", "receiver runtime differs: " + file + result.stderr);
			}
		}
		Sys.println("UNTYPED_RECEIVER_INPUT:PASS " + caseName);
	}
}
