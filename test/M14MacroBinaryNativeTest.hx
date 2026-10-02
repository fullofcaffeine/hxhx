import backend.cpp.CppMacroExpr;
import backend.js.JsExprEmitter;
import backend.source.SourceTargetCommon;
import backend.vm.NekoMacroExprLowering;
import sys.io.File;

/** Native observers inspect emitted macro values, including their nested operator arguments. */
class M14MacroBinaryNativeTest {
	static final root = "test/oracle/source_parenthesized_seed/";
	static final output = ".tmp/macro-binary-native/";

	/** Bound each compiler/runtime process group and return only successful observer output. */
	static function command(executable:String, arguments:Array<String>):String {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", executable].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw executable + " failed: " + stdout + stderr;
		return stdout;
	}

	public static function run():Void {
		sys.FileSystem.createDirectory(output);
		final tokens = [
			for (token in File.getContent(root + "binary.tokens").split("\n"))
				if (token.length > 0) token
		];
		final expressions = [
			for (token in tokens)
				HxParser.parseCompleteExprText("((left " + token + " right))")
		];
		for (target in ["cpp", "js", "py", "php", "neko"]) {
			final calls = new Array<String>();
			for (index in 0...tokens.length) {
				final source = expressions[index];
				final value = switch target {
					case "cpp": CppMacroExpr.macroExpr(source, []);
					case "js": JsExprEmitter.emit(EMacroExpr(source, []), null);
					case "py": @:privateAccess SourceTargetCommon.pythonMacroExpr(source, []);
					case "php": @:privateAccess SourceTargetCommon.phpMacroExpr(source, []);
					case "neko": NekoMacroExprLowering.render(source, [], _ -> throw "native operator probe reached unsupported fallback");
					case _: throw "unknown native observer";
				};
				calls.push("check(" + haxe.Json.stringify(tokens[index]) + ", " + value + ")" + (target == "py" ? "" : ";"));
			}
			var program = File.getContent(root + "observers/main." + target);
			program = StringTools.replace(program, target == "py" ? "# VALUES" : "/*VALUES*/", calls.join("\n"));
			if (target == "cpp")
				program = StringTools.replace(program, "/*RUNTIME*/", CppMacroExpr.runtimePreludeLines().join("\n"));
			final path = output + "main." + target;
			File.saveContent(path, program);
			final stdout = switch target {
				case "cpp":
					command("c++", ["-std=c++17", path, "-o", output + "main"]);
					command(output + "main", []);
				case "js": command("node", [path]);
				case "py": command("python3", [path]);
				case "php": command("php", [path]);
				case "neko":
					command("nekoc", [path]);
					command("neko", [output + "main.n"]);
				case _: throw "unknown observer runner";
			};
			File.saveContent(output + target + ".stdout", stdout);
			if (stdout != File.getContent(root + "binary.stdout"))
				throw target + " macro values differ from upstream:\n" + stdout;
			Sys.println("MACRO_BINARY_NATIVE:PASS " + target);
		}
	}

	static function main():Void
		run();
}
