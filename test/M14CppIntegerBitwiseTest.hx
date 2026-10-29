import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare integer bit operations with upstream, then prove native execution and sanitizer safety. */
class M14CppIntegerBitwiseTest {
	static function execute(command:String, arguments:Array<String>):Void {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "integer bitwise runtime assertions failed: " + stdout + stderr;
	}

	/** Bit operators must not admit dynamic values or unrelated scalar types. */
	static function rejected(left:TyType, right:TyType):Void {
		for (op in ["&", "|", "^", "<<", ">>", ">>>"]) {
			try {
				backend.cpp.CppManagedInteger.compute(op, left, right, "left", "right", "result", "negative_", "");
			} catch (failure:haxe.Exception) {
				if (failure.message.indexOf("requires exact Int or nullable Int operands") >= 0)
					continue;
				throw failure;
			}
			throw "integer bit operation accepted an unrelated type";
		}
	}

	static function main():Void {
		final root = "test/oracle/cpp_integer_bitwise_seed";
		execute("haxe", ["-cp", root, "-main", "EvalMain", "--interp"]);
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final revisions = [
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					CompilerTypedTreeRevision.functionBody(fn)
		];
		final integer = TyType.fromHintText("Int");
		for (hint in ["Float", "Bool", "String", "Dynamic", "Null<Float>"]) {
			rejected(integer, TyType.fromHintText(hint));
			rejected(TyType.fromHintText(hint), integer);
		}
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules([typed], index), false);
		final result = CppTargetCore.emit(program, new BackendContext(".tmp/cpp-integer-bitwise", null, "Main", true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "integer bitwise fixture did not build";
		execute(result.entryPath, []);
		final after = [
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					CompilerTypedTreeRevision.functionBody(fn)
		];
		if (revisions.join("\n") != after.join("\n"))
			throw "integer bit emission changed authored source";
		CppManagedAssertionFixture.sanitizers(".tmp/cpp-integer-bitwise", "CPP_INTEGER_BITWISE");
		Sys.println("CPP_INTEGER_BITWISE:PASS");
	}
}
