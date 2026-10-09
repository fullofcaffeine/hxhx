import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Recursive storage is valid; alias-only cycles still fail before any target can observe them. */
class M14RecursiveTypedefTest {
	static function main():Void {
		final args = Stage1Args.parse(["-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final cases = [
			{name: "record", accepted: true, source: "typedef Branch = {name:String, ?children:Array<Branch>};"},
			{name: "array", accepted: true, source: "typedef Branch = Array<Branch>;"},
			{name: "function", accepted: true, source: "typedef Branch = Int -> Branch;"},
			{name: "mutual record", accepted: true, source: "typedef Branch = {next:Other}; typedef Other = {next:Branch};"},
			{name: "generic record", accepted: true, source: "typedef Tree<T> = {value:T, ?children:Array<Tree<T>>}; typedef Branch = Tree<Int>;"},
			{name: "array alias", accepted: true, source: "typedef Box<T> = Array<T>; typedef Branch = Box<Branch>;"},
			{name: "unused argument", accepted: true, source: "typedef Drop<T> = Int; typedef Branch = Drop<Branch>;"},
			{name: "growing argument", accepted: true, source: "typedef Tree<T> = {value:T, next:Tree<Array<T>>}; typedef Branch = Tree<Int>;"},
			{name: "defaulted record", accepted: true, source: "typedef Tree<T=Int> = {value:T, ?next:Tree}; typedef Branch = Tree;"},
			{name: "unused recursive default", accepted: true, source: "typedef Tree<T=Tree> = Int; typedef Branch = Tree;"},
			{name: "direct cycle", accepted: false, source: "typedef Branch = Branch;"},
			{name: "mutual alias cycle", accepted: false, source: "typedef Branch = Other; typedef Other = Branch;"},
			{name: "identity argument cycle", accepted: false, source: "typedef Id<T> = T; typedef Branch = Id<Branch>;"}
		];
		for (input in cases) {
			final source = input.source + "\nclass Main { static var root:Branch; static function main():Void {} }";
			var failure:Null<String> = null;
			try {
				final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
				final index = TyperIndex.buildHeaders([module]);
				// Recursive Array fields need the real standard-library declaration.
				// Header publication must use the same dependency loader as compilation.
				final loader = new ModuleLoader(paths, defines, index, null, false);
				loader.markResolvedAlready([module]);
				if (input.source.indexOf("Array<") >= 0) {
					final provider = index.getRegisteredModule("Array");
					if (provider == null || !sys.FileSystem.exists(provider.filePath))
						throw "recursive fixture did not load the real Array declaration";
				}
			} catch (error:TyperError) {
				failure = error.toString();
			}
			if (input.accepted && failure != null)
				throw input.name + " must resolve: " + failure;
			if (!input.accepted && (failure == null || failure.indexOf("Recursive typedef is not allowed") < 0))
				throw input.name + " must reject its alias-only cycle";
			Sys.println("RECURSIVE_TYPEDEF_CASE:PASS " + input.name);
		}
		Sys.println("RECURSIVE_TYPEDEF:PASS");
	}
}
