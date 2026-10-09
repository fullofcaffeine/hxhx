/** Callback arguments must retain nested generic constraints until their function's inference is complete. */
class M14GenericCallbackContextTest {
	static function main():Void {
		previewIsolation();
		for (entry in [
			{name: "written", hint: ":Box<Dynamic>", permission: ""},
			{name: "open", hint: "", permission: ""},
			{name: "untyped_written", hint: ":Box<Dynamic>", permission: "untyped "},
			{name: "untyped_open", hint: "", permission: "untyped "}
		]) {
			final source = 'class Box<T>{public var value:T;public function new(value:T){this.value=value;}}'
				+ 'class Helper{public static function wrap<T>(value:Box<T>):Box<T>{return value;}}'
				+ 'class Main{static function assemble(f:Box<Dynamic>->Dynamic):Dynamic{return '
				+ entry.permission
				+ 'function(a'
				+ entry.hint
				+ '){return f(Helper.wrap(a));};}'
				+
				'static function main():Void{var callback=assemble(function(value:Box<Dynamic>):Dynamic{return value.value;});trace(callback(new Box<Int>(2)));}}';
			final root = ".tmp/generic-callback-context-contract-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stdout != path + ":1: 2\n")
				throw "upstream callback context differs: " + entry.name + stdout + stderr;
			Sys.println("GENERIC_CALLBACK_CONTEXT_UPSTREAM:PASS " + entry.name);
			final typed = @:privateAccess M14GenericDynamicInferenceTest.typeSource(source, root, path);
			typed.getBackendProjection();
			JsRuntimeFixture.assertRuntime(typed, "Main", "2\n");
			if (entry.name == "open") {
				// Use the same call chain with a plain stdout observer for native execution.
				final nativeSource = StringTools.replace(source, "trace(callback", "Sys.println(callback");
				@:privateAccess M14NekoClosureControlTest.assertSource("generic_callback_context", nativeSource, "2\n");
			}
			Sys.println("GENERIC_CALLBACK_CONTEXT:PASS " + entry.name);
		}
		laterContext();
		argumentOrder();
	}

	/** Retain the selected omission and rest slots while a later use supplies the nested generic argument. */
	static function argumentOrder():Void {
		for (entry in [
			{
				name: "optional",
				signature: "(?Int,Box<Dynamic>)->Int",
				callback: "function(?prefix:Int,value:Box<Dynamic>):Int{return (prefix==null?100:prefix)+value.value;}",
				expected: "102\n"
			},
			{
				name: "rest",
				signature: "(...values:Box<Dynamic>)->Int",
				callback: "function(...values:Box<Dynamic>):Int{return values[0].value;}",
				expected: "2\n"
			}
		]) {
			final source = 'class Box<T>{public var value:T;public function new(value:T){this.value=value;}}'
				+ 'class Helper{public static function wrap<T>(value:Box<T>):Box<T>{return value;}}'
				+ 'class Main{static function assemble(f:'
				+ entry.signature
				+ '):Dynamic{return function(a){'
				+ 'var result=f(Helper.wrap(a));var ints:Box<Int>=a;return result;};}'
				+ 'static function main():Void{var callback=assemble('
				+ entry.callback
				+ ');Sys.println(callback(new Box<Int>(2)));}}';
			final root = ".tmp/generic-callback-context-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stdout != entry.expected)
				throw "upstream callback order differs: " + entry.name + stdout + stderr;
			final typed = @:privateAccess M14GenericDynamicInferenceTest.typeSource(source, root, path);
			typed.getBackendProjection();
			JsRuntimeFixture.assertRuntime(typed, "Main", entry.expected);
			Sys.println("GENERIC_CALLBACK_CONTEXT_ORDER:PASS " + entry.name);
		}
	}

	/** A candidate can observe recorded defaults without erasing later evidence or admitting missing facts. */
	static function previewIsolation():Void {
		final solver = new TyInferenceSolver("callback-context-preview");
		final variable = solver.freshOmittedParameter();
		final unrelated = solver.freshOmittedParameter();
		solver.observeDynamicUse(variable);
		if (!solver.previewDynamicUses(variable).isDynamic()
			|| !solver.preview(variable).isUnknown()
			|| !solver.previewDynamicUses(unrelated).isUnknown())
			throw "callback preview changed source inference or invented Dynamic evidence";
		final immutable = TyInferenceTerm.Known(TyType.unknown());
		solver.observeDynamicUse(immutable);
		if (!solver.previewDynamicUses(immutable).isUnknown())
			throw "callback preview replaced an immutable Unknown";
		if (!solver.constrain(variable, TyInferenceTerm.Known(TyType.fromHintText("Int"))))
			throw "callback preview fixed a variable before a later concrete use";
		solver.seal();
		if (solver.published(variable).getSemanticKey() != "primitive:Int" || !solver.published(unrelated).isUnknown())
			throw "final publication lost the later constraint";
		Sys.println("GENERIC_CALLBACK_CONTEXT_PREVIEW:PASS");
	}

	/** Passing a value to a Dynamic destination must leave its later concrete uses and conflicts visible. */
	static function laterContext():Void {
		for (conflict in [false, true]) {
			final source = 'class Box<T>{public var value:T;public function new(value:T){this.value=value;}}'
				+ 'class Helper{public static function wrap<T>(value:Box<T>):Box<T>{return value;}}'
				+ 'class Main{static function assemble(f:Box<Dynamic>->Dynamic):Dynamic{return function(a){'
				+ 'f(Helper.wrap(a));var ints:Box<Int>=a;'
				+ (conflict ? 'var strings:Box<String>=a;' : '')
				+ 'return ints.value;};}'
				+
				'static function main():Void{var callback=assemble(function(value:Box<Dynamic>):Dynamic{return value.value;});trace(callback(new Box<Int>(2)));}}';
			final root = ".tmp/generic-callback-context-later-" + conflict;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (conflict ? code == 0 || stderr.indexOf("should be") < 0 : code != 0 || stdout != path + ":1: 2\n")
				throw "upstream later callback context differs: " + stdout + stderr;
			var rejected = false;
			try {
				final typed = @:privateAccess M14GenericDynamicInferenceTest.typeSource(source, root, path);
				typed.getBackendProjection();
				if (!conflict)
					JsRuntimeFixture.assertRuntime(typed, "Main", "2\n");
			} catch (error:haxe.Exception) {
				if (!conflict || (error.message.indexOf("conflict") < 0 && error.message.indexOf("not compatible") < 0))
					throw error;
				rejected = true;
			}
			if (rejected != conflict)
				throw "later callback context lost a conflicting use";
			Sys.println("GENERIC_CALLBACK_CONTEXT_LATER:PASS conflict=" + conflict);
		}
	}
}
