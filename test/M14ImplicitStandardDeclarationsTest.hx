import hxhx.Stage1Compiler.Stage1Args;
import sys.FileSystem;
import sys.io.File;
import TyTypeDeclaration.TyTypeResolutionContext;

/** Implicit standard aliases retain upstream scope precedence regardless of earlier header loads. */
class M14ImplicitStandardDeclarationsTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function context(module:String, directives:Array<HxModuleDirective>):TyTypeResolutionContext {
		return {
			packagePath: module == "nested.Main" ? "nested" : "",
			modulePath: module,
			directives: directives,
			filePath: "Main.hx",
			position: HxPos.unknown(),
			parameters: []
		};
	}

	/** Each test gets a fresh request; declarations loaded in one request cannot satisfy another. */
	static function request(root:String, source:String, module:String = "Main"):{index:TyperIndex, loader:ModuleLoader, module:ResolvedModule} {
		FileSystem.createDirectory(root);
		final path = root + "/" + StringTools.replace(module, ".", "/") + ".hx";
		final resolved = new ResolvedModule(module, path, ParserStage.parse(source, path));
		final index = TyperIndex.buildHeaders([resolved]);
		final standardRoot = Stage1Args.getStandardLibraryRoot(Stage1Args.parse([], true));
		final loader = new ModuleLoader([root, standardRoot], HxDefineMap.fromRawDefines(["js", "sys"]), index, null, false);
		loader.markResolvedAlready([resolved]);
		return {index: index, loader: loader, module: resolved};
	}

	/** Upstream checks the original inferred-array contract and rejects an incompatible item type. */
	static function inferredReturn():Void {
		for (valid in [true, false]) {
			final root = ".tmp/implicit_standard_return_" + (valid ? "valid" : "invalid");
			final source = "class Main { static function copy<T>(value:T):Iterator<"
				+ (valid ? "T" : "String")
				+ "> { var values=[]; values.push(value); return values.iterator(); } static function main():Void {} }";
			final input = request(root, source);
			File.saveContent(root + "/Main.hx", source);
			final oracle = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = oracle.stdout.readAll().toString();
			final stderr = oracle.stderr.readAll().toString();
			final code = oracle.exitCode();
			oracle.close();
			require((code == 0) == valid && stdout == "", "upstream iterator return changed: " + stderr);
			var accepted = true;
			try {
				TyperStage.typeResolvedModule(input.module, input.index, input.loader, true);
			} catch (error:TyperError) {
				accepted = false;
			}
			require(accepted == valid, "implicit iterator return acceptance differs: " + valid);
			final declared = input.index.getByFullName("Main").staticMethod("copy").getReturnType();
			require(!declared.isUnresolved()
				&& TyAliasExpansion.reveal(declared).isAnonymous(), "return retained an unresolved standard alias");
		}
		Sys.println("IMPLICIT_STANDARD_RETURN:PASS");
	}

	/** Warming StdTypes first must not hide a file which has not yet entered the index. */
	static function shadowing():Void {
		for (kind in ["local", "import", "package"])
			for (warm in [false, true]) {
				final root = ".tmp/implicit_standard_scope_" + kind + "_" + warm;
				final prefix = kind == "local" ? "package nested; typedef Iterator<T> = {value:T}; " : kind == "import" ? "import custom.Reader as Iterator; " : "package nested; ";
				final source = prefix
					+ "class Main {static function main():Void {var selected:Iterator<Int> = "
					+ (kind == "package" ? "[7].iterator()" : "{value:7}")
					+ ";}}";
				final input = request(root, source, kind == "import" ? "Main" : "nested.Main");
				final lookup = context(input.module.modulePath, HxModuleDecl.getDirectives(input.module.parsed.getDecl()));
				final relative = kind == "import" ? "custom/Reader.hx" : kind == "package" ? "nested/Iterator.hx" : "Iterator.hx";
				if (kind != "local") {
					FileSystem.createDirectory(haxe.io.Path.directory(root + "/" + relative));
					File.saveContent(root
						+ "/"
						+ relative,
						(kind == "import" ? "package custom; typedef Reader<T>" : kind == "package" ? "package nested; typedef Iterator<T>" : "typedef Iterator<T>")
						+ " = {value:T};");
				}
				final mainPath = root + "/" + (kind == "import" ? "" : "nested/") + "Main.hx";
				FileSystem.createDirectory(haxe.io.Path.directory(mainPath));
				File.saveContent(mainPath, source);
				final oracle = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", input.module.modulePath, "--interp"]);
				final stdout = oracle.stdout.readAll().toString();
				final stderr = oracle.stderr.readAll().toString();
				final code = oracle.exitCode();
				oracle.close();
				require(code == 0 && stdout == "", "upstream shadowing differs for " + kind + ": " + stderr);
				if (warm)
					require(input.loader.ensureDeclarationAvailable("Iterable", lookup) != null, "standard warmup did not load its alias");
				TyperStage.typeResolvedModule(input.module, input.index, input.loader, true);
				final selected = input.loader.ensureDeclarationAvailable("Iterator", lookup);
				final expected = kind == "local" ? "nested.Main.Iterator" : kind == "import" ? "custom.Reader" : "StdTypes.Iterator";
				require(selected != null && selected.getCanonicalName() == expected, "standard alias hid " + expected + " warm=" + warm);
				require(input.loader.ensureDeclarationAvailable("MissingStandardType", lookup) == null, "missing declaration became a successful fallback");
			}
		Sys.println("IMPLICIT_STANDARD_SHADOWING:PASS");
	}

	static function main():Void {
		inferredReturn();
		shadowing();
	}
}
