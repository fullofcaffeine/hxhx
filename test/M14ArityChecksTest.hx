/**
	Explicit type-argument counts and constructor argument counts must be checked like
	Haxe 4.3.7 does.

	Before this test, hxhx accepted `new Box<Int>()` for `class Box<A, B>`, accepted
	`new P(1)` and `new P(1, 2, 3)` for `new(x:Int, y:Int)`, and accepted `new NoCtor()`.
	Each case in test/oracle/arity_checks_seed is first checked with upstream Haxe, then
	typed by hxhx with the production class paths. `Accepted` holds neighbors that must
	still type: inferred and defaulted type arguments, optional and rest arguments,
	inherited, generic and overloaded constructors, and standard-library types.
 */
class M14ArityChecksTest {
	static final root = "test/oracle/arity_checks_seed";

	static function main():Void {
		upstream("Accepted", null);
		load("Accepted");
		Sys.println("ARITY_CHECK_ACCEPT:PASS");
		for (entry in [
			{module: "AbstractNoConstructor", diagnostic: "Bare does not have a constructor"},
			{module: "AbstractTooFew", diagnostic: "Not enough arguments, expected v:Int"},
			{module: "AbstractTooManyTypes", diagnostic: "Too many type parameters for Wrap"},
			{module: "ArgumentTooFewTypes", diagnostic: "Not enough type parameters for Box"},
			{module: "CtorNone", diagnostic: "Not enough arguments, expected x:Int, y:Int"},
			{module: "CtorTooFew", diagnostic: "Not enough arguments, expected y:Int"},
			{module: "CtorTooMany", diagnostic: "Too many arguments"},
			{module: "FieldTooFewTypes", diagnostic: "Not enough type parameters for Box"},
			{module: "GenericCtorTooManyTypes", diagnostic: "Too many type parameters for G"},
			{module: "GenericInheritedTooFew", diagnostic: "Not enough arguments, expected v:Int"},
			{module: "GenericTooFew", diagnostic: "Not enough arguments, expected v:Unknown<0>"},
			{module: "GenericTooMany", diagnostic: "Too many arguments"},
			{module: "InheritedTooFew", diagnostic: "Not enough arguments, expected y:Int"},
			{module: "InheritedTooMany", diagnostic: "Too many arguments"},
			{module: "InterfaceConstructor", diagnostic: "IFace does not have a constructor"},
			{module: "LocalTooFewTypes", diagnostic: "Not enough type parameters for Box"},
			{module: "NewEmptyTypes", diagnostic: "Unexpected >"},
			{module: "NewTooFewTypes", diagnostic: "Not enough type parameters for Box"},
			{module: "NewTooManyTypes", diagnostic: "Too many type parameters for Box"},
			{module: "NewTrailingTypeComma", diagnostic: "Unexpected >"},
			{module: "NoConstructor", diagnostic: "NoCtor does not have a constructor"},
			{module: "NoInheritedConstructor", diagnostic: "NoCtorChild does not have a constructor"},
			{module: "OptionalTooFew", diagnostic: "Not enough arguments, expected x:Int, y:Null<Int>"},
			{module: "OptionalTooMany", diagnostic: "Too many arguments"},
			{module: "OverloadNoMatch", diagnostic: "Could not find a suitable overload, reasons follow"},
			{module: "RestTooFew", diagnostic: "Not enough arguments, expected x:Int, more:haxe.Rest<Int>"},
			{module: "ReturnTooManyTypes", diagnostic: "Too many type parameters for Box"},
			{module: "StdTooFew", diagnostic: "Not enough arguments, expected message:String, previous:Null<haxe.Exception>, native:Null<Any>"},
			{module: "TypedefTooFewTypes", diagnostic: "Not enough type parameters for Pair"},
			{module: "TypedefTooManyTypes", diagnostic: "Too many type parameters for Pair"}
		]) {
			upstream(entry.module, entry.diagnostic);
			var message:Null<String> = null;
			try
				load(entry.module)
			catch (error:TyperError) {
				if (!StringTools.endsWith(error.getFilePath(), root + "/" + entry.module + ".hx"))
					throw error;
				message = error.getMessage();
			} catch (error:haxe.Exception) {
				// Syntax errors surface from module loading as "parse_failed <path>: <message>".
				final prefix = "parse_failed ";
				final suffix = entry.module + ".hx: " + entry.diagnostic;
				if (!StringTools.startsWith(error.message, prefix) || !StringTools.endsWith(error.message, suffix))
					throw error;
				message = entry.diagnostic;
			}
			if (message != entry.diagnostic)
				throw "arity diagnostic differs for " + entry.module + ": " + message;
			Sys.println("ARITY_CHECK_REJECT:PASS " + entry.module);
		}
		Sys.println("ARITY_CHECKS:PASS");
	}

	static function load(module:String):Void {
		CppResolvedFixture.load({sourceRoot: root, mainModule: module, requiredModules: []});
	}

	/** The first upstream diagnostic line must carry the same message hxhx reports. */
	static function upstream(module:String, diagnostic:Null<String>):Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", module, "--no-output"]);
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		final first = stderr.split("\n")[0];
		if (diagnostic == null ? code != 0 : code == 0 || !StringTools.endsWith(first, " : " + diagnostic))
			throw "upstream arity contract differs for " + module + ": " + stderr;
	}
}
