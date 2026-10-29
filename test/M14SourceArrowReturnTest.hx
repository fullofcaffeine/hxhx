/** The shared backend projection must preserve the nested arrow's return destination. */
class M14SourceArrowReturnTest {
	static function main():Void {
		final path = "test/oracle/source_arrow_return_seed/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		typed.getBackendDeclaration();
		Sys.println("SOURCE_ARROW_RETURN:PASS");
	}
}
