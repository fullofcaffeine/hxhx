import backend.cpp.CppManagedStartupOrder;
import backend.cpp.CppTypedProgramProjection;
import backend.vm.NekoStaticInitializationPlan;
import backend.vm.NekoTypedProgramProjection;

/** Authored dependency fixtures preserve class order through both target admission adapters. */
class M14SharedStaticStartupOrderTest {
	static function check(sources:Array<{name:String, source:String}>, expected:String):Void {
		final resolved = [
			for (entry in sources)
				new ResolvedModule(entry.name, entry.name + ".hx", ParserStage.parse(entry.source, entry.name + ".hx"))
		];
		final index = TyperIndex.buildHeaders(resolved);
		final loader = new ModuleLoader(["."], HxDefineMap.fromRawDefines([]), index, function(_):Bool return false);
		loader.markResolvedAlready(resolved);
		final typed = [for (entry in resolved) TyperStage.typeResolvedModule(entry, index, loader)];
		final source = new MacroExpandedProgram(typed, false);
		final cpp = new CppManagedStartupOrder(new CppTypedProgramProjection(source));
		final neko = new NekoStaticInitializationPlan(source,
			new NekoTypedProgramProjection(source.getTypedProgramRevision().getCanonicalIdentity(), [for (entry in typed) entry.getBackendProjection()]));
		for (order in [cpp.getClasses(), neko.getClasses()]) {
			final actual = [for (owner in order) HxClassDecl.getName(owner.getDeclaration())].join(",");
			if (actual != expected)
				throw "shared startup order: expected " + expected + ", got " + actual;
		}
		cpp.getClasses().pop();
		neko.getClasses().pop();
		if (cpp.getClasses().length != neko.getClasses().length || cpp.getClasses().length != expected.split(",").length)
			throw "startup order exposed its owned result array";
		Sys.println("SHARED_STATIC_STARTUP_ORDER:PASS " + expected);
	}

	static function main():Void {
		check([
			{
				name: "Main",
				source: 'class Main {static var own:Int=9; public static function mark(value:Int):Int{return value;} static function main():Void {}}
class Alpha {public static var first:Int=Main.mark(1); public static var second:Int=Main.mark(Beta.value);}
class Beta {public static var value:Int=Main.mark(2);}
class Unused {public static var value:Int=Main.mark(3);}'
			}
		], "Main,Beta,Alpha,Unused");
		check([
			{
				name: "Main",
				source: 'class Main {static function main():Void {}}
class Alpha {public static var value:Int=Beta.read();}
class Beta {public static var value:Int=2; public static var later:Void->Int=function():Int {return Gamma.value;}; public static function read():Int {final get=function():Int {return Gamma.value;}; return value;}}
class Gamma {public static var value:Int=3;}'
			}
		], "Main,Beta,Gamma,Alpha");
		check([
			{name: "Main", source: 'import Helper; class Main {static var own:Int=1; static function main():Void {}} class Sibling {static var value:Int=2;}'},
			{name: "Helper", source: 'class Helper {public static var value:Int=3;}'}
		], "Helper,Main,Sibling");
	}
}
