import backend.ocaml.HxhxOcamlTargetFunctionAdapter;
import backend.ocaml.HxhxOcamlTargetProgramAdapter;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.OcamlTargetFunctionLowerer;
import reflaxe.ocaml.target.OcamlTargetProgramCore;
import reflaxe.ocaml.target.OcamlTargetProgramCore.OcamlTargetProgramPublisher;
import sys.io.File;

/** Require both hosts to preserve complete function facts before an independent native observer runs. */
class SharedFunctionValuesFixture {
	static function main():Void {
		final rejected = StockFunctionValuesMacro.rejectedSignatures();
		final unsupportedPath = "test/reflaxe_ocaml_shared_function_values/source/Unsupported.hx";
		final unsupported = new ResolvedModule("Unsupported", unsupportedPath, ParserStage.parse(File.getContent(unsupportedPath), unsupportedPath));
		final unsupportedModule = TyperStage.typeResolvedModule(unsupported, TyperIndex.build([unsupported]));
		var rejectedCount = 0;
		for (cls in unsupportedModule.getTypedClasses())
			for (fn in cls.getFunctions()) {
				if (rejected.indexOf(HxFunctionDecl.getName(fn.getSourceDeclaration())) < 0
					|| HxhxOcamlTargetFunctionAdapter.fromFunction(cls.getSemanticInfo(), fn) != null)
					throw "native adapter admitted an unsupported signature or changed the stock inventory";
				rejectedCount++;
			}
		if (rejectedCount != 6 || rejected.length != rejectedCount)
			throw "unsupported signature fixture lost a case";
		if (Sys.command("node_modules/.bin/haxe", [
			"-cp",
			"test/reflaxe_ocaml_shared_function_values/source",
			"-cp",
			"test/reflaxe_ocaml_shared_function_values/upstream",
			"-main",
			"UpstreamFunctionValuesProbe",
			"--interp"
		]) != 0)
			throw "upstream function values disagree with the independent result contract";
		Sys.println("SHARED_FUNCTION_VALUES:UPSTREAM_PASS");
		final sourcePath = "test/reflaxe_ocaml_shared_function_values/source/Main.hx";
		final resolved = new ResolvedModule("Main", sourcePath, ParserStage.parse(File.getContent(sourcePath), sourcePath));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final before = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final stock = StockFunctionValuesMacro.expected();
		final failures = new Array<String>();
		var compared = 0;
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions()) {
				final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
				final matches = stock.filter(row -> row.name == name);
				if (matches.length != 1)
					throw "stock function inventory differs for " + name;
				final fact = HxhxOcamlTargetFunctionAdapter.fromFunction(cls.getSemanticInfo(), fn);
				if (!matches[0].admitted || fact == null) {
					final failure = name + " stock=" + matches[0].admitted + " native=" + (fact != null);
					Sys.println("SHARED_FUNCTION_VALUES:REJECTED " + failure);
					failures.push(failure);
					continue;
				}
				if (fact.getCanonicalIdentity() != matches[0].identity
					|| new OcamlASTPrinter().printExpr(OcamlTargetFunctionLowerer.build(fact)) != matches[0].syntax)
					throw "host function facts or syntax differ for " + name;
				compared++;
			}
		if (failures.length != 0)
			throw "shared function arguments/results are incomplete: " + failures.join("; ");
		if (compared != 7 || stock.length != compared)
			throw "shared function values did not compare the complete authored inventory";
		final request = HxhxOcamlTargetProgramAdapter.fromProgram(new MacroExpandedProgram([typed], false), "Main");
		FunctionValuesValidation.check(request);
		final plan = OcamlTargetProgramCore.lower(request);
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != before)
			throw "shared function value adaptation changed its original typed module";
		final output = ".tmp/shared-function-values-" + Std.string(Date.now().getTime()) + "-" + Std.random(0x3fffffff);
		final executable = OcamlTargetProgramPublisher.publish(plan, output, "native-hxhx", true);
		if (Sys.command(executable, []) != 0)
			throw "shared function value application failed";
		File.copy("test/reflaxe_ocaml_shared_function_values/Observer.ml", output + "/Observer.ml");
		File.saveContent(output + "/Order.ml", FunctionValuesValidation.orderObserverSource());
		final cwd = Sys.getCwd();
		try {
			Sys.setCwd(output);
			if (Sys.command("ocamlopt", ["Main.ml", "Observer.ml", "Order.ml", "-o", "observer.exe"]) != 0)
				throw "shared function observer did not typecheck against the emitted module";
			if (Sys.command("./observer.exe", []) != 0)
				throw "shared function observer rejected an argument or result";
			Sys.setCwd(cwd);
		} catch (error:haxe.Exception) {
			Sys.setCwd(cwd);
			throw error;
		}
		Sys.println("REFLAXE_OCAML_SHARED_FUNCTION_VALUES:PASS");
	}
}
