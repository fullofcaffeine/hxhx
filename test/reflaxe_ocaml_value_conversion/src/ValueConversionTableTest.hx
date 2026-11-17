#if macro
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.lowered.OcamlValueConversion;
#end

enum ConversionColor {
	Red;
	Green;
}

enum ConversionShape {
	Dot;
}

class ConversionBox {
	public function new() {}
}

abstract ConversionList(Array<Int>) {}
typedef ConversionMaybeColor = Null<ConversionColor>;

/**
	Checks the value conversion table of `reflaxe.ocaml` (bead `haxe_ocaml-9cqxj`).

	For each pair of Haxe types, the test compares the carrier of both types and
	the selected conversion with the expected result. The check runs at compile
	time, in a macro, because the table reads typed Haxe types. A wrong entry
	stops the compile with the pair and both results.
**/
class ValueConversionTableTest {
	static function main() {
		Sys.println(check());
	}

	static macro function check():Expr {
		final failures:Array<String> = [];
		final carriers:Array<{type:ComplexType, expected:String}> = [
			{type: macro :Int, expected: "NativePrimitive(int)"},
			{type: macro :haxe.Int32, expected: "NativePrimitive(int)"},
			{type: macro :Float, expected: "NativePrimitive(float)"},
			{type: macro :Bool, expected: "NativePrimitive(bool)"},
			{type: macro :Null<Int>, expected: "NullablePrimitive(int)"},
			{type: macro :Null<Float>, expected: "NullablePrimitive(float)"},
			{type: macro :Null<Bool>, expected: "NullablePrimitive(bool)"},
			{type: macro :ConversionColor, expected: "NativeEnum(ConversionColor)"},
			{type: macro :Null<ConversionColor>, expected: "NullableEnum(ConversionColor)"},
			{type: macro :ConversionMaybeColor, expected: "NullableEnum(ConversionColor)"},
			{type: macro :Dynamic, expected: "DynamicObj"},
			{type: macro :Any, expected: "DynamicObj"},
			{type: macro :{a:Int}, expected: "DynamicObj"},
			{type: macro :ConversionBox, expected: "ObjectReference"},
			{type: macro :Null<ConversionBox>, expected: "ObjectReference"},
			{type: macro :String, expected: "ObjectReference"},
			{type: macro :ConversionList, expected: "ObjectReference"},
			{type: macro :Void, expected: "UnclassifiedCarrier"},
		];
		for (entry in carriers) {
			final actual = Std.string(OcamlValueConversion.carrierOf(ComplexTypeTools.toType(entry.type)));
			if (actual != entry.expected)
				failures.push('carrier of ${ComplexTypeTools.toString(entry.type)}: expected ${entry.expected}, got $actual');
		}

		final pairs:Array<{from:ComplexType, to:ComplexType, expected:String}> = [
			// Same carrier.
			{from: macro :Int, to: macro :Int, expected: "SameCarrier"},
			{from: macro :Int, to: macro :haxe.Int32, expected: "SameCarrier"},
			{from: macro :Null<Int>, to: macro :Null<Int>, expected: "SameCarrier"},
			{from: macro :ConversionColor, to: macro :ConversionColor, expected: "SameCarrier"},
			{from: macro :Null<ConversionColor>, to: macro :ConversionMaybeColor, expected: "SameCarrier"},
			{from: macro :Dynamic, to: macro :Any, expected: "SameCarrier"},
			{from: macro :ConversionBox, to: macro :Null<ConversionBox>, expected: "SameCarrier"},
			// A native value enters a nullable carrier.
			{from: macro :Int, to: macro :Null<Int>, expected: "BoxNullable"},
			{from: macro :Float, to: macro :Null<Float>, expected: "BoxNullable"},
			{from: macro :Bool, to: macro :Null<Bool>, expected: "BoxNullable"},
			{from: macro :Int, to: macro :Null<Float>, expected: "BoxIntAsNullableFloat"},
			{from: macro :ConversionColor, to: macro :Null<ConversionColor>, expected: "BoxNullable"},
			{from: macro :ConversionColor, to: macro :ConversionMaybeColor, expected: "BoxNullable"},
			// A nullable carrier gives its native value.
			{from: macro :Null<Int>, to: macro :Int, expected: "UnboxNullablePrimitive(int)"},
			{from: macro :Null<Float>, to: macro :Float, expected: "UnboxNullablePrimitive(float)"},
			{from: macro :Null<Bool>, to: macro :Bool, expected: "UnboxNullablePrimitive(bool)"},
			{from: macro :Null<ConversionColor>, to: macro :ConversionColor, expected: "UnboxObj"},
			{from: macro :ConversionMaybeColor, to: macro :ConversionColor, expected: "UnboxObj"},
			// A Dynamic value gives a typed reference or enum.
			{from: macro :Dynamic, to: macro :ConversionColor, expected: "UnboxDynamicEnum(ConversionColor)"},
			{from: macro :Dynamic, to: macro :Null<ConversionColor>, expected: "UnboxDynamicEnum(ConversionColor)"},
			{from: macro :Dynamic, to: macro :ConversionBox, expected: "UnboxObj"},
			{from: macro :Any, to: macro :String, expected: "UnboxObj"},
			{from: macro :Dynamic, to: macro :ConversionList, expected: "UnboxObj"},
			// A nullable Boolean enters Dynamic with its tag.
			{from: macro :Null<Bool>, to: macro :Dynamic, expected: "TagNullableBool"},
			{from: macro :Null<Bool>, to: macro :Any, expected: "TagNullableBool"},
			// A Boolean read out of Dynamic accepts the tag.
			{from: macro :Dynamic, to: macro :Null<Bool>, expected: "UntagNullableBool"},
			{from: macro :Dynamic, to: macro :Bool, expected: "UnboxNullablePrimitive(bool)"},
			// Pairs that the table does not list yet.
			{from: macro :ConversionColor, to: macro :Null<ConversionShape>, expected: "null"},
			{from: macro :ConversionShape, to: macro :ConversionColor, expected: "null"},
			{from: macro :Null<Int>, to: macro :Float, expected: "null"},
			{from: macro :Dynamic, to: macro :Int, expected: "null"},
			{from: macro :Int, to: macro :Dynamic, expected: "null"},
		];
		for (pair in pairs) {
			final actual = Std.string(OcamlValueConversion.decide(ComplexTypeTools.toType(pair.from), ComplexTypeTools.toType(pair.to)));
			if (actual != pair.expected)
				failures.push('${ComplexTypeTools.toString(pair.from)} -> ${ComplexTypeTools.toString(pair.to)}: expected ${pair.expected}, got $actual');
		}

		if (failures.length > 0)
			Context.error("VALUE_CONVERSION_TABLE:FAIL\n" + failures.join("\n"), Context.currentPos());
		final summary = 'VALUE_CONVERSION_TABLE:PASS carriers=${carriers.length} pairs=${pairs.length}';
		return macro $v{summary};
	}
}
