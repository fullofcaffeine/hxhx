import sys.io.File;

/**
	Type `new` on a bare generic alias the way upstream Haxe 4.3.7 does.
	Standard `Xml` stores attributes with `attributeMap = new Map()`, where `Map`
	is the generic alias `Map<K, V> = haxe.ds.Map<K, V>`. Value type uses must
	still supply alias arguments, but a constructor path may omit all of them.
	The typer used to resolve that path as a value type and rejected every
	program that reached `Xml` with "Not enough type parameters for Map" at
	position 0:0. This test types the real standard `Xml` provider through the
	production declaration loader, checks that one omitted binder is shared by
	every place the alias body repeats it, keeps the value-use rejection (now
	with a real position), and runs the CI `Xml.parse` program natively.
 */
class M14Stage3BareAliasConstructorTest {
	static final root = "test/fixtures/stage3_bare_alias_constructor";

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Ask upstream Haxe 4.3.7 whether it accepts a program. */
	static function upstreamAccepts(directory:String):Bool {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", directory, "-main", "Main", "--no-output"]);
		process.stdout.readAll();
		process.stderr.readAll();
		final status = process.exitCode();
		process.close();
		return status == 0;
	}

	/** Visit every typed expression in every method of the module. */
	static function walk(typed:TypedModule, visit:TypedExpr->Void):Void {
		function expression(value:TypedExpr):Void {
			visit(value);
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in typed.getTypedClasses())
			for (method in owner.getFunctions())
				for (body in method.getBody().getStatements())
					statement(body);
	}

	/** Write a one-file program with the Pair alias; callers type it through the real standard library. */
	static function program(name:String, body:String):{directory:String, path:String, source:String} {
		final directory = ".tmp/stage3-bare-alias-constructor-" + name;
		sys.FileSystem.createDirectory(directory);
		final source = 'class Couple<A, B> {public final first:A; public final second:B; public function new(first:A, second:B) {this.first = first; this.second = second;}}\n'
			+ 'typedef Pair<T> = Couple<T, T>;\n'
			+ 'class Main {static function main() {'
			+ body
			+ '}}\n';
		File.saveContent(directory + "/Main.hx", source);
		return {directory: directory, path: directory + "/Main.hx", source: source};
	}

	static function main():Void {
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_BARE_ALIAS_CONSTRUCTOR_UPSTREAM:PASS");

		// Preparation types every loaded provider body, including Xml's `new Map()`.
		final typed = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		final constructed = new Array<String>();
		var selectedStringMap = false;
		walk(typed, value -> {
			if (value.getTag() == NewValue)
				constructed.push(value.getType().getSemanticKey());
			if (value.getTag() == Call && value.getType().getSemanticKey() == "nominal:haxe.ds.StringMap<primitive:Int>")
				selectedStringMap = true;
		});
		require(constructed.join(",") == "nominal:Main.Couple<primitive:Int,primitive:Int>",
			"bare alias constructor did not share its binder: " + constructed.join(","));
		require(selectedStringMap, "bare Map constructor did not select its String-key implementation from the expected type");
		Sys.println("M14_STAGE3_BARE_ALIAS_CONSTRUCTOR_TYPES:PASS");

		final conflicting = program("conflicting", 'final pair = new Pair(1, "two");');
		require(!upstreamAccepts(conflicting.directory), "upstream accepted one alias binder with two different types");
		var conflict:Null<TyperError> = null;
		try {
			M14Stage3RuntimeFixture.typeMain({source: conflicting.source, path: conflicting.path, root: conflicting.directory});
		} catch (error:TyperError) {
			conflict = error;
		}
		require(conflict != null
			&& conflict.message.indexOf("generic constructor") >= 0, "omitted alias binder was inferred separately for each occurrence");

		final valueUse = program("value-use", 'final names:Map = null;');
		require(!upstreamAccepts(valueUse.directory), "upstream accepted a bare generic alias value type");
		var missing:Null<TyperError> = null;
		try {
			M14Stage3RuntimeFixture.typeMain({source: valueUse.source, path: valueUse.path, root: valueUse.directory});
		} catch (error:TyperError) {
			missing = error;
		}
		require(missing != null && missing.message == "Not enough type parameters for Map", "bare generic alias value type was accepted");
		require(missing.filePath == valueUse.path && missing.pos.line == 3, "missing alias argument diagnostic lost its position: " + missing.toString());
		Sys.println("M14_STAGE3_BARE_ALIAS_CONSTRUCTOR_REJECTIONS:PASS");

		// The CI bring-up program: Xml.parse must type, and the native root still runs.
		final parse = program("xml-parse", 'var x = Xml.parse("<a/>"); Sys.println("ok");');
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", parse.directory, "--run", "Main"], expected: "ok\n"});
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: parse.source, path: parse.path, root: parse.directory});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/stage3_bare_alias_constructor_xml_parse", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: "ok\n"});
		Sys.println("M14_STAGE3_BARE_ALIAS_CONSTRUCTOR_XML_NATIVE:PASS");
	}
}
