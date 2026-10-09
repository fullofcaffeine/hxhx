/** Compare independent local generic calls, captures, and bounds with upstream before native execution. */
class M14LocalGenericFunctionIntegrationTest {
	static function observe(command:String, arguments:Array<String>):{code:Int, output:String, errors:String} {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["30", command].concat(arguments));
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, output: output, errors: errors};
	}

	static function main():Void {
		final upstreamOnly = #if local_generic_upstream_only true #else false #end;
		for (entry in [
			{
				name: "identity",
				body: 'function identity<T>(value:T):T return value; Sys.println(identity(3)); Sys.println(identity("ok"));',
				output: "3\nok\n"
			},
			{
				name: "capture",
				body: 'var count = 0; function identity<T>(value:T):T { count++; return value; } Sys.println(identity(3)); Sys.println(identity("ok")); Sys.println(count);',
				output: "3\nok\n2\n"
			},
			{
				name: "constraint",
				body: 'function length<T:Array<Int>>(value:T):Int return value.length; Sys.println(length([1,2]));',
				output: "2\n"
			},
			{
				name: "shadow",
				body: 'function outer<T>(x:T):T { function inner<T>(y:T):T return y; Sys.println(inner("nested")); return x; } Sys.println(outer(3));',
				output: "nested\n3\n"
			},
			{
				name: "metadata",
				body: 'function identity<@:localMarker T>(value:T):T return value; Sys.println(identity(3));',
				output: "3\n"
			},
			{
				name: "recursive",
				body: 'function identity<T>(value:T, count:Int):T { return count == 0 ? value : identity(value, count - 1); } Sys.println(identity(3, 2)); Sys.println(identity("ok", 1));',
				output: "3\nok\n"
			}
		]) {
			final directory = ".tmp/local-generic-integration/" + entry.name;
			sys.FileSystem.createDirectory(directory);
			final path = directory + "/Main.hx";
			final source = "class Main { static function main():Void { " + entry.body + " } }";
			sys.io.File.saveContent(path, source);
			final upstream = observe("haxe", ["-cp", directory, "--run", "Main"]);
			if (upstream.code != 0 || upstream.output != entry.output || upstream.errors.length != 0)
				throw entry.name + " upstream contract differs: " + upstream.output + upstream.errors;
			if (upstreamOnly)
				continue;
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]), null, true);
			final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), directory + "/ocaml", true);
			final native = observe(executable, []);
			if (native.code != 0 || native.output != entry.output || native.errors.length != 0)
				throw entry.name + " native contract differs: " + native.output + native.errors;
		}
		for (entry in [
			{
				name: "constraint_bad",
				body: 'function length<T:Array<Int>>(value:T):Int return value.length; Sys.println(length(["bad"]));',
				upstream: ["String should be Int"],
				local: ["Constraint", "length"]
			},
			{
				name: "alias",
				body: 'function identity<T>(value:T):T return value; var alias = identity; Sys.println(alias(3)); Sys.println(alias("ok"));',
				upstream: ["String should be Int"],
				local: ["String", "Int"]
			},
			{
				name: "shared_parameter",
				body: 'function choose<T>(first:T, second:T):T return first; Sys.println(choose(3,"ok"));',
				upstream: ["String should be Int"],
				local: ["String", "Int"]
			},
			{
				name: "default",
				body: 'function identity<T=String>(value:T):T return value; Sys.println(identity("ok"));',
				upstream: ["Default type parameters are only supported on types"],
				local: ["Default type parameters are only supported on types"]
			},
			{
				name: "anonymous",
				body: 'var identity = function<T>(value:T):T return value; Sys.println(identity(3));',
				upstream: ["Type parameters not supported in unnamed local functions"],
				local: ["Type parameters not supported in unnamed local functions"]
			},
			{
				name: "named_value",
				body: 'var identity = function named<T>(value:T):T return value; Sys.println(identity(3));',
				upstream: ["Type parameters are not supported for rvalue functions"],
				local: ["Type parameters are not supported for rvalue functions"]
			}
		]) {
			final directory = ".tmp/local-generic-integration/" + entry.name;
			sys.FileSystem.createDirectory(directory);
			final path = directory + "/Main.hx";
			final source = "class Main { static function main():Void { " + entry.body + " } }";
			sys.io.File.saveContent(path, source);
			final upstream = observe("haxe", ["-cp", directory, "--run", "Main"]);
			if (upstream.code == 0)
				throw entry.name + " unexpectedly passed upstream";
			for (part in entry.upstream)
				if (upstream.errors.indexOf(part) < 0)
					throw entry.name + " failed for an unrelated upstream reason: " + upstream.errors;
			if (upstreamOnly)
				continue;
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			var rejected = false;
			try {
				TyperStage.typeResolvedModule(module, TyperIndex.build([module]), null, true);
			} catch (error:TyperError) {
				for (part in entry.local)
					if (error.toString().indexOf(part) < 0)
						throw entry.name + " failed for an unrelated local reason: " + error.toString();
				rejected = true;
			}
			if (!rejected)
				throw entry.name + " accepted an invalid generic call";
		}
		Sys.println(upstreamOnly ? "LOCAL_GENERIC_UPSTREAM:PASS" : "LOCAL_GENERIC_NATIVE:PASS");
	}
}
