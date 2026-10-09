#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.OcamlBuildContext;
import reflaxe.ocaml.macros.StrictModeEnforcer;

/**
	Observes when validation reads its declaration inventory.

	The enum wrapper forwards to a real compiler declaration and counts reads.
	It instruments the validator boundary only; it does not claim that arbitrary
	macro getters are eligible for native-surface result reuse.
**/
class NativeSurfaceOrderFixture {
	public static function run():Void {
		final pure = classDeclaration("NativeSurfaceOrderCases.PureOrderCase");
		final strict = classDeclaration("NativeSurfaceOrderCases.StrictOrderCase");
		final enumeration = switch Context.getType("NativeSurfaceOrderCases.InventoryOrderCase") {
			case TEnum(reference, _): reference;
			case _: throw new haxe.Exception("Expected enum declaration");
		};
		Context.onAfterGenerate(() -> {
			@:privateAccess StrictModeEnforcer.performanceLogLine = _ -> {};
			var inventoryReads = 0;
			final observed:ModuleType = TEnumDecl({
				get: () -> {
					inventoryReads++;
					if (Context.defined("native_surface_order_strict"))
						Sys.println("NATIVE_SURFACE_INVENTORY_READ");
					return enumeration.get();
				},
				toString: () -> "inventory observation"
			});
			final activeContext = new OcamlBuildContext(Portable, Emulated, false, true, Warn, Full, [], false, false, false);
			if (Context.defined("native_surface_order_strict")) {
				// The runner checks the compiler's fatal diagnostic and absence of inventory reads.
				@:privateAccess StrictModeEnforcer.enforce([strict, observed], Sys.getCwd(), activeContext);
				throw new haxe.Exception("Expected first strict diagnostic");
			}
			final strictContext = new OcamlBuildContext(Metal, Emulated, false, true, Allow, Full, [], false, false, false);
			@:privateAccess StrictModeEnforcer.enforce([pure, observed], Sys.getCwd(), strictContext);
			check(inventoryReads == 0, "inactive native policies must not read the inventory");
			check(StrictModeEnforcer.performanceSnapshot().strictChecks >= 2, "pure class must actually be scanned");

			@:privateAccess StrictModeEnforcer.enforce([pure, observed], Sys.getCwd(), activeContext);
			check(inventoryReads == 1, "an active native query must read the inventory once");
			check(StrictModeEnforcer.performanceSnapshot().portableNativeSurfaceChecks >= 2, "multiple native queries must share the inventory");
			@:privateAccess StrictModeEnforcer.performanceLogLine = null;
			Sys.println("NATIVE_SURFACE_ORDER:PASS");
		});
	}

	static function classDeclaration(path:String):ModuleType {
		return switch Context.getType(path) {
			case TInst(reference, _): TClassDecl(reference);
			case _: throw new haxe.Exception("Expected class declaration");
		};
	}

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw new haxe.Exception(message);
	}
}
#end
