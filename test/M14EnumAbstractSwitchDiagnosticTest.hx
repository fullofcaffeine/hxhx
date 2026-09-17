/** Checks ordinary switch diagnostics against independently observed Haxe 4.3.7 cases. */
class M14EnumAbstractSwitchDiagnosticTest {
	/** The explicit capture returns the scrutinee even when a constant shares its name. */
	static function checkForcedBindingRuntime():Void {
		final source = "enum abstract Signal(Int) { var Red = 10; var Blue = 20; }\n"
			+ "class Main { static function select(value:Signal):Signal { return switch(value) { case var Red: Red; }; }"
			+ "static function main():Void { Sys.println(select(Signal.Blue)); } }";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = MacroStage.expandProgram([typed], []);
		final outputDir = ".tmp/m14_enum_switch_capture_" + Std.string(Date.now().getTime());
		sys.FileSystem.createDirectory(outputDir);
		final outputPath = outputDir + "/main.js";
		new backend.js.JsBackend().emit(program,
			new backend.BackendContext(outputDir, outputPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		final process = new sys.io.Process("node", [outputPath]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != "20\n")
			throw "forced binding runtime mismatch: " + output + errors;
	}

	/** Alias-value edits change public typing behavior even without an explicit field read. */
	static function checkDomainRevision():Void {
		function revision(aliasValue:Int):CompilerTypedModuleRevision {
			final source = "enum abstract Signal(Int) { var Red = 10; var Alias = " + aliasValue + "; var Blue = 20; }";
			final resolved = new ResolvedModule("Signal", "Signal.hx", ParserStage.parse(source, "Signal.hx"));
			final index = TyperIndex.build([resolved]);
			final domain = index.getAbstractByFullName("Signal").getEnumDomain();
			final members = domain.getMembers();
			if (members.length != 3
				|| members[0].field.getName() != "Red"
				|| members[1].field.getName() != "Alias"
				|| members[2].field.getName() != "Blue"
				|| members[0].position.line != 1)
				throw "enum domain lost declaration order or source positions";
			return CompilerTypedModuleRevision.fromTypedModule(TyperStage.typeResolvedModule(resolved, index));
		}
		if (revision(10).publicInterfaceRevision == revision(30).publicInterfaceRevision)
			throw "enum value change was invisible to dependent switch typing";

		function snapshot(aliasValue:Int):CompilerDependencySnapshot {
			final provider = "enum abstract Signal(Int) { var Red=10; var Alias=" + aliasValue + "; var Blue=20; }";
			final consumer = "class Main { static function select(value:Signal):Int { return switch(value) { case Red: 1; case Blue: 2; default: 3; }; } }";
			final resolved = [
				new ResolvedModule("Signal", "Signal.hx", ParserStage.parse(provider, "Signal.hx")),
				new ResolvedModule("Main", "Main.hx", ParserStage.parse(consumer, "Main.hx"))
			];
			final index = TyperIndex.build(resolved);
			return CompilerDependencyCollector.collect([for (module in resolved) TyperStage.typeResolvedModule(module, index)], index);
		}
		final before = snapshot(10);
		final after = snapshot(30);
		if (before.findModule("Main").sourceRevision != after.findModule("Main").sourceRevision)
			throw "dependency control unexpectedly changed the consumer source";
		if (!CompilerDependencyInvalidator.compare(before, after).isAffected("Main"))
			throw "enum domain edit did not invalidate its unchanged switch consumer";
	}

	static function check(name:String, declaration:String, patterns:String, expected:Null<String>, statement:Bool = false):Void {
		final source = declaration + "\nclass Main {\n" + "static function select(value:Signal, flag:Bool):" + (statement ? "Void" : "Int") + " {\n"
			+ (statement ? "" : "return ") + "switch(value) { " + patterns + " };\n}\nstatic function main():Void {}\n}\n";
		final path = name + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		var observed:Null<TyperError> = null;
		try {
			TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		} catch (error:TyperError) {
			observed = error;
		}
		if (expected == null) {
			if (observed != null)
				throw name + " unexpectedly failed: " + observed.toString();
		} else {
			if (observed == null)
				throw name + " accepted an incomplete switch; expected " + expected;
			if (observed.message != expected || observed.filePath != path || observed.pos.line != 4 || observed.pos.column <= 0)
				throw name + " reported the wrong diagnostic or source position: " + observed.toString();
		}
	}

	static function main():Void {
		Sys.putEnv("HXHX_TYPER_STRICT", "1");
		final signal = "enum abstract Signal(Int) { var Red = 10; var Blue = 20; }";
		check("missing", signal, "case Red: 1;", "Unmatched patterns: Blue");
		check("independent", "enum abstract Signal(Int) { var Idle = 7; var Busy = 9; }", "case Idle: 1;", "Unmatched patterns: Busy");
		check("complete", signal, "case Red: 1; case Blue: 2;", null);
		check("default", signal, "case Red: 1; default: 2;", null);
		check("wildcard", signal, "case _: 2;", null);
		check("binding", signal, "case value: 2;", null);
		check("forced_binding", signal, "case var Red: 2;", null);
		check("or", signal, "case Red | Blue: 1;", null);
		check("qualified", signal, "case Signal.Red: 1;", "Unmatched patterns: Blue");
		check("statement", signal, "case Red: Sys.println(1);", "Unmatched patterns: Blue", true);
		check("guard", signal, "case Red if (flag): 1; case Blue: 2;", "Unmatched patterns: Red");
		check("true_guard", signal, "case Red if (true): 1; case Blue: 2;", "Unmatched patterns: Red");
		check("guard_fallback", signal, "case Red if (flag): 1; case Red: 3; case Blue: 2;", null);
		check("guarded_capture_only", signal, "case var Red if (flag): 1;", "Unmatched patterns: _");
		check("guarded_wildcard_only", signal, "case _ if (flag): 1;", "Unmatched patterns: _");
		check("guarded_binding_only", signal, "case value if (flag): 1;", "Unmatched patterns: _");
		check("guarded_capture_then_member", signal, "case var value if (flag): 1; case Red: 2;", "Unmatched patterns: Blue");
		check("member_then_guarded_capture", signal, "case Red: 2; case var value if (flag): 1;", "Unmatched patterns: Blue");
		check("guarded_capture_and_member", signal, "case var value if (flag): 1; case Red if (flag): 2;", "Unmatched patterns: Blue | Red");
		check("guarded_capture_complete", signal, "case var value if (flag): 1; case Red: 2; case Blue: 3;", null);
		check("guarded_capture_default", signal, "case var value if (flag): 1; default: 2;", null);
		check("guarded_or_members", signal, "case Red | Blue if (flag): 1;", "Unmatched patterns: Blue | Red");
		check("guarded_wildcard_or_member", signal, "case _ | Red if (flag): 1;", "Unmatched patterns: Blue | Red");
		check("guarded_member_or_wildcard", signal, "case Red | _ if (flag): 1;", "Unmatched patterns: Blue | Red");
		check("invalid_guard_member", signal, "case Missing if (flag): 1; default: 2;", "Cannot analyze enum-abstract switch: unresolved enum pattern Missing");
		final aliases = "enum abstract Signal(Int) { var Red = 10; var Alias = 10; var Blue = 20; }";
		check("alias_coverage", aliases, "case Alias: 1; case Blue: 2;", null);
		check("alias_witness", aliases, "case Blue: 2;", "Unmatched patterns: Red");
		check("witness_order", "enum abstract Signal(Int) { var Red = 10; var Blue = 20; var Green = 30; }", "case Red if (flag): 1;",
			"Unmatched patterns: Blue | Green | Red");
		check("string", "enum abstract Signal(String) { var Red = 'red'; var Blue = 'blue'; }", "case Red: 1;", "Unmatched patterns: Blue");
		check("bool", "enum abstract Signal(Bool) { var Red = true; var Blue = false; }", "case Red: 1;", "Unmatched patterns: Blue");
		check("ordinary_int", "typedef Signal = Int;", "case 10: 1; default: 2;", null);
		checkDomainRevision();
		checkForcedBindingRuntime();
		Sys.println("ENUM_ABSTRACT_SWITCH_DIAGNOSTICS:PASS");
	}
}
