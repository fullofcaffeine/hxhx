package hxhx;

import haxe.ds.StringMap;

/**
	A JSON document decoded into concrete values for compiler metadata readers.

	Each object field and array element retains its JSON kind. Schema readers match
	these variants before constructing a plugin manifest or macro-module receipt.
	A missing object field remains distinct from an explicit `JsonNull` value.
	Integer tokens retain `Int` payloads; fraction and exponent tokens retain `Float`.
**/
enum CompilerJsonValue {
	JsonNull;
	JsonBool(value:Bool);
	JsonInt(value:Int);
	JsonFloat(value:Float);
	JsonString(value:String);
	JsonArray(values:Array<CompilerJsonValue>);
	JsonObject(fields:StringMap<CompilerJsonValue>);
}
