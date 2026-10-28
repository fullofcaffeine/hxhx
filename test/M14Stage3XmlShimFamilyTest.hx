import sys.io.File;

/**
	Keep the Stage3 Xml bring-up shims and the emitted program consistent.
	Stage3 serves `Xml` with a small OCaml shim instead of the std body. Now that
	std `Xml.hx` types, its body loads `haxe.xml.Parser` and `haxe.xml.Printer`,
	whose bodies call the real Xml API (`Xml.iterator`), so the native build failed
	with an unbound OCaml value. The whole Xml family is shim-served: none of those
	std bodies is emitted. Program code that calls an Xml member the shims do not
	define is rejected before the native build with a message naming the member.
	This mirrors the two Stage3 e2e steps in scripts/test-hxhx-targets.sh.
 */
class M14Stage3XmlShimFamilyTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Start from an empty output directory; emission leaves earlier units in place. */
	static function clean(directory:String):String {
		function remove(path:String):Void {
			if (!sys.FileSystem.exists(path))
				return;
			if (sys.FileSystem.isDirectory(path)) {
				for (entry in sys.FileSystem.readDirectory(path))
					remove(path + "/" + entry);
				sys.FileSystem.deleteDirectory(path);
			} else
				sys.FileSystem.deleteFile(path);
		}
		remove(directory);
		return directory;
	}

	/** Write a one-file program and prepare it with every provider module typing loaded. */
	static function prepare(name:String, body:String):{directory:String, modules:Array<TypedModule>} {
		final directory = ".tmp/stage3-xml-shim-family-" + name;
		sys.FileSystem.createDirectory(directory);
		final source = 'class Main {static function main() {' + body + '}}\n';
		File.saveContent(directory + "/Main.hx", source);
		return {
			directory: directory,
			modules: M14Stage3RuntimeFixture.prepareProgram({source: source, path: directory + "/Main.hx", root: directory})
		};
	}

	static function main():Void {
		// Step "Xml.parse collapses to bring-up poison": the program builds and runs.
		final parse = prepare("parse", 'var x = Xml.parse("<a/>"); Sys.println("ok");');
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", parse.directory, "--run", "Main"], expected: "ok\n"});
		final parseOut = clean(".tmp/stage3_xml_shim_family_parse");
		final parseArtifact = EmitterStage.emitToDir(new MacroExpandedProgram(parse.modules, false), parseOut, true);
		M14Stage3RuntimeFixture.observe({command: parseArtifact, arguments: [], expected: "ok\n"});
		for (module in ["Haxe_xml_Printer.ml", "Haxe_xml_Parser.ml", "Xml.ml"])
			require(sys.FileSystem.exists(parseOut + "/" + module) == (module != "Haxe_xml_Printer.ml"), "Xml family module selection changed for " + module);
		require(File.getContent(parseOut + "/Haxe_xml_Parser.ml").indexOf("bootstrap shim") >= 0, "std haxe.xml.Parser body was emitted");
		Sys.println("M14_STAGE3_XML_SHIM_FAMILY_PARSE:PASS");

		// Step "Xml.createElement camelCase constructor mapping links": compile-only.
		final create = prepare("create", 'var xml = Xml.createElement("node"); Sys.println(xml.nodeName);');
		final createArtifact = EmitterStage.emitToDir(new MacroExpandedProgram(create.modules, false), clean(".tmp/stage3_xml_shim_family_create"), true);
		require(sys.FileSystem.exists(createArtifact), "Xml.createElement program did not link");
		Sys.println("M14_STAGE3_XML_SHIM_FAMILY_CREATE:PASS");

		// Real Xml API the shims do not define fails before the native build.
		final unsupported = prepare("unsupported", 'var x = Xml.parse("<a/>"); Sys.println(x.firstElement().nodeName);');
		var message:Null<String> = null;
		try {
			EmitterStage.emitToDir(new MacroExpandedProgram(unsupported.modules, false), clean(".tmp/stage3_xml_shim_family_unsupported"), true);
		} catch (error:String) {
			message = error;
		}
		require(message != null && message.indexOf("Main calls Xml.firstElement") >= 0 && message.indexOf("bring-up shims") >= 0,
			"unsupported Xml call was not rejected clearly: " + message);
		Sys.println("M14_STAGE3_XML_SHIM_FAMILY_UNSUPPORTED:PASS");
	}
}
