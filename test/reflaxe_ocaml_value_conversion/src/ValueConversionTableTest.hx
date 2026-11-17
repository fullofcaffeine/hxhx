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

class ConversionHolder<T> {
	public var value:T;

	public function new(value:T)
		this.value = value;
}

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
			{type: macro :Int->Int, expected: "FunctionValue"},
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
			{from: macro :Dynamic, to: macro :ConversionColor, expected: "UnboxObj"},
			{from: macro :Dynamic, to: macro :Null<ConversionColor>, expected: "UnboxObj"},
			{from: macro :Dynamic, to: macro :ConversionBox, expected: "UnboxObj"},
			{from: macro :Any, to: macro :String, expected: "UnboxObj"},
			{from: macro :Dynamic, to: macro :ConversionList, expected: "UnboxObj"},
			// A nullable Boolean enters Dynamic with its tag.
			{from: macro :Null<Bool>, to: macro :Dynamic, expected: "TagNullableBool"},
			{from: macro :Null<Bool>, to: macro :Any, expected: "TagNullableBool"},
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

		// A field declared with the class type parameter, read at concrete types.
		final holderValue = switch (Context.getType("ConversionHolder")) {
			case TInst(classRef, _): classRef.get().fields.get().filter(field -> field.name == "value")[0].type;
			case _: throw "ConversionHolder is not a class";
		}
		final typeParameterCarrier = Std.string(OcamlValueConversion.carrierOf(holderValue));
		if (typeParameterCarrier != "TypeParameterValue")
			failures.push('carrier of ConversionHolder.T: expected TypeParameterValue, got $typeParameterCarrier');
		final genericReads:Array<{actual:ComplexType, expected:String}> = [
			{actual: macro :Int, expected: "UnboxNullablePrimitive(int)"},
			{actual: macro :Float, expected: "UnboxNullablePrimitive(float)"},
			{actual: macro :Bool, expected: "UnboxNullablePrimitive(bool)"},
			{actual: macro :String, expected: "UnboxObj"},
			{actual: macro :Array<Int>, expected: "UnboxObj"},
			{actual: macro :ConversionBox, expected: "UnboxObj"},
			{actual: macro :Int->Int, expected: "UnboxObj"},
			{actual: macro :Null<Int>, expected: "null"},
			{actual: macro :Dynamic, expected: "null"},
			{actual: macro :ConversionColor, expected: "null"},
		];
		for (read in genericReads) {
			final actual = Std.string(OcamlValueConversion.decideGenericRead(holderValue, ComplexTypeTools.toType(read.actual)));
			if (actual != read.expected)
				failures.push('ConversionHolder.value read as ${ComplexTypeTools.toString(read.actual)}: expected ${read.expected}, got $actual');
		}
		final plainRead = Std.string(OcamlValueConversion.decideGenericRead(ComplexTypeTools.toType(macro :Int), ComplexTypeTools.toType(macro :Int)));
		if (plainRead != "null")
			failures.push('a field declared Int is not a generic read: expected null, got $plainRead');

		if (failures.length > 0)
			Context.error("VALUE_CONVERSION_TABLE:FAIL\n" + failures.join("\n"), Context.currentPos());
		final summary = 'VALUE_CONVERSION_TABLE:PASS carriers=${carriers.length + 1} pairs=${pairs.length} generic_reads=${genericReads.length + 1}';
		return macro $v{summary};
	}
}
