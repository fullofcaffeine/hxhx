import sys.io.File;

/** Written abstract destinations retain source inference and real runtime identity through declared header conversions. */
class M14AbstractDestinationInferenceTest {
	static function main():Void {
		check();
	}

	public static function check():Void {
		for (entry in [
			{
				name: "dynamic",
				header: "abstract Token(Dynamic) from Dynamic {}",
				body: "return [];",
				element: "Dynamic",
				value: "empty",
				accepted: true
			},
			{
				name: "array",
				header: "abstract Token(Array<String>) from Array<String> {}",
				body: "return [];",
				element: "String",
				value: "empty",
				accepted: true
			},
			{
				name: "missing",
				header: "abstract Token(Dynamic) {}",
				body: "return [];",
				element: "",
				value: "",
				accepted: false
			},
			{
				name: "later",
				header: "abstract Token(Dynamic) from Dynamic {}",
				body: "var a=[];var t:Token=a;a.push(7);return t;",
				element: "Int",
				value: "7",
				accepted: true
			},
			{
				name: "first",
				header: "abstract Token(Dynamic) from Array<String> from Array<Int> {}",
				body: 'var a=[];var t:Token=a;a.push("word");return t;',
				element: "String",
				value: "word",
				accepted: true
			},
			{
				name: "conflict",
				header: "abstract Token(Dynamic) from Array<String> from Array<Int> {}",
				body: "var a=[];var t:Token=a;a.push(7);return t;",
				element: "",
				value: "",
				accepted: false
			},
			{
				name: "reverse",
				header: "abstract Token(Dynamic) from Array<Int> from Array<String> {}",
				body: "var a=[];var t:Token=a;a.push(7);return t;",
				element: "Int",
				value: "7",
				accepted: true
			},
			{
				name: "rollback",
				header: "abstract Token(Dynamic) from Array<String> from Array<Int> {}",
				body: "var a=[];a.push(7);var t:Token=a;return t;",
				element: "Int",
				value: "7",
				accepted: true
			},
			{
				name: "generic",
				header: "abstract Box<T>(Array<T>) from Array<T> {} typedef Token=Box<String>;",
				body: 'var a=[];var t:Token=a;a.push("word");return t;',
				element: "String",
				value: "word",
				accepted: true
			},
			{
				name: "identity",
				header: "abstract Token(Dynamic) from Dynamic {}",
				body: "var a=[];var t:Token=a;Host.remember(a);a.push(7);return t;",
				element: "Int",
				value: "7",
				accepted: true
			}
		]) {
			final root = ".tmp/abstract_destination_" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = entry.header
				+
				'@:native("Host")extern class Host{public static function start():Void;public static function remember(value:Dynamic):Void;public static function observe(value:Token):Void;}'
				+ 'class Main{static function make():Token{Host.start();'
				+ entry.body
				+ '}static function main():Void{Host.observe(make());}}';
			File.saveContent(path, source);
			final upstream = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
			if ((upstream.code == 0) != entry.accepted)
				throw "upstream abstract destination acceptance differs: " + entry.name + upstream.stderr;
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final args = hxhx.Stage1Compiler.Stage1Args.parse(["-main", "Main"], true);
			final standardRoot = hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(args);
			final index = TyperIndex.buildHeaders([module]);
			final loader = new ModuleLoader([standardRoot + "/js/_std", standardRoot], hxhx.Stage3SetupSupport.buildDefinesMap([], "js", "js-native"), index,
				null, true);
			loader.markResolvedAlready([module]);
			if (loader.ensureTypeAvailable("Array", "", []) == null)
				throw "missing real Array provider";
			var typed:Null<TypedModule> = null;
			var failure = "";
			try {
				typed = TyperStage.typeResolvedModule(module, index, loader, true);
			} catch (error:TyperError) {
				failure = error.message;
			}
			if ((typed != null) != entry.accepted)
				throw "abstract destination acceptance differs: " + entry.name + failure;
			if (typed != null) {
				var arrays = 0;
				function inspect(expression:TypedExpr):Void {
					final type = expression.getType();
					final identity = type.getNominalIdentity();
					if (identity != null && identity.getCanonicalName() == "Array") {
						arrays++;
						if (type.getTypeArguments().length != 1 || type.getTypeArguments()[0].getDisplay() != entry.element)
							throw "abstract destination changed source element inference: " + entry.name + type.getSemanticKey();
					}
					for (child in expression.getExpressions())
						inspect(child);
				}
				for (owner in typed.getTypedClasses())
					for (method in owner.getFunctions())
						for (statement in method.getBody().getStatements())
							for (expression in statement.getExpressions())
								inspect(expression);
				if (arrays == 0)
					throw "abstract destination fixture missed its source array";
				final harness = root + "/host.cjs";
				File.saveContent(harness,
					'let starts=0,observations=0,remembered;global.Host={start(){starts++;},remember(value){remembered=value;},observe(value){observations++;'
					+ 'if(!Array.isArray(value)||remembered!==undefined&&remembered!==value)throw Error("lost array identity");'
					+ 'const expected="'
					+ entry.value
					+ '";if(expected==="empty"?value.length!==0:value.length!==1||String(value[0])!==expected)throw Error("array contents");'
					+ '}};require(process.argv[2]);if(starts!==1||observations!==1)throw Error("evaluation count");console.log("ok");');
				new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
					new backend.BackendContext(root, root + "/native.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
				for (file in ["upstream.js", "native.js"]) {
					final result = run("node", [harness, sys.FileSystem.fullPath(root + "/" + file)]);
					if (result.code != 0 || result.stdout != "ok\n")
						throw "abstract destination runtime differs: " + entry.name + file + result.stdout + result.stderr;
				}
			}
			Sys.println("ABSTRACT_DESTINATION_INFERENCE:PASS " + entry.name);
		}
	}

	/** Observe both compiler acceptance and independent host assertions. */
	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}
}
