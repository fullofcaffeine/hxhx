import sys.io.File;

/** Compare declaration selection with independently executed upstream programs. */
class M14AbstractBinarySelectionOrderTest {
	/** Prove the shared selection reaches a real executable without changing evaluation order. */
	static function native(name:String):Void {
		final root = "test/oracle/abstract_binary_selection_order/" + name;
		function observe(command:String, args:Array<String>):Void {
			final process = new sys.io.Process(command, args);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stdout != "" || stderr != "")
				throw "operator selection runtime differs: " + stdout + stderr;
		}
		observe("haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final fixture = CppResolvedFixture.load({
			sourceRoot: root,
			mainModule: "Main",
			requiredModules: name == "method_effects" ? ["haxe.Exception", "haxe.ValueException"] : []
		});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final program = CppResolvedFixture.prepare(fixture);
		final result = backend.cpp.CppTargetCore.emit(program,
			new backend.BackendContext(".tmp/abstract-binary-selection-order-" + name, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "operator selection did not build a native executable";
		for (i in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[i]).getCanonicalIdentity() != revisions[i])
				throw "operator selection changed its typed input";
		program.assertTypedBodyRevisionsCurrent();
		observe(result.entryPath, []);
		Sys.println("ABSTRACT_BINARY_SELECTION:" + name + ":PASS");
	}

	static function check(name:String, left:String, right:String, op:String, selected:String, expected:String, reverse:Bool = false):Void {
		final root = "test/oracle/abstract_binary_selection_order/" + name;
		final upstream = new sys.io.Process("haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final stdout = upstream.stdout.readAll().toString();
		final stderr = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (selected == "") {
			if (code == 0 || stderr.indexOf("String should be Number") < 0)
				throw "upstream accepted incompatible compound result: " + stdout + stderr;
		} else if (code != 0 || stdout != expected + "\n" || stderr != "") {
			throw "upstream operator selection differs for " + name + ": " + stdout + stderr;
		}
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		function type(name:String):TyType {
			final owner = index.getAbstractByFullName("Main." + name);
			return owner == null ? TyType.fromHintText(name) : TyType.nominal(owner.getIdentity(), []);
		}
		try {
			final binding = TyAbstractBinaryBinding.select(index, type(left), type(right), op, path, HxPos.unknown());
			if (selected == ""
				|| binding == null
				|| binding.getOperatorInfo().getDeclaration().getSignature().getName() != selected
				|| binding.getReverseArguments() != reverse)
				throw "local operator selection differs for " + name;
		} catch (error:TyperError) {
			if (selected != "" || error.message.indexOf("No applicable abstract binary operator") < 0)
				throw error;
		}
		Sys.println("ABSTRACT_BINARY_SELECTION:" + name + ":PASS");
	}

	static function main():Void {
		check("general_first", "Int", "Number", "/", "general", "general");
		check("method_conversion_first", "Int", "Number", "/", "general", "general");
		check("specific_first", "Int", "Number", "/", "specific", "specific");
		check("equal_candidates", "Int", "Number", "/", "first", "first");
		check("skip_inapplicable", "Int", "Number", "/", "specific", "specific");
		check("commutative_first", "Int", "Number", "/", "reversed", "reversed", true);
		check("direct_before_reverse", "Int", "Number", "/", "orient", "24", true);
		check("left_owner", "Left", "Right", "/", "left", "left");
		check("right_after_left_miss", "Left", "Right", "/", "right", "right");
		check("compound_result", "Number", "Int", "+=", "", "");
		check("compound_explicit", "Number", "Int", "+=", "explicit", "4:9");
		native("native");
		native("method_effects");
	}
}
