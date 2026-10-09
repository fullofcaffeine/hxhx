import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** A reduced source contract checks enum erasure at required inline parameter storage. */
class M14InlineEnumValueTest {
	static function main():Void {
		final root = "test/fixtures/inline_enum_value";
		final expected = "INLINE_ENUM_VALUE_RUNTIME:PASS\n";
		final output = JsRuntimeFixture.reserveOutput();
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		if (@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("node", [output + "/upstream.js"]) != expected)
			throw "upstream inline enum contract differs";
		Sys.println("INLINE_ENUM_VALUE_UPSTREAM:PASS");
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final index = TyperIndex.buildHeaders([resolved]);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader, true);
		if (index.getAbstractByFullName("EnumValue") == null)
			throw "inline enum test did not load the core EnumValue declaration";
		final lowered = TypedAbstractOperatorLowering.lowerModules([typed], index);
		var conversions = 0;
		function expression(node:TypedExpr):Void {
			if (node.getTag() == Cast
				&& node.getType().getNominalIdentity() != null
				&& node.getType().getNominalIdentity().getCanonicalName() == "EnumValue"
				&& node.getExpressions()[0].getType().getNominalIdentity() != null
				&& node.getExpressions()[0].getType().getNominalIdentity().getCanonicalName() == "Main.Token") {
				if (!node.isRepresentationPreservingCast())
					throw "inline enum storage lost the shared representation proof";
				conversions++;
			}
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (child in node.getExpressions())
				expression(child);
			for (child in node.getStatements())
				statement(child);
		}
		for (owner in lowered[0].getTypedClasses())
			for (fn in owner.getFunctions())
				for (body in fn.getBody().getStatements())
					statement(body);
		if (conversions != 1)
			throw "inline enum storage requires one explicit conversion: " + conversions;
		final script = output + "/candidate.js";
		new backend.js.JsBackend().emit(new MacroExpandedProgram(lowered, false), new backend.BackendContext(output, script, "Main", true, false, defines));
		if (@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("node", [script]) != expected)
			throw "candidate inline enum contract differs: " + output;
		Sys.println("INLINE_ENUM_VALUE:PASS " + output);
	}
}
