/** Extern interfaces have no generated Neko class object; ordinary interfaces retain membership. */
class M14NekoExternInterfaceIntegrationTest {
	static function main():Void {
		assertHeaderFacts();
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.assertRuntimeFixture("test/neko_extern_interface", true);
		Sys.println("NEKO_EXTERN_INTERFACE:PASS");
	}

	/** Parsed copies, typed facts, and public revisions must retain the extern declaration boundary. */
	static function assertHeaderFacts():Void {
		final source = "interface Left {} interface Right {} extern interface Main extends Left extends Right {}";
		final ordinarySource = StringTools.replace(source, "extern interface Main", "interface Main");
		final parsed = ParserStage.parse(source, "Main.hx");
		final ordinary = ParserStage.parse(ordinarySource, "Main.hx");
		final changedTree = new ParsedModule(source, ordinary.getDecl(), "Main.hx");
		if (ParsedModuleIntegrity.revision(parsed) == ParsedModuleIntegrity.revision(changedTree))
			throw "parser integrity ignored extern status";
		for (cls in ParserStageScanHelpers.scanModuleLocalHelperClasses(source, "Other"))
			if (HxClassDecl.getName(cls) == "Main" && !HxClassDecl.getIsExtern(cls))
				throw "declaration scanner discarded extern";
		final module = new ResolvedModule("Main", "Main.hx", parsed);
		final expanded = hxhx.Stage3BuildMacroSupport.applyGeneratedMembers(module, ["function read():Int;"]);
		final copied = HxModuleDecl.getMainClass(ResolvedModule.getParsed(expanded).getDecl());
		if (!HxClassDecl.getIsExtern(copied) || HxClassDecl.getInterfaceExtendsPaths(copied).join(",") != "Left,Right")
			throw "generated-member application discarded interface header facts";
		final typed = @:privateAccess M14RuntimeTypeOperandsIntegrationTest.typeSource(source);
		final regular = @:privateAccess M14RuntimeTypeOperandsIntegrationTest.typeSource(ordinarySource);
		final graph = new TypedBackendClassGraph("extern-header-test", [
			for (cls in typed.getBackendProjection().getClasses())
				cls.requireSemanticFacts()
		]);
		if (graph.requireAssignableTypes("Main").length != 3)
			throw "runtime admission changed the full shared interface relation";
		var found = false;
		for (cls in typed.getBackendProjection().getClasses())
			if (HxClassDecl.getName(cls.getDeclaration()) == "Main") {
				found = true;
				if (!cls.requireSemanticFacts().getIsExtern() || !HxClassDecl.getIsExtern(cls.getDeclaration()))
					throw "typing or projection discarded extern";
			}
		if (!found)
			throw "missing typed extern interface";
		if (CompilerTypedModuleRevision.fromTypedModule(typed)
			.publicInterfaceRevision == CompilerTypedModuleRevision.fromTypedModule(regular)
			.publicInterfaceRevision)
			throw "public interface revision ignored extern status";
	}
}
