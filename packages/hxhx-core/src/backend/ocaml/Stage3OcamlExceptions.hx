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

	Ordinary class values retain their most-derived descriptor in private object
	storage. Throwing through Dynamic or a broader catch keeps that identity.
	Class storage admits nominal carriers; runtime-owned representations stay
	under their own boundaries instead of borrowing a static throw-site tag.
	Registered enums retain their existing boxes, including constructor payloads.
	Enum handlers check the box's runtime enum identity before binding that value.
 */
function throwValue(value:TypedBackendThrownValue, rendered:String, classes:Stage3OcamlClassStorage, enums:Stage3OcamlEnums):String {
	final type = value.type;
	final payload = switch type.getSemanticKey() {
		case "primitive:Bool": "HxRuntime.box_bool (" + rendered + ")";
		case "primitive:Int" | "primitive:Float" | "primitive:String" | "null": "Obj.repr (" + rendered + ")";
		case _ if (type.isDynamic()): rendered;
		case _ if (classes.nominalName(type) != null): "Obj.repr (" + rendered + ")";
		case _ if (enums.runtimeName(type) != null): rendered;
		case _: throw "Stage3 OCaml throw requires a supported exact runtime carrier: " + type.getSemanticKey();
	};
	return "HxType.hx_throw_typed_rtti (" + payload + ") [\"Dynamic\"]";
}

/** Catch only language exceptions; native returns and loop signals retain their destinations. */
function tryStatement(body:String, catches:Array<Stage3OcamlCatch>, names:Stage3OcamlLocalNames, classes:Stage3OcamlClassStorage, enums:Stage3OcamlEnums,
		quote:String->String):String {
	final value = names.internalName("__hx_thrown_value");
	final tags = names.internalName("__hx_thrown_tags");
	final original = names.internalName("__hx_original_exception");
	var handlers = "raise " + original;
	for (offset in 0...catches.length) {
		final entry = catches[catches.length - offset - 1];
		final nominal = classes.nominalName(entry.type);
		final enumName = enums.runtimeName(entry.type);
		final converted = switch entry.type.getSemanticKey() {
			case "primitive:Bool": "HxRuntime.unbox_bool_or_obj " + value;
			case "primitive:Int": "(Obj.obj " + value + " : int)";
			case "primitive:Float": "(Obj.obj " + value + " : float)";
			case "primitive:String": "(Obj.obj " + value + " : string)";
			case _ if (entry.type.isDynamic()): value;
			case _ if (nominal != null): value;
			case _ if (enumName != null): value;
			case _: throw "Stage3 OCaml catch requires a supported exact runtime carrier: " + entry.type.getSemanticKey();
		};
		final bound = entry.mutable ? "ref (" + converted + ")" : converted;
		final selected = "(let " + entry.targetName + " = " + bound + " in ignore " + entry.targetName + "; " + entry.body + ")";
		if (entry.type.isDynamic()) {
			handlers = selected;
		} else if (enumName != null) {
			// Test the original enum box, not a class tag with coincidentally equal text.
			handlers = "(if HxEnum.name_opt " + value + " = Some " + quote(enumName) + " then " + selected + " else " + handlers + ")";
		} else {
			final tag = nominal == null ? entry.type.getDisplay() : nominal;
			handlers = "(if HxRuntime.tags_has " + tags + " " + quote(tag) + " then " + selected + " else " + handlers + ")";
		}
	}
	return "(try (" + body + ") with HxRuntime.Hx_exception (" + value + ", " + tags + ") as " + original + " -> " + handlers + ")";
}

/** Each loop catches its own nearest break and resumes after a continue. */
function loopBody(body:String):String
	return "(try (" + body + ") with HxRuntime.Hx_continue -> ())";

function loop(loop:String):String
	return "(try (" + loop + ") with HxRuntime.Hx_break -> ())";
