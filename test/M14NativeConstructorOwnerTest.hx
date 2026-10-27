import backend.BackendContext;
import backend.BackendRegistry;
import backend.source.SourceNativeConstructorLowering;
import backend.source.SourceNativeFunctionLocals;
import backend.source.SourceNativeTarget;
import backend.source.SourceTargetCommon;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Exact constructor owners survive native rewrites without changing argument effects. */
@:access(backend.source.SourceTargetCommon)
class M14NativeConstructorOwnerTest {
	static function module(path:String, source:String):ResolvedModule {
		final file = StringTools.replace(path, ".", "/") + ".hx";
		return new ResolvedModule(path, file, ParserStage.parse(source, file));
	}

	static function program(modules:Array<ResolvedModule>):MacroExpandedProgram {
		final index = TyperIndex.build(modules);
		return new MacroExpandedProgram([for (entry in modules) TyperStage.typeResolvedModule(entry, index)], false);
	}

	static function projection(program:MacroExpandedProgram):TypedBackendFunctionProjection
		return program.getTypedModules()[0].getBackendProjection().getClasses()[0].getFunctions()[0];

	static function locals(program:MacroExpandedProgram, target:SourceNativeTarget):SourceNativeFunctionLocals
		return new SourceNativeFunctionLocals({
			target: target,
			program: program,
			projection: projection(program),
			noRoot: false
		});

	static function rejects(action:Void->Void, expected:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) >= 0)
				return;
			throw error;
		}
		throw "constructor admission accepted " + expected;
	}

	/** Same-named secondary classes keep their package owners; copied and missing providers cannot borrow facts. */
	static function ownership():Void {
		final main = module("Main", "class Main { static function probe():Void {new left.Types.Holder(); new right.Types.Holder();} }");
		final left = module("left.Types", "package left; class Types {} class Holder {public function new() {}} ");
		final right = module("right.Types", "package right; class Types {} class Holder {public function new() {}} ");
		final whole = program([main, left, right]);
		final body = projection(whole);
		final entries = body.getConstructorCatalog().getEntries();
		for (target in [Java, Cs]) {
			final scope = locals(whole, target);
			final prefix = target == Cs ? "global::" : "";
			if (scope.constructorName(entries[0].getExpression()) != prefix + "left.Holder"
				|| scope.constructorName(entries[1].getExpression()) != prefix + "right.Holder")
				throw "constructor selected a module path or another package's class";
			final copied:HxExpr = switch entries[0].getExpression() {
				case ENew(path, args): ENew(path, args.copy());
				case _: throw "missing allocation";
			};
			rejects(() -> scope.constructorName(copied), "absent from the current function projection");
			final foreign = projection(program([main, left, right])).getConstructorCatalog().getEntries()[0].getExpression();
			rejects(() -> scope.constructorName(foreign), "absent from the current function projection");
		}
		final incomplete = new MacroExpandedProgram([whole.getTypedModules()[0]], false);
		rejects(() -> locals(incomplete, Java).constructorName(entries[0].getExpression()), "cannot find its exact provider");

		final external = program([
			module("Main", "class Main {static function probe():Void {new Host();}} extern class Host {public function new();}")
		]);
		final original = projection(external).getConstructorCatalog().getEntries()[0].getExpression();
		for (target in [Java, Cs]) {
			final lowered = SourceNativeConstructorLowering.expression(locals(external, target), original, original);
			final selected = SourceNativeConstructorLowering.decode(lowered);
			if (selected == null || selected.target != target)
				throw "extern construction lost its checked target";
			switch selected.kind {
				case Runtime("Main.Host"):
				case _:
					throw "extern construction was treated as an emitted class";
			}
		}
		final namesake = program([
			module("Main", "class Main {static function probe():Void {new Array();}} class Array {public function new() {}}")
		]);
		final namesakeExpression = projection(namesake).getConstructorCatalog().getEntries()[0].getExpression();
		final namesakePlan = SourceNativeConstructorLowering.decode(SourceNativeConstructorLowering.expression(locals(namesake, Cs), namesakeExpression,
			namesakeExpression));
		switch namesakePlan.kind {
			case EmittedClass("global::Array"):
			case _:
				throw "authored Array namesake was captured by core runtime construction";
		}
	}

	/**
		Use real C# standard-library declarations for allocation admission and run the emitted allocations.
		Array is fully typed. NativeArray uses its resolved extern header only: its separate iterator
		currently fails Int-to-UInt typing, so this focused check makes no iterator or whole-module claim.
	**/
	@:access(TyperStage)
	static function runtimeProviders(root:String):Void {
		final main = module("Main",
			'class Main {static function core():Dynamic return new Array<Int>();' + 'static function native():Dynamic return new cs.NativeArray<Int>(2);}');
		final args = Stage1Args.parse(["-cp", ".", "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: ["."],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "cs"
		});
		final index = TyperIndex.buildHeaders([main]);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "cs", "cs"), index);
		loader.markResolvedAlready([main]);
		final typedMain = TyperStage.typeResolvedModule(main, index, loader, true);
		final array = index.getRegisteredModule("Array");
		final native = index.getRegisteredModule("cs.NativeArray");
		if (array == null || native == null)
			throw "real standard-library constructor providers were not loaded";
		final typedArray = TyperStage.typeResolvedModule(array, index, loader, true);
		final nativeDeclaration = HxModuleDecl.getMainClass(native.parsed.getDecl());
		final nativeInfo = index.getForSourceClass(nativeDeclaration);
		if (nativeInfo == null
			|| nativeInfo.getIdentity().getCanonicalName() != "cs.NativeArray"
			|| !Std.isOfType(nativeInfo, TyClassInfo)
			|| !(cast nativeInfo : TyClassInfo).getIsExtern())
			throw "NativeArray header is not the selected standard-library extern";
		final directives = HxModuleDecl.getDirectives(native.parsed.getDecl());
		final context = new TyperContext(index, native.filePath, native.modulePath, "cs", directives, "cs.NativeArray", loader);
		final relationships = TyperStage.resolveClassHeaderTypes(nativeDeclaration, context);
		final header = new TypedModule(native.parsed, new TyModuleEnv("cs", directives, new TyClassEnv("NativeArray", [])), [
			new TypedClass(nativeDeclaration, nativeInfo, [], [], relationships.extendsType, relationships.implementsTypes, relationships.interfaceExtendsTypes)
		], 1, native.sourceOrigin);
		final typed = new MacroExpandedProgram([typedMain, typedArray, header], false);
		final functions = typedMain.getBackendProjection().getClasses()[0].getFunctions();
		final bodies = [
			for (function_ in functions)
				SourceTargetCommon.renderNativeFunctionBody(new SourceNativeFunctionLocals({
					target: Cs,
					program: typed,
					projection: function_,
					noRoot: false
				}), function_.getBody(), "").join("\n")
		];
		final harness = 'class RuntimeProbe {static object core(){'
			+ bodies[0]
			+ '} static object native(){'
			+ bodies[1]
			+ '} public static void Main(){System.Console.WriteLine(((hxhx.__HxArray)core()).length);'
			+ 'System.Console.WriteLine(((object[])native()).Length);}}';
		sys.io.File.saveContent(root + "/RuntimeProbe.cs", harness);
		sys.io.File.saveContent(root + "/RuntimeSupport.cs", SourceTargetCommon.renderCsRuntimeSupportSource());
		run("mcs", [
			"-r:Microsoft.CSharp",
			"-out:" + root + "/RuntimeProbe.exe",
			root + "/RuntimeProbe.cs",
			root + "/RuntimeSupport.cs"
		]);
		if (run("mono", [root + "/RuntimeProbe.exe"]) != "0\n2")
			throw "core Array or NativeArray allocation changed runtime representation";
	}

	static function run(command:String, args:Array<String>):String {
		final process = new sys.io.Process(command, args);
		final output = process.stdout.readAll().toString();
		final error = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " failed: " + output + error;
		return StringTools.trim(output);
	}

	/** Independent native constructors observe nested argument order and one execution per effect. */
	static function effects(root:String):Void {
		final source = 'class Main { static function probe():Int {return new Holder(Effects.mark(1),new Other(Effects.mark(2))) == null ? 0 : 1;}'
			+ 'static function main():Void {Sys.println(probe());}}'
			+ 'class Effects {public static function mark(value:Int):Int {Sys.println(value);return value;}}'
			+ 'class Other {public function new(value:Int) {Sys.println("other");}}'
			+ 'class Holder {public function new(value:Int, other:Other) {Sys.println("holder");}}';
		sys.io.File.saveContent(root + "/Main.hx", source);
		final expected = "1\n2\nother\nholder\n1";
		if (run("haxe", ["-cp", root, "--run", "Main"]) != expected)
			throw "upstream constructor effects differ";
		final typed = program([module("Main", source)]);
		for (target in [Java, Cs]) {
			final java = target == Java;
			final body = SourceTargetCommon.renderNativeFunctionBody(locals(typed, target), projection(typed).getBody(), "").join("\n");
			final print = java ? "System.out.println" : "System.Console.WriteLine";
			final entry = java ? "public static void main(String[] args)" : "public static void Main(string[] args)";
			final harness = 'class Effects {public static int mark(int value){' + print + '(value);return value;}}'
				+ 'class Other {public Other(int value){' + print + '("other");}}' + 'class Holder {public Holder(int value,Other other){' + print
				+ '("holder");}}' + 'class ' + (java ? 'Main' : 'Probe') + ' {static int probe(){' + body + '}' + entry + '{' + print + '(probe());}}';
			final path = root + (java ? "/Main.java" : "/Main.cs");
			sys.io.File.saveContent(path, harness);
			run(java ? "javac" : "mcs", java ? [path] : ["-out:" + root + "/Main.exe", path]);
			if (run(java ? "java" : "mono", java ? ["-cp", root, "Main"] : [root + "/Main.exe"]) != expected)
				throw "native constructor effects differ";
		}
	}

	/** Public emission must construct the same secondary class used by the typed local declaration. */
	static function publicRoute(root:String):Void {
		final source = "class Main {static function main():Void {var value:Holder; value=new Holder(); Sys.println(value==null ? 0 : 1);}}"
			+ "class Holder {public function new() {}}";
		for (target in ["java-native", "cs-native"]) {
			final result = BackendRegistry.requireForTarget(target)
				.emit(program([module("Main", source)]), new BackendContext(root + "/" + target, null, "Main", true, true, new haxe.ds.StringMap<String>()));
			if (run(target == "java-native" ? "java" : "mono", target == "java-native" ? ["-jar", result.entryPath] : [result.entryPath]) != "1")
				throw "public backend constructor result differs";
		}
	}

	public static function main():Void {
		ownership();
		final root = ".tmp/native_constructor_owner_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		effects(root);
		runtimeProviders(root);
		publicRoute(root);
		Sys.println("NATIVE_CONSTRUCTOR_OWNER:PASS");
	}
}
