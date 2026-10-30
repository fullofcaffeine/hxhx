/** Prove grouped direct calls and callback-return conversion against upstream Haxe and native execution. */
class M14NativeCallbackCallPathsTest {
	static function observe(command:String, arguments:Array<String>):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = try process.exitCode() catch (error:haxe.Exception) {
			process.close();
			throw "Callback child failed while collecting its exit status: "
				+ command
				+ " "
				+ arguments.join(" ")
				+ "\n"
				+ output
				+ errors
				+ "\n"
				+ error.message;
		};
		process.close();
		if (code != 0 || output != "7\n")
			throw "Callback call-path observation differs: " + output + errors;
	}

	static function check(name:String, source:String, checkDirectReturn:Bool):Void {
		final directory = ".tmp/native_callback_call_paths/" + name;
		sys.FileSystem.createDirectory(directory);
		final path = directory + "/Main.hx";
		sys.io.File.saveContent(path, source);
		observe("node_modules/.bin/haxe", ["-cp", directory, "--run", "Main"]);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		if (!Lambda.exists(backend.ocaml.Stage3OcamlCallableSelection.select([typed]), selected -> selected.fieldName == "main"))
			throw "Callback invocation must select its consuming method";
		final expanded = MacroStage.expandProgram([typed], []);
		final executable = EmitterStage.emitToDir(expanded, directory + "/full");
		observe(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable]);
		if (checkDirectReturn) {
			// This bootstrap route omits ordinary statements. Successful native compilation
			// proves its returned callback type; full-body execution above proves behavior.
			EmitterStage.emitToDir(expanded, directory + "/direct");
		}
		Sys.println("NATIVE_CALLBACK_CALL_PATH:PASS " + name);
	}

	/**
		Compile through the production `Stage3Compiler` request path, then run the native program.

		A selected instance method call on a captured value (`values.push`) inside a callback, and
		another (`values.join`) in the same program, are method calls on their receiver. Their exact
		payload must not be counted as callback arguments (haxe_ocaml-fikpj); before the fix the
		emitter stopped with "Native callback call lost its fixed argument mapping".
	**/
	static function checkCompiled(name:String, source:String):Void {
		final directory = ".tmp/native_callback_call_paths/" + name;
		sys.FileSystem.createDirectory(directory);
		sys.io.File.saveContent(directory + "/Main.hx", source);
		observe("node_modules/.bin/haxe", ["-cp", directory, "--run", "Main"]);
		final request = hxhx.CompilationRequestContext.server(1);
		final code = hxhx.Stage3Compiler.runRequest([
			"--hxhx-no-run",
			"--hxhx-out",
			directory + "/stage3",
			"-cp",
			directory,
			"-main",
			"Main"
		], request);
		final output = new StringBuf();
		for (event in request.output.events())
			output.add(event.text);
		request.close(code == 0);
		if (code != 0)
			throw "Callback program did not compile natively: " + output.toString();
		observe(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", directory + "/stage3/out.exe"]);
		Sys.println("NATIVE_CALLBACK_CALL_PATH:PASS " + name);
	}

	static function main():Void {
		check("grouped", "class Main {
			static function observe(value:Dynamic):Dynamic { Sys.println(value); return value; }
			static function apply(callback:Int->Void):Void { callback(7); }
			static function main():Void { apply((value:Dynamic) -> (observe)(value)); }
		}", false);
		check("returned", "class Main {
			static function observe(value:Dynamic):Dynamic return value;
			static function factory():Int->Dynamic return observe;
			static function main():Void { Sys.println(factory()(7)); }
		}", true);
		checkCompiled("captured-instance-calls", "class Main {
			static function main():Void {
				final values = new Array<String>();
				final record = function(value:Int):Void { values.push(Std.string(value)); };
				record(7);
				Sys.println(values.join(\",\"));
			}
		}");
	}
}
