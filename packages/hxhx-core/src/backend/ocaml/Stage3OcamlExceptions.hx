package backend.ocaml;

/** One authored handler with an exact typed binding and an already-rendered body. */
typedef Stage3OcamlCatch = {
	final targetName:String;
	final type:TyType;
	final body:String;
	final mutable:Bool;
}

/**
	Render exception boundaries for the independent Stage3 OCaml route.

	Only the selected handler runs. Unmatched values keep their original native
	exception, and compiler control signals pass through every authored handler.
	The existing runtime owns value storage and type tags; this Haxe module owns
	handler order and conversions. It does not infer types from emitted text.

	Nominal throws still require instance identity metadata in this route. Reject
	them until that carrier is proved; a source type name cannot establish a
	runtime subtype after a value passes through Dynamic.
 */
function throwValue(value:TypedBackendThrownValue, rendered:String):String {
	final type = value.type;
	final payload = switch type.getSemanticKey() {
		case "primitive:Bool": "HxRuntime.box_bool (" + rendered + ")";
		case "primitive:Int" | "primitive:Float" | "primitive:String" | "null": "Obj.repr (" + rendered + ")";
		case _ if (type.isDynamic()): rendered;
		case _: throw "Stage3 OCaml throw requires a supported exact runtime carrier: " + type.getSemanticKey();
	};
	return "HxType.hx_throw_typed_rtti (" + payload + ") [\"Dynamic\"]";
}

/** Catch only language exceptions; native returns and loop signals retain their destinations. */
function tryStatement(body:String, catches:Array<Stage3OcamlCatch>, names:Stage3OcamlLocalNames):String {
	final value = names.internalName("__hx_thrown_value");
	final tags = names.internalName("__hx_thrown_tags");
	final original = names.internalName("__hx_original_exception");
	var handlers = "raise " + original;
	for (offset in 0...catches.length) {
		final entry = catches[catches.length - offset - 1];
		final converted = switch entry.type.getSemanticKey() {
			case "primitive:Bool": "HxRuntime.unbox_bool_or_obj " + value;
			case "primitive:Int": "(Obj.obj " + value + " : int)";
			case "primitive:Float": "(Obj.obj " + value + " : float)";
			case "primitive:String": "(Obj.obj " + value + " : string)";
			case _ if (entry.type.isDynamic()): value;
			case _: throw "Stage3 OCaml catch requires a supported exact runtime carrier: " + entry.type.getSemanticKey();
		};
		final bound = entry.mutable ? "ref (" + converted + ")" : converted;
		final selected = "(let " + entry.targetName + " = " + bound + " in ignore " + entry.targetName + "; " + entry.body + ")";
		if (entry.type.isDynamic()) {
			handlers = selected;
		} else {
			final tag = entry.type.getDisplay();
			handlers = "(if HxRuntime.tags_has " + tags + " \"" + tag + "\" then " + selected + " else " + handlers + ")";
		}
	}
	return "(try (" + body + ") with HxRuntime.Hx_exception (" + value + ", " + tags + ") as " + original + " -> " + handlers + ")";
}

/** Each loop catches its own nearest break and resumes after a continue. */
function loopBody(body:String):String
	return "(try (" + body + ") with HxRuntime.Hx_continue -> ())";

function loop(loop:String):String
	return "(try (" + loop + ") with HxRuntime.Hx_break -> ())";
