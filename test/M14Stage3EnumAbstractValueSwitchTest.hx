import sys.io.File;

/**
	Lower value switches that cover every member of an Int-backed enum abstract.
	Std `XmlType(Int).toString` returns a switch over all seven values with no
	default arm. Upstream Haxe 4.3.7 accepts that switch as exhaustive, but the
	native lowering refused to store its result because it also demanded a null
	arm. An exact Int, Float, or Bool backing cannot hold null, so its declared
	members are enough; String and object backings still need the null arm. The
	test runs a user fixture natively against upstream output, keeps the
	missing-member rejection that upstream reports, and lowers every typed body
	that `Xml.parse` loads, including `XmlType.toString`.
 */
class M14Stage3EnumAbstractValueSwitchTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Report whether upstream Haxe 4.3.7 accepts a program and return its output. */
	static function upstream(directory:String):{accepted:Bool, output:String} {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", directory, "-main", "Main", "--no-output"]);
		final output = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		return {accepted: status == 0, output: output};
	}

	static function main():Void {
		final root = "test/fixtures/stage3_enum_abstract_value_switch";
		final path = root + "/Main.hx";
		final source = File.getContent(path);
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_ENUM_ABSTRACT_VALUE_SWITCH_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: source, path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/stage3_enum_abstract_value_switch", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_ENUM_ABSTRACT_VALUE_SWITCH_NATIVE:PASS");

		// Dropping a member without a default arm stays an error, as upstream reports it.
		final missing = ".tmp/stage3-enum-abstract-value-switch-missing";
		sys.FileSystem.createDirectory(missing);
		final missingSource = StringTools.replace(source, 'case Beta | Gamma: "BG";', 'case Beta: "B";');
		require(missingSource != source, "fixture lost the alternative arm used by the missing-member control");
		File.saveContent(missing + "/Main.hx", missingSource);
		final reference = upstream(missing);
		require(!reference.accepted && reference.output.indexOf("Unmatched patterns: Gamma") >= 0,
			"upstream missing-member result changed: " + reference.output);
		var rejection:Null<TyperError> = null;
		try {
			M14Stage3RuntimeFixture.typeMain({source: missingSource, path: missing + "/Main.hx", root: missing});
		} catch (error:TyperError) {
			rejection = error;
		}
		require(rejection != null && rejection.message == "Unmatched patterns: Gamma", "missing enum abstract member was accepted");
		Sys.println("M14_STAGE3_ENUM_ABSTRACT_VALUE_SWITCH_MISSING:PASS");

		// The CI Xml.parse program loads std Xml; every loaded body must lower.
		final xml = ".tmp/stage3-enum-abstract-value-switch-xml";
		sys.FileSystem.createDirectory(xml);
		final xmlSource = 'class Main {static function main() {var x = Xml.parse("<a/>"); Sys.println("ok");}}\n';
		File.saveContent(xml + "/Main.hx", xmlSource);
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", xml, "--run", "Main"], expected: "ok\n"});
		var xmlTypeFunctions = 0;
		for (module in M14Stage3RuntimeFixture.prepareProgram({source: xmlSource, path: xml + "/Main.hx", root: xml}))
			for (owner in module.getTypedClasses())
				for (method in owner.getFunctions()) {
					TypedControlLowering.functionBody(method);
					if (module.getSourceOrigin().sourceModulePath == "Xml"
						&& HxClassDecl.getName(owner.getSourceDeclaration()) == "XmlType")
						xmlTypeFunctions++;
				}
		require(xmlTypeFunctions > 0, "Xml.parse did not load the std XmlType abstract body");
		Sys.println("M14_STAGE3_ENUM_ABSTRACT_VALUE_SWITCH_XML:PASS");
	}
}
