import backend.vm.NekoTypedProgramProjection;
import backend.vm.NekoExactCallPlan;
import backend.vm.NekoTargetCore;
import backend.BackendContext;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;

/** Checks exact secondary-type ownership through the normal indexed typer. */
class M14NekoTypedProgramProjectionIntegrationTest {
	/** Uses the same resolved module and semantic index as normal compilation. */
	static function project(source:String):TypedBackendModuleProjection {
		return typeSource(source).getBackendProjection();
	}

	static function typeSource(source:String):TypedModule {
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		return TyperStage.typeResolvedModule(resolved, index, loader);
	}

	static function expectFailure(fragment:String, action:Void->Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(fragment) < 0)
				throw "unexpected projection error: " + error.message;
			return;
		}
		throw "expected projection rejection: " + fragment;
	}

	static function main():Void {
		final source = 'enum abstract Flavor(String) { var Bold = "strong"; public function label():String return this; }
class Main { static function main():Void { Sys.println(Flavor.Bold.label()); } }';
		final module = project(source);
		final projection = new NekoTypedProgramProjection([module]);
		final owner = projection.requireClass("Main.Flavor");
		final bold = owner.requireSemanticFacts().findField("Main.Flavor#static#Bold");
		if (bold == null || bold.typeIdentity != TyType.nominal(new TyNominalTypeId("Main.Flavor"), []).getSemanticKey())
			throw "enum value lost its abstract identity before method selection";
		switch (owner.requireSemanticFacts().getNominalKind()) {
			case AbstractValue(underlying):
				if (underlying.getSemanticKey() != "primitive:String")
					throw "the abstract lost its exact String backing type";
			case _:
				throw "the abstract was projected as an ordinary object";
		}
		if (!projection.requireClass("Main").requireSemanticFacts().getNominalKind().match(ClassInstance))
			throw "the ordinary class gained an abstract receiver";
		final declaration = "Main.Flavor#instance:label()->primitive:String#0";
		final selected = projection.requireFunction("Main.Flavor", declaration);
		if (selected.owner != owner || selected.body.getStableIdentity() != declaration)
			throw "the selected helper lost its canonical owner or declaration";
		if (selected.body.getReturnType().getCanonicalDisplay() != "String" || selected.body.getBody().length == 0)
			throw "the selected helper lost its typed result or body";
		expectFailure("cannot find class Flavor", () -> projection.requireClass("Flavor"));
		expectFailure("does not belong to Main", () -> projection.requireFunction("Main", declaration));
		expectFailure("cannot find function missing", () -> projection.requireFunction("Main.Flavor", "missing"));
		expectFailure("duplicate class", () -> new NekoTypedProgramProjection([module, module]));
		final exact = TypedExactCallSource.encodeInstance("Main.Flavor", declaration, "label", "String", EString("strong"), []);
		final call = NekoExactCallPlan.fromExpression(projection, exact);
		if (call == null || call.selected.body != selected.body || call.getArguments().length != 0)
			throw "the exact call did not select the indexed helper body";
		if (NekoExactCallPlan.fromExpression(projection, ECall(EIdent("ordinary"), [])) != null)
			throw "an ordinary call gained an exact declaration";
		expectFailure("malformed typed payload",
			() -> NekoExactCallPlan.fromExpression(projection, ECall(EIdent(TypedExactCallSource.INSTANCE_INTRINSIC), [])));
		expectFailure("conflicts with declaration",
			() -> NekoExactCallPlan.fromExpression(projection,
				TypedExactCallSource.encodeInstance("Main.Flavor", declaration, "different", "String", EString("strong"), [])));
		assertNominalKinds();
		assertInferredResults();
		assertOptionalNullInference();
		assertResultBoundaries();
		assertEnumValueDeclarations();
		assertConstantDependencies();
		assertConstantReadBoundary();
		assertConstantRuntime();
		assertStaticCallBoundary();
		expectFailure("requires 3 arguments", () -> backend.vm.NekoStringIntrinsics.renderCall(EIdent("__dollar__ssub"), ["value"]));
		expectFailure("requires 2 arguments", () -> backend.vm.NekoStringIntrinsics.renderCall(EIdent("__dollar__sget"), ["value"]));
		expectFailure("requires 1 argument", () -> backend.vm.NekoStringIntrinsics.renderConstructor([]));
		if (backend.vm.NekoStringIntrinsics.renderCall(EField(EIdent("user"), "__dollar__ssub"), ["a", "b", "c"]) != null
			|| backend.vm.NekoStringIntrinsics.renderCall(EIdent("__dollar__ssub_extra"), []) != null)
			throw "an ordinary function name was treated as a Neko primitive";
		assertRuntimeFixture("test/neko_native_string_slice", true);
		assertRuntimeFixture("test/neko_typed_field_reads", true);
		assertRuntimeFixture("test/neko_array_join", true);
		assertRuntimeFixture("test/neko_qualified_static_calls", true, ["Main", "providers.Api", "other.Api"]);
		assertRuntimeFixture("test/neko_statement_separation", true);
		Sys.println("OK m14 Neko typed program projection");
	}

	/** Static calls must bind their exact owner and reject malformed transport records. */
	static function assertStaticCallBoundary():Void {
		final module = project("class Api { public static function value():Int return 7; } class Main { static function main():Void {} }");
		final program = new NekoTypedProgramProjection([module]);
		final declaration = "Main.Api#static:value()->primitive:Int#0";
		final sourceCall:HxExpr = EField(EIdent("Api"), "value");
		final encoded = TypedExactStaticCallSource.encode("Main.Api", declaration, "value", "Int", sourceCall, []);
		final plan = backend.vm.NekoExactStaticCallPlan.fromExpression(program, encoded);
		if (plan == null || plan.selected.body.getStableIdentity() != declaration)
			throw "static call lost its selected declaration";
		if (!TypedExactStaticCallSource.ordinaryCall(plan.call).match(ECall(EField(EIdent("Api"), "value"), [])))
			throw "static call changed its ordinary source callee";
		expectFailure("malformed typed payload", () -> TypedExactStaticCallSource.decode(ECall(EIdent(TypedExactStaticCallSource.INTRINSIC), [])));
		expectFailure("empty typed identities",
			() -> TypedExactStaticCallSource.decode(TypedExactStaticCallSource.encode("", declaration, "value", "Int", sourceCall, [])));
		expectFailure("requires its typed program", () -> backend.vm.NekoExactStaticCallPlan.fromExpression(null, encoded));
		expectFailure("conflicts with declaration",
			() -> backend.vm.NekoExactStaticCallPlan.fromExpression(program,
				TypedExactStaticCallSource.encode("Main.Api", declaration, "different", "Int", sourceCall, [])));
		expectFailure("does not belong to Main",
			() -> backend.vm.NekoExactStaticCallPlan.fromExpression(program,
				TypedExactStaticCallSource.encode("Main", declaration, "value", "Int", sourceCall, [])));
	}

	/** Embedding must reject mutable-field evidence and preserve receiver effects. */
	static function assertConstantReadBoundary():Void {
		final owner = new TyNominalTypeId("Holder");
		final ownerType = TyType.nominal(owner, []);
		final constant = new TyFieldConstant(IntValue(3));
		expectFailure("inline read-only field",
			() -> new TyFieldInfo(owner, "Holder", "Value", ownerType, true, true, false, false, true, false, "", "", constant));
		final field = new TyFieldInfo(owner, "Holder", "Value", ownerType, true, true, false, true, true, false, "inline", "never", constant);
		final receiver = TypedExpr.call(TypedExpr.nameRead("make", TyType.unknown(), null), [], null, ownerType, null);
		expectFailure("cannot discard a value receiver", () -> TypedBodySource.expression(TypedExpr.fieldRead(receiver, "Value", ownerType, null, field)));
		final ordinary = new TyFieldInfo(owner, "Holder", "mutable", TyType.fromHintText("Int"), true, true, false, false, true);
		final read = TypedBodySource.expression(TypedExpr.fieldRead(TypedExpr.nameRead("Holder", ownerType, null), "mutable", ordinary.getType(), null,
			ordinary));
		if (!read.match(EField(_, "mutable")))
			throw "ordinary static field lost its runtime read";
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " failed: " + stderr;
		return StringTools.replace(stdout, "\r\n", "\n");
	}

	/** The authored source must match upstream and execute in both generated Neko layouts. */
	static function assertConstantRuntime():Void {
		assertRuntimeFixture("test/neko_enum_abstract_values", false);
	}

	/** Compare authored Haxe with both generated layouts; target primitives require the upstream Neko target. */
	static function assertRuntimeFixture(fixture:String, upstreamNeko:Bool, ?modulePaths:Array<String>):Void {
		final expected = File.getContent(fixture + "/expected.stdout");
		final directory = Path.normalize(Sys.getCwd() + "/.tmp/m14_neko_enum_values_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(directory);
		final upstream = if (upstreamNeko) {
			run("haxe", ["-cp", fixture, "-main", "Main", "-neko", directory + "/upstream.n"]);
			run("neko", [directory + "/upstream.n"]);
		} else {
			run("haxe", ["-cp", fixture, "-main", "Main", "--interp"]);
		};
		if (upstream != expected)
			throw "upstream runtime fixture differs from its expected output: " + fixture + "; artifacts: " + directory;
		final modules = modulePaths == null ? ["Main"] : modulePaths;
		final resolved = [
			for (module in modules) {
				final file = fixture + "/" + StringTools.replace(module, ".", "/") + ".hx";
				new ResolvedModule(module, file, ParserStage.parse(File.getContent(file), file));
			}
		];
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader([fixture], new haxe.ds.StringMap<String>(), index, _ -> false);
		loader.markResolvedAlready(resolved);
		final program = new MacroExpandedProgram([for (module in resolved) TyperStage.typeResolvedModule(module, index, loader)], false);
		final context = new BackendContext(directory, directory + "/main.n", "Main", true, false, new haxe.ds.StringMap<String>());
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, directory + "/main.neko");
		File.saveContent(directory + "/main.neko", split.entrySource);
		for (part in split.support)
			File.saveContent(part.path, part.source);
		File.saveContent(directory + "/single.neko", @:privateAccess NekoTargetCore.renderProgram(program, context));
		for (file in FileSystem.readDirectory(directory)) {
			if (!StringTools.endsWith(file, ".neko"))
				continue;
			final path = directory + "/" + file;
			if (File.getContent(path).indexOf("must-stay-unused") >= 0)
				throw "unused abstract helper became reachable in " + path;
			run("nekoc", [path]);
		}
		for (layout in ["single", "main"])
			if (run("neko", [directory + "/" + layout + ".n"]) != expected)
				throw fixture + " runtime differs in " + layout + "; artifacts: " + directory;
		for (file in FileSystem.readDirectory(directory))
			FileSystem.deleteFile(directory + "/" + file);
		FileSystem.deleteDirectory(directory);
	}

	/** A provider edit must change the caller's body revision and retain its constant-value dependency. */
	static function assertConstantDependencies():Void {
		function observe(value:Int):{revision:String, edges:Array<CompilerDependencyEdge>} {
			final providerSource = 'enum abstract Provider(Int) { var Start = ' + value + '; var Pick; }';
			final mainSource = 'class Main { static function main():Void { Sys.println(Provider.Pick); } }';
			final provider = new ResolvedModule("Provider", "Provider.hx", ParserStage.parse(providerSource, "Provider.hx"));
			final main = new ResolvedModule("Main", "Main.hx", ParserStage.parse(mainSource, "Main.hx"));
			final index = TyperIndex.build([provider, main]);
			final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, function(_):Bool return false);
			loader.markResolvedAlready([provider, main]);
			final typedProvider = TyperStage.typeResolvedModule(provider, index, loader);
			final typedMain = TyperStage.typeResolvedModule(main, index, loader);
			return {
				revision: typedMain.getBackendProjection().getClasses()[0].getFunctions()[0].getBodyRevision(),
				edges: CompilerDependencyCollector.collect([typedProvider, typedMain], index).getEdges()
			};
		}
		final first = observe(4);
		final second = observe(7);
		if (first.revision == second.revision)
			throw "a changed implicit enum constant reused the caller's body revision";
		var found = false;
		for (edge in first.edges)
			if (edge.consumerModule == "Main"
				&& edge.providerModule == "Provider"
				&& edge.kind.match(ConstantValue)
				&& edge.factIdentity == "field:Provider#static#Pick")
				found = true;
		if (!found)
			throw "embedding an implicit enum constant lost the provider dependency";
		expectFailure("unresolved enum-abstract constant", () -> project('enum abstract Cycle(Int) { var A = B; var B = A; }
class Main { static function main():Void { Sys.println(Cycle.A); } }'));
	}

	/** Enum values retain spelling and omitted initializers until the shared typer resolves their backing type. */
	static function assertEnumValueDeclarations():Void {
		final parsed = ParserStage.parse('enum abstract Word(String) { var First; final Second; var lower = "small";
public static var ordinary:Int = 9; public function label():String { final local = "local"; return local; } } class Main {}', "Main.hx");
		var checked = false;
		for (cls in HxModuleDecl.getClasses(parsed.getDecl())) {
			if (HxClassDecl.getName(cls) != "Word")
				continue;
			final fields = HxClassDecl.getFields(cls);
			if (fields.length != 4)
				throw "enum values lost a declaration or captured a method local";
			for (field in fields) {
				final name = HxFieldDecl.getName(field);
				final valueMarker = HxFieldDecl.getMetadata(field).indexOf("__hxhx_enum_abstract_value") >= 0;
				if (name == "ordinary") {
					if (valueMarker || HxFieldDecl.getMetadata(field).indexOf("inline") >= 0)
						throw "an ordinary static field became an enum constant";
				} else {
					if (!valueMarker || !HxFieldDecl.getIsStatic(field) || HxFieldDecl.getPropertySet(field) != "never")
						throw "enum value lost its inline read-only declaration: " + name;
					if ((name == "First" || name == "Second") && HxFieldDecl.getInit(field) != null)
						throw "the parser invented an implicit enum constant";
					if (name == "lower" && !HxFieldDecl.getInit(field).match(EString("small")))
						throw "lowercase enum value lost its explicit initializer";
				}
			}
			checked = true;
		}
		if (!checked)
			throw "enum abstract declaration was not retained";
	}

	/** Constructors, explicit contracts, and foreign bodies must not be mistaken for inferred method results. */
	static function assertResultBoundaries():Void {
		final constructorModule = project('class Main { public function new() {} static function main():Void {} }');
		new NekoTypedProgramProjection([constructorModule]);
		final explicitConstructor = project('class Main { public var value:Int; public function new(value:Int):Void { this.value = value; } static function main():Void {} }');
		new NekoTypedProgramProjection([explicitConstructor]);
		final typed = typeSource('class Main { static function answer():String { return "ok"; } }').getTypedClasses()[0];
		final fn = typed.getFunctions()[0];
		final wrongEnvironment = fn.getEnvironment().withReturnTypes(TyType.fromHintText("Int"), TyType.fromHintText("Int"));
		final wrong = new TypedFunction(fn.getOwnerName(), fn.getSourceOrdinal(), fn.getSourceDeclaration(), fn.getDeclaration(), wrongEnvironment,
			fn.getBody());
		expectFailure("conflicting function result", () -> new TypedBackendClassSemanticFacts(typed.getSemanticInfo(), null, [wrong]));
		expectFailure("duplicate function result", () -> new TypedBackendClassSemanticFacts(typed.getSemanticInfo(), null, [fn, fn]));
		final foreign = typeSource('class Main { static function answer():String { return "foreign"; } }').getTypedClasses()[0].getFunctions()[0];
		expectFailure("foreign function result", () -> new TypedBackendClassSemanticFacts(typed.getSemanticInfo(), null, [foreign]));
		final externModule = project('extern class Service { static function label():String; } class Main {}');
		final externFacts = new NekoTypedProgramProjection([externModule]).requireClass("Main.Service").requireSemanticFacts();
		final method = externFacts.findMethod("Main.Service#static:label()->primitive:String#0");
		if (method == null || method.hasBody || method.returnTypeIdentity != "primitive:String")
			throw "bodyless method lost its declared String result";
	}

	/** Optional or explicitly nullable null arguments must not erase another argument's generic type evidence. */
	static function assertOptionalNullInference():Void {
		for (parameter in ["?fallback:T", "fallback:Null<T>"]) {
			final module = project('class Main { static function choose<T>(value:T, '
				+ parameter
				+ '):T return value; static function answer() { return choose("kept", null); } }');
			var found = false;
			for (body in module.getClasses()[0].getFunctions()) {
				if (HxFunctionDecl.getName(body.getDeclaration()) == "answer") {
					if (body.getReturnType().getSemanticKey() != "primitive:String")
						throw "null erased the String binding from the required argument: " + parameter;
					found = true;
				}
			}
			if (!found)
				throw "generic null observer was not projected: " + parameter;
		}
	}

	/** Unannotated functions must retain the same inferred result in declaration and body facts. */
	static function assertInferredResults():Void {
		final module = project('class Main { static function main() {} static function answer() { return 42; } }');
		final projection = new NekoTypedProgramProjection([module]);
		final owner = projection.requireClass("Main");
		for (body in owner.getFunctions()) {
			final name = HxFunctionDecl.getName(body.getDeclaration());
			final expected = name == "main" ? "primitive:Void" : "primitive:Int";
			final method = owner.requireSemanticFacts().findMethod(body.getStableIdentity());
			if (method == null || method.returnTypeIdentity != expected || body.getReturnType().getSemanticKey() != expected)
				throw "inferred result was not finalized consistently for " + name;
		}
	}

	/** A declaration kind or abstract backing-type change must invalidate the shared facts. */
	static function assertNominalKinds():Void {
		final variants = [
			'class Value {} class Main {}',
			'enum Value { Item; } class Main {}',
			'abstract Value(String) {} class Main {}',
			'abstract Value(Int) {} class Main {}'
		];
		final facts = [
			for (source in variants)
				new NekoTypedProgramProjection([project(source)]).requireClass("Main.Value").requireSemanticFacts()
		];
		if (!facts[0].getNominalKind().match(ClassInstance) || !facts[1].getNominalKind().match(EnumValue))
			throw "ordinary class and enum declarations lost their distinct receiver kinds";
		for (i in 0...facts.length)
			for (j in i + 1...facts.length)
				if (facts[i].getCanonicalIdentity() == facts[j].getCanonicalIdentity())
					throw "a declaration kind or abstract backing-type change reused the same class facts";
		final generic = new NekoTypedProgramProjection([project('class Backing<T> {} abstract Value<T>(Backing<T>) {} class Main {}')])
			.requireClass("Main.Value")
			.requireSemanticFacts();
		switch (generic.getNominalKind()) {
			case AbstractValue(underlying):
				final expected = TyType.nominal(new TyNominalTypeId("Main.Backing"), [TyType.typeParameter(generic.getTypeParameterIds()[0])]);
				if (underlying.getSemanticKey() != expected.getSemanticKey())
					throw "the abstract backing type lost its exact generic binder: "
						+ underlying.getSemanticKey()
						+ " versus "
						+ expected.getSemanticKey();
			case _:
				throw "the generic abstract lost its backing type";
		}
	}
}
