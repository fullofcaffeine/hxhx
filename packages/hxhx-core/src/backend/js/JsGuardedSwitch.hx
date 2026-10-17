package backend.js;

import TypedGuardedPatternPlan;

/**
	Emit the shared decisions as ordinary ES5 branches and local observations.
	Each attempt gets its own symbols and captured-pattern cells. No function or
	loop surrounds a case, so its return, break, and continue keep their targets.
 */
function emit(writer:JsWriter, input:HxExpr, enabled:HxExpr, plan:TypedGuardedPatternPlan, bodies:Array<HxStmt>, scope:JsFunctionScope):Void {
	final expressionScope = scope.exprScope();
	final retry = JsExprEmitter.emit(enabled, expressionScope);
	final source = GuardedPatternRenderer.render(plan, JsExprEmitter.emit(input, expressionScope), {fresh: () -> scope.freshTemp("__pattern"),
		empty: "",
		nullAccess: "throw \"Null Access\";",
		test: (value, test) -> switch test {
			case IsNull: value + " == null";
			case IsBool(literal): value + " === " + literal;
			case IsInt(literal): value + " === " + literal;
			case IsString(literal): value + " === " + JsNameMangler.quoteString(literal);
			case ArrayLength(length): "Array.isArray(" + value + ") && " + value + ".length === " + length;
			case EnumConstructor(pattern, selected):
				final exact = expressionScope.namedPatterns == null ? null : expressionScope.namedPatterns(pattern);
				if (exact == null || exact.getSemanticKey() != selected.getSemanticKey())
					throw "JavaScript guarded pattern lost its exact constructor selection";
				final constructor = JsSwitchPatternLowering.constructor(pattern, expressionScope);
				constructor.parameters == null ? value + " === " + constructor.reference : "$hx_enum_constructor("
					+ value
					+ ") === "
					+ constructor.reference;
		},
		read: (read, value) -> switch read {
			case Input: throw "JavaScript guarded switch cannot read its input twice";
			case ArrayItem(parent, index): value(parent) + "[" + index + "]";
			case ObjectField(parent, name): value(parent) + JsNameMangler.propertySuffix(name);
			case EnumArgument(parent, pattern, index):
				final constructor = JsSwitchPatternLowering.constructor(pattern, expressionScope);
				if (constructor.parameters == null || index < 0 || index >= constructor.parameters.length)
					throw "JavaScript guarded extraction has no exact payload field";
				value(parent) + JsNameMangler.propertySuffix(constructor.parameters[index]);
		},
		observe: (name, value, next) -> "var " + name + " = " + value + ";\n" + next,
		branch: (condition, yes, no) -> "if ("
			+ condition
			+ ") {\n"
			+ yes
			+ "\n} else {\n"
			+ no
			+ "\n}",
		attempt: (index, captures, rejected) -> {
			final body = scope.withLexicalScope(() -> {
				final out = new JsWriter();
				for (capture in captures) {
					final name = switch capture.source {
						case PBind(name) | PCapture(name, _): name;
						case _: throw "JavaScript guarded capture lost its binding occurrence";
					};
					final local = scope.declareLocal(name);
					final value = scope.isIterationCapture(name) ? "{value: " + capture.value + "}" : capture.value;
					out.writeln("var " + local + " = " + value + ";");
				}
				JsStmtEmitter.emitStmt(out, bodies[index], scope);
				return out.toString();
			});
			"{\n" + body + "}\nif (" + retry + ") {\n" + rejected + "\n}";
		}
	});
	for (line in source.split("\n"))
		writer.writeln(line);
}
