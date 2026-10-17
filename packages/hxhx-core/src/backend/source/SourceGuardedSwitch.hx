package backend.source;

import TypedGuardedPatternPlan;
import backend.source.SourceFunctionRenderFrame;

/**
	Render shared guard decisions in the enclosing source function.
	Observations survive a rejected guard, and each attempt initializes its own
	pattern bindings. Branches introduce no function or loop, so returns and loop
	exits keep the destinations checked by shared control adaptation.
 */
@:access(backend.source.SourceTargetCommon)
function render(frame:SourceFunctionRenderFrame, input:HxExpr, enabled:HxExpr, plan:TypedGuardedPatternPlan, bodies:Array<HxStmt>,
		indent:String):Array<String> {
	final target = SourceFunctionRenderFrameTools.target(frame);
	final step = SourceTargetCommon.indentStep(target);
	final nativeScope = target == Java || target == Cs;
	final exitLabel = nativeScope ? SourceFunctionRenderFrameTools.freshPatternName(frame) : "";
	function nested(source:String):String {
		if (source.length == 0)
			return step + SourceTargetCommon.emptyStmt(target);
		return [for (line in source.split("\n")) step + line].join("\n");
	}
	function branch(condition:String, yes:String, no:String):String
		return switch target {
			case Python: "if " + condition + ":\n" + nested(yes) + "\nelse:\n" + nested(no);
			case Lua: "if " + condition + " then\n" + nested(yes) + "\nelse\n" + nested(no) + "\nend";
			case _: "if (" + condition + ") {\n" + nested(yes) + "\n} else {\n" + nested(no) + "\n}";
		};
	function quote(value:String):String
		return target == Php ? PhpSyntax.quoteString(value) : SourceTargetCommon.quoteString(value);
	function exactConstructor(pattern:HxSwitchPattern, selected:TypedNamedPattern):String {
		final current = SourceFunctionRenderFrameTools.findNamedPattern(frame, pattern);
		if (current == null || current.getSemanticKey() != selected.getSemanticKey())
			throw "source guarded pattern lost its exact constructor selection";
		return switch selected.getKind() {
			case Constructor(owner, name, _, _):
				if (target != Php)
					return SourceFunctionRenderFrameTools.requireEnumName(frame, owner);
				final fact = SourceFunctionRenderFrameTools.requirePhpRenderer(frame).findEnumConstructor(name, owner.getCanonicalName());
				if (fact == null || fact.ownerIdentity != owner.getCanonicalName())
					throw "PHP guarded enum has no exact emitted declaration owner";
				fact.enumName;
			case _: throw "guarded constructor test requires an enum constructor";
		};
	}
	final retry = SourceTargetCommon.renderExprWithFrame(frame, enabled);
	final source = GuardedPatternRenderer.render(plan, SourceTargetCommon.renderExprWithFrame(frame, input), {
		fresh: () -> SourceTargetCommon.valueName(target, SourceFunctionRenderFrameTools.freshPatternName(frame)),
		empty: plan.getHasExhaustiveCoverage() ? SourceTargetCommon.throwStmt(target, quote("guarded switch exhausted inputs covered by shared typing")) : "",
		nullAccess: SourceTargetCommon.throwStmt(target, quote("Null Access")),
		test: (value, test) -> switch test {
			case IsNull: target == Python ? value + " is None" : target == Php ? value
				+ " === null" : SourceTargetCommon.equalityCond(target, value, SourceTargetCommon.defaultValue(target));
			case IsBool(literal):
				final constant = literal ? SourceTargetCommon.trueLiteral(target) : SourceTargetCommon.falseLiteral(target);
				target == Cs ? "System.Object.Equals(" + value + ", " + constant + ")" : target == Python ? value + " is " + constant : target == Php ? value +
				" === " + constant : SourceTargetCommon.equalityCond(target, value, constant);
			case IsInt(literal): target == Cs ? "System.Object.Equals(" + value + ", " + literal + ")" : target == Python ? "type("
				+ value
				+ ") is int and "
				+ value
				+ " == "
				+ literal : target == Php ? value
				+ " === "
				+ literal : SourceTargetCommon.equalityCond(target, value, Std.string(literal));
			case IsString(literal): target == Cs ? "System.Object.Equals(" + value + ", " + quote(literal) + ")" : target == Php ? value
				+ " === "
				+ quote(literal) : SourceTargetCommon.equalityCond(target, value, quote(literal));
			case ArrayLength(length): SourceTargetCommon.lowerSourceArrayPattern(target, [for (_ in 0...length) PWildcard], value, frame).cond;
			case EnumConstructor(pattern, selected):
				final owner = exactConstructor(pattern, selected);
				final constructor = switch selected.getKind() {
					case Constructor(_, name, _, _): name;
					case _: throw "guarded enum lost its constructor";
				};
				switch target {
					case Php:
						"is_object("
						+ value
						+ ") && isset("
						+ value
						+ "->__hx_enum) && "
						+ value
						+ "->__hx_enum === "
						+ quote(owner)
						+ " && "
						+ value
						+ "->__hx_ctor === "
						+ quote(constructor);
					case Python:
						"getattr("
						+ value
						+ ", \"__hx_enum\", None) == "
						+ quote(owner)
						+ " and getattr("
						+ value
						+ ", \"__hx_ctor\", None) == "
						+ quote(constructor);
					case Cs:
						final enumValue = "((global::hxhx.__HxEnumValue)" + value + ")";
						value
						+ " is global::hxhx.__HxEnumValue && "
						+ enumValue
						+ ".__hx_enum == "
						+ quote(owner)
						+ " && "
						+ enumValue
						+ ".__hx_ctor == "
						+ quote(constructor);
					case Lua:
						"type("
						+ value
						+ ") == \"table\" and "
						+ value
						+ ".__hx_enum == "
						+ quote(owner)
						+ " and "
						+ value
						+ ".__hx_ctor == "
						+ quote(constructor);
					case Java:
						throw "Java source guarded enum requires a supported enum runtime representation";
				}
		},
		read: (read, value) -> switch read {
			case Input: throw "guarded source switch cannot observe its input twice";
			case ArrayItem(parent, index): SourceTargetCommon.sourceSwitchArrayItemExpr(target, value(parent), index);
			case ObjectField(parent, name): SourceTargetCommon.sourceSwitchFieldExpr(target, value(parent), SourceTargetCommon.sanitizeTypeName(name));
			case EnumArgument(parent, pattern, index):
				final selected = SourceFunctionRenderFrameTools.findNamedPattern(frame, pattern);
				if (selected == null)
					throw "guarded enum payload lost its exact pattern occurrence";
				exactConstructor(pattern, selected);
				target == Python ? "getattr("
				+ value(parent)
				+ ", \"__hx_params\")["
				+ index
				+ "]" : SourceTargetCommon.sourceSwitchParamExpr(target, value(parent), index);
		},
		observe: (name, value, next) -> (switch target {
			case Php: name + " = " + value + ";";
			case _: SourceTargetCommon.varDecl(target, name, value);
		}) + "\n" + next,
		branch: branch,
		attempt: (index, captures, rejected) -> {
			var caseFrame = frame;
			var scope = target == Php ? SourceFunctionRenderFrameTools.requirePhpScope(frame).derive(SwitchCase) : null;
			final lines = new Array<String>();
			for (capture in captures) {
				final name = switch capture.source {
					case PBind(name) | PCapture(name, _): name;
					case _: throw "source guarded capture lost its exact binding occurrence";
				};
				if (scope != null) {
					final local = PhpName.valueIdentifier(name);
					scope = scope.withPlannedLocal(local);
					for (line in SourceFunctionRenderFrameTools.requirePhpRenderer(frame).getPlan().getCaptureStorage().renewal(local, ""))
						lines.push(line);
				}
				lines.push(switch frame {
					case NativeFunction(locals, _) if (target == Cs): locals.patternDeclaration(name, capture.value);
					case _: SourceTargetCommon.varDecl(target, name, capture.value);
				});
			}
			if (scope != null)
				caseFrame = SourceFunctionRenderFrameTools.withPhpScope(frame, scope);
			// Shared lowering ends a completing attempt with its guard branch.
			// Put the retry in that branch's else arm so native definite-assignment
			// analysis sees every value assignment without inferring a flag relation.
			switch bodies[index] {
				case SBlock(entries, _) if (entries.length > 0):
					switch entries[entries.length - 1] {
						case SIf(condition, accepted, null, _):
							for (line in SourceTargetCommon.renderStmtsWithFrame(caseFrame, entries.slice(0, entries.length - 1), ""))
								lines.push(line);
							var yes = SourceTargetCommon.renderStmtWithFrame(caseFrame, accepted, "").join("\n");
							if (nativeScope) {
								if (plan.caseCanCompleteNormally(index))
									yes += "\n" + (target == Java ? "break " : "goto ") + exitLabel + ";";
								lines.push(condition.match(EBool(true)) ? yes : branch(SourceTargetCommon.renderExprWithFrame(caseFrame, condition), yes, ""));
								// End the capture scope before retrying. A selected body exits the
								// enclosing labeled block, preserving native definite assignment.
								return "{\n" + nested(lines.join("\n")) + "\n}" + (condition.match(EBool(true)) ? "" : "\n" + rejected);
							}
							lines.push(condition.match(EBool(true)) ? yes : branch(SourceTargetCommon.renderExprWithFrame(caseFrame, condition), yes,
								rejected));
							return lines.join("\n");
						case _:
					}
				case _:
			}
			for (line in SourceTargetCommon.renderStmtWithFrame(caseFrame, bodies[index], ""))
				lines.push(line);
			final body = lines.join("\n");
			if (nativeScope) {
				if (plan.caseCanCompleteNormally(index))
					throw "completing guarded attempt lost its acceptance branch";
				return "{\n" + nested(body) + "\n}";
			}
			return (target == Lua ? "do\n" + nested(body) + "\nend" : target == Python ? body : "{\n" + nested(body) + "\n}")
				+ "\n"
				+ branch(retry, rejected, "");
		}
	});
	final scoped = target == Java ? exitLabel + ": {\n" + nested(source) + "\n}" : target == Cs ? "{\n"
		+ nested(source)
		+ "\n}\n"
		+ exitLabel
		+ ": ;" : source;
	return [for (line in scoped.split("\n")) indent + line];
}
