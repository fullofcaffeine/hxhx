import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Array literals acquire a selected element context without changing stored class handles. */
class M14ArrayClassContextTest {
	static function main():Void {
		literalFacts();
		for (entry in [
			{name: "literal", body: "take(Array);", accepted: true},
			{name: "parenthesized", body: "take((Array));", accepted: true},
			{name: "private_access", body: "take(@:privateAccess Array);", accepted: true},
			{name: "optional", body: "slots(Array);", accepted: true},
			{name: "stored_concrete", body: "final value:Class<Array<Bool>> = Array; take(value);", accepted: true},
			{name: "stored_erased", body: "final value:Class<Array<Dynamic>> = Array; take(value);", accepted: false},
			{name: "shadowed", body: "final Array:Class<Array<Dynamic>> = null; take(Array);", accepted: false},
			{name: "wrong_element", body: "final value:Class<Array<String>> = Array; take(value);", accepted: false}
		]) {
			final root = ".tmp/array-class-context/" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = "class Main { static function take(value:Class<Array<Bool>>):Void {}"
				+ "static function slots(?count:Int, value:Class<Array<Bool>>):Void {} static function main():Void {"
				+ entry.body
				+ "} }";
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final upstream = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = upstream.stdout.readAll().toString();
			final stderr = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if ((code == 0) != entry.accepted || (!entry.accepted && stderr.indexOf("should be") < 0))
				throw "upstream Array class context differs: " + entry.name + stdout + stderr;
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
			var accepted = false;
			try {
				final typed = TyperStage.typeResolvedModule(module, index, loader, true);
				TypedBodyInvariant.assertClasses(typed.getTypedClasses());
				TypedAbstractOperatorLowering.lowerModules([typed], index)[0].getBackendProjection();
				accepted = true;
			} catch (error:haxe.Exception) {
				if (entry.accepted)
					throw error;
				final diagnostic = entry.name == "wrong_element" ? "No compatible method signature for take" : "selected call conversion does not satisfy its retained parameter";
				if (error.message.indexOf(diagnostic) < 0)
					throw "unexpected rejection for " + entry.name + ": " + error.message;
			}
			if (accepted != entry.accepted)
				throw "local Array class context differs: " + entry.name;
			Sys.println("ARRAY_CLASS_CONTEXT:PASS " + entry.name);
		}
	}

	/** The context wrapper retains one exact literal child; equal-looking stored values never qualify. */
	static function literalFacts():Void {
		final target = new TypedRuntimeTypeTarget(ArrayCore, "ImportedArray");
		final literal = TypedExpr.runtimeTypeValue(target, null);
		final arrayType = TyType.nominal(new TyNominalTypeId("Array"), [TyType.fromHintText("Bool")]);
		final expected = TyType.nominal(new TyNominalTypeId("Class"), [arrayType]);
		for (value in [
			literal,
			TypedExpr.parenthesized(literal, null),
			TypedExpr.privateAccess(literal, null)
		]) {
			final converted = TypedArrayClassContext.convert(value, expected);
			if (converted == null
				|| !converted.isRepresentationPreservingCast()
				|| converted.getType().getSemanticKey() != expected.getSemanticKey()
				|| converted.getExpressions().length != 1
				|| converted.getExpressions()[0] != value
				|| literal.getRuntimeTypeTarget() != target
				|| literal.getType().getSemanticKey() != target.getValueType().getSemanticKey())
				throw "Array context lost its exact literal or changed its runtime type";
			@:privateAccess TypedBodyInvariant.assertExpr(converted, "array-context");
			if (TypedArrayClassContext.convert(converted, expected) != null)
				throw "Array context added a redundant conversion";
		}
		for (value in [
			TypedExpr.localRead("Array", literal.getType(), null),
			TypedExpr.runtimeTypeValue(new TypedRuntimeTypeTarget(Nominal(new TyNominalTypeId("other.Array"))), null),
			TypedExpr.runtimeTypeValue(new TypedRuntimeTypeTarget(Nominal(new TyNominalTypeId("Array"))), null),
			TypedExpr.castValue(literal, literal.getType().getDisplay(), literal.getType(), null),
			TypedExpr.nullValue(literal.getType(), null)
		])
			if (TypedArrayClassContext.convert(value, expected) != null)
				throw "Array context narrowed a stored, explicitly cast, or unrelated value";
		for (destination in [
			arrayType,
			TyType.nominal(new TyNominalTypeId("Class"), [TyType.fromHintText("String")]),
			TyType.nominal(new TyNominalTypeId("other.Class"), [arrayType]),
			TyType.nominal(new TyNominalTypeId("Class"), [TyType.nominal(new TyNominalTypeId("other.Array"), arrayType.getTypeArguments())]),
			TyType.nominal(new TyNominalTypeId("Class"), [TyType.nominal(new TyNominalTypeId("Array"), [])]),
			TyType.nominal(new TyNominalTypeId("Class"), [
				TyType.nominal(new TyNominalTypeId("Array"), [TyType.fromHintText("Bool"), TyType.fromHintText("Int")])
			])
		])
			if (TypedArrayClassContext.convert(literal, destination) != null)
				throw "Array context accepted another type or invalid generic arity: " + destination.getSemanticKey();
		Sys.println("ARRAY_CLASS_CONTEXT_FACTS:PASS");
	}
}
