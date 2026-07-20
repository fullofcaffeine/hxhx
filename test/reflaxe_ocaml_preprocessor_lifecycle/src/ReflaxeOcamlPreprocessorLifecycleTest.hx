#if macro
import haxe.macro.Context;
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Type.TypedExpr;
import reflaxe.preprocessors.implementations.RemovePureExpressionsImpl;
#end

/** Focused executable probe for the generic Reflaxe metadata-preservation boundary. */
class ReflaxeOcamlPreprocessorLifecycleTest {
	#if macro
	public static function verifyMarkerPreservation():Void {
		final position = Context.currentPos();
		final intType = Context.getType("Int");
		final operand:TypedExpr = {
			expr: TConst(TInt(0)),
			pos: position,
			t: intType
		};
		final update:TypedExpr = {
			expr: TUnop(OpIncrement, true, operand),
			pos: position,
			t: intType
		};
		final metadata:MetadataEntry = {
			name: ":reflaxeOcamlPlaceProtection",
			params: [],
			pos: position
		};
		final marked:TypedExpr = {
			expr: TMeta(metadata, update),
			pos: position,
			t: intType
		};

		final processed = RemovePureExpressionsImpl.process([marked]);
		switch (processed) {
			case [{expr: TMeta(result, {expr: TUnop(OpIncrement, true, _)})}] if (result.name == metadata.name):
				Sys.println("REFLAXE_REMOVE_PURE_MARKER_PRESERVATION:CONFIRMED");
			case [{expr: TUnop(OpIncrement, true, _)}]:
				Context.fatalError("Reflaxe cleanup removed the target-owned standalone-update envelope", position);
			case _:
				Context.fatalError("unexpected standalone-update shape after Reflaxe pure-expression cleanup", position);
		}
	}
	#end

	static function main():Void {}
}
