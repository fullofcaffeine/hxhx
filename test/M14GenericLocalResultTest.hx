import sys.io.File;

/** Compare local-context inference with upstream and inspect the allocated type, not only the return annotation. */
class M14GenericLocalResultTest {
	static function main():Void {
		final root = "test/fixtures/generic_local_result";
		final expected = "ok\ntrue\ntrue\ntrue\ntyped\n";
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "upstream local result contract differs: " + output + errors;
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(File.getContent(root + "/Main.hx"), root + "/Main.hx"));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final allocations = new Array<String>();
		function expression(node:TypedExpr):Void {
			if (node.getTag() == NewValue)
				allocations.push(node.getType().getSemanticKey());
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
		final wanted = [
			"dynamic",
			"primitive:String",
			"primitive:Int",
			"primitive:Int",
			"primitive:String"
		].map(argument -> "nominal:Main.Store<" + argument + ">");
		allocations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		wanted.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (allocations.join(";") != wanted.join(";"))
			throw "local context did not solve original allocation: " + allocations.join(";");
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		rejectConflictingContext();
		Sys.println("GENERIC_LOCAL_RESULT:PASS allocations=5");
	}

	/** A return annotation may fill missing evidence but cannot replace an argument already fixed by construction. */
	static function rejectConflictingContext():Void {
		final source = 'class Pair<A,B>{public function new(first:A){}}'
			+ 'class Main{static function make():Pair<Int,String>{final value=new Pair("wrong");final alias=value;return alias;}static function main():Void{}}';
		final root = ".tmp/generic_local_result_conflict";
		sys.FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 1 || errors.length == 0)
			throw "upstream accepted conflicting return context: " + output + errors;
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		var rejected = false;
		try {
			TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		} catch (error:TyperError) {
			if (error.message.indexOf("generic value conflicts with its expected type") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "return context replaced an already fixed constructor argument";
	}
}
