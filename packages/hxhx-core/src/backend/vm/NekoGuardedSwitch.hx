package backend.vm;

import TypedGuardedPatternPlan;

/** The enclosing emitter owns expression spelling and the exact case-body scope. */
typedef NekoGuardedSwitchInput = {
	final context:NekoEmitContext;
	final plan:TypedGuardedPatternPlan;
	final value:String;
	final enabled:String;
	final identifier:String->String;
	final quote:String->String;
	final body:(Int, Array<String>) -> String;
}

/**
	Render shared pattern decisions as lexical Neko blocks. Observations survive
	a rejected guard, while each attempted case creates fresh binding cells.
	No callable or loop surrounds a case, so returns and loop exits keep their
	original destinations. The VM retains observed values through ordinary locals.
 */
function render(input:NekoGuardedSwitchInput):String {
	var next = 0;
	final program = input.context.typedProgram;
	return "{\n" + GuardedPatternRenderer.render(input.plan, input.value, {fresh: () -> program.runtimeHelperName("__hxhx_guard_value_" + next++),
		empty: "",
		nullAccess: "$throw(" + input.quote("Null Access") + ");",
		test: (value, test) -> switch test {
			case IsNull: value + " == null";
			case IsBool(literal): value + " == " + (literal ? "true" : "false");
			case IsInt(literal): value + " == " + literal;
			case IsString(literal): value + " == " + input.quote(literal);
			case ArrayLength(length): NekoArrayProvider.matchesLength(program, value, length);
			case EnumConstructor(source, selected): enumCondition(input, source, selected, value);
		},
		read: (read, value) -> switch read {
			case Input: throw "Neko guarded switch cannot read its input twice";
			case ArrayItem(parent, index): value(parent) + "[" + index + "]";
			case ObjectField(parent, name): "$objget(" + value(parent) + ", $hash(" + input.quote(name) + "))";
			case EnumArgument(parent, _, index): "__hxhx_enum_params(" + value(parent) + ")[" + index + "]";
		},
		observe: (name, value, after) -> "var "
			+ name
			+ " = "
			+ value
			+ ";\n"
			+ after,
		branch: (condition, yes, no) -> "if ("
			+ condition
			+ ") {\n"
			+ yes
			+ "\n} else {\n"
			+ no
			+ "\n}",
		attempt: (index, captures, rejected) -> {final names = new Array<String>();
			final declarations = new Array<String>();
			for (capture in captures) {
				final name = switch capture.source {
					case PBind(name) | PCapture(name, _): name;
					case _: throw "Neko guarded capture lost its exact binding occurrence";
				};
				names.push(name);
				final storage = input.context.captureStorage;
				final value = storage == null ? capture.value : storage.initialize(name, capture.value);
				declarations.push("var " + input.identifier(name) + " = " + value + ";");
			}
			"{\n"
			+ declarations.join("\n")
			+ "\n"
			+ input.body(index, names)
			+ "\n}\nif ("
			+ input.enabled
			+ ") {\n"
			+ rejected
			+ "\n}";
		}
	}) + "\n}";
}

/** Validate the exact pattern occurrence and enum inventory before testing runtime owner and constructor. */
private function enumCondition(input:NekoGuardedSwitchInput, source:HxSwitchPattern, selected:TypedNamedPattern, value:String):String {
	final exact = switch input.context.currentExecutable {
		case FunctionBody(fn): fn.body.findNamedPattern(source);
		case FieldInitializer(initializer): initializer.findNamedPattern(source);
		case null: null;
	};
	if (exact == null || exact.getSemanticKey() != selected.getSemanticKey())
		throw "Neko guarded pattern lost its exact constructor selection";
	final program = input.context.typedProgram;
	final pattern = NekoEnumConstructorPlan.patternTarget(program, selected);
	final key = NekoRuntimeTypeRegistry.requireTarget(program, pattern.target);
	if (key == null)
		throw "Neko guarded enum requires its runtime type descriptor";
	final descriptor = program.runtimeHelperName("__hxhx_runtime_type_definition") + "(" + input.quote(key) + ")";
	return value + " != null && $typeof(" + value + ") == $tobject && $objget(" + value + ", $hash(\"__enum__\")) == " + descriptor
		+ " && __hxhx_enum_ctor_is(" + value + ", " + input.quote(pattern.name) + ")";
}
