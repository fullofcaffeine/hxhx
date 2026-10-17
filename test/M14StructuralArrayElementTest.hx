import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Stored record elements keep their identity and declared fields after structural array checking. */
class M14StructuralArrayElementTest {
	static function main():Void {
		final root = JsRuntimeFixture.reserveOutput();
		for (input in [
			{
				name: "optional",
				actual: "{var name:String;var ?tag:String;}",
				value: "value",
				accepted: true
			},
			{
				name: "width",
				actual: "{var name:String;var tag:String;var extra:Int;}",
				value: "value",
				accepted: true
			},
			{
				name: "missing",
				actual: "{var name:String;}",
				value: "value",
				accepted: false
			},
			{
				name: "wrong",
				actual: "{var name:String;var tag:Int;}",
				value: "value",
				accepted: false
			},
			{
				name: "fresh_extra",
				actual: "{var name:String;var tag:String;}",
				value: '{name:"n",tag:"t",extra:1}',
				accepted: false
			}
		]) {
			final observer = !input.accepted ? "" : 'final input:Supplied={name:"n",tag:"t"'
				+ (input.name == "width" ? ',extra:1' : '')
				+ '}; final values=check(input); js.Syntax.code("console.log({0} === {1})",values[0],input);'
				+ 'values[0].tag="changed"; js.Syntax.code("console.log({0})",input.tag);';
			final source = 'typedef Supplied='
				+ input.actual
				+ '; typedef Required={var name:String;var tag:String;};'
				+ 'class Main { static function check(value:Supplied):Array<Required> { return ['
				+ input.value
				+ ']; } static function main():Void {'
				+ observer
				+ '} }';
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final upstream = run(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
			if ((upstream.code == 0) != input.accepted || (upstream.code != 0 && upstream.code != 1))
				throw "unexpected upstream result " + input.name + upstream.stdout + upstream.stderr;
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
			final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
			final loader = new ModuleLoader(paths, defines, index, null, false);
			loader.markResolvedAlready([module]);
			var typed:Null<TypedModule> = null;
			try {
				typed = TyperStage.typeResolvedModule(module, index, loader, true);
			} catch (error:TyperError) {
				if (input.accepted)
					throw error;
			}
			if ((typed != null) != input.accepted)
				throw "stored record array acceptance differs: " + input.name;
			if (typed != null) {
				var observed = false;
				for (owner in typed.getTypedClasses())
					for (fn in owner.getFunctions())
						if (fn.getDeclaration().getSignature().getName() == "check") {
							final array = fn.getBody().getStatements()[0].getExpressions()[0];
							final operand = array.getExpressions()[0];
							if (array.getTag() != ArrayDecl
								|| operand.getTag() != LocalRead
								|| operand.getType()
									.getSemanticKey() != fn.getDeclaration()
									.getSignature()
									.getArgs()[0].getSemanticKey())
								throw "structural array checking changed its stored operand type";
							observed = true;
						}
				if (!observed)
					throw "structural array observer missed the authored return";
				final script = root + "/candidate.js";
				new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
					new backend.BackendContext(root, script, "Main", true, false, defines));
				for (file in [root + "/upstream.js", script]) {
					final result = run("node", [file]);
					if (result.code != 0 || result.stdout != "true\nchanged\n")
						throw "structural array identity or mutation differs: " + input.name + result.stdout + result.stderr;
				}
			}
			Sys.println("STRUCTURAL_ARRAY_ELEMENT:PASS " + input.name);
		}
	}

	/** A timeout or abnormal compiler exit is not evidence of type rejection. */
	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}
}
