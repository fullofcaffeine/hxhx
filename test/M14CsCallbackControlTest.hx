import backend.BackendContext;
import backend.BackendRegistry;

/** Compare typed callback control with upstream C# and execute both native artifacts. */
class M14CsCallbackControlTest {
	public static function main():Void {
		final root = ".tmp/cs_callback_control_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final cases = [
			{
				name: "early_return",
				body: "var result = (function(value:Int):Int { if(value > 0) return value + 2; return 7; })(40); Sys.println(result);",
				expected: "42"
			},
			{
				name: "capture_mutation",
				body: "var total = 1; var add = function(value:Int):Int { total += value; return total; }; Sys.println(add(2)); Sys.println(add(4)); Sys.println(total);",
				expected: "3\n7\n7"
			},
			{
				name: "void_return",
				body: "var total = 0; var add = function(value:Int):Void { if(value < 0) return; total += value; }; add(-1); add(7); Sys.println(total);",
				expected: "7"
			},
			{
				name: "loop_and_shadow",
				body: "var value = 100; var sum = (function(value:Int):Int { var total = 0; for(i in 0...value) { if(i == 1) continue; if(i == 4) break; total += i; } return total; })(6); Sys.println(sum); Sys.println(value);",
				expected: "5\n100"
			},
			{
				name: "nested_return",
				body: "var outer = function(value:Int):Int { var inner = function(value:Int):Int { if(value > 0) return 3; return 4; }; var result = inner(value); return result + 2; }; Sys.println(outer(1));",
				expected: "5"
			},
			{
				name: "argument_once",
				body: "var count = 0; var result = (function(value:Int):Int { Sys.println(value); return value + 2; })(++count); Sys.println(result); Sys.println(count);",
				expected: "1\n3\n1"
			},
			{name: "callback_in_argument", body: "Sys.println((function(value:Int):Int { return value + 2; })(40));", expected: "42"},
			{
				name: "range_bounds",
				body: "var order = ''; var lower = function():Int { order += 'L'; return 2; }; var upper = function():Int { order += 'U'; return 5; }; var end = upper(); var sum = 0; for(i in lower()...end) { sum += i; end = 2; } var count = 0; var start = 5; for(i in start...3) count++; for(i in start...start) count++; for(i in 2147483646...2147483647) count++; Sys.println(order); Sys.println(sum); Sys.println(count); order = ''; for(i in lower()...upper()) {} Sys.println(order);",
				expected: "UL\n9\n1\nLU"
			}
		];
		for (entry in cases) {
			final directory = root + "/" + entry.name;
			sys.FileSystem.createDirectory(directory);
			final source = "class Main { static function main() { " + entry.body + " } }";
			sys.io.File.saveContent(directory + "/Main.hx", source);
			run("haxe", ["-cp", directory, "-main", "Main", "-cs", directory + "/upstream"]);
			expect(run("mono", [directory + "/upstream/bin/Main.exe"]), entry.expected);
			final module = typed(source, directory + "/Main.hx");
			final result = BackendRegistry.requireForTarget("cs-native")
				.emit(new MacroExpandedProgram([module], false),
					new BackendContext(directory + "/candidate", null, "Main", true, true, new haxe.ds.StringMap<String>()));
			expect(run("gtimeout", ["30", "mono", result.entryPath]), entry.expected);
			Sys.println("CS_CALLBACK_CONTROL:PASS " + entry.name);
		}
		checkOccurrenceOwnership();
		checkInvalidCall(root);
	}

	static function typed(source:String, path:String):TypedModule {
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	/** Equal syntax and mutation cannot borrow the original callback's checked signature. */
	static function checkOccurrenceOwnership():Void {
		final module = typed("class Main { static function main() { var f = function(value:Int):Int { return value; }; Sys.println(f(1)); } }", "ownership.hx");
		final projection = module.getBackendProjection().getClasses()[0].getFunctions()[0];
		var found = false;
		TypedBackendSourceWalk.functionDeclaration(projection.getDeclaration(), expression -> {
			switch expression {
				case ELambda(arguments, body, signature):
					final occurrence = projection.findLambda(expression);
					if (occurrence == null || projection.findLambda(ELambda(arguments.copy(), body, signature)) != null)
						throw "callback occurrence ownership differs";
					final name = arguments[0];
					arguments[0] = name + "_changed";
					var rejected = false;
					try
						projection.findLambda(expression)
					catch (_:haxe.Exception)
						rejected = true;
					arguments[0] = name;
					if (!rejected)
						throw "mutated callback retained its checked signature";
					found = true;
				case _:
			}
		}, _ -> {});
		if (!found)
			throw "ownership test did not visit a callback";
		Sys.println("CS_CALLBACK_OWNERSHIP:PASS");
	}

	static function expect(actual:String, expected:String):Void {
		if (StringTools.trim(actual) != expected)
			throw "callback result differs: " + actual + " expected " + expected;
	}

	/** Preserve the source type error before any target callback adaptation runs. */
	static function checkInvalidCall(root:String):Void {
		final directory = root + "/invalid_call";
		sys.FileSystem.createDirectory(directory);
		final source = "class Main { static function main() { var result = (function(value:Int):Int { return value; })('wrong'); } }";
		sys.io.File.saveContent(directory + "/Main.hx", source);
		final upstream = run("haxe", [
			"-cp",
			directory,
			"-main",
			"Main",
			"-cs",
			directory + "/upstream",
			"-D",
			"no-compilation"
		], false);
		var diagnostic = "";
		try
			typed(source, directory + "/Main.hx").getBackendProjection()
		catch (error:haxe.Exception)
			diagnostic = error.message;
		for (message in [upstream, diagnostic])
			if (message.indexOf("String") < 0 || message.indexOf("Int") < 0)
				throw "invalid callback argument did not retain its type error: " + message;
		Sys.println("CS_CALLBACK_INVALID_ARGUMENT:PASS");
	}

	static function run(command:String, arguments:Array<String>, expectSuccess:Bool = true):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final error = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if ((code == 0) != expectSuccess)
			throw command + " failed: " + output + error;
		return expectSuccess ? output : output + error;
	}
}
