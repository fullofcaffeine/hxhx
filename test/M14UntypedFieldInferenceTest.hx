/** Independent reduction of unchecked fields used by a generic named call. */
class M14UntypedFieldInferenceTest {
	static function main():Void {
		var failures = 0;
		for (entry in [
			{name: "typed", hint: "{values:Array<Int>}", body: "return first(handle.values);"},
			{name: "dynamic", hint: "Dynamic", body: "return first(handle.values);"},
			{name: "known", hint: "{values:Array<Int>}", body: "return untyped first(handle.values);"},
			{name: "untyped_unused", hint: "{}", body: "untyped handle.absent;return untyped first(handle.values);"},
			{name: "untyped_method", hint: "{}", body: "return untyped handle.read();"},
			{name: "untyped_receiver", hint: "{}", body: "return untyped receiver(handle).read();"},
			{name: "untyped_alias", hint: "{}", body: "untyped {var values=handle.values;var alias=values;return first(alias);}"},
			{name: "untyped_direct", hint: "{}", body: "return untyped first(handle.values);"},
			{name: "untyped_field", hint: "{}", body: "return first(untyped handle.values);"},
			{name: "untyped_conditional", hint: "{}", body: "return untyped if(handle.values==null) 0 else first(handle.values);"}
		]) {
			final source = 'class Main{static function first<T>(values:Array<T>):T{return values[0];}'
				+ 'static function receiver(value:{}):{}{return value;}'
				+ 'static function read(handle:'
				+ entry.hint
				+ '):Int{'
				+ entry.body
				+ '}'
				+ 'static function main():Void{var data='
				+ ((entry.name == "untyped_method" || entry.name == "untyped_receiver") ? ' {read:function():Int{return 7;}}' : '{values:[7]}')
				+ ';Sys.println(read(data));}}';
			final root = '.tmp/untyped-generic-field-' + entry.name;
			sys.FileSystem.createDirectory(root);
			sys.io.File.saveContent(root + '/Main.hx', source);
			final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stdout != '7\n')
				throw 'upstream failed ' + entry.name + stdout + stderr;
			Sys.println('UPSTREAM_UNTYPED_GENERIC_FIELD:PASS ' + entry.name);
			try {
				final typed = @:privateAccess M14GenericDynamicInferenceTest.typeSource(source, root, root + '/Main.hx');
				typed.getBackendProjection();
				for (cls in typed.getTypedClasses())
					for (fn in cls.getFunctions())
						if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "read")
							for (stmt in fn.getBody().getStatements())
								checkStatement(stmt);
				JsRuntimeFixture.assertRuntime(typed, 'Main', '7\n');
				Sys.println('LOCAL_UNTYPED_GENERIC_FIELD:PASS ' + entry.name);
			} catch (error:haxe.Exception) {
				failures++;
				Sys.println('LOCAL_UNTYPED_GENERIC_FIELD:FAIL ' + entry.name + ' ' + error.message);
			}
		}
		@:privateAccess M14NekoClosureControlTest.assertSource("untyped_field_inference",
			'class Box<T>{public var value:T;public function new(value:T){this.value=value;}}'
			+ 'class Main{static function first<T>(box:Box<T>):T{return box.value;}'
			+ 'static function read(handle:{}):Int{return untyped first(handle.box);}'
			+ 'static function main():Void{Sys.println(read({box:new Box<Int>(7)}));}}',
			"7\n");
		rejected("ordinary", "static function read(handle:{}):Void{first(handle.values);}");
		rejected("known_argument", "static function read(handle:{values:Array<String>}):Void{untyped takeInts(handle.values);}");
		rejected("alias_conflict", "static function read(handle:{}):Void{untyped {var value=handle.values;takeInts(value);takeStrings(value);}}");
		if (failures > 0)
			throw 'unchecked generic field failures: ' + failures;
	}

	/** Published generic argument bindings must describe complete operands. */
	static function checkExpression(value:TypedExpr):Void {
		final declaration = value.getDeclaration();
		if (value.getTag() == Call && declaration != null && declaration.getSignature().getName() == "first") {
			value.assertArgumentBinding();
			final operand = value.getExpressions()[1].getType();
			if (operand.hasUnknownComponent())
				throw "unchecked field argument remained unresolved";
		}
		if (value.getTag() == FieldRead && value.getTexts()[0] == "absent" && !value.getType().isUnknown())
			throw "unused unchecked field acquired a fabricated type";
		for (child in value.getExpressions())
			checkExpression(child);
	}

	static function checkStatement(value:TypedStmt):Void {
		for (child in value.getExpressions())
			checkExpression(child);
		for (child in value.getStatements())
			checkStatement(child);
	}

	/** A missing ordinary field and conflicting known calls remain errors. */
	static function rejected(name:String, body:String):Void {
		final root = ".tmp/untyped-field-rejection-" + name;
		final source = 'class Main{static function first<T>(values:Array<T>):T{return values[0];}'
			+ 'static function takeInts(values:Array<Int>):Void{}static function takeStrings(values:Array<String>):Void{}'
			+ body
			+ 'static function main():Void{}}';
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Main.hx", source);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code == 0 || (stderr.indexOf("has no field") < 0 && stderr.indexOf("should be") < 0))
			throw "upstream unchecked field rejection differs: " + name + stdout + stderr;
		var failure = "";
		try {
			final typed = @:privateAccess M14GenericDynamicInferenceTest.typeSource(source, root, root + "/Main.hx");
			typed.getBackendProjection();
		} catch (error:haxe.Exception)
			failure = error.message;
		if (failure.indexOf("No compatible method signature") < 0
			&& failure.indexOf("conflict") < 0
			&& failure.indexOf("selected call conversion does not satisfy") < 0
			&& failure.indexOf("Unknown field") < 0)
			throw "unchecked field rejection differs: " + name + " " + failure;
		Sys.println("UNTYPED_FIELD_REJECTION:PASS " + name);
	}
}
