import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Independent source checks keep recursive proof reuse from hiding incompatible payloads or optional fields. */
class M14RecursiveStructuralCompatibilityTest {
	static function main():Void {
		final declarations = "typedef Left<T>={final value:T; final ?next:Left<T>;}; "
			+ "typedef Right<T>={final value:T; final ?next:Right<T>;}; "
			+ "typedef Optional={var ?value:Int; var ?next:Optional;}; "
			+ "typedef Required={var value:Int; var ?next:Required;}; "
			+ "typedef Missing={var ?next:Missing;}; "
			+ "class Box<T> {} typedef GrowingLeft<T>={final value:T; final ?next:GrowingLeft<Box<T>>;}; "
			+ "typedef GrowingRight<T>={final value:T; final ?next:GrowingRight<Box<T>>;}; "
			+ "typedef PhantomLeft<T>={final ?next:PhantomLeft<Box<T>>;}; "
			+ "typedef PhantomRight<T>={final ?next:PhantomRight<Box<T>>;}; "
			+ "typedef ExtraParameter<Unused,T>={final value:T; final ?next:ExtraParameter<Unused,Box<T>>;}; "
			+ "typedef NestedLeft={var nodes:Array<GrowingLeft<Int>>;}; "
			+ "typedef NestedRight={var nodes:Array<{final value:Int; final ?next:GrowingLeft<Box<Int>>;}>;}; "
			+ "typedef NestedWrong={var nodes:Array<{final value:String; final ?next:GrowingLeft<Box<Int>>;}>;}; ";
		final cases = [
			{
				name: "nested array alias expansion",
				expected: "NestedLeft",
				actual: "NestedRight",
				accepted: true
			},
			{
				name: "nested array payload mismatch",
				expected: "NestedLeft",
				actual: "NestedWrong",
				accepted: false
			},
			{
				name: "different alias names",
				expected: "Right<Int>",
				actual: "Left<Int>",
				accepted: true
			},
			{
				name: "different payloads",
				expected: "Right<Int>",
				actual: "Left<String>",
				accepted: false
			},
			{
				name: "different applications",
				expected: "Left<Int>",
				actual: "Left<String>",
				accepted: false
			},
			{
				name: "optional to required",
				expected: "Required",
				actual: "Optional",
				accepted: true
			},
			{
				name: "required to optional",
				expected: "Optional",
				actual: "Required",
				accepted: true
			},
			{
				name: "missing required field",
				expected: "Required",
				actual: "Missing",
				accepted: false
			},
			{
				name: "growing applications with different payloads",
				expected: "GrowingRight<Int>",
				actual: "GrowingLeft<String>",
				accepted: false
			},
			{
				name: "growing equivalent applications",
				expected: "GrowingRight<Int>",
				actual: "GrowingLeft<Int>",
				accepted: true
			},
			{
				name: "phantom growing arguments",
				expected: "PhantomRight<Int>",
				actual: "PhantomLeft<String>",
				accepted: true
			},
			{
				name: "extra phantom parameter",
				expected: "GrowingRight<Int>",
				actual: "ExtraParameter<String,Int>",
				accepted: true
			}
		];
		final root = JsRuntimeFixture.reserveOutput();
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final args = Stage1Args.parse(["-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		for (input in cases) {
			final source = declarations + "class Main { static function check(value:" + input.actual + "):" + input.expected
				+ " { return value; } static function main():Void {} }";
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", [
				"30",
				compiler == null ? "node_modules/.bin/haxe" : compiler,
				"-cp",
				root,
				"-main",
				"Main",
				"-js",
				root + "/upstream.js"
			]);
			final stdout = upstream.stdout.readAll().toString();
			final stderr = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if ((code == 0) != input.accepted || (code != 0 && code != 1))
				throw "upstream recursive compatibility differs for " + input.name + ": " + stdout + stderr;
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final index = TyperIndex.buildHeaders([module]);
			final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "js", "js-native"), index, null, false);
			loader.markResolvedAlready([module]);
			final context:TyTypeDeclaration.TyTypeResolutionContext = {
				packagePath: "",
				modulePath: "Main",
				directives: [],
				filePath: path,
				position: HxPos.unknown(),
				parameters: []
			};
			final expected = index.resolveTypeUse(TyType.fromHintText(input.expected), context).getType();
			final actual = index.resolveTypeUse(TyType.fromHintText(input.actual), context).getType();
			final result = TyStructuralArgument.compatibility(index, expected, actual);
			if (result != (input.accepted ? Compatible : Incompatible))
				throw "recursive compatibility differs for " + input.name;
			Sys.println("RECURSIVE_STRUCTURAL_CASE:PASS " + input.name);
		}
		Sys.println("RECURSIVE_STRUCTURAL_COMPATIBILITY:PASS");
	}
}
