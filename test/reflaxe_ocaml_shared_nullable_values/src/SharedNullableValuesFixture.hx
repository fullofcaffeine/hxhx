import backend.ocaml.HxhxOcamlTargetFunctionAdapter;
import backend.ocaml.HxhxOcamlTargetProgramAdapter;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.OcamlTargetFunctionLowerer;
import reflaxe.ocaml.target.OcamlTargetProgramCore;
import sys.io.File;
import haxe.io.Path;
import haxe.crypto.Sha256;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifest;

/** Require nullable facts from both hosts and observe the resulting native application. */
class SharedNullableValuesFixture {
	static function main():Void {
		NullableValuesValidation.check();
		if (Sys.command("node_modules/.bin/haxe", [
			"-cp",
			"test/reflaxe_ocaml_shared_nullable_values/source",
			"-cp",
			"test/reflaxe_ocaml_shared_nullable_values/upstream",
			"-main",
			"UpstreamNullableValuesProbe",
			"--interp"
		]) != 0)
			throw "upstream nullable value contract failed";
		Sys.println("SHARED_NULLABLE_VALUES:UPSTREAM_PASS");
		final path = "test/reflaxe_ocaml_shared_nullable_values/source/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final before = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final stock = StockNullableValuesMacro.expected();
		var compared = 0;
		final rejected = new Array<String>();
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions()) {
				final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
				final matches = stock.filter(row -> row.name == name);
				if (matches.length != 1)
					throw "nullable function inventory differs for " + name;
				final fact = HxhxOcamlTargetFunctionAdapter.fromFunction(cls.getSemanticInfo(), fn);
				if (!matches[0].admitted || fact == null) {
					final failure = name + " stock=" + matches[0].admitted + " native=" + (fact != null);
					Sys.println("SHARED_NULLABLE_VALUES:REJECTED " + failure);
					rejected.push(failure);
					continue;
				}
				if (fact.getCanonicalIdentity() != matches[0].identity
					|| new OcamlASTPrinter().printExpr(OcamlTargetFunctionLowerer.build(fact)) != matches[0].syntax)
					throw "nullable host facts or syntax differ for " + name;
				compared++;
			}
		if (rejected.length != 0)
			throw "shared nullable values are incomplete: " + rejected.join("; ");
		if (compared != 5 || stock.length != compared)
			throw "nullable function inventory is incomplete";
		final request = HxhxOcamlTargetProgramAdapter.fromProgram(new MacroExpandedProgram([typed], false), "Main");
		NullableValuesValidation.reject(() -> OcamlTargetProgramCore.lower(request), "requires a checked runtime source provider");
		final plan = OcamlTargetProgramCore.lower(request, () -> new reflaxe.ocaml.target.OcamlTargetRuntimeSources("packages/reflaxe.ocaml/std/runtime"));
		if (plan.report("native-hxhx").runtimeReasons.length == 0)
			throw "nullable program lost its runtime requirements";
		final runtimeFiles = plan.copyFiles().filter(file -> file.path == "HxRuntime.ml"
			|| StringTools.endsWith(file.path, "/HxRuntime.ml"));
		if (runtimeFiles.length != 1)
			throw "nullable program must package its exact runtime source";
		final catalog = RuntimeSourceManifest.load("packages/reflaxe.ocaml/std/runtime");
		final runtime = RuntimeSourceManifest.resolveClosure(catalog, ["HxRuntime"], "portable", false);
		if (runtime.length != 1
			|| runtime[0].files.length != 1
			|| "sha256:" + runtimeFiles[0].sha256 != runtime[0].files[0].sha256
			|| "sha256:" + Sha256.make(haxe.io.Bytes.ofString(runtimeFiles[0].contents)).toHex() != runtime[0].files[0].sha256)
			throw "nullable program runtime differs from its checked source manifest";
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != before)
			throw "nullable adaptation changed the original typed module";
		final output = ".tmp/shared-nullable-values-" + Std.string(Date.now().getTime()) + "-" + Std.random(0x3fffffff);
		final defines = new haxe.ds.StringMap<String>();
		defines.set("reflaxe_ocaml_runtime_directory", sys.FileSystem.absolutePath("packages/reflaxe.ocaml/std/runtime"));
		final context = new backend.BackendContext(sys.FileSystem.absolutePath(output), null, "Main", true, true, defines);
		new backend.ocaml.OcamlNativeTargetCore().emit(new MacroExpandedProgram([typed], false), context);
		if (File.getContent(output + "/" + OcamlTargetProgramCore.REPORT_FILE) != plan.reportJson("native-hxhx"))
			throw "native target wrapper changed the shared plan report";
		if (Sys.command(output + "/_build/default/" + OcamlTargetProgramCore.ENTRY_NAME + ".exe", []) != 0)
			throw "nullable application failed";
		File.copy("test/reflaxe_ocaml_shared_nullable_values/Observer.ml", output + "/Observer.ml");
		final cwd = Sys.getCwd();
		try {
			Sys.setCwd(output);
			final runtimeDirectory = Path.directory(runtimeFiles[0].path);
			if (Sys.command("ocamlopt", [
				"-I",
				runtimeDirectory.length == 0 ? "." : runtimeDirectory,
				runtimeFiles[0].path,
				"Main.ml",
				"Observer.ml",
				"-o",
				"nullable-observer.exe"
			]) != 0)
				throw "nullable observer failed to compile against the packaged runtime and emitted functions";
			if (Sys.command("./nullable-observer.exe", []) != 0)
				throw "nullable observer rejected the emitted values or runtime representation";
			Sys.setCwd(cwd);
		} catch (error:haxe.Exception) {
			Sys.setCwd(cwd);
			throw error;
		}
		Sys.println("REFLAXE_OCAML_SHARED_NULLABLE_VALUES:PASS");
	}
}
