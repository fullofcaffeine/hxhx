import sys.FileSystem;
import sys.io.File;

/** Declared extern indexing retains its substituted element type and requires integer indices. */
class M14ArrayAccessContractTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function main():Void {
		final cases = [
			{
				name: "direct",
				declarations: "extern class Store<T> implements ArrayAccess<T> {}",
				receiver: "Store<Int>",
				expression: "store[0] - 1",
				accepted: true
			},
			{
				name: "inherited",
				declarations: "extern class Base<A,B> implements ArrayAccess<B> {} extern class Store<T> extends Base<String,T> {}",
				receiver: "Store<Int>",
				expression: "store[0] - 1",
				accepted: true
			},
			{
				name: "nullable",
				declarations: "extern class Store<T> implements ArrayAccess<T> {}",
				receiver: "Null<Store<Int>>",
				expression: "store[0] - 1",
				accepted: true
			},
			{
				name: "wrong_element",
				declarations: "extern class Store<T> implements ArrayAccess<T> {}",
				receiver: "Store<String>",
				expression: "store[0]",
				accepted: false
			},
			{
				name: "wrong_index",
				declarations: "extern class Store<T> implements ArrayAccess<T> {}",
				receiver: "Store<Int>",
				expression: 'store["bad"] - 1',
				accepted: false
			},
			{
				name: "lookalike",
				declarations: "extern interface ArrayAccess<T> {} extern class Store<T> implements ArrayAccess<T> {}",
				receiver: "Store<Int>",
				expression: "store[0] - 1",
				accepted: false
			}
		];
		cases.push({
			name: "untyped_index",
			declarations: "extern class Store<T> implements ArrayAccess<T> {}",
			receiver: "Store<Int>",
			expression: 'untyped store["bad"] - 1',
			accepted: true
		});
		cases.push({
			name: "write",
			declarations: "extern class Store<T> implements ArrayAccess<T> {}",
			receiver: "Store<Int>",
			expression: '(store[0] = 7)',
			accepted: true
		});
		cases.push({
			name: "wrong_write",
			declarations: "extern class Store<T> implements ArrayAccess<T> {}",
			receiver: "Store<Int>",
			expression: '{store[0] = "bad"; 7;}',
			accepted: false
		});
		cases.push({
			name: "untyped_index_operand",
			declarations: "extern class Store<T> implements ArrayAccess<T> {}",
			receiver: "Store<Int>",
			expression: 'store[untyped "bad"] - 1',
			accepted: true
		});
		final root = ".tmp/declared_array_access";
		for (input in cases) {
			final directory = root + "/" + input.name;
			FileSystem.createDirectory(directory);
			final source = input.declarations
				+ " class Main { static function take(value:Int):Int return value; static function read(store:"
				+ input.receiver
				+ "):Int return take("
				+ input.expression
				+ "); static function main():Void {}}";
			File.saveContent(directory + "/Main.hx", source);
			final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout",
				["30", "node_modules/.bin/haxe", "-cp", directory, "--run", "Main"]);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			require(input.accepted ? code == 0 && output == "" && errors == "" : code == 1 && errors != "",
				"upstream indexed access differs: "
				+ input.name
				+ " "
				+ errors);
		}
		Sys.println("ARRAY_ACCESS_UPSTREAM:PASS");
		for (input in cases) {
			final directory = root + "/" + input.name;
			final path = directory + "/Main.hx";
			var typed:Null<TypedModule> = null;
			var diagnostic = "";
			try {
				typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: directory});
			} catch (error:TyperError) {
				diagnostic = error.message;
			}
			require((typed != null) == input.accepted, "indexed access differs: " + input.name + " " + diagnostic);
			if (typed != null) {
				var accesses = 0;
				function inspect(expression:TypedExpr):Void {
					if (expression.getTag() == ArrayAccess) {
						accesses++;
						require(expression.getType().getSemanticKey() == "primitive:Int", "indexed element lost Int: " + input.name);
					}
					for (child in expression.getExpressions())
						inspect(child);
				}
				for (owner in typed.getTypedClasses())
					for (fn in owner.getFunctions())
						for (statement in fn.getBody().getStatements())
							for (expression in statement.getExpressions())
								inspect(expression);
				require(accesses == 1, "missing indexed expression: " + input.name);
			}
			Sys.println("ARRAY_ACCESS_CASE:PASS " + input.name);
		}
		M14ArrayAccessLuaObserver.run();
	}
}
