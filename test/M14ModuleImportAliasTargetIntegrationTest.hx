import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves builtin targets consume the type selected by Haxe alias resolution.

	The source calls a constructor, static field, and static method through the
	local name `Service`. Shared typing resolves that name to `model.Api`; generated
	target code must therefore reference the real provider rather than inventing a
	class named `Service` or reimplementing Haxe import lookup per target.
**/
class M14ModuleImportAliasTargetIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
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

	static function commandExists(name:String):Bool
		return Sys.command("sh", ["-c", "command -v " + name + " >/dev/null 2>&1"]) == 0;

	static function commandOutput(command:String, args:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, args);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function programFromSources(sources:Array<{path:String, module:String, source:String}>):backend.GenIrProgram {
		final resolved = [
			for (entry in sources)
				new ResolvedModule(entry.module, entry.path, ParserStage.parse(entry.source, entry.path))
		];
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready(resolved);
		return MacroStage.expandProgram([
			for (module in resolved)
				TyperStage.typeResolvedModule(module, index, loader, true)
		], []);
	}

	static function program():backend.GenIrProgram {
		final baseSource = [
			"package model;",
			"class Base {",
			"  public function new() {}",
			"  public function inherited():String return \"base\";",
			"}"
		].join("\n");
		final apiSource = [
			"package model;",
			"class Api {",
			"  public static var label:String = \"service\";",
			"  public static var PI:Int = 3;",
			"  public var value:Int;",
			"  public function new(value:Int) { this.value = value; }",
			"  public static function twice(value:Int):Int return value * 2;",
			"}"
		].join("\n");
		final contractSource = [
			"package model;",
			"interface Contract {",
			"  public function role():String;",
			"}"
		].join("\n");
		final extensionsSource = [
			"package model;",
			"class Extensions {",
			"  public static function marked(value:String):String return value;",
			"}",
			"class MoreExtensions {",
			"  public static function alsoMarked(value:String):String return value;",
			"}"
		].join("\n");
		final mainSource = [
			"import model.Api as Service;",
			"import model.Base as Parent;",
			"import model.Contract as Role;",
			"import model.Api.PI;",
			"import model.Api.twice as double;",
			"using model.Extensions;",
			"class Main extends Parent implements Role {",
			"  public static var current:Service;",
			"  public function role():String return \"role\";",
			"  public static function main():Void {",
			"    var services:Array<Service> = [new Service(4)];",
			"    var main = new Main();",
			"    Sys.println(\"alias-target:\" + main.inherited() + \":\" + main.role() + \":\" + Service.label + \":\" + Std.string(PI) + \":\" + Std.string(double(services[0].value)));",
			"  }",
			"}"
		].join("\n");
		final resolved = [
			new ResolvedModule("model.Base", "model/Base.hx", ParserStage.parse(baseSource, "model/Base.hx")),
			new ResolvedModule("model.Api", "model/Api.hx", ParserStage.parse(apiSource, "model/Api.hx")),
			new ResolvedModule("model.Contract", "model/Contract.hx", ParserStage.parse(contractSource, "model/Contract.hx")),
			new ResolvedModule("model.Extensions", "model/Extensions.hx", ParserStage.parse(extensionsSource, "model/Extensions.hx")),
			new ResolvedModule("Main", "Main.hx", ParserStage.parse(mainSource, "Main.hx"))
		];
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready(resolved);
		final typed = [
			for (module in resolved)
				TyperStage.typeResolvedModule(module, index, loader, true)
		];
		return MacroStage.expandProgram(typed, []);
	}

	/**
		Build a toolchain-check fixture that isolates import aliases from target
		features such as inherited method dispatch and Haxe-array indexing.
	**/
	static function compiledAliasProgram():backend.GenIrProgram {
		return programFromSources([
			{
				path: "model/Api.hx",
				module: "model.Api",
				source: [
					"package model;",
					"class Api {",
					"  public static var label:String = \"service\";",
					"  public static var PI:Int = 3;",
					"  public static function twice(value:Int):Int return value * 2;",
					"}"
				].join("\n")
			},
			{
				path: "Main.hx",
				module: "Main",
				source: [
					"import model.Api as Service;",
					"import model.Api.PI;",
					"import model.Api.twice as double;",
					"class Main {",
					"  public static function main():Void {",
					"    Sys.println(\"alias-target:\" + Service.label + \":\" + Std.string(PI) + \":\" + Std.string(double(4)));",
					"  }",
					"}"
				].join("\n")
			}
		]);
	}

	/** Build the smallest program that proves generated Java follows Haxe's later-import-wins rule. **/
	static function javaCollisionProgram():backend.GenIrProgram {
		return programFromSources([
			{path: "a/Tools.hx", module: "a.Tools", source: "package a; class Tools {}"},
			{path: "b/Tools.hx", module: "b.Tools", source: "package b; class Tools {}"},
			{path: "values/Provider.hx", module: "values.Provider", source: "package values; class Provider { public static function make():Int return 1; }"},
			{
				path: "Main.hx",
				module: "Main",
				source: "import a.Tools; import b.Tools; import values.Provider.make as Tools; class Main { static var selected:Tools; static function main():Void { Tools(); } }"
			}
		]);
	}

	static function assertJavaCollisionOutput(root:String):Void {
		final outputRoot = Path.join([root, "java-collision"]);
		final result = BackendRegistry.requireForTarget("java-native")
			.emit(javaCollisionProgram(), new BackendContext(outputRoot, null, "Main", true, false, new StringMap<String>()));
		final content = File.getContent(result.entryPath);
		assertTrue(content.indexOf("import b.Tools;") >= 0, "Java did not import the later Haxe type binding");
		assertTrue(content.indexOf("import a.Tools;") < 0, "Java emitted the shadowed earlier Haxe type import");
		assertTrue(content.indexOf("import static values.Provider.make;") >= 0,
			"Java dropped a static-value import whose Haxe local name also names a type import");
	}

	static function wildcardProgram():backend.GenIrProgram {
		return programFromSources([
			{
				path: "values/Provider.hx",
				module: "values.Provider",
				source: [
					"package values;",
					"class Provider {",
					"  public static function visible():Int return 1;",
					"  @:noImportGlobal public static function hidden():Int return 2;",
					"}"
				].join("\n")
			},
			{
				path: "Main.hx",
				module: "Main",
				source: "import values.Provider.*; class Main { static function main():Void { visible(); values.Provider.hidden(); } }"
			}
		]);
	}

	static function assertWildcardTargetOutput(root:String):Void {
		final typedProgram = wildcardProgram();
		final javaRoot = Path.join([root, "java-wildcard"]);
		final javaResult = BackendRegistry.requireForTarget("java-native")
			.emit(typedProgram, new BackendContext(javaRoot, null, "Main", true, false, new StringMap<String>()));
		final java = File.getContent(javaResult.entryPath);
		assertTrue(java.indexOf("import static values.Provider.visible;") >= 0, "Java did not emit the eligible wildcard static member");
		assertTrue(java.indexOf("import static values.Provider.hidden;") < 0 && java.indexOf("import static values.Provider.*;") < 0,
			"Java re-exposed a @:noImportGlobal member through wildcard target syntax");

		final ocamlRoot = Path.join([root, "ocaml-wildcard"]);
		EmitterStage.emitToDir(typedProgram, ocamlRoot, true, false);
		final ocamlMain = File.getContent(Path.join([ocamlRoot, "Main.ml"]));
		assertTrue(ocamlMain.indexOf("Values_Provider.visible") >= 0, "OCaml did not qualify the eligible wildcard static member");
		assertTrue(ocamlMain.indexOf("Values_Provider.hidden") >= 0, "OCaml did not preserve the explicitly qualified @:noImportGlobal member access");
	}

	static function phpUsingOrderProgram():backend.GenIrProgram {
		return programFromSources([
			{
				path: "Main.hx",
				module: "Main",
				source: [
					"using Main;",
					"class ZFirst { public static function choose(value:String):String return \"first\"; }",
					"class ASecond { public static function choose(value:String):String return \"second\"; }",
					"class Main { static function main():Void { Sys.println(\"x\".choose()); } }"
				].join("\n")
			}
		]);
	}

	static function assertPhpUsingOrder(root:String):Void {
		final outputRoot = Path.join([root, "php-using-order"]);
		final result = BackendRegistry.requireForTarget("php-native")
			.emit(phpUsingOrderProgram(), new BackendContext(outputRoot, null, "Main", true, false, new StringMap<String>()));
		if (!commandExists("php"))
			return;
		final runtime = commandOutput("php", [result.entryPath]);
		assertTrue(runtime.code == 0, "PHP using-order program failed: " + runtime.stderr);
		assertTrue(StringTools.trim(runtime.stdout) == "second",
			"PHP did not match Haxe 4.3.7's later-module-type precedence while selecting an extension method: " + runtime.stdout);
	}

	static function emit(targetId:String, root:String):String {
		final outputRoot = Path.join([root, targetId]);
		final result = BackendRegistry.requireForTarget(targetId)
			.emit(program(), new BackendContext(outputRoot, null, "Main", true, false, new StringMap<String>()));
		assertTrue(FileSystem.exists(result.entryPath), targetId + " did not produce its entry source file");
		final content = File.getContent(result.entryPath);
		assertTrue(content.indexOf("Service") < 0, targetId + " leaked the Haxe-only alias instead of consuming the resolved model.Api identity");
		assertTrue(content.indexOf("Role") < 0, targetId + " leaked the Haxe-only interface alias instead of consuming the resolved model.Contract identity");
		if (targetId == "php-native")
			assertTrue(content.indexOf("class Main extends Base") >= 0, "PHP did not render Main with the resolved Base parent")
		else
			assertTrue(content.indexOf("Parent") < 0, targetId + " leaked the Haxe-only parent alias instead of consuming the resolved model.Base identity");
		assertTrue(content.indexOf("Api") >= 0, targetId + " output did not reference the selected Api provider");
		if (targetId != "cs-native")
			assertTrue(content.indexOf("Base") >= 0, targetId + " output did not reference the selected Base parent");
		if (targetId == "java-native") {
			assertTrue(content.indexOf("import model.Api.PI;") < 0,
				"Java guessed that uppercase PI was a type instead of using the resolved static-field fact");
			assertTrue(content.indexOf("import static model.Api.PI;") >= 0,
				"Java did not translate the resolved Haxe static-field import to Java static-import syntax");
			assertTrue(content.indexOf("import static model.Api.twice;") >= 0,
				"Java did not translate the aliased Haxe static-method import to Java static-import syntax");
			assertTrue(content.indexOf("import model.Extensions;") < 0,
				"Java treated a Haxe using directive as an ordinary import instead of leaving extension lowering to shared typing");
		}
		if (targetId == "cs-native") {
			assertTrue(content.indexOf("using model.Api.PI;") < 0, "C# emitted a field path as a namespace import");
			assertTrue(content.indexOf("using model.Extensions;") < 0, "C# treated a Haxe using directive as an ordinary namespace import");
		}
		return result.entryPath;
	}

	static function assertResolvedClassHeader():Void {
		for (module in program().getTypedModules())
			for (cls in HxModuleDecl.getClasses(module.getBackendDeclaration()))
				if (HxClassDecl.getName(cls) == "Main") {
					assertTrue(HxClassDecl.getExtendsPath(cls) == "model.Base",
						"target-neutral projection kept the source-only Parent alias instead of the resolved model.Base parent");
					assertTrue(HxClassDecl.getImplementsPaths(cls).join(",") == "model.Contract",
						"target-neutral projection kept the source-only Role alias instead of the resolved model.Contract interface");
					return;
				}
		throw "target-neutral projection did not contain Main";
	}

	/** Prove shared typing, rather than a target spelling rule, classifies every directive. **/
	static function assertResolvedDirectives():Void {
		for (module in program().getTypedModules()) {
			final semanticPath = CompilerTypedModuleRevision.semanticModulePath(module);
			if (semanticPath != "Main")
				continue;
			final actual = [
				for (directive in module.getEnv().getResolvedDirectives())
					directive.canonicalIdentity()
			];
			final expected = [
				"import-alias:model.Api:Service=>types:model.Api",
				"import-alias:model.Base:Parent=>types:model.Base",
				"import-alias:model.Contract:Role=>types:model.Contract",
				"import-normal:model.Api.PI=>static-member:model.Api:PI",
				"import-alias:model.Api.twice:double=>static-member:model.Api:twice",
				"using:model.Extensions=>using-types:model.Extensions,model.Extensions.MoreExtensions"
			];
			assertTrue(actual.join("\n") == expected.join("\n"), "shared typing produced the wrong resolved directive sequence: " + actual.join(", "));
			return;
		}
		throw "typed program did not contain the Main module's resolved directives";
	}

	/**
		Prove the visibility and collision rules that differ between type, static,
		and package imports. These are target-neutral Haxe rules, so testing the
		shared context prevents every emitter from inventing its own answer.
	**/
	static function assertImportVisibilityAndPrecedence():Void {
		final sources = [
			{
				path: "model/Api.hx",
				module: "model.Api",
				source: [
					"package model;",
					"class Api {",
					"  public static var PI:Int = 3;",
					"  @:noImportGlobal public static var hidden:Int = 4;",
					"  private static var privateValue:Int = 5;",
					"  public static function twice(value:Int):Int return value * 2;",
					"  @:noImportGlobal public static function hiddenMethod():Int return 4;",
					"  private static function privateMethod():Int return 5;",
					"}",
					"class NestedBase {}",
					"private class Hidden {}"
				].join("\n")
			},
			{
				path: "order/Extensions.hx",
				module: "order.Extensions",
				source: [
					"package order;",
					"class ZFirst { public static function choose(value:String):String return value; }",
					"private class HiddenMiddle { public static function choose(value:String):String return value; }",
					"class ASecond { public static function choose(value:String):String return value; }"
				].join("\n")
			},
			{path: "UsingOrderMain.hx", module: "UsingOrderMain", source: "using order.Extensions; class UsingOrderMain {}"},
			{path: "other/NestedBase.hx", module: "other.NestedBase", source: "package other; class NestedBase {}"},
			{
				path: "a/Tools.hx",
				module: "a.Tools",
				source: [
					"package a;",
					"class Tools {",
					"  public static var leftValue:Int = 1;",
					"  public static function leftMethod():Int return 1;",
					"}"
				].join("\n")
			},
			{
				path: "b/Tools.hx",
				module: "b.Tools",
				source: [
					"package b;",
					"class Tools {",
					"  public static var rightValue:Int = 2;",
					"  public static function rightMethod():Int return 2;",
					"}"
				].join("\n")
			},
			{path: "pack/Bundle.hx", module: "pack.Bundle", source: "package pack; class Helper {}"},
			{path: "rival/Helper.hx", module: "rival.Helper", source: "package rival; class Helper {}"},
			{
				path: "SignatureMain.hx",
				module: "SignatureMain",
				source: "import pack.Bundle; class SignatureMain { public var value:Helper; }"
			},
			{
				path: "PrivateSignatureMain.hx",
				module: "PrivateSignatureMain",
				source: "import model.Api; class PrivateSignatureMain { public var value:Hidden; }"
			},
			{
				path: "PrivateStaticImportMain.hx",
				module: "PrivateStaticImportMain",
				source: [
					"import model.Api.privateValue;",
					"import model.Api.privateMethod;",
					"class PrivateStaticImportMain {}"
				].join("\n")
			},
			{path: "Main.hx", module: "Main", source: "class Main {}"}
		];
		final resolved = [
			for (entry in sources)
				new ResolvedModule(entry.module, entry.path, ParserStage.parse(entry.source, entry.path))
		];
		final index = TyperIndex.build(resolved);
		final signatureOwner = index.getByFullName("SignatureMain");
		final signatureType = signatureOwner == null ? null : signatureOwner.fieldType("value");
		assertTrue(signatureType != null
			&& signatureType.getNominalIdentity() != null
			&& signatureType.getNominalIdentity().getCanonicalName() == "pack.Bundle.Helper",
			"a module with no same-named main type should still expose its declared type in a field signature");
		final privateSignatureOwner = index.getByFullName("PrivateSignatureMain");
		final privateSignatureType = privateSignatureOwner == null ? null : privateSignatureOwner.fieldType("value");
		assertTrue(privateSignatureType != null && privateSignatureType.getNominalIdentity() == null,
			"a private secondary type must not leak into another module's field signature");

		final ordinarySource = HxModuleDirective.normalImport("model.Api");
		final ordinary = new TyModuleDirective(ordinarySource, TypeImport, [for (provider in index.getByModulePath("model.Api")) provider.getIdentity()]);
		final ordinaryContext = new TyperContext(index, "Main.hx", "Main", "", [ordinarySource], "Main", null, [ordinary]);
		assertTrue(ordinaryContext.importedStaticField("PI") == null, "a plain module import must not expose a class's static field as a bare name");
		assertTrue(ordinaryContext.importedStaticMethod("twice") == null, "a plain module import must not expose a class's static method as a bare name");
		final importedSecondary = ordinaryContext.resolveType("NestedBase");
		assertTrue(importedSecondary != null && importedSecondary.getFullName() == "model.Api.NestedBase",
			"a plain module import should expose the module's secondary types");
		assertTrue(ordinaryContext.resolveType("Hidden") == null, "a plain module import must not resolve a private secondary type");
		assertTrue(ordinary.getProviders().filter(function(provider) return provider.getCanonicalName() == "model.Api.Hidden").length == 0,
			"a plain module import must not expose a private secondary type");

		final api = index.getByFullName("model.Api");
		final wildcardSource = HxModuleDirective.wildcardImport("model.Api");
		final wildcard = new TyModuleDirective(wildcardSource, StaticWildcardImport, [api.getIdentity()]);
		final wildcardContext = new TyperContext(index, "Main.hx", "Main", "", [wildcardSource], "Main", null, [wildcard]);
		assertTrue(wildcardContext.importedStaticField("PI") != null && wildcardContext.importedStaticMethod("twice") != null,
			"a type wildcard should expose the provider's static members");
		assertTrue(wildcardContext.importedStaticField("hidden") == null && wildcardContext.importedStaticMethod("hiddenMethod") == null,
			"a type wildcard must withhold static members marked @:noImportGlobal");
		assertTrue(wildcardContext.resolveType("NestedBase") == null, "a type wildcard must not expose a secondary type from the provider's module");

		final exactHiddenFieldSource = HxModuleDirective.normalImport("model.Api.hidden");
		final exactHiddenMethodSource = HxModuleDirective.normalImport("model.Api.hiddenMethod");
		final exactHiddenContext = new TyperContext(index, "Main.hx", "Main", "", [exactHiddenFieldSource, exactHiddenMethodSource], "Main", null, [
			new TyModuleDirective(exactHiddenFieldSource, StaticMemberImport("hidden"), [api.getIdentity()]),
			new TyModuleDirective(exactHiddenMethodSource, StaticMemberImport("hiddenMethod"), [api.getIdentity()])
		]);
		assertTrue(exactHiddenContext.importedStaticField("hidden") != null
			&& exactHiddenContext.importedStaticMethod("hiddenMethod") != null,
			"@:noImportGlobal should affect wildcard imports without rejecting an explicit member import");
		final exactPrivateFieldSource = HxModuleDirective.normalImport("model.Api.privateValue");
		final exactPrivateMethodSource = HxModuleDirective.normalImport("model.Api.privateMethod");
		final exactPrivateContext = new TyperContext(index, "Main.hx", "Main", "", [exactPrivateFieldSource, exactPrivateMethodSource], "Main", null, [
			new TyModuleDirective(exactPrivateFieldSource, StaticMemberImport("privateValue"), [api.getIdentity()]),
			new TyModuleDirective(exactPrivateMethodSource, StaticMemberImport("privateMethod"), [api.getIdentity()])
		]);
		assertTrue(exactPrivateContext.importedStaticField("privateValue") == null
			&& exactPrivateContext.importedStaticMethod("privateMethod") == null,
			"an explicit static import must not expose another type's private member");

		final privateImportModule = resolved.filter(function(module) return ResolvedModule.getModulePath(module) == "PrivateStaticImportMain")[0];
		final privateImportLoader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		privateImportLoader.markResolvedAlready(resolved);
		final privateImportTyped = TyperStage.typeResolvedModule(privateImportModule, index, privateImportLoader, true);
		final privateImportKinds = privateImportTyped.getEnv().getResolvedDirectives().map(function(directive) return directive.canonicalIdentity());
		assertTrue(privateImportKinds.join("\n") == "import-normal:model.Api.privateValue=>unresolved\nimport-normal:model.Api.privateMethod=>unresolved",
			"directive resolution must reject exact imports of private static members: " + privateImportKinds.join(", "));

		final usingOrderModule = resolved.filter(function(module) return ResolvedModule.getModulePath(module) == "UsingOrderMain")[0];
		final usingOrderLoader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		usingOrderLoader.markResolvedAlready(resolved);
		final usingOrderTyped = TyperStage.typeResolvedModule(usingOrderModule, index, usingOrderLoader, true);
		final usingProviders = usingOrderTyped.getEnv().getResolvedDirectives()[0].getProviders();
		assertTrue([for (provider in usingProviders) provider.getCanonicalName()].join(",") == "order.Extensions.ZFirst,order.Extensions.ASecond",
			"module-level using providers must retain source declaration order because equal extension names are tried in that order");
		final scannedPrivate = ParserStageScanHelpers.scanModuleLocalHelperClasses("class PublicHelper {} private class PrivateHelper {}", "Main");
		assertTrue(scannedPrivate.length == 2
			&& HxClassDecl.getVisibility(scannedPrivate[0]) == HxVisibility.Public
			&& HxClassDecl.getVisibility(scannedPrivate[1]) == HxVisibility.Private,
			"the Haxe frontend sibling scanner must retain top-level type visibility");
		final scannedPrivateEnum = ParserStageScanHelpers.scanModuleLocalHelperEnums("enum PublicEnum { A; } private enum PrivateEnum { B; }", "Main");
		final scannedPrivateTypedef = ParserStageScanHelpers.scanModuleLocalHelperTypedefs("typedef PublicShape = {}; private typedef PrivateShape = {};",
			"Main");
		final scannedPrivateAbstract = ParserStageScanHelpers.scanModuleLocalHelperAbstracts("abstract PublicId(Int) {} private abstract PrivateId(Int) {}",
			"Main");
		for (pair in [scannedPrivateEnum, scannedPrivateTypedef, scannedPrivateAbstract])
			assertTrue(pair.length == 2
				&& HxClassDecl.getVisibility(pair[0]) == HxVisibility.Public
				&& HxClassDecl.getVisibility(pair[1]) == HxVisibility.Private,
				"every Haxe frontend secondary-type scanner must retain public/private visibility");

		final leftTypeSource = HxModuleDirective.normalImport("a.Tools");
		final rightTypeSource = HxModuleDirective.normalImport("b.Tools");
		final typeContext = new TyperContext(index, "Main.hx", "Main", "", [leftTypeSource, rightTypeSource], "Main", null, [
			new TyModuleDirective(leftTypeSource, TypeImport, [index.getByFullName("a.Tools").getIdentity()]),
			new TyModuleDirective(rightTypeSource, TypeImport, [index.getByFullName("b.Tools").getIdentity()])
		]);
		assertTrue(typeContext.resolveType("Tools").getFullName() == "b.Tools", "the later type import should win a local-name collision");

		final leftFieldSource = HxModuleDirective.aliasImport("a.Tools.leftValue", "selected");
		final rightFieldSource = HxModuleDirective.aliasImport("b.Tools.rightValue", "selected");
		final leftMethodSource = HxModuleDirective.aliasImport("a.Tools.leftMethod", "run");
		final rightMethodSource = HxModuleDirective.aliasImport("b.Tools.rightMethod", "run");
		final staticContext = new TyperContext(index, "Main.hx", "Main", "", [leftFieldSource, rightFieldSource, leftMethodSource, rightMethodSource], "Main",
			null, [
				new TyModuleDirective(leftFieldSource, StaticMemberImport("leftValue"), [index.getByFullName("a.Tools").getIdentity()]),
				new TyModuleDirective(rightFieldSource, StaticMemberImport("rightValue"), [index.getByFullName("b.Tools").getIdentity()]),
				new TyModuleDirective(leftMethodSource, StaticMemberImport("leftMethod"), [index.getByFullName("a.Tools").getIdentity()]),
				new TyModuleDirective(rightMethodSource, StaticMemberImport("rightMethod"), [index.getByFullName("b.Tools").getIdentity()])
			]);
		final selectedField = staticContext.importedStaticField("selected");
		assertTrue(selectedField != null
			&& selectedField.getOwner().getCanonicalName() == "b.Tools"
			&& selectedField.getName() == "rightValue",
			"the later exact static-field import should win without combining providers");
		final selectedMethod = staticContext.importedStaticMethod("run");
		assertTrue(selectedMethod != null
			&& selectedMethod.getProvider().getFullName() == "b.Tools"
			&& selectedMethod.getMemberName() == "rightMethod",
			"the later exact static-method import should keep its provider and original name together");
	}

	static function assertRuntime(command:String, entryPath:String, label:String):Void {
		if (!commandExists(command))
			return;
		final result = commandOutput(command, [entryPath]);
		assertTrue(result.code == 0, label + " alias output failed: " + result.stderr);
		assertTrue(StringTools.trim(result.stdout) == "alias-target:base:role:service:3:8", label + " alias runtime output mismatch: " + result.stdout);
	}

	/** Compile the alias fixture with target toolchains when they are installed. **/
	static function assertCompiledTargetOutput(targetId:String, root:String):Void {
		final available = switch (targetId) {
			case "java-native": commandExists("java") && commandExists("javac") && commandExists("jar");
			case "cs-native": commandExists("mcs") || commandExists("csc");
			case _: false;
		};
		if (!available)
			return;
		final outputRoot = Path.join([root, targetId + "-compiled"]);
		final result = BackendRegistry.requireForTarget(targetId)
			.emit(compiledAliasProgram(), new BackendContext(outputRoot, null, "Main", true, true, new StringMap<String>()));
		assertTrue(FileSystem.exists(result.entryPath), targetId + " did not produce its compiled alias artifact");
	}

	static function main():Void {
		final root = Path.normalize(".tmp/m14_module_import_alias_targets_" + Std.string(Date.now().getTime()));
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		var thrown:Dynamic = null;
		try {
			assertResolvedClassHeader();
			assertResolvedDirectives();
			assertImportVisibilityAndPrecedence();
			final python = emit("python-native", root);
			emit("java-native", root);
			assertJavaCollisionOutput(root);
			assertWildcardTargetOutput(root);
			emit("cs-native", root);
			final php = emit("php-native", root);
			final lua = emit("lua-native", root);
			assertRuntime("python3", python, "Python");
			assertRuntime("php", php, "PHP");
			assertRuntime("lua", lua, "Lua");
			assertCompiledTargetOutput("java-native", root);
			assertCompiledTargetOutput("cs-native", root);
			assertPhpUsingOrder(root);
		} catch (error:Dynamic) {
			thrown = error;
		}
		if (thrown == null)
			deleteRecursive(root)
		else {
			Sys.println("debug_out=" + root);
			throw thrown;
		}
		Sys.println("MODULE_IMPORT_ALIAS_TARGETS:PASS");
	}
}
