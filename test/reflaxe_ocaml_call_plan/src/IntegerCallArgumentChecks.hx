import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlCallIntegerArgument.select as selectIntegerArgument;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Keep the standard integer argument proof separate from arbitrary abstract erasure. */
class IntegerCallArgumentChecks {
	public static function run():Void {
		final registry = new OcamlRepresentationRegistry();
		registry.beginProgram("program:integer-call-arguments");
		final word = Context.getType("haxe.Int32");
		for (destination in ["Int", "Null<Int>"]) {
			final selected = selectIntegerArgument(word, destination, registry);
			if (selected == null || selected.carrierTypeId != "int" || selected.semanticTypeId != "Int")
				Context.error("A standard Int32 argument must supply the integer value before optional boxing.", Context.currentPos());
		}
		final excluded:Array<Type> = [
			Context.getType("CallWord"),
			Context.resolveType(macro :Null<haxe.Int32>, Context.currentPos()),
			Context.getType("haxe.Int64"),
			Context.getType("Float")
		];
		for (type in excluded)
			if (selectIntegerArgument(type, "Int", registry) != null)
				Context.error("An unproved source type inherited the standard Int32 argument conversion.", Context.currentPos());
		if (selectIntegerArgument(word, "Dynamic", registry) != null)
			Context.error("The integer argument proof must not select a Dynamic conversion.", Context.currentPos());
	}
}
