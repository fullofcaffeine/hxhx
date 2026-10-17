import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.lowered.OcamlSingleWriteSource.localInitializerSources;
import reflaxe.ocaml.lowered.OcamlMapLookupSource.producesObjectCarrier;

/** Checks that a local producer proof requires one dominating write without capture. */
class SingleWriteSourceFixture {
	public static function run():Void {
		check("direct initializer", macro {
			final value:String = "value";
			final copy = value;
		}, 1);
		check("lowered block result", macro {
			var value:String;
			value = "value";
			final copy = value;
		}, 1);
		check("conditional write does not dominate", macro {
			var value:String;
			if (Sys.args().length == 0)
				value = "value";
			final copy = value;
		}, 0);
		check("a later write cannot prove an earlier read", macro {
			var value:String;
			final copy = value;
			value = "later";
		}, 0);
		check("second write rejects the whole local", macro {
			var value:String;
			value = "first";
			final copy = value;
			value = "second";
		}, 0);
		check("compound write rejects the whole local", macro {
			var value:String = "first";
			final copy = value;
			value += "second";
		}, 0);
		check("captured read is excluded", macro {
			var value:String = "value";
			final read = () -> value;
			final copy = value;
		}, 0);
		check("captured write is excluded", macro {
			var value:String;
			value = "value";
			final write = () -> value = "later";
			final copy = value;
		}, 0);
		check("nested write is not a same-block proof", macro {
			var value:String;
			{
				value = "value";
			}
			final copy = value;
		}, 0);
		final innerMap = Context.resolveType(macro :Map<Int, String>, Context.currentPos());
		final unknownCall = Context.typeExpr(macro UnknownMapProducer.get());
		if (producesObjectCarrier(unknownCall, innerMap))
			Context.error("a user method must not claim the native lookup contract", unknownCall.pos);
		final unknownLocal = Context.typeExpr(macro {
			var value:Null<Map<Int, String>> = null;
			value;
		});
		if (producesObjectCarrier(unknownLocal, innerMap))
			Context.error("a nullable type alone must not prove the lookup producer", unknownLocal.pos);
		Sys.println("REFLAXE_OCAML_SINGLE_WRITE_SOURCE:PASS");
	}

	static function check(name:String, source:Expr, expected:Int):Void {
		final links = localInitializerSources(Context.typeExpr(source));
		final count = [for (_ in links.keys()) true].length;
		if (count != expected)
			Context.error(name + ": expected " + expected + " proven reads, got " + count, source.pos);
	}
}
