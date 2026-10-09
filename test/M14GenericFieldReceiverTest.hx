import sys.io.File;

/** Prove declaration-owned field parameters specialize through direct, nullable, and inherited receivers. */
class M14GenericFieldReceiverTest {
	static function main():Void {
		final root = "test/fixtures/generic_field_receiver";
		final expected = "true\ntrue\nfalse\ntrue\n7\nok\n9\n";
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "upstream generic field contract differs: " + output + errors;
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(File.getContent(root + "/Main.hx"), root + "/Main.hx"));
		final index = TyperIndex.build([module]);
		final owner = index.getByFullName("Main.Node");
		final before = owner.fieldInfo("value").getType().getSemanticKey();
		final typed = TyperStage.typeResolvedModule(module, index);
		if (owner.fieldInfo("value").getType().getSemanticKey() != before)
			throw "receiver specialization mutated the shared field declaration";
		var integerReads = 0;
		function expression(node:TypedExpr):Void {
			final field = node.getFieldInfo();
			if (field != null
				&& field.getCanonicalKey() == "Main.Node#instance#value"
				&& node.getType().getSemanticKey() == "primitive:Int")
				integerReads++;
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (value in node.getExpressions())
				expression(value);
			for (child in node.getStatements())
				statement(child);
		}
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				for (entry in fn.getBody().getStatements())
					statement(entry);
		if (integerReads != 1)
			throw "concrete field occurrence lost its declared owner or applied Int type";
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		rejectUnrelatedParameters();
		Sys.println("GENERIC_FIELD_RECEIVER:PASS");
	}

	/** Equal parameter names from independent owners cannot make a callback argument compatible. */
	static function rejectUnrelatedParameters():Void {
		final source = 'class Node<T>{public var value:T; public function new(value:T){this.value=value;}}'
			+ 'class Other<T>{public function new(){} public function apply(node:Node<Int>, callback:T->Bool):Bool{return callback(node.value);}}'
			+ 'class Main{static function main():Void{}}';
		final root = ".tmp/generic_field_receiver_negative";
		sys.FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 1 || errors.length == 0)
			throw "upstream did not reject unrelated generic callback: " + output + errors;
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		var rejected = false;
		try {
			TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		} catch (error:TyperError) {
			rejected = true;
		}
		if (!rejected)
			throw "unrelated generic callback parameter was accepted";
	}
}
