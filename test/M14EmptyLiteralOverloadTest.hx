/** An empty literal must not hide a second applicable overload behind its default Array type. */
class M14EmptyLiteralOverloadTest {
	static function main():Void {
		final root = "test/oracle/shared_map_literal_typing_seed/ambiguous";
		final source = sys.io.File.getContent(root + "/Api.hx");
		final provider = new ResolvedModule("Api", root + "/Api.hx", ParserStage.parse(source, root + "/Api.hx"));
		final index = TyperIndex.build([provider]);
		if (index.getByFullName("Api").staticMethodCandidates("pick").length != 2)
			throw "ambiguity fixture requires both indexed declarations";
		var rejected = false;
		try {
			CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["Api", "Array", "haxe.ds.Map"]});
		} catch (error:TyperError) {
			if (error.message.indexOf("Ambiguous overload, candidates follow") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "empty literal selected one of two applicable overloads";
		Sys.println("EMPTY_LITERAL_OVERLOAD:PASS");
	}
}
