import haxe.ds.StringMap;
import hxhx.Stage1Compiler.Stage1Args;
import sys.FileSystem;
import sys.io.File;
import TyTypeDeclaration.TyTypeResolutionContext;

/** Root-qualified source types retain their declaration when local names or imports collide. */
class M14RootQualifiedTypeResolutionTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function context(module:ResolvedModule):TyTypeResolutionContext {
		return {
			packagePath: HxModuleDecl.getPackagePath(module.parsed.getDecl()),
			modulePath: module.modulePath,
			directives: HxModuleDecl.getDirectives(module.parsed.getDecl()),
			filePath: module.filePath,
			position: HxPos.unknown(),
			parameters: []
		};
	}

	static function source(root:String, name:String, body:String):ResolvedModule {
		final path = root + "/" + name.split(".").join("/") + ".hx";
		FileSystem.createDirectory(haxe.io.Path.directory(path));
		File.saveContent(path, body);
		return new ResolvedModule(name, path, ParserStage.parse(body, path));
	}

	/** Compare ordinary scope selection with explicit root selection, with both cold and loaded headers. */
	static function lookup():Void {
		for (scope in ["local", "import", "package"])
			for (eager in [false, true]) {
				final root = ".tmp/root_qualified_" + scope + "_" + eager;
				final modules = [
					source(root, "Top", "class Top { public function new() {} }"),
					source(root, "Box", "class Box<T> { public function new() {} }"),
					source(root, "Alias", "typedef Alias<T> = Box<T>;"),
					source(root, "Bundle", "class Bundle {} class Secondary {} private class Hidden {}"),
					source(root, "pkg.Top", "package pkg; class Top { public function new() {} }"),
					source(root, "pkg.OnlyPackage", "package pkg; class OnlyPackage {}")
				];
				final prefix = scope == "local" ? "package nested; class Top {} " : scope == "import" ? "package nested; import pkg.Top; " : "package pkg; ";
				final main = source(root, scope == "package" ? "pkg.Main" : "nested.Main",
					prefix + "class Main {static function main() {var selected:std.Top = new std.Top(); var ordinary:Top=null; Sys.println(7);}}");
				M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", main.modulePath], expected: "7\n"});
				final index = TyperIndex.buildHeaders(eager ? modules.concat([main]) : [main]);
				final standardRoot = Stage1Args.getStandardLibraryRoot(Stage1Args.parse([], true));
				final loader = new ModuleLoader([root, standardRoot], new StringMap<String>(), index);
				loader.markResolvedAlready(eager ? modules.concat([main]) : [main]);
				final ctx = context(main);
				final selected = loader.ensureDeclarationAvailable("std.Top", ctx);
				require(selected != null && selected.getCanonicalName() == "Top", "root lookup failed: " + scope + " eager=" + eager);
				final ordinary = loader.ensureDeclarationAvailable("Top", ctx);
				final expected = scope == "local" ? "nested.Main.Top" : "pkg.Top";
				require(ordinary != null && ordinary.getCanonicalName() == expected, "root lookup changed ordinary scope");
				for (path in [
					"std.Bundle.Secondary",
					"std.pkg.Top",
					"std.Alias",
					"std.String",
					"std.StdTypes.Int",
					"std.StdTypes.Iterator"
				]) {
					final declaration = loader.ensureDeclarationAvailable(path, ctx);
					require(declaration != null
						&& declaration.getCanonicalName() == path.substr(4), "wrong qualified declaration: " + path);
				}
				final alias = index.resolveTypeUse(TyType.fromHintText("std.Alias<Int>"), ctx).getType();
				require(alias.getNominalIdentity() != null
					&& alias.getNominalIdentity().getCanonicalName() == "Box"
					&& alias.getTypeArguments()[0].getSemanticKey() == "primitive:Int",
					"qualified alias lost its argument or defining scope");
				for (path in [
					"std.Bundle.Hidden",
					"std.Missing",
					"std.OnlyPackage",
					"std.std.Top",
					"std.Secondary",
					"std.Int",
					"std.Void",
					"std.Iterator"
				])
					require(loader.ensureDeclarationAvailable(path, ctx) == null && index.resolveTypeDeclaration(path, ctx) == null,
						"root lookup escaped its exact path: " + path);
				final nominal = index.resolveTypePath("std.Top", ctx.packagePath, ctx.directives, null, ctx.modulePath);
				require(nominal != null && nominal.getFullName() == "Top", "nominal lookup differs from declaration lookup");
				TyperStage.typeResolvedModule(main, index, loader, true);
			}
		Sys.println("ROOT_QUALIFIED_LOOKUP:PASS");
	}

	/** A missing-type callback receives the exact root path, never lexical or import candidates. */
	static function missingType():Void {
		final root = ".tmp/root_qualified_missing_callback";
		final main = source(root, "nested.Main", "package nested; import other.Placeholder; class Main {}");
		final index = TyperIndex.buildHeaders([main]);
		final seen = new Array<String>();
		final loader = new ModuleLoader([root], new StringMap<String>(), index, path -> {
			seen.push(path);
			return false;
		});
		loader.markResolvedAlready([main]);
		require(loader.ensureDeclarationAvailable("std.NotHere", context(main)) == null, "missing root unexpectedly resolved");
		require(seen.join(",") == "NotHere", "missing-type callback searched unrelated scopes: " + seen.join(","));
		Sys.println("ROOT_QUALIFIED_MISSING:PASS");
	}

	/** These invalid root paths must stay invalid even after other scopes and StdTypes are loaded. */
	static function upstreamRejections():Void {
		final root = ".tmp/root_qualified_rejections";
		source(root, "Bundle", "class Bundle {} private class Hidden {}");
		source(root, "Top", "class Top {}");
		source(root, "pkg.OnlyPackage", "package pkg; class OnlyPackage {}");
		for (path in [
			"std.Bundle.Hidden",
			"std.Missing",
			"std.OnlyPackage",
			"std.std.Top",
			"std.Secondary",
			"std.Int",
			"std.Void",
			"std.Iterator<Int>",
			"std.Renamed"
		]) {
			final main = source(root, "pkg.Main", "package pkg; import Top as Renamed; class Main {static function main() {var value:" + path + "=null;}}");
			final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
			final process = new sys.io.Process(timeout, ["30", "node_modules/.bin/haxe", "-cp", root, "--run", "pkg.Main"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			require(code == 1
				&& stdout == ""
				&& (stderr.indexOf("Type not found") >= 0 || stderr.indexOf("Cannot access private type") >= 0),
				"upstream root-path rejection changed: "
				+ path
				+ " "
				+ stderr);
			final index = TyperIndex.buildHeaders([main]);
			final standardRoot = Stage1Args.getStandardLibraryRoot(Stage1Args.parse([], true));
			final loader = new ModuleLoader([root, standardRoot], new StringMap<String>(), index);
			loader.markResolvedAlready([main]);
			final type = TyType.fromHintText(path);
			require(loader.ensureDeclarationAvailable(type.getUnresolvedPath(), context(main)) == null
				&& index.resolveTypeUse(type, context(main)).getType().isUnresolved(),
				"candidate accepted rejected root path: "
				+ path);
		}
		Sys.println("ROOT_QUALIFIED_UPSTREAM_REJECTIONS:PASS");
	}

	/** Qualified parameters and generic aliases must survive actual native compilation and execution. */
	static function runtime():Void {
		final root = ".tmp/root_qualified_runtime";
		final modules = [
			source(root, "Box", "class Box<T> {public var value:T; public function new(value:T) {this.value=value;}}"),
			source(root, "Alias", "typedef Alias<T> = Box<T>;")
		];
		final main = source(root, "Main",
			"class Main {static function read(value:std.Alias<Int>):Int return value.value; " +
			"static function main():Void {Sys.println(read(new std.Box<Int>(7)));}}");
		// The program contract puts the executable root before its dependencies.
		modules.unshift(main);
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: "7\n"});
		final index = TyperIndex.build(modules);
		final typed = [for (module in modules) TyperStage.typeResolvedModule(module, index)];
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(typed, false), root + "/out", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: "7\n"});
		Sys.println("ROOT_QUALIFIED_NATIVE:PASS");
	}

	static function main():Void {
		lookup();
		missingType();
		upstreamRejections();
		runtime();
	}
}
