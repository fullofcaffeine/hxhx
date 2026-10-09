import sys.io.File;

/** Imported enum constructors constrain generic arguments with their exact declaration type. */
class M14EnumImportConstraintTest {
	static function main():Void {
		for (directive in ["import Entries.Entry;", "import Entries;", "import Entries.Entry as Renamed;"])
			check(directive, false);
		check("", true);
		precedence();
	}

	/** A module import keeps declaration order; later explicit type imports shadow earlier ones. */
	static function precedence():Void {
		final root = ".tmp/enum_import_constraint_precedence";
		sys.FileSystem.createDirectory(root);
		final entries = 'enum First{Shared;}enum Second{Shared;}';
		File.saveContent(root + "/Entries.hx", entries);
		for (row in [
			{directive: "import Entries;", expected: "First"},
			{directive: "import Entries.First;import Entries.Second;", expected: "Second"},
			{directive: "import Entries.Second;import Entries.First;", expected: "First"}
		]) {
			final source = row.directive + 'class Main{static function main():Void{var value=Shared;Sys.println(Type.getEnumName(Type.getEnum(value)));}}';
			File.saveContent(root + "/Main.hx", source);
			final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || output != row.expected + "\n")
				throw "upstream enum precedence differs: " + output + errors;
			final main = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
			final enums = new ResolvedModule("Entries", root + "/Entries.hx", ParserStage.parse(entries, root + "/Entries.hx"));
			final typed = TyperStage.typeResolvedModule(main, TyperIndex.build([enums, main]));
			final selected = [
				for (cls in typed.getTypedClasses())
					for (fn in cls.getFunctions())
						for (local in fn.getEnvironment().getLocals())
							if (local.getName() == "value")
								local.getType().getSemanticKey()
			];
			if (selected.length != 1 || selected[0] != "nominal:Entries." + row.expected)
				throw "local enum precedence differs";
			Sys.println("ENUM_IMPORT_PRECEDENCE:PASS " + row.directive);
		}
	}

	/** Keep a real indexed generic method, so a guessed String cannot pass as an unconstrained value. */
	static function check(directive:String, sameModule:Bool):Void {
		final root = ".tmp/enum_import_constraint_"
			+ (sameModule ? "local" : directive.indexOf("as") >= 0 ? "alias" : directive.indexOf(".Entry") >= 0 ? "type" : "module");
		sys.FileSystem.createDirectory(root);
		final declaration = 'enum Entry{Native;Module(name:String);}';
		final enumName = directive.indexOf("as") >= 0 ? "Renamed" : "Entry";
		final source = (sameModule ? declaration : directive)
			+ 'class Bag<T>{public function new(){}public function push(value:T):Void{}}class Main{static function entries():Bag<'
			+ enumName
			+ '>{var values=new Bag();values.push(Native);values.push(Module("test"));return values;}static function read(value:'
			+ enumName
			+
			'):Int{return switch(value){case Native:1;case Module(text):text.length;};}static function main():Void{Sys.println(entries()!=null);Sys.println(read(Native));Sys.println(read(Module("text")));}}';
		File.saveContent(root + "/Main.hx", source);
		File.saveContent(root + "/Entries.hx", declaration);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != "true\n1\n4\n")
			throw "upstream enum import differs: " + directive + output + errors;
		final main = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final enums = new ResolvedModule("Entries", root + "/Entries.hx", ParserStage.parse(declaration, root + "/Entries.hx"));
		final index = TyperIndex.build(sameModule ? [main] : [enums, main]);
		final typed = TyperStage.typeResolvedModule(main, index);
		final owner = (sameModule ? "Main" : "Entries") + ".Entry";
		var fields = 0;
		var calls = 0;
		function inspect(node:TypedExpr):Void {
			final field = node.getFieldInfo();
			if (field != null && field.getName() == "Native") {
				if (field.getOwner().getCanonicalName() != owner || node.getType().getSemanticKey() != "nominal:" + owner)
					throw "nullary enum value lost its exact declaration";
				fields++;
			}
			final selected = node.getDeclaration();
			if (node.getTag() == Call && selected != null && selected.getIsEnumConstructor()) {
				if (selected.getOwner().getCanonicalName() != owner || node.getType().getSemanticKey() != "nominal:" + owner)
					throw "payload constructor lost its exact declaration";
				calls++;
			}
			for (child in node.getExpressions())
				inspect(child);
		}
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				for (statement in fn.getBody().getStatements())
					for (node in statement.getExpressions())
						inspect(node);
		if (fields != 2 || calls != 2)
			throw "enum import did not retain both constructor categories";
		final revision = typed.getRevision();
		typed.getBackendProjection();
		if (typed.getRevision() != revision)
			throw "enum projection mutated typed facts";
		#if enum_import_ocaml
		// The emitter's first module owns the executable entry point.
		final modules = sameModule ? [typed] : [typed, TyperStage.typeResolvedModule(enums, index)];
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(modules, false), root + "/ocaml", true);
		final native = new sys.io.Process("gtimeout", ["30", executable]);
		final nativeOutput = native.stdout.readAll().toString();
		final nativeErrors = native.stderr.readAll().toString();
		final nativeCode = native.exitCode();
		native.close();
		if (nativeCode != 0 || nativeOutput != output)
			throw "native enum import differs (exit " + nativeCode + "): " + nativeOutput + nativeErrors;
		Sys.println("OCAML_ENUM_IMPORT:PASS " + (sameModule ? "same_module" : directive));
		#end
		Sys.println("ENUM_IMPORT_CONSTRAINT:PASS " + (sameModule ? "same_module" : directive));
	}
}
