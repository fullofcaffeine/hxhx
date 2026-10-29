import sys.io.File;
import TypedExpr.TypedExprTag;

/** Compare a saved interval's cursor contract through upstream and the real authored JS driver. */
class M14Stage3RangeValueTest {
	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0)
			throw "range observer failed: " + command + ": " + stdout + stderr;
		return stdout;
	}

	/** Quotation retains interval syntax without any executable constructor application. */
	static function quotation():Void {
		final quoted = TypedBodyBuilder.buildExpression(EMacroExpr(ERange(EInt(2), EInt(6)), []), HxPos.unknown(), null);
		if (quoted.getTag() != MacroExpr
			|| quoted.getExpressions()[0].getTag() != Range
			|| quoted.getExpressions()[0].getConstructorApplication() != null)
			throw "quoted interval became executable construction";
		switch TypedSourceSyntax.expression(quoted) {
			case EMacroExpr(ERange(EInt(2), EInt(6)), wrappers) if (wrappers.length == 0):
			case _:
				throw "quoted interval lost its original operator syntax";
		}
	}

	/** Exact constructor projection keeps the applied arguments as well as the selected class owner. */
	static function genericProjection():Void {
		final source = 'class Main { static function main() { var cell = new Cell<Int>(3); } }' + ' class Cell<T> { public function new(value:T) {} }';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final module = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		var checked = false;
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody().getStatements())
					for (value in statement.getExpressions())
						if (value.getTag() == NewValue) {
							final application = value.getConstructorApplication();
							if (application == null || application.getParameterTypes()[0].getSemanticKey() != "primitive:Int")
								throw "generic constructor lost its selected application";
							switch TypedBodySource.expression(value) {
								case ENew("Main.Cell<Int>", arguments) if (arguments.length == 1 && arguments[0].match(EInt(3))):
									checked = true;
								case _:
									throw "generic constructor lost its exact owner or applied argument in source projection";
							}
						}
		if (!checked)
			throw "generic constructor projection control was not reached";
	}

	/** Allocation facts belong to the root provider and survive typed replay; direct loops retain their range nodes. */
	static function ownership(root:String):Void {
		final path = root + "/Main.hx";
		final module = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		var allocations = 0;
		var direct = false;
		function expression(value:TypedExpr):Void {
			final children = value.getExpressions();
			if (value.getTag() == SourceFor && children.length > 0 && children[0].getTag() == Range)
				direct = true;
			if (value.getTag() == NewValue
				&& value.getType().getNominalIdentity() != null
				&& value.getType().getNominalIdentity().getCanonicalName() == "IntIterator") {
				final constructor = value.getConstructorApplication();
				if (constructor == null
					|| constructor.getDeclaration().getOwner().getCanonicalName() != "IntIterator"
					|| value.withExpressions(children).getConstructorApplication() != constructor)
					throw "interval lost its exact core constructor through replay";
				allocations++;
			}
			for (child in children)
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			final children = value.getExpressions();
			if (value.getTag() == ForIn && children.length > 0 && children[0].getTag() == Range)
				direct = true;
			for (child in children)
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions())
				if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")
					for (value in fn.getBody().getStatements())
						statement(value);
		if (allocations != 7 || !direct)
			throw "range fixture lost exact allocation/direct-loop facts: " + allocations + ":" + direct;
	}

	static function check(root:String, entry:String, suffix:String):Void {
		final output = ".tmp/stage3-range-values-" + suffix;
		sys.FileSystem.createDirectory(output);
		final expected = File.getContent(root + "/expected.stdout");
		run("node_modules/.bin/haxe", ["-cp", root, "-main", entry, "-js", output + "/upstream.js"]);
		final normalized = [
			for (line in run("node", [output + "/upstream.js"]).split("\n"))
				if (line.length > 0) line.substr(line.indexOf("RANGE|"))
		];
		if (normalized.join("\n") + "\n" != expected)
			throw "upstream saved-range expectation changed";
		final status = hxhx.Stage3Compiler.run([
			"--hxhx-backend",
			"js-native",
			"--hxhx-no-run",
			"-cp",
			root,
			"-main",
			entry,
			"-js",
			output + "/native.js"
		]);
		if (status != 0 || run("node", [output + "/native.js"]) != expected)
			throw "authored driver differs for saved ranges: " + suffix + ":" + status;
		Sys.println("RANGE_CONTROL:PASS " + suffix);
	}

	static function negative(input:{root:String, upstream:String, local:String}):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", [
			"60",
			"node_modules/.bin/haxe",
			"-cp",
			input.root,
			"-main",
			"Main",
			"-js",
			".tmp/stage3-range-values-cursor/rejected.js"
		]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status == 0 || stderr.indexOf(input.upstream) < 0)
			throw "upstream range rejection changed: " + stdout + stderr;
		final path = input.root + "/Main.hx";
		var diagnostic = "";
		try
			M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: input.root})
		catch (error:TyperError)
			diagnostic = error.getMessage();
		if (diagnostic.indexOf(input.local) < 0)
			throw "range negative failed for another reason: " + diagnostic;
	}

	public static function runContract():Void {
		final root = "test/fixtures/stage3_range_values";
		quotation();
		genericProjection();
		ownership(root);
		check(root, "Main", "cursor");
		check(root + "/shadow_import", "Main", "import");
		check(root + "/shadow_package", "shadows.Main", "package");
		negative({root: root + "/bad_bound", upstream: "Float should be Int", local: "should be Int for a range bound"});
		negative({root: root + "/key_value", upstream: "Int has no field key", local: "key/value loop requires a resolved iterator protocol"});
		Sys.println("M14_STAGE3_RANGE_VALUES:PASS");
	}

	static function main():Void
		runContract();
}
