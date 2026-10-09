import backend.js.JsClassInheritancePlan;
import backend.js.JsWriter;

/** Exact constructor selection must retain declaration order, payload names, identity, and argument evaluation. */
class M14JsEnumConstructionTest {
	static function rejects(action:Void->Void, message:String):Void {
		var rejected = false;
		try {
			action();
		} catch (error:String) {
			rejected = error.indexOf(message) >= 0;
		}
		if (!rejected)
			throw "enum construction did not reject " + message;
	}

	static function main():Void {
		final source = "enum Item { Empty; Payload(value:Int, ?note:String); } enum Other { Payload(value:Int); } class Main { static function main():Void {} }";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([typed], false);
		final plan = new JsClassInheritancePlan(program);
		final item = plan.requireRuntimeEnum("Main.Item");
		final other = plan.requireRuntimeEnum("Main.Other");
		final writer = new JsWriter();
		writer.writeln("var $hxEnums = Object.create(null);");
		backend.js.JsEnumDeclaration.emit(writer, {constructors: item.enumConstructors, reference: item.reference, runtimeName: item.fullName});
		backend.js.JsEnumDeclaration.emit(writer, {constructors: other.enumConstructors, reference: other.reference, runtimeName: other.fullName});
		writer.writeln("var calls=0; function next(){ calls++; return 7; }");
		writer.writeln("var value=" + backend.js.JsEnumDeclaration.construct(item, "Payload", ["next()", '"note"']) + ";");
		writer.writeln("var omitted=" + backend.js.JsEnumDeclaration.construct(item, "Payload", ["8"]) + ";");
		writer.writeln("var empty=" + backend.js.JsEnumDeclaration.construct(item, "Empty", []) + ";");
		writer.writeln("var other=" + backend.js.JsEnumDeclaration.construct(other, "Payload", ["9"]) + ";");
		writer.writeln('if(calls!==1 || value._hx_index!==1 || value.value!==7 || value.note!=="note" || omitted.note!==null || empty._hx_index!==0) throw Error("payload");');
		writer.writeln('if(other.__enum__===value.__enum__ || other._hx_index!==0 || $$hxEnums[value.__enum__].__constructs__[1].__params__.join(",")!=="value,note") throw Error("owner");');
		writer.writeln('console.log("ENUM_CONSTRUCTION_RUNTIME:PASS");');
		final root = JsRuntimeFixture.reserveOutput();
		final script = root + "/constructors.js";
		sys.io.File.saveContent(script, writer.toString());
		if (@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("node", [script]) != "ENUM_CONSTRUCTION_RUNTIME:PASS\n")
			throw "enum construction runtime output differs";
		rejects(() -> {
			plan.requireRuntimeEnum("Item");
		}, "exact retained provider");
		rejects(() -> {
			plan.requireRuntimeEnum("Main");
		}, "exact retained provider");
		rejects(() -> {
			backend.js.JsEnumDeclaration.construct(item, "Absent", []);
		}, "absent or ambiguous");
		rejects(() -> {
			backend.js.JsEnumDeclaration.construct(item, "Empty", ["1"]);
		}, "cannot receive arguments");
		rejects(() -> {
			backend.js.JsEnumDeclaration.construct(item, "Payload", []);
		}, "missing a required argument");
		rejects(() -> {
			backend.js.JsEnumDeclaration.construct(item, "Payload", ["1", "2", "3"]);
		}, "argument count differs");
		Sys.println("JS_ENUM_CONSTRUCTION:PASS");
	}
}
