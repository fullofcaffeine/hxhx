import backend.cpp.CppManagedStartupOrder;
import backend.cpp.CppTypedProgramProjection;

/** Use the native-oracle source fixtures and real loaded providers to check initialization order. */
class M14CppManagedStartupOrderTest {
	static var checked:Int = 0;

	static function check(fixture:String, mode:String, expected:String):Void {
		final requested = Sys.args();
		if (requested.length > 0 && requested[0] != fixture + "/" + mode)
			return;
		checked++;
		final started = haxe.Timer.stamp();
		final resolved = CppResolvedFixture.load({
			sourceRoot: "test/fixtures/cpp_static_startup_oracle/" + fixture,
			mainModule: "Main",
			requiredModules: ["Sys"],
			defines: [mode]
		});
		final loaded = haxe.Timer.stamp();
		final program = new CppTypedProgramProjection(new MacroExpandedProgram(resolved.modules, false));
		final projected = haxe.Timer.stamp();
		final order = new CppManagedStartupOrder(program).getClasses();
		final scheduled = haxe.Timer.stamp();
		final observed = [];
		for (owner in order) {
			final facts = owner.requireSemanticFacts();
			if (facts.getModuleIdentity() != "Main" && facts.getModuleIdentity() != "Helper")
				continue;
			final hasStartup = owner.getFieldInitializers().length > 0
				|| Lambda.exists(owner.getFunctions(), fn -> fn.requireSemanticDeclaration().getSignature().getName() == "__init__");
			if (hasStartup)
				observed.push(HxClassDecl.getName(owner.getDeclaration()));
		}
		if (observed.join(",") != expected)
			throw fixture + "/" + mode + ": expected " + expected + ", got " + observed.join(",");
		if (order.length != Lambda.fold(program.getModules(), (module, count) -> count + module.projection.getClasses().length, 0))
			throw "startup order discarded a loaded class";
		Sys.println("CPP_MANAGED_STARTUP_ORDER_CASE:PASS " + fixture + "/" + mode + " load_s=" + (loaded - started) + " projection_s="
			+ (projected - loaded) + " schedule_s=" + (scheduled - projected));
	}

	static function main():Void {
		check("order", "none", "Main,Beta,Alpha,Unused");
		check("transitive", "none", "Beta,Alpha,Gamma");
		for (mode in ["eager", "invoked", "stored", "dead"])
			check("transitive", mode, "Beta,Gamma,Alpha");
		check("modules", "none", "Main,Sibling");
		for (mode in ["dead_call", "type_only", "deferred_call"])
			check("modules", mode, "Helper,Main,Sibling");
		check("cycle", "none", "Main,Beta,Alpha");
		if (checked == 0)
			throw "unknown startup fixture selection";
		Sys.println("CPP_MANAGED_STARTUP_ORDER:PASS");
	}
}
