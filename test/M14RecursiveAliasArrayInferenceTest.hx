/** Inferred collections must accept equivalent finite views of a recursive record without erasing their declarations. */
class M14RecursiveAliasArrayInferenceTest {
	static function main():Void {
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		final source = 'typedef Ref<T>={function get():T;};
typedef Field={var value:Int;var siblings:Ref<Array<Field>>;};
typedef Node={var fields:Ref<Array<Field>>;};
class Main {
 static function wrap(value:Ref<Node>) return [value];
 static function main():Void {
  var leaves:Array<Field> = [];
  var ref:Ref<Array<Field>> = {get:function():Array<Field> {return leaves;}};
  var leaf:Field = {value:7,siblings:ref};
  leaves.push(leaf);
  var node:Node = {fields:ref};
  var owner:Ref<Node> = {get:function():Node {return node;}};
  var values = wrap(owner);
  var selected = values[0].get().fields.get();
  trace(selected[0].value);
  selected[0].siblings.get()[0].value = 9;
  trace(leaf.value);
  trace(selected.length);
 }
}';
		sys.io.File.saveContent(path, source);
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "upstream recursive array inference failed: " + stdout + stderr;
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		typed.getBackendProjection();
		var observed = false;
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				if (fn.getDeclaration().getSignature().getName() == "wrap") {
					final actual = fn.getDeclaration().getSignature().getArgs()[0];
					final inferred = fn.getEnvironment().getReturnType().getTypeArguments()[0];
					if (!TyAliasEquivalence.equivalentTypes(actual, inferred))
						throw "inferred recursive array changed its element contract";
					final get = actual.getAnonymousFields()[0];
					switch get.kind {
						case Method([]):
						case _:
							throw "recursive inference erased the method declaration";
					}
					final fields = get.type.getFunctionReturn().getAnonymousFieldTypes()[0];
					if (fields.getAliasDefinition() == null || fields.getAliasDefinition().getCanonicalName() != "Main.Ref")
						throw "recursive inference lost its retained alias declaration";
					final array = fields.getTypeArguments()[0];
					if (array.getNominalIdentity() == null
						|| array.getNominalIdentity().getCanonicalName() != "Array"
						|| array.getTypeArguments().length != 1)
						throw "recursive alias lost its applied collection argument";
					observed = true;
				}
		if (!observed)
			throw "recursive inference observer missed the authored method";
		final expected = "7\n9\n1\n";
		M14Stage3RuntimeFixture.observe({
			command: "node",
			arguments: [root + "/upstream.js"],
			expected: path + ":15: 7\n" + path + ":17: 9\n" + path + ":18: 1\n"
		});
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("RECURSIVE_ALIAS_ARRAY_INFERENCE:PASS");
	}
}
