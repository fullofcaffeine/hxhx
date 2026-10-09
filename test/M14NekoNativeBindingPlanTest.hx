import backend.vm.NekoStaticInitializationPlan;
import backend.vm.NekoTypedProgramProjection;

/** Selection-only observer: the library body throws if anyone accidentally executes it. */
class M14NekoNativeBindingPlanTest {
	static function main():Void {
		final libSource = 'package neko;class Lib {public static function load(library:String,primitive:String,arity:Int):Dynamic {throw "selection fixture must not execute";}}';
		final source = 'import neko.Lib as Native;class Main {static var literal=neko.Lib.load("std","sys_string",0);static var alias=Native.load("std","sys_string",0);static var dynamicField:Dynamic=neko.Lib.load("std","sys_string",0);static var typed:Void->String=neko.Lib.load("std","sys_string",0);static var computed=neko.Lib.load(library(),"sys_string",0);static var concat=neko.Lib.load("s"+"td","sys_string",0);static var factory=create();static var other=Other.load("std","sys_string",0);static function library():String{return "std";}static function create():Dynamic{return neko.Lib.load("std","sys_string",0);}static function main():Void {}}class Other {public static function load(library:String,primitive:String,arity:Int):Dynamic {throw "wrong owner";}}';
		final modules = [
			new ResolvedModule("neko.Lib", "neko/Lib.hx", ParserStage.parse(libSource, "neko/Lib.hx")),
			new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"))
		];
		final index = TyperIndex.buildHeaders(modules);
		final loader = new ModuleLoader([], HxDefineMap.fromRawDefines(["neko=1"]), index);
		loader.markResolvedAlready(modules);
		final expanded = MacroStage.expandProgram([for (module in modules) TyperStage.typeResolvedModule(module, index, loader)], []);
		final projections = [for (module in expanded.getTypedModules()) module.getBackendProjection()];
		final program = new NekoTypedProgramProjection("native-binding-selection", projections);
		final plan = new NekoStaticInitializationPlan(expanded, program);
		var checked = 0;
		for (module in projections)
			for (owner in module.getClasses())
				for (initializer in owner.getFieldInitializers()) {
					final name = initializer.getField().getName();
					final expected = name == "literal" || name == "alias" || name == "dynamicField";
					final binding = plan.earlyNativeBinding(initializer);
					if ((binding != null) != expected) {
						Sys.println(name + " type=" + initializer.getField().getType().getSemanticKey() + " expr=" + Std.string(initializer.getExpression()));
						throw "wrong native binding selection: " + name;
					}
					if (binding != null && (binding.library != "std" || binding.primitive != "sys_string" || binding.arity != 0))
						throw "wrong primitive payload";
					checked++;
				}
		if (checked != 8)
			throw "selection cases missing";
		Sys.println("NEKO_NATIVE_BINDING_PLAN:PASS cases=" + checked);
	}
}
