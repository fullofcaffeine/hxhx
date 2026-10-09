import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Real enum providers obey explicit-using and member precedence without inventing method signatures. */
class M14DefaultEnumExtensionTest {
	static function main():Void {
		for (entry in [
			{
				name: "erased",
				prefix: "",
				generic: "",
				parameter: "value:EnumValue",
				result: "Array<Dynamic>",
				method: "getParameters",
				owner: "haxe.EnumTools.EnumValueTools",
				accepted: true
			},
			{
				name: "concrete",
				prefix: "",
				generic: "",
				parameter: "value:Token",
				result: "Int",
				method: "getIndex",
				owner: "haxe.EnumTools.EnumValueTools",
				accepted: true
			},
			{
				name: "bounded",
				prefix: "",
				generic: "<T:EnumValue>",
				parameter: "value:T",
				result: "Int",
				method: "getIndex",
				owner: "haxe.EnumTools.EnumValueTools",
				accepted: true
			},
			{
				name: "enum_type",
				prefix: "",
				generic: "",
				parameter: "value:Enum<Token>",
				result: "String",
				method: "getName",
				owner: "haxe.EnumTools",
				accepted: true
			},
			{
				name: "override",
				prefix: "using Main.Custom;",
				generic: "",
				parameter: "value:EnumValue",
				result: "Int",
				method: "getIndex",
				owner: "Main.Custom",
				accepted: true
			},
			{
				name: "member",
				prefix: "using Main.Custom;",
				generic: "",
				parameter: "value:Own",
				result: "Int",
				method: "getIndex",
				owner: "Main.Own",
				accepted: true
			},
			{
				name: "unrelated",
				prefix: "",
				generic: "",
				parameter: "value:String",
				result: "Int",
				method: "getIndex",
				owner: "",
				accepted: false
			}
		]) {
			final root = ".tmp/default-enum-extension-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = entry.prefix
				+ 'enum Token{Item(value:Int);} class Custom{public static function getIndex(value:EnumValue):Int{return 42;}}'
				+ 'class Own{public function new(){}public function getIndex():Int{return 19;}}'
				+ 'class Main{static function inspect'
				+ entry.generic
				+ '('
				+ entry.parameter
				+ '):'
				+ entry.result
				+ '{return value.'
				+ entry.method
				+ '();}static function main():Void{}}';
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if ((code == 0) != entry.accepted || (!entry.accepted && errors.indexOf("has no field getIndex") < 0))
				throw "upstream default extension differs: " + entry.name + output + errors;
			final arguments = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
			final paths = Stage3SetupSupport.projectClassPaths({
				explicitPaths: [root],
				libraries: [],
				cwd: Sys.getCwd(),
				standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
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
				typed = null;
			}
			if ((typed != null) != entry.accepted)
				throw "local default extension differs: " + entry.name;
			if (typed != null) {
				var calls = 0;
				function expression(value:TypedExpr):Void {
					final declaration = value.getDeclaration();
					if (value.getTag() == Call && declaration != null && declaration.getSignature().getName() == entry.method) {
						if (declaration.getOwner().getCanonicalName() != entry.owner)
							throw "extension priority changed: " + declaration.getOwner().getCanonicalName();
						final provider = value.getExtensionProvider();
						if (entry.name == "member" ? provider != null : provider == null || provider.getCanonicalName() != entry.owner)
							throw "extension provider identity changed";
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
						if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "inspect")
							for (body in fn.getBody().getStatements())
								statement(body);
				if (calls != 1)
					throw "default extension call was lost";
			}
			Sys.println("DEFAULT_ENUM_EXTENSION:PASS " + entry.name);
		}
	}
}
