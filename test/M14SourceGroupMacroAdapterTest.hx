import backend.cpp.CppMacroExpr;
import backend.source.SourceTargetCommon;
import backend.vm.NekoMacroExprLowering;

/** Native quotation adapters preserve authored brace boundaries, including empty and nested groups. */
class M14SourceGroupMacroAdapterTest {
	public static function run():Void {
		final sources = ["{ 1; 2; }", "{ { 1; 2; } 3; }", "{ 1; { 2; 3; } }", "{}"];
		final expected = "block(1,2)\nblock(block(1,2),3)\nblock(1,block(2,3))\nblock()";
		final root = ".tmp/source_group_adapters_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final upstream = "import haxe.macro.Expr; class Main { static function shape(value:Expr):String return switch value.expr {"
			+ " case EBlock(items): 'block(' + [for (item in items) shape(item)].join(',') + ')';"
			+ " case EConst(CInt(value, _)): value; case _: throw 'unexpected macro shape'; }; static function main() {"
			+ [for (source in sources) "Sys.println(shape(macro " + source + "));"].join("\n") + "} }";
		sys.io.File.saveContent(root + "/Main.hx", upstream);
		check("haxe", ["-cp", root, "-main", "Main", "--interp"], expected);
		final projected = new Array<HxExpr>();
		for (source in sources) {
			final parsed = ParserStage.parse("class Main { static function main() { var quoted = macro " + source + "; } }", "Main.hx");
			final typed = TyperStage.typeModule(parsed);
			typed.getBackendProjection();
			final quote = typed.getTypedClasses()[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0];
			projected.push(TypedSourceSyntax.expression(quote.getExpressions()[0]));
		}
		final cpp = "#include <iostream>\n#include <memory>\n#include <sstream>\n#include <stdexcept>\n#include <string>\n#include <vector>\n"
			+ CppMacroExpr.runtimePreludeLines().join("\n")
			+ "\nstd::string shape(const __HxMacroExpr& value) { const auto& node = *value.expr;"
			+ " if(node.__hx_ctor == \"EBlock\") { std::string out=\"block(\"; for(std::size_t i=0;i<node.__hx_params.size();++i) {"
			+ " if(i)out+=\",\"; out+=shape(node.__hx_params.at(i)); } return out+\")\"; }"
			+ " if(node.__hx_ctor != \"EConst\" || node.__hx_params.at(0).__hx_ctor != \"CInt\") throw std::runtime_error(\"quote shape\");"
			+ " return node.__hx_params.at(0).__hx_params.at(0).__hx_value; } int main() {"
			+ [
				for (value in projected)
					"std::cout << shape(" + CppMacroExpr.macroExpr(value, []) + ") << std::endl;"
			].join("\n") + "}";
		sys.io.File.saveContent(root + "/quote.cpp", cpp);
		command("c++", ["-std=c++17", "-o", root + "/quote.exe", root + "/quote.cpp"]);
		check(root + "/quote.exe", [], expected);
		// Neko closures capture locals by value; keep the recursive observer in a shared object slot.
		final neko = "var observer=$new(null); observer.shape=function(value) { var node=value.expr; if(node.__hx_ctor == \"EBlock\") {"
			+ " var items=node.__hx_params[0]; var out=\"block(\"; var i=0; while(i<$asize(items)){ if(i>0)out=out+\",\";"
			+ " out=out+observer.shape(items[i]); i=i+1; } return out+\")\"; }"
			+ " if(node.__hx_ctor != \"EConst\" || node.__hx_params[0].__hx_ctor != \"CInt\") $throw(\"quote shape\");"
			+ " return node.__hx_params[0].__hx_params[0]; };\n"
			+ [
				for (value in projected)
					"$print(observer.shape(" + NekoMacroExprLowering.render(value, [], _ -> throw "source group used fallback") + "),\"\\n\");"
			].join("\n");
		sys.io.File.saveContent(root + "/quote.neko", neko);
		command("nekoc", [root + "/quote.neko"]);
		check("neko", [root + "/quote.n"], expected);
		final python = "from types import SimpleNamespace as hxhx_anon\ndef shape(value):\n node=value.expr\n"
			+ " if node.__hx_ctor == 'EBlock': return 'block('+','.join(shape(item) for item in node.__hx_params[0])+')'\n"
			+ " assert node.__hx_ctor == 'EConst' and node.__hx_params[0].__hx_ctor == 'CInt'\n return node.__hx_params[0].__hx_params[0]\n"
			+ [
				for (value in projected)
					"print(shape(" + @:privateAccess SourceTargetCommon.pythonMacroExpr(value, []) + "))"
			].join("\n");
		sys.io.File.saveContent(root + "/quote.py", python);
		check("python3", [root + "/quote.py"], expected);
		final php = "<?php function shape($value) { $node=$value->expr; if($node->__hx_ctor === 'EBlock')"
			+ " return 'block('.implode(',',array_map('shape',$node->__hx_params[0])).')';"
			+ " if($node->__hx_ctor !== 'EConst' || $node->__hx_params[0]->__hx_ctor !== 'CInt') throw new Exception('quote shape');"
			+ " return $node->__hx_params[0]->__hx_params[0]; }\n"
			+ [
				for (value in projected)
					"echo shape(" + @:privateAccess SourceTargetCommon.phpMacroExpr(value, []) + "),\"\\n\";"
			].join("\n");
		sys.io.File.saveContent(root + "/quote.php", php);
		check("php", [root + "/quote.php"], expected);
		Sys.println("SOURCE_GROUP_MACRO_ADAPTERS:PASS");
	}

	static function check(executable:String, arguments:Array<String>, expected:String):Void {
		final output = command(executable, arguments);
		if (StringTools.trim(output) != expected)
			throw executable + " changed source brace grouping: " + output;
	}

	static function command(executable:String, arguments:Array<String>):String {
		final process = new sys.io.Process(executable, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw executable + " failed: " + output + errors;
		return output;
	}
}
