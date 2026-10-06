import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Empty arrays retain their own element variable until later source uses supply a type. */
class M14EmptyArrayInferenceTest {
	static function main():Void {
		final helpers = 'using Main.Extensions;'
			+ 'class Extensions{public static function fill(value:String,output:Array<Int>):Void{output.push(7);}'
			+ 'public static function fillGeneric<T>(value:T,output:Array<T>):Void{output.push(value);}}'
			+ 'class Main{static function take(values:Array<Int>):Void{values.push(7);}'
			+ 'static function text(values:Array<String>):Void{values.push("word");}'
			+ 'static function collect<T>(value:T):Array<T>{var values=[];values.push(value);return values;}';
		for (entry in [
			{
				name: "extension",
				body: 'var a=[];"witness".fill(a);trace(a[0]);',
				output: "7\n",
				accepted: true
			},
			{
				name: "generic_extension",
				body: 'var a=[];"word".fillGeneric(a);trace(a[0]);',
				output: "word\n",
				accepted: true
			},
			{
				name: "call",
				body: 'var values=[];take(values);trace(values[0]);',
				output: "7\n",
				accepted: true
			},
			{
				name: "alias",
				body: 'var values=[];var alias=values;take(alias);trace(values[0]);',
				output: "7\n",
				accepted: true
			},
			{
				name: "push",
				body: 'var values=[];values.push(7);trace(values[0]);',
				output: "7\n",
				accepted: true
			},
			{
				name: "independent",
				body: 'var a=[];var b=[];take(a);text(b);trace(a[0]);trace(b[0]);',
				output: "7\nword\n",
				accepted: true
			},
			{
				name: "context",
				body: 'var a=[];var typed:Array<Int>=a;take(typed);trace(a[0]);',
				output: "7\n",
				accepted: true
			},
			{
				name: "generic",
				body: 'var a=collect(7);trace(a[0]);',
				output: "7\n",
				accepted: true
			},
			{
				name: "unused",
				body: 'var a=[];trace(a.length);',
				output: "0\n",
				accepted: true
			},
			{
				name: "explicit_dynamic",
				body: 'var a:Array<Dynamic>=[];a.push(7);a.push("word");trace(a[0]);trace(a[1]);',
				output: "7\nword\n",
				accepted: true
			},
			{
				name: "conflict",
				body: 'var a=[];take(a);text(a);',
				output: "",
				accepted: false
			}
		]) {
			final root = ".tmp/empty-array-inference-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = helpers + 'static function main():Void{' + entry.body + '}}';
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final upstream = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = upstream.stdout.readAll().toString();
			final stderr = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			final expected = entry.output.split("\n")
				.filter(line -> line.length > 0)
				.map(line -> path + ":1: " + line + "\n")
				.join("");
			if ((code == 0) != entry.accepted
				|| (entry.accepted ? stdout != expected || stderr.length != 0 : stderr.indexOf("should be") < 0))
				throw "upstream empty-array contract differs: " + entry.name + stdout + stderr;
			final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
			final paths = Stage3SetupSupport.projectClassPaths({
				explicitPaths: [root],
				libraries: [],
				cwd: Sys.getCwd(),
				standardRoot: Stage1Args.getStandardLibraryRoot(args),
				targetDefine: "cpp"
			});
			final defines = Stage3SetupSupport.buildDefinesMap([], "cpp", "cpp-native");
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final index = TyperIndex.buildHeaders([module]);
			final loader = new ModuleLoader(paths, defines, index, null, false);
			loader.markResolvedAlready([module]);
			var typed:Null<TypedModule> = null;
			try {
				typed = TyperStage.typeResolvedModule(module, index, loader, true);
				typed.getBackendProjection();
			} catch (error:haxe.Exception) {
				if (entry.accepted)
					throw error;
				if (error.message.indexOf("conflict") < 0
					&& error.message.indexOf("not compatible") < 0
					&& error.message.indexOf("No compatible") < 0)
					throw "empty-array rejection lost its type diagnostic: " + error.message;
				typed = null;
			}
			if ((typed != null) != entry.accepted)
				throw "local empty-array acceptance differs: " + entry.name;
			if (typed != null) {
				assertElementTypes(typed, entry.name);
				JsRuntimeFixture.assertRuntime(typed, "Main", entry.output);
			}
			Sys.println("EMPTY_ARRAY_INFERENCE:PASS " + entry.name);
		}
	}

	/** Published locals must retain concrete elements and the exact enclosing method parameter. */
	static function assertElementTypes(module:TypedModule, name:String):Void {
		var observed = 0;
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions()) {
				final signature = fn.getDeclaration().getSignature();
				if (signature.getName() != "main" && signature.getName() != "collect")
					continue;
				for (local in fn.getEnvironment().getLocals()) {
					final type = local.getType();
					if (type.getNominalIdentity() == null || type.getNominalIdentity().getCanonicalName() != "Array")
						continue;
					final expected = signature.getName() == "collect" ? signature.getReturnType().getTypeArguments()[0].getSemanticKey() : switch name {
						case "explicit_dynamic" | "unused": "dynamic";
						case "generic_extension": "primitive:String";
						case "independent" if (local.getName() == "b"): "primitive:String";
						case _: "primitive:Int";
					};
					if (type.hasUnknownComponent()
						|| type.getTypeArguments().length != 1
						|| type.getTypeArguments()[0].getSemanticKey() != expected)
						throw "empty-array element identity differs: " + name + " " + local.getName() + " " + type.getSemanticKey();
					observed++;
				}
			}
		if (observed < 2)
			throw "empty-array test missed its main and generic locals";
	}
}
