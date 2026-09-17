import TypedExpr.TypedExprTag;

/** Declared abstract inputs must preserve selected calls and explicit conversion facts. */
class M14AbstractInputConversionIntegrationTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	/** Missing input declarations and incompatible storage cannot authorize a plain cast. */
	static function assertRejectedConversions():Void {
		final root = ".tmp/abstract_input_rejection_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		for (scenario in [
			{header: "abstract Box(String) {}", diagnostic: "String should be Box"},
			{header: "abstract Box(String) from Bool {}", diagnostic: "compatible types"}
		]) {
			sys.io.File.saveContent(root + "/Main.hx",
				scenario.header + " class Main { static function accept(value:Box):Bool return true; static function main() accept(\"text\"); }");
			var diagnostic = "";
			try {
				@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("haxe", ["-cp", root, "-main", "Main", "--interp"]);
			} catch (error:String) {
				diagnostic = error;
			}
			check(diagnostic.indexOf(scenario.diagnostic) >= 0, "upstream rejection contract changed: " + diagnostic);
		}
		sys.FileSystem.deleteFile(root + "/Main.hx");
		sys.FileSystem.deleteDirectory(root);
		final source = "abstract NoInput(String) {} abstract WrongInput(String) from Bool {}";
		final parsed = ParserStage.parse(source, "Boundary.hx");
		final index = TyperIndex.build([new ResolvedModule("Boundary", "Boundary.hx", parsed)]);
		final text = TyType.fromHintText("String");
		for (name in ["Boundary.NoInput", "Boundary.WrongInput"]) {
			final expected = TyType.nominal(new TyNominalTypeId(name), []);
			check(TyImplicitConversionPlan.select(index, expected, text) == null, "undeclared input acquired a conversion: " + name);
		}
		final incompatible = TyImplicitConversionPlan.select(index, TyType.nominal(new TyNominalTypeId("Boundary.WrongInput"), []),
			TyType.fromHintText("Bool"));
		check(incompatible != null
			&& !incompatible.isRepresentationPreservingAbstractConversion(index), "incompatible header became a storage cast");
	}

	static function main():Void {
		assertRejectedConversions();
		final source = sys.io.File.getContent("test/neko_abstract_inputs/Main.hx");
		final module = @:privateAccess M14RuntimeTypeOperandsIntegrationTest.typeSource(source);
		for (entry in [{name: "probe", type: "Main.Box"}, {name: "probeText", type: "Main.Text"}]) {
			final call = @:privateAccess M14RuntimeTypeOperandsIntegrationTest.returned(module, entry.name);
			check(call.getDeclaration() != null
				&& call.getType().getSemanticKey() == "primitive:Bool", "abstract input lost selected call: " + entry.name);
			final argument = call.getExpressions()[1];
			check(argument.getTag() == TypedExprTag.Cast && argument.getType().getSemanticKey() == "nominal:" + entry.type,
				"abstract input lost its explicit parameter conversion: " + entry.name);
			check(argument.getExpressions().length == 1, "input conversion duplicated the argument");
		}
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.assertRuntimeFixture("test/neko_abstract_inputs", true);
		Sys.println("ABSTRACT_INPUT_CONVERSION:PASS");
	}
}
