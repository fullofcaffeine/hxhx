import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare authored scalar-abstract switches with upstream and execute the emitted native program. */
class M14CppAbstractSwitchTest {
	/** Backing storage does not authorize non-scalar inputs or patterns that need new bindings. */
	static function rejected(plan:backend.cpp.CppManagedCastPlan, type:TyType, pattern:HxSwitchPattern, message:String):Void {
		try {
			backend.cpp.CppManagedSwitch.render({
				value: EInt(0),
				type: type,
				casts: plan,
				patterns: [pattern],
				heap: "heap",
				prefix: "switch_test_",
				renderValue: (_, _, _) -> [],
				renderBody: (_, _) -> []
			}, "");
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(message) >= 0)
				return;
			throw failure;
		}
		throw "unsupported abstract switch was accepted";
	}

	static function execute(command:String, arguments:Array<String>):Void {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "abstract switch runtime assertions failed: " + stdout + stderr;
	}

	static function main():Void {
		final root = "test/oracle/cpp_abstract_switch_seed";
		execute("haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final revisions = [
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					CompilerTypedTreeRevision.functionBody(fn)
		];
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules([typed], index), false);
		final plan = new backend.cpp.CppManagedCastPlan(new backend.cpp.CppTypedProgramProjection(program));
		final box = index.getAbstractByFullName("Main.Box");
		if (box == null)
			throw "abstract switch fixture lost its generic declaration";
		for (type in [TyType.fromHintText("Dynamic"), TyType.fromHintText("Float")])
			rejected(plan, TyType.nominal(box.getIdentity(), [type]), PWildcard, "exact supported scalar type");
		final integerBox = TyType.nominal(box.getIdentity(), [TyType.fromHintText("Int")]);
		rejected(plan, integerBox, PBind("value"), "exact matching or binding support");
		rejected(plan, integerBox, PBool(false), "exact matching or binding support");
		final result = CppTargetCore.emit(program, new BackendContext(".tmp/cpp-abstract-switch", null, "Main", true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "abstract switch fixture did not build";
		execute(result.entryPath, []);
		final after = [
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					CompilerTypedTreeRevision.functionBody(fn)
		];
		if (after.join("\n") != revisions.join("\n"))
			throw "abstract switch emission changed authored source";
		CppManagedAssertionFixture.sanitizers(".tmp/cpp-abstract-switch", "CPP_ABSTRACT_SWITCH");
		Sys.println("CPP_ABSTRACT_SWITCH:PASS");
	}
}
