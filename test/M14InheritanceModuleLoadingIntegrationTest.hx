import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that class headers participate in native demand-driven module loading.

	A class header is the `extends` / `implements` part before the class body. The
	test starts with only the requested root module in the type index, then checks
	that typing that root asks the ordinary module loader for every parent type.
	This keeps the fast path honest: it must discover required files without
	scanning the whole source directory first.
**/
class M14InheritanceModuleLoadingIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function ensureDirectory(path:String):Void {
		if (!FileSystem.exists(path))
			FileSystem.createDirectory(path);
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function saveSource(root:String, modulePath:String, source:String):String {
		final parts = modulePath.split(".");
		final fileName = parts.pop() + ".hx";
		var directory = root;
		for (part in parts) {
			directory = Path.join([directory, part]);
			ensureDirectory(directory);
		}
		final filePath = Path.join([directory, fileName]);
		File.saveContent(filePath, source);
		return filePath;
	}

	static function typeFromRoot(root:String, rootModulePath:String, ?prepareModule:ResolvedModule->ResolvedModule):{
		modules:Array<TypedModule>,
		index:TyperIndex,
		prepared:Array<String>
	} {
		final rootFile = Path.join([root, rootModulePath.split(".").join("/") + ".hx"]);
		final rootResolved = new ResolvedModule(rootModulePath, rootFile, ParserStage.parse(File.getContent(rootFile), rootFile));
		final index = TyperIndex.build([rootResolved]);
		programIndexProbe = index;
		final prepared = new Array<String>();
		final loader = new ModuleLoader([root], new StringMap<String>(), index, function(_):Bool return false, false, null, function(module) {
			final modulePath = ResolvedModule.getModulePath(module);
			prepared.push(modulePath);
			return prepareModule == null ? module : prepareModule(module);
		});
		loader.markResolvedAlready([rootResolved]);

		final toType = [rootResolved];
		final typed = new Array<TypedModule>();
		var cursor = 0;
		while (cursor < toType.length) {
			typed.push(TyperStage.typeResolvedModule(toType[cursor++], index, loader, true));
			for (loaded in loader.drainNewModules())
				toType.push(loaded);
		}
		programIndexProbe = null;
		return {modules: typed, index: index, prepared: prepared};
	}

	static function modulePaths(modules:Array<TypedModule>):Array<String> {
		final out = [for (module in modules) CompilerTypedModuleRevision.semanticModulePath(module)];
		out.sort(compareText);
		return out;
	}

	static function assertModuleSet(program:{modules:Array<TypedModule>, index:TyperIndex, prepared:Array<String>}, expected:Array<String>, label:String):Void {
		final actual = modulePaths(program.modules);
		expected.sort(compareText);
		assertTrue(actual.join(",") == expected.join(","), label + ": expected " + expected.join(",") + ", got " + actual.join(","));
	}

	static function hasEdge(snapshot:CompilerDependencySnapshot, consumer:String, provider:String, factPrefix:String):Bool {
		for (edge in snapshot.getEdges())
			if (edge.consumerModule == consumer
				&& edge.providerModule == provider
				&& StringTools.startsWith(edge.factIdentity, factPrefix))
				return true;
		return false;
	}

	static function resolvedExtends(program:{modules:Array<TypedModule>, index:TyperIndex, prepared:Array<String>}, modulePath:String):Null<TyType> {
		for (module in program.modules)
			if (CompilerTypedModuleRevision.semanticModulePath(module) == modulePath)
				for (typedClass in module.getTypedClasses())
					if (HxClassDecl.getName(typedClass.getSourceDeclaration()) == "Main")
						return typedClass.getResolvedExtends();
		return null;
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);

	static function main():Void {
		final root = Path.normalize(".tmp/m14_inheritance_module_loading_" + Std.string(Date.now().getTime()));
		deleteRecursive(root);
		ensureDirectory(root);

		var thrown:Dynamic = null;
		try {
			saveSource(root, "Unrelated", "this source is deliberately not a valid Haxe module");
			saveSource(root, "Base", "class Base {}");
			saveSource(root, "Middle", "class Middle extends Base {}");
			saveSource(root, "IContract", "interface IContract {}");
			saveSource(root, "Main", "class Main extends Middle implements IContract { public static function main():Void {} }");

			var baseWasVisibleDuringPreparation = true;
			final program = typeFromRoot(root, "Main", function(module) {
				if (ResolvedModule.getModulePath(module) == "Base")
					baseWasVisibleDuringPreparation = programIndexProbe == null ? false : programIndexProbe.getByFullName("Base") != null;
				return module;
			});
			final paths = modulePaths(program.modules);
			assertTrue(paths.join(",") == "Base,IContract,Main,Middle", "typing Main should load and type its complete parent chain: " + paths.join(","));
			assertTrue(program.prepared.join(",") == "Middle,IContract,Base",
				"each lazily discovered parent module should run request-owned preparation exactly once in discovery order");
			assertTrue(program.prepared.indexOf("Unrelated") == -1,
				"inheritance loading should not inspect an unrelated source file merely because it shares the class path");
			assertTrue(!baseWasVisibleDuringPreparation, "a lazy base must be prepared before its declarations become visible to typing");

			final snapshot = CompilerDependencyCollector.collect(program.modules, program.index);
			assertTrue(hasEdge(snapshot, "Main", "Middle", "extends:"), "Main should record its selected base-class dependency");
			assertTrue(hasEdge(snapshot, "Main", "IContract", "implements:"), "Main should record its selected interface dependency");
			assertTrue(hasEdge(snapshot, "Middle", "Base", "extends:"), "multi-level inheritance should record the transitive class edge");

			saveSource(root, "same.Base", "package same; class Base {}");
			saveSource(root, "same.Main", "package same; class Main extends Base { public static function main():Void {} }");
			assertModuleSet(typeFromRoot(root, "same.Main"), ["same.Base", "same.Main"], "an unqualified base should resolve from the current package");

			saveSource(root, "model.ImportedBase", "package model; class ImportedBase {}");
			saveSource(root, "imported.Main",
				"package imported; import model.ImportedBase; class Main extends ImportedBase { public static function main():Void {} }");
			assertModuleSet(typeFromRoot(root, "imported.Main"), ["imported.Main", "model.ImportedBase"],
				"an imported base should resolve through its selected module");

			saveSource(root, "model.QualifiedBase", "package model; class QualifiedBase {}");
			saveSource(root, "qualified.Main", "package qualified; class Main extends model.QualifiedBase { public static function main():Void {} }");
			assertModuleSet(typeFromRoot(root, "qualified.Main"), ["model.QualifiedBase", "qualified.Main"],
				"a fully qualified base should resolve without an import");

			saveSource(root, "model.AliasedBase", "package model; class AliasedBase {}");
			saveSource(root, "aliased.Main",
				"package aliased; import model.AliasedBase as Parent; class Main extends Parent { public static function main():Void {} }");
			final aliasedProgram = typeFromRoot(root, "aliased.Main");
			assertModuleSet(aliasedProgram, ["aliased.Main", "model.AliasedBase"],
				"an aliased base should resolve through the local name declared by the import");
			final aliasedMain = aliasedProgram.modules.filter(module -> CompilerTypedModuleRevision.semanticModulePath(module) == "aliased.Main")[0];
			final aliasDirectives = HxModuleDecl.getDirectives(aliasedMain.getParsed().getDecl());
			final aliasHit = aliasedProgram.index.resolveTypePath("Parent", "aliased", aliasDirectives);
			assertTrue(aliasHit != null && aliasHit.getIdentity().getCanonicalName() == "model.AliasedBase",
				"the alias should resolve to the imported type after its module is loaded");
			assertTrue(aliasedProgram.index.resolveTypePath("AliasedBase", "aliased", aliasDirectives) == null,
				"an alias import must not also expose the provider's original short name through the global fallback");

			saveSource(root, "secondary.Holder", "package secondary; class Holder {} class NestedBase {}");
			saveSource(root, "secondary.Main", "package secondary; class Main extends secondary.Holder.NestedBase { public static function main():Void {} }");
			assertModuleSet(typeFromRoot(root, "secondary.Main"), ["secondary.Holder", "secondary.Main"],
				"a secondary type should load the Haxe module file that declares it");
			saveSource(root, "secondaryAlias.Main",
				"package secondaryAlias; import secondary.Holder.NestedBase as Parent; class Main extends Parent { public static function main():Void {} }");
			assertModuleSet(typeFromRoot(root, "secondaryAlias.Main"), ["secondary.Holder", "secondaryAlias.Main"],
				"an alias for a secondary type should load the owner module and resolve the declared local name");

			saveSource(root, "wildcard.Thing", "package wildcard; class Thing {}");
			saveSource(root, "wildcardUse.Main", "package wildcardUse; import wildcard.*; class Main extends Thing { public static function main():Void {} }");
			assertModuleSet(typeFromRoot(root, "wildcardUse.Main"), ["wildcard.Thing", "wildcardUse.Main"],
				"a package wildcard should demand-load the referenced type instead of depending on unrelated prior indexing");

			saveSource(root, "wildcard.Holder", [
				"package wildcard;",
				"class Holder {",
				"  public static var VALUE:Int = 1;",
				"  public static function twice(value:Int):Int return value * 2;",
				"}",
				"class NestedBase {}"
			].join("\n"));
			saveSource(root, "wildcardModuleUse.Main", [
				"package wildcardModuleUse;",
				"import wildcard.Holder.*;",
				"class Main extends NestedBase {",
				"  public static function main():Void { var value = twice(VALUE); }",
				"}"
			].join("\n"));
			final staticWildcardProgram = typeFromRoot(root, "wildcardModuleUse.Main");
			assertModuleSet(staticWildcardProgram, ["wildcard.Holder", "wildcardModuleUse.Main"],
				"a type wildcard should load the owner module for its static members");
			final invalidWildcardParent = resolvedExtends(staticWildcardProgram, "wildcardModuleUse.Main");
			assertTrue(invalidWildcardParent != null && invalidWildcardParent.isUnresolved(),
				"a type wildcard must not make a secondary type from the same module visible");

			saveSource(root, "normalModuleUse.Main",
				"package normalModuleUse; import wildcard.Holder; class Main extends NestedBase { public static function main():Void {} }");
			final normalModuleProgram = typeFromRoot(root, "normalModuleUse.Main");
			assertModuleSet(normalModuleProgram, ["normalModuleUse.Main", "wildcard.Holder"],
				"a plain module import should load the owner module for a selected secondary type");
			final normalModuleParent = resolvedExtends(normalModuleProgram, "normalModuleUse.Main");
			assertTrue(normalModuleParent != null
				&& normalModuleParent.getNominalIdentity() != null
				&& normalModuleParent.getNominalIdentity().getCanonicalName() == "wildcard.Holder.NestedBase",
				"a plain module import should expose the module's secondary type");

			saveSource(root, "resolver.Api", [
				"package resolver;",
				"class Api {",
				"  public static var PI:Int = 3;",
				"  public static function twice(value:Int):Int return value * 2;",
				"}"
			].join("\n"));
			saveSource(root, "resolverUse.Main", [
				"package resolverUse;",
				"import resolver.Api.PI;",
				"import resolver.Api.twice;",
				"class Main { public static function main():Void { var value = twice(PI); } }"
			].join("\n"));
			final resolverModules = ResolverStage.parseProject([root], "resolverUse.Main");
			final resolverPaths = [for (module in resolverModules) ResolvedModule.getModulePath(module)];
			resolverPaths.sort(compareText);
			assertTrue(resolverPaths.join(",") == "resolver.Api,resolverUse.Main",
				"two exact static-member imports should load one canonical provider module, not two member-shaped copies: " + resolverPaths.join(","));

			saveSource(root, "generic.Payload", "package generic; class Payload {}");
			saveSource(root, "generic.GenericBase", "package generic; class GenericBase<T> {}");
			saveSource(root, "generic.Main", "package generic; class Main extends GenericBase<Payload> { public static function main():Void {} }");
			assertModuleSet(typeFromRoot(root, "generic.Main"), ["generic.GenericBase", "generic.Main", "generic.Payload"],
				"generic parent headers should load both the parent and its type arguments");

			saveSource(root, "cycle.A", "package cycle; class A extends B { public static function main():Void {} }");
			saveSource(root, "cycle.B", "package cycle; class B extends A {}");
			assertModuleSet(typeFromRoot(root, "cycle.A"), ["cycle.A", "cycle.B"], "cyclic headers should terminate without duplicate module loading");
		} catch (e:Dynamic) {
			thrown = e;
		}

		if (thrown == null)
			deleteRecursive(root)
		else {
			Sys.println("debug_out=" + root);
			throw thrown;
		}
		Sys.println("m14_inheritance_module_loading_ok");
	}

	static var programIndexProbe:Null<TyperIndex>;
}
