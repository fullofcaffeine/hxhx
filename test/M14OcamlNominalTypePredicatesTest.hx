import backend.ocaml.Stage3OcamlClassStorage;
import backend.ocaml.Stage3OcamlRuntimeTypes;
import sys.io.File;
import sys.FileSystem;

/** Prove exact nominal predicates and rejection before native output is replaced. */
class M14OcamlNominalTypePredicatesTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function reject(action:Void->Void, diagnostic:String):Void {
		var rejected = false;
		try
			action()
		catch (error:String)
			rejected = error.indexOf(diagnostic) >= 0;
		require(rejected, "missing runtime type rejection: " + diagnostic);
	}

	static function typed(source:String):TypedModule {
		return M14Stage3RuntimeFixture.typeMain({source: source, path: "Main.hx", root: "."});
	}

	/** Equal spelling, a copied marker, and a stale operand cannot borrow the current program's facts. */
	static function ownership():Void {
		final source = "class Main { static var accepted:Bool = Std.isOfType(null, Main); static function check(value:Dynamic):Bool return value is Main; }";
		final first = typed(source);
		final second = typed(source);
		final storage = new Stage3OcamlClassStorage();
		for (owner in first.getBackendProjection().getClasses())
			storage.add(owner, false);
		final plan = new Stage3OcamlRuntimeTypes([first], storage);
		final fn = first.getBackendProjection().getClasses()[0].getFunctions()[0];
		final foreign = second.getBackendProjection().getClasses()[0].getFunctions()[0];
		final entry = fn.getRuntimeTypeCatalog().getEntries()[0];
		require(plan.occurrence(entry.getExpression(), fn, null) == entry, "exact runtime occurrence was not retained");
		reject(() -> plan.occurrence(entry.getExpression(), foreign, null), "foreign function projection");
		reject(() -> plan.occurrence(ECall(EIdent(TypedRuntimeTypeSource.TEST), [entry.getValue()]), fn, null), "absent from the current function projection");
		reject(() -> plan.render(foreign.getRuntimeTypeCatalog().getEntries()[0], "unused", null, value -> value), "foreign occurrence");
		final field = first.getBackendProjection().getClasses()[0].getFieldInitializers()[0];
		final foreignField = second.getBackendProjection().getClasses()[0].getFieldInitializers()[0];
		final fieldEntry = field.getRuntimeTypeCatalog().getEntries()[0];
		reject(() -> plan.occurrence(fieldEntry.getExpression(), null, foreignField), "foreign field initializer");
		var call:Null<HxExpr> = null;
		TypedBackendSourceWalk.expression(field.getExpression(), expression -> {
			if (TypedExactStaticCallSource.decode(expression) != null)
				call = expression;
		});
		final copied:HxExpr = switch call {
			case ECall(callee, arguments): ECall(callee, arguments.copy());
			case _: throw "predicate ownership fixture lost its exact call";
		};
		reject(() -> plan.renderCall(copied, null, field, _ -> "unused", null, value -> value), "exact typed call");
		switch entry.getExpression() {
			case ECall(_, arguments):
				arguments[0] = ENull;
			case _:
				throw "test requires a runtime marker";
		}
		reject(() -> entry.assertCurrent(), "mutated");
		// Simulate request cleanup after emission was interrupted. The server's
		// outer reset must release this plan even when normal scope unwinding did not.
		@:privateAccess EmitterStage.currentRuntimeTypes = plan;
		CompilerRequestStaticState.reset();
		require(@:privateAccess EmitterStage.currentRuntimeTypes == null, "request reset retained the previous runtime type plan");
		Sys.println("OCAML_NOMINAL_TYPE_OWNERSHIP:PASS");
	}

	/** Failed admission must preserve the previous artifact and create no additional files. */
	static function admission():Void {
		final previousTypes = @:privateAccess EmitterStage.currentRuntimeTypes;
		final previousClasses = @:privateAccess EmitterStage.currentClassStorage;
		final root = ".tmp/ocaml_nominal_type_rejection";
		FileSystem.createDirectory(root);
		final sentinel = root + "/Main.ml";
		File.saveContent(sentinel, "preserved native artifact\n");
		final before = FileSystem.readDirectory(root);
		before.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
		for (source in [
			"class Main { static var target = Main; static function main():Void {} }",
			"class Main { static function main():Void { Sys.println(Std.isOfType(1, Int)); } }",
			"extern class Host {} class Main { static function main():Void { Sys.println(Std.isOfType(null, Host)); } }",
			'@:native("Int") class NativeNamed {} class Main { static function main():Void { Sys.println(Std.isOfType(1, NativeNamed)); } }',
			'@:native("Same") class Left {} @:native("Same") class Right {} class Main { static function main():Void { Sys.println(Std.isOfType(null, Left)); } }'
		]) {
			var rejected = false;
			try
				EmitterStage.emitToDir(MacroStage.expandProgram([typed(source)], []), root, true, false)
			catch (error:String) {
				rejected = error.indexOf("does not support runtime type operands") >= 0
					|| error.indexOf("requires an admitted generated class") >= 0
					|| error.indexOf("require distinct runtime names") >= 0;
			}
			require(rejected, "unsupported type operand was admitted");
			require(@:privateAccess EmitterStage.currentRuntimeTypes == previousTypes, "rejected request leaked runtime type ownership");
			require(@:privateAccess EmitterStage.currentClassStorage == previousClasses, "rejected request leaked class storage ownership");
			final after = FileSystem.readDirectory(root);
			after.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
			require(before.join("\n") == after.join("\n") && File.getContent(sentinel) == "preserved native artifact\n",
				"rejected operand changed native output");
		}
		Sys.println("OCAML_NOMINAL_TYPE_ADMISSION:PASS");
		final program = MacroStage.expandProgram([
			typed("class Main { static function check(value:Main):Bool return value is Main; }")
		], []);
		reject(() -> backend.ocaml.MetalProfileVerifier.verifyProgram(program), "runtime type operation");
		final plan = backend.ocaml.PortableMetalizationPlanner.buildPlan(program, backend.OcamlProfile.Portable);
		final region = backend.ocaml.PortableMetalizationPlanner.functionRegionKey("Main.hx", "Main", "check");
		require(!plan.isAutoMetalized(region), "runtime class predicate bypassed portable representation selection");
		final reports = plan.toReport().regions.filter(row -> row.regionKey == region);
		require(reports.length == 1 && reports[0].status == "excluded" && reports[0].reasonCodes.indexOf("reflection_call") >= 0,
			"runtime class predicate lost its explicit portable representation reason");
		Sys.println("OCAML_NOMINAL_TYPE_PROFILE:PASS");
	}

	static function main():Void {
		ownership();
		admission();
		final root = "test/fixtures/ocaml_nominal_type_predicates";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final module = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		final program = MacroStage.expandProgram([module], []);
		final context = new backend.BackendContext(".tmp/ocaml_nominal_type_predicates", null, "Main", true, true,
			HxDefineMap.fromRawDefines(["ocaml_profile=portable"]));
		final result = new backend.ocaml.OcamlTargetCore().emit(program, context);
		require(result.builtExecutable, "native target did not build the predicate observer");
		M14Stage3RuntimeFixture.observe({command: result.entryPath, arguments: [], expected: expected});
		Sys.println("OCAML_NOMINAL_TYPE_RUNTIME:PASS");
	}
}
