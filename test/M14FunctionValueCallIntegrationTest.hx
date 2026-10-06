import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Function values use the same argument rules with direct and typedef signatures. */
class M14FunctionValueCallIntegrationTest {
	static var standardModules:Null<Array<ResolvedModule>>;

	/** Use real provider headers so container compatibility cannot succeed on unresolved spelling. */
	static function spreadProviders():Array<ResolvedModule> {
		if (standardModules == null) {
			final arguments = Stage1Args.parse(["-main", "Main"], true);
			require(arguments != null, "spread fixture arguments did not parse");
			final paths = Stage3SetupSupport.projectClassPaths({
				explicitPaths: [],
				libraries: [],
				cwd: Sys.getCwd(),
				standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
				targetDefine: "neko"
			});
			standardModules = ResolverStage.parseProjectRootsShallow(paths, ["Array", "haxe.Rest"],
				Stage3SetupSupport.buildDefinesMap([], "neko", "neko-native"));
		}
		return standardModules.copy();
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function typed(signature:String, call:String, alias:Bool, extraParameter:String = ""):TypedFunction {
		final source = (alias ? "typedef Callback=" + signature + ";" : "") + "class Main { static function check(f:" + (alias ? "Callback" : signature)
			+ extraParameter + "):Int return " + call + "; }";
		final parsed = ParserStage.parse(source, "Main.hx");
		final module = new ResolvedModule("Main", "Main.hx", parsed);
		final modules = extraParameter.length == 0 ? [module] : [module].concat(spreadProviders());
		return TyperStage.typeResolvedModule(module, TyperIndex.build(modules)).getTypedClasses()[0].getFunctions()[0];
	}

	static function main():Void {
		final cases = [
			{signature: "(value:Int,?text:String)->Int", call: "f()", error: "Not enough arguments"},
			{signature: "(value:Int,?text:String)->Int", call: 'f("wrong")', error: "String should be Int"},
			{signature: "(value:Int,?text:String)->Int", call: 'f(1,"x",true)', error: "Too many arguments"},
			{signature: "(value:Int,?text:String)->Int", call: "f(1)", error: ""},
			{signature: "(value:Int,?text:String)->Int", call: 'f(1,"x")', error: ""},
			{signature: "(value:Int,?text:String)->Int", call: "f(1,null)", error: ""},
			{signature: "(?text:String,value:Int)->Int", call: "f(1)", error: ""},
			{signature: "(?text:String,value:Int)->Int", call: 'f("text")', error: "Not enough arguments"},
			{signature: "(?first:Int,value:Int)->Int", call: "f(1)", error: "Not enough arguments"},
			{signature: "(?text:String,value:Int)->Int", call: "f(null,1)", error: ""},
			{signature: "(?text:String,?flag:Bool,value:Int)->Int", call: "f(1)", error: ""},
			{signature: "(?text:String,?flag:Bool,value:Int)->Int", call: "f(1,2)", error: "Int should be String"},
			{signature: "(?text:String,?flag:Bool,value:Int)->Int", call: "f(true,1)", error: ""},
			{signature: "(?text:String,?flag:Bool,value:Int,...tail:Int)->Int", call: "f(1,2)", error: ""},
			{signature: "(?text:String,?flag:Bool,value:Int,...tail:Int)->Int", call: "f(1,2,3)", error: "Int should be String"},
			{signature: "(?text:String,?flag:Bool,value:Int,...tail:Int)->Int", call: "f(true,1,2)", error: ""},
			{signature: "(?text:String,?flag:Bool,value:Int,...tail:Int)->Int", call: "f(true,1,2,3)", error: "Bool should be String"},
			{signature: "(?text:String,?flag:Bool,value:Int,...tail:Int)->Int", call: "f(null,true,1,2)", error: ""},
			{signature: "(?text:String,value:Int,flag:Bool)->Int", call: "f(1,2)", error: "Int should be String"},
			{signature: "(?text:String,value:Int,flag:Bool)->Int", call: "f(1,true)", error: ""},
			{signature: "(?text:String,value:Int,flag:Bool)->Int", call: "f(null,1,2)", error: "Int should be Bool"},
			{signature: "(?text:String,value:Int,flag:Bool)->Int", call: "f(1)", error: "Not enough arguments"}
		];
		final mismatches = new Array<String>();
		for (alias in [false, true])
			for (entry in cases) {
				var diagnostic = "";
				try {
					typed(entry.signature, entry.call, alias);
				} catch (error:TyperError) {
					diagnostic = error.message;
					require(error.filePath == "Main.hx" && error.pos.getLine() == 1, "call error lost its source: " + error.toString());
				}
				if (!(entry.error.length == 0 ? diagnostic.length == 0 : StringTools.startsWith(diagnostic, entry.error)))
					mismatches.push("wrong function call result for " + entry.signature + " " + entry.call + " alias=" + alias + ": " + diagnostic);
			}
		require(mismatches.length == 0, mismatches.join("\n"));
		Sys.println("FUNCTION_VALUE_CALL_DIAGNOSTICS:PASS cases=" + (cases.length * 2));
		spreadCalls();
		observe("(?text:String,value:Int)->Int", "f(7)", "function(text,value){seen.push(arguments.length,text===null);return value;}", "7:2:true",
			"[Omitted,Supplied(0)]");
		observe("(value:Int,?text:String)->Int", "f(7)", "function(value,text){seen.push(arguments.length,text===undefined);return value;}", "7:1:true",
			"[Supplied(0),Omitted]");
		observe("(value:Int,?text:String)->Int", "f(7,null)", "function(value,text){seen.push(arguments.length,text===null);return value;}", "7:2:true",
			"[Supplied(0),Supplied(1)]");
		observe("(?text:String,?flag:Bool,value:Int)->Int", "f(7)",
			"function(text,flag,value){seen.push(arguments.length,text===null,flag===null);return value;}", "7:3:true:true", "[Omitted,Omitted,Supplied(0)]");
		observe("(value:Int,?text:String,...tail:Int)->Int", "f(7)",
			"function(value,text,...tail){seen.push(arguments.length,text===undefined,tail.length);return value;}", "7:1:true:0",
			"[Supplied(0),Omitted,RestElements([])]");
		observe("(?text:String,value:Int,...tail:Int)->Int", "f(7,8)",
			"function(text,value,...tail){seen.push(arguments.length,text===null,tail.join(','));return value;}", "7:3:true:8",
			"[Omitted,Supplied(0),RestElements([1])]");
		Sys.println("FUNCTION_VALUE_CALL_BINDING:PASS");
	}

	/** Typed container inputs distinguish invariant spread elements from individual rest arguments. */
	static function spreadCalls():Void {
		final cases = [
			{
				element: "Int",
				container: "Array<Int>",
				call: "f(...values)",
				accepted: true
			},
			{
				element: "Float",
				container: "Array<Int>",
				call: "f(...values)",
				accepted: false
			},
			{
				element: "Int",
				container: "Array<Float>",
				call: "f(...values)",
				accepted: false
			},
			{
				element: "Int",
				container: "Array<Dynamic>",
				call: "f(...values)",
				accepted: false
			},
			{
				element: "Int",
				container: "haxe.Rest<Int>",
				call: "f(...values)",
				accepted: true
			},
			{
				element: "Float",
				container: "haxe.Rest<Int>",
				call: "f(...values)",
				accepted: false
			},
			{
				element: "Int",
				container: "Dynamic",
				call: "f(...values)",
				accepted: true
			},
			{
				element: "Int",
				container: "Int",
				call: "f(...values)",
				accepted: false
			},
			{
				element: "Int",
				container: "Array<Int>",
				call: "f(1,...values)",
				accepted: false
			}
		];
		for (alias in [false, true])
			for (entry in cases) {
				var diagnostic = "";
				try {
					typed("(...tail:" + entry.element + ")->Int", entry.call, alias, ",values:" + entry.container);
				} catch (error:TyperError) {
					diagnostic = error.message;
					require(error.filePath == "Main.hx" && error.pos.getLine() == 1, "spread error lost its source");
				}
				require((diagnostic.length == 0) == entry.accepted,
					"spread acceptance differs for "
					+ entry.container
					+ " into "
					+ entry.element
					+ " alias="
					+ alias
					+ ": "
					+ diagnostic);
				require(diagnostic.indexOf("not yet supported") < 0, "spread case lacks compatibility proof: " + diagnostic);
			}
		Sys.println("FUNCTION_VALUE_SPREAD_DIAGNOSTICS:PASS cases=" + (cases.length * 2));
	}

	/** A native JS observer distinguishes a skipped interior argument from an omitted tail. */
	static function observe(signature:String, call:String, observer:String, expected:String, expectedSlots:String):Void {
		final functionBody = typed(signature, call, true);
		final typedCall = functionBody.getBody().getStatements()[0].getExpressions()[0];
		require(typedCall.getArgumentBinding() != null, "function-value call lost its checked argument mapping");
		final mapping = typedCall.getArgumentBinding().getSlots();
		require(Std.string(mapping) == expectedSlots, "call omission mapping differs: " + Std.string(mapping));
		final projection = TypedBodySource.functionProjection(functionBody);
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>(), null, null, projection.getLocalCatalog());
		final argument = HxFunctionDecl.getArgs(projection.getDeclaration())[0];
		final name = scope.declareLocal(HxFunctionArg.getName(argument));
		final expression = switch (HxFunctionDecl.getBody(projection.getDeclaration())[0]) {
			case SReturn(value, _): value;
			case _: throw "missing projected call";
		};
		final generated = JsExprEmitter.emit(expression, scope.exprScope());
		final process = new sys.io.Process("node", [
			"-e",
			"const seen=[];const " + name + "=" + observer + ";console.log([" + generated + "].concat(seen).join(':'));"
		]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0 && StringTools.trim(output) == expected, "native call observation differs: "
			+ output
			+ errors
			+ " from "
			+ generated);
	}
}
