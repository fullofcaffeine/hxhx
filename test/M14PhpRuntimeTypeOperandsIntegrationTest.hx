import backend.BackendContext;
import backend.BackendRegistry;
import backend.GenIrProgram;
import backend.source.PhpTypedProgramProjection;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/** Proves runtime-type behavior and exact occurrence rejection through the PHP consumer. */
class M14PhpRuntimeTypeOperandsIntegrationTest {
	static function run(command:String, args:Array<String>):String {
		final child = new Process(command, args);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0)
			throw command + " failed: " + stderr;
		return StringTools.replace(stdout, "\r\n", "\n");
	}

	static function program(name:String):GenIrProgram {
		final path = "test/php_runtime_type_operands/src/" + name + ".hx";
		final module = new ResolvedModule(name, path, ParserStage.parse(File.getContent(path), path));
		return MacroStage.expandProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], []);
	}

	static function reject(action:Void->Void, expected:String):Void {
		try
			action()
		catch (error:String) {
			if (error.indexOf(expected) >= 0)
				return;
			throw "unexpected rejection: " + error;
		}
		throw "expected rejection: " + expected;
	}

	static function checkOccurrenceOwnership():Void {
		final projection = new PhpTypedProgramProjection(program("Main"));
		final main = projection.requireMain("Main").main;
		final plan = projection.requireFunctionLoweringPlan(main.getDeclaration());
		final original = main.getRuntimeTypeCatalog().getEntries()[0].getExpression();
		plan.requireRuntimeType(original);
		final copied:HxExpr = switch (original) {
			case ECall(callee, arguments): ECall(callee, arguments.copy());
			case _: throw "fixture lost its runtime type operand";
		};
		reject(() -> {
			plan.requireRuntimeType(copied);
		}, "absent from the current function projection");
		final other = new PhpTypedProgramProjection(program("Main")).requireMain("Main").main;
		reject(() -> {
			plan.requireRuntimeType(other.getRuntimeTypeCatalog().getEntries()[0].getExpression());
		}, "absent from the current function projection");
		switch (original) {
			case ECall(_, arguments):
				arguments.push(EString("changed"));
				reject(() -> {
					plan.requireRuntimeType(original);
				}, "marker was mutated");
				arguments.pop();
			case _:
				throw "fixture lost its runtime type operand";
		}
		main.getBody().resize(0);
		reject(() -> {
			plan.requireRuntimeType(original);
		}, "absent from the current function projection");
	}

	/** A typed reference whose provider is omitted from the output program must fail before publication. */
	static function checkMissingProvider(root:String):Void {
		final main = new ResolvedModule("Main", "Main.hx",
			ParserStage.parse("import foreign.Provider; class Main { static function main() { var value = Provider; } }", "Main.hx"));
		final provider = new ResolvedModule("foreign.Provider", "foreign/Provider.hx",
			ParserStage.parse("package foreign; class Provider {}", "foreign/Provider.hx"));
		final index = TyperIndex.build([main, provider]);
		final incomplete = MacroStage.expandProgram([TyperStage.typeResolvedModule(main, index)], []);
		for (previous in [false, true]) {
			final output = Path.join([root, previous ? "existing" : "missing"]);
			final artifact = Path.join([output, "index.php"]);
			if (previous) {
				FileSystem.createDirectory(output);
				File.saveContent(artifact, "previous-output\n");
			}
			reject(() -> {
				BackendRegistry.requireForTarget("php-native")
					.emit(incomplete, new BackendContext(output, artifact, "Main", true, false, new StringMap<String>()));
			}, "PHP runtime type operand has no emitted declaration");
			if (previous) {
				if (File.getContent(artifact) != "previous-output\n" || FileSystem.readDirectory(output).length != 1)
					throw "unsupported PHP operand changed existing output";
			} else if (FileSystem.exists(output))
				throw "unsupported PHP operand published output";
		}
	}

	/** Replacing syntax with equal copies must be rejected before even creating an output directory. */
	static function checkCopiedPublication(root:String):Void {
		final altered = program("Main");
		final main = new PhpTypedProgramProjection(altered).requireMain("Main").main;
		final body = main.getBody();
		final copied = backend.source.SourceFunctionBodyRewriter.body(body, expression -> expression);
		body.resize(0);
		for (statement in copied)
			body.push(statement);
		final output = Path.join([root, "copied"]);
		reject(() -> {
			BackendRegistry.requireForTarget("php-native").emit(altered, new BackendContext(output, null, "Main", true, false, new StringMap<String>()));
		}, "not an exact occurrence");
		if (FileSystem.exists(output))
			throw "copied PHP operand published output";
	}

	static function main():Void {
		checkOccurrenceOwnership();
		final root = ".tmp/m14_php_runtime_types_" + Std.string(Date.now().getTime());
		checkMissingProvider(root);
		checkCopiedPublication(root);
		final native = Sys.command("sh", ["-c", "command -v php >/dev/null 2>&1"]) == 0;
		for (name in ["Main", "TypeTests"]) {
			final expected = File.getContent("test/php_runtime_type_operands/" + (name == "Main" ? "expected.stdout" : "types.stdout"));
			if (run("haxe", ["-cp", "test/php_runtime_type_operands/src", "-main", name, "--interp"]) != expected)
				throw "upstream runtime type behavior changed for " + name;
			final result = BackendRegistry.requireForTarget("php-native")
				.emit(program(name), new BackendContext(Path.join([root, name]), null, name, true, false, new StringMap<String>()));
			if (native) {
				final actual = run("php", [result.entryPath]);
				if (actual != expected)
					throw "PHP runtime type behavior differs from upstream for " + name + ":\n" + actual;
			}
		}
		Sys.println(native ? "PHP_RUNTIME_TYPE_OPERANDS:PASS native" : "PHP_RUNTIME_TYPE_OPERANDS:PASS source only; PHP unavailable");
	}
}
