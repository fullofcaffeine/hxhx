import backend.cpp.CppMacroExpr;
import backend.source.SourceTargetCommon;
import backend.vm.NekoMacroExprLowering;

/**
	Quotations keep authored brace boundaries, including empty and nested groups: in the typer's
	lowering (every typed module) and in the per-target quote adapters used by fallback modules.
**/
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
		// The typer lowers each quote to the construction of its `Expr` value; that construction
		// must keep the authored grouping (`{ { 1; 2; } 3; }` is two nested `EBlock`s).
		final lowered = [
			for (source in sources) {
				final typed = TyperStage.typeModule(ParserStage.parse(wrap(source), "Main.hx"));
				typed.getBackendProjection();
				loweredShape(typed.getTypedClasses()[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0]);
			}
		];
		if (lowered.join("\n") != expected)
			throw "typed quotation lowering changed source brace grouping: " + lowered.join("\n");
		// The per-target quote adapters below now run only for modules built without the typer
		// (`TypedBodyBuilder.buildFallbackModule`), which keeps the quote node; feed them that input.
		final projected = new Array<HxExpr>();
		for (source in sources) {
			final fallback = TypedBodyBuilder.buildFallbackModule(ParserStage.parse(wrap(source), "Main.hx"), null);
			final quote = fallback[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0];
			if (quote.getTag() != MacroExpr)
				throw "fallback module lost its quotation node";
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
		final arrayFactory = NekoMacroArrayFixture.prepare(root);
		// Neko closures capture locals by value; keep the recursive observer in a shared object slot.
		final neko = "var observer=$new(null); observer.shape=function(value) { var node=value.expr; if(node.__hx_ctor == \"EBlock\") {"
			+ " var items=node.__hx_params[0]; var out=\"block(\"; var i=0; while(i<items.length){ if(i>0)out=out+\",\";"
			+ " out=out+observer.shape(items[i]); i=i+1; } return out+\")\"; }"
			+ " if(node.__hx_ctor != \"EConst\" || node.__hx_params[0].__hx_ctor != \"CInt\") $throw(\"quote shape\");"
			+ " return node.__hx_params[0].__hx_params[0]; };\n"
			+ [
				for (value in projected)
					"$print(observer.shape(" + NekoMacroExprLowering.render(value, [], _ -> throw "source group used fallback", arrayFactory) + "),\"\\n\");"
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

	static function wrap(source:String):String
		return "class Main { static function main() { var quoted = macro " + source + "; } }";

	/** The `block(...)`/integer shape of a lowered `{expr: <ExprDef>, pos: <Position>}` construction. */
	static function loweredShape(record:TypedExpr):String {
		if (record.getTag() != Anonymous || record.getTexts().join(",") != "expr,pos")
			throw "quotation was not lowered to an Expr record";
		final definition = record.getExpressions()[0];
		return switch constructorName(definition) {
			case "EBlock": "block(" + [for (item in definition.getExpressions()[1].getExpressions()) loweredShape(item)].join(",") + ")";
			case "EConst":
				final constant = definition.getExpressions()[1];
				if (constructorName(constant) != "CInt")
					throw "lowered constant is not an integer";
				constant.getExpressions()[1].getTexts()[0];
			case name: throw "unexpected lowered constructor `" + name + "`";
		};
	}

	/** The constructor a lowered call names; `typeModule` loads no `haxe.macro.Expr`, so read the callee's last segment. */
	static function constructorName(call:TypedExpr):String {
		final callee = call.getTag() == Call ? call.getExpressions()[0] : null;
		return callee != null && callee.getTag() == FieldRead ? callee.getTexts()[0] : "";
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
