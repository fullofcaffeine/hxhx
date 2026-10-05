/** Compare effective member visibility with upstream, then execute the admitted extern helper cases. */
class M14ExternVisibilityParserTest {
	static function main():Void {
		for (entry in [
			{
				name: "extern_default",
				owner: "extern class",
				access: "",
				accepted: true
			},
			{
				name: "extern_public",
				owner: "extern class",
				access: "public ",
				accepted: true
			},
			{
				name: "extern_private",
				owner: "extern class",
				access: "private ",
				accepted: false
			},
			{
				name: "class_default",
				owner: "class",
				access: "",
				accepted: false
			}
		]) {
			final root = ".tmp/extern-member-visibility-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = 'using Main.Helper;'
				+ entry.owner
				+ ' Helper {'
				+ entry.access
				+ 'static var token:Int;'
				+ entry.access
				+ 'static inline function twice(value:Int):Int{return value*2;}}'
				+ 'class Main {static function take(value:Int):Void{if(value!=6)throw "extension result";}'
				+ 'static function main():Void{var value=3;take(value.twice());}}';
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if ((code == 0) != entry.accepted || (!entry.accepted && errors.indexOf("has no field twice") < 0))
				throw "upstream extern visibility differs: " + entry.name + output + errors;
			// Extern storage needs a host implementation to execute. Type-check its
			// visibility separately while the inline method supplies runtime evidence.
			final fieldSource = entry.owner
				+ ' FieldProvider {'
				+ entry.access
				+ 'static var token:Int;}'
				+ 'class FieldMain {static function main():Void{var value:Int=FieldProvider.token;}}';
			sys.io.File.saveContent(root + "/FieldMain.hx", fieldSource);
			final fieldCheck = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "FieldMain", "--no-output"]);
			final fieldOutput = fieldCheck.stdout.readAll().toString();
			final fieldErrors = fieldCheck.stderr.readAll().toString();
			final fieldCode = fieldCheck.exitCode();
			fieldCheck.close();
			if ((fieldCode == 0) != entry.accepted || (!entry.accepted && fieldErrors.indexOf("private field token") < 0))
				throw "upstream field visibility differs: " + entry.name + fieldOutput + fieldErrors;
			final parsed = ParserStage.parse(source, path);
			final expected = entry.accepted ? HxVisibility.Public : HxVisibility.Private;
			for (owner in HxModuleDecl.getClasses(parsed.getDecl()))
				if (HxClassDecl.getName(owner) == "Helper") {
					if (HxFieldDecl.getVisibility(HxClassDecl.getFields(owner)[0]) != expected
						|| HxFunctionDecl.getVisibility(HxClassDecl.getFunctions(owner)[0]) != expected)
						throw "extern field or method visibility differs";
				}
			if (!entry.accepted) {
				Sys.println("EXTERN_VISIBILITY_PARSER:PASS " + entry.name);
				continue;
			}
			var typed:Null<TypedModule> = null;
			try {
				final module = new ResolvedModule("Main", path, parsed);
				typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
				typed.getBackendProjection();
			} catch (error:haxe.Exception) {
				if (entry.accepted)
					throw error;
				typed = null;
			}
			if ((typed != null) != entry.accepted)
				throw "local extern visibility differs: " + entry.name;
			if (typed != null)
				JsRuntimeFixture.assertRuntime(typed, "Main", "");
			Sys.println("EXTERN_VISIBILITY_PARSER:PASS " + entry.name);
		}
	}
}
