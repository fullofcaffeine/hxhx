package backend.cpp;

/** The exact lowered occurrence owns the plan, operands, and canonical case bodies. */
typedef CppManagedGuardedSwitchInput = {
	final source:HxExpr;
	final locals:CppManagedExpressionLocals;
	final heap:String;
	final prefix:String;
	final requireExpression:HxExpr->Void;
	final renderValue:(HxExpr, String, String) -> Array<String>;
	final condition:HxExpr->String;
	final body:(Int, String) -> Array<String>;
	final valueType:HxExpr->TyType;
	final namedPattern:HxSwitchPattern->Null<TypedNamedPattern>;
	final ?casts:CppManagedCastPlan;
	final ?enums:CppManagedEnumDescriptors;
}

/**
	Keep every observed value rooted across collecting guards and fresh cell allocation.
	The shared plan controls reads and retries. Lexical native blocks keep source
	return, break, and continue in the enclosing function or loop. A rejected guard
	ends its case-local storage before retrying with the retained observations.
 */
function render(input:CppManagedGuardedSwitchInput, indent:String):Array<String> {
	input.requireExpression(input.source);
	final selected = switch input.source {
		case ELoweredControl(PatternAttempts(plan), "", children, _) if (children.length == plan.getPatterns().length + 2):
			{plan: plan, value: children[0], enabled: children[1]};
		case _: throw "managed guarded switch requires its exact lowered plan and case layout";
	};
	final root = input.prefix + "input";
	final observations = new CppManagedPatternObservations({
		plan: selected.plan,
		type: input.valueType(selected.value),
		named: input.namedPattern,
		casts: input.casts,
		enums: input.enums
	});
	var next = 0;
	final rendered = GuardedPatternRenderer.render(selected.plan, root + ".get()", {fresh: () -> input.prefix + "observed_" + next++,
		empty: "",
		nullAccess: 'throw hxhx::managed::ThrownValue(' + input.heap + ', hxhx::managed::Value::string("Null Access"));',
		test: observations.test,
		read: observations.read,
		observe: (name, value, after) -> "hxhx::managed::Root<hxhx::managed::Value> "
			+ name
			+ "("
			+ input.heap
			+ ", "
			+ value
			+ ");\n"
			+ after,
		branch: (condition, yes, no) -> "if ("
			+ condition
			+ ") {\n"
			+ nested(yes)
			+ "\n} else {\n"
			+ nested(no)
			+ "\n}",
		attempt: (index, captures, rejected) -> {
			final lines = new Array<String>();
			for (capture in captures) {
				final name = switch capture.source {
					case PBind(name) | PCapture(name, _): name;
					case _: throw "managed guarded capture lost its exact pattern binding";
				};
				for (line in input.locals.renderPattern(input.locals.binding(name), capture.value, input.heap, "  "))
					lines.push(line);
			}
			for (line in input.body(index, "  "))
				lines.push(line);
			return "{\n" + lines.join("\n") + "\n}\nif (" + input.condition(selected.enabled) + ") {\n" + nested(rejected) + "\n}";
		}
	});
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"
	];
	for (line in input.renderValue(selected.value, root, indent + "  "))
		lines.push(line);
	for (line in rendered.split("\n"))
		lines.push(indent + "  " + line);
	// Shared typing proves whether every possible selected arm leaves this region.
	// Native flag/value conversions can hide that proof from C++ return analysis.
	// Preserve it as a checked failure if generated control ever contradicts it.
	if (!selected.plan.getCanCompleteNormally())
		lines.push(indent + '  throw std::logic_error("guarded switch reached a path excluded by typed control flow");');
	lines.push(indent + "}");
	input.requireExpression(input.source);
	return lines;
}

/** Indent native blocks without changing their control destinations. */
private function nested(source:String):String
	return [for (line in source.split("\n")) "  " + line].join("\n");
