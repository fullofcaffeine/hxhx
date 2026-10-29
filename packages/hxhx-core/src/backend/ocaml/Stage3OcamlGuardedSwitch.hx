package backend.ocaml;

import TypedGuardedPatternPlan;

/** Native primitives retain the shared plan's read order and the caller's exact local storage. */
typedef GuardedSwitchInput = {
	final plan:TypedGuardedPatternPlan;
	final value:String;
	final enabled:String;
	final names:Stage3OcamlLocalNames;
	final dialect:HihBackendDialect;
	final quote:String->String;
	final enums:Stage3OcamlEnums;
	final body:Int->String;
	final mutable:String->Bool;
}

/**
	Keep extracted values in lexical lets across rejected guards. A case creates
	its binding storage anew on each attempt, so a saved closure retains that
	attempt's values. Native exceptions still carry returns and loop exits to
	their original handlers; this renderer introduces no callable or loop.
 */
function render(input:GuardedSwitchInput):String {
	if (input.names == null)
		throw "OCaml guarded switch requires its exact local naming owner";
	var next = 0;
	return GuardedPatternRenderer.render(input.plan, input.value, {fresh: () -> input.names.internalName("__hx_guard_value_" + next++),
		empty: "()",
		nullAccess: "HxRuntime.hx_throw_typed (Obj.repr " + input.quote("Null Access") + ") [\"String\"; \"Dynamic\"]",
		test: (value, test) -> switch test {
			case IsNull: input.dialect.runtimeIsNull(value);
			case IsBool(literal): input.dialect.runtimeDynamicEquals(value, literal ? "true" : "false");
			case IsInt(literal): input.dialect.runtimeDynamicEquals(value, Std.string(literal));
			case IsString(literal): input.dialect.runtimeDynamicEquals(value, input.quote(literal));
			case ArrayLength(length): "(HxArray.length (Obj.magic " + value + ") = " + length + ")";
			case EnumConstructor(_, selection):
				if (input.enums == null)
					throw "OCaml guarded enum requires its exact program provider";
				input.enums.patternCondition(selection, value);
		},
		read: (read, value) -> switch read {
			case Input: throw "OCaml guarded switch cannot read its input twice";
			case ArrayItem(parent, index): "HxArray.get (Obj.magic " + value(parent) + ") " + index;
			case ObjectField(parent, name): "HxAnon.get (Obj.repr " + value(parent) + ") " + input.quote(name);
			case EnumArgument(parent, _, index): "HxArray.get (HxType.enumParameters (Obj.repr " + value(parent) + ")) " + index;
		},
		observe: (name, value, next) -> "(let "
			+ name
			+ " = ("
			+ value
			+ ") in "
			+ next
			+ ")",
		branch: (condition, yes, no) -> "(if "
			+ condition
			+ " then "
			+ yes
			+ " else "
			+ no
			+ ")",
		attempt: (index, captures, rejected) -> {
			var body = input.body(index);
			for (capture in captures) {
				final name = switch capture.source {
					case PBind(name) | PCapture(name, _): name;
					case _: throw "OCaml guarded capture requires its exact binding occurrence";
				};
				final type = input.names.findType(name);
				if (type == null)
					throw "OCaml guarded capture requires its exact local type";
				var value = type.getSemanticKey() == "primitive:Bool" ? "HxRuntime.unbox_bool_or_obj (Obj.repr " + capture.value + ")" : "Obj.magic "
					+ capture.value;
				if (input.mutable(name))
					value = "ref (" + value + ")";
				body = "(let " + input.names.targetName(name) + " = " + value + " in " + body + ")";
			}
			"(let () = " + body + " in if " + input.enabled + " then " + rejected + " else ())";
		}
	});
}
