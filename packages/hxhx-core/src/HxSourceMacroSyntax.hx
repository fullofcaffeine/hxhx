import haxe.macro.Expr;

/**
	Convert authored groups, functions, and access metadata to public macro syntax.

	Callers supply leaf-expression and type conversion. This shared mapping owns
	function kind, grouping, optional markers, and default placement across hosts.
	It reads source facts only; inferred types cannot create written annotations.
 */
function definition(source:HxExpr, convert:HxExpr->Expr, parseType:String->Null<ComplexType>, ?parseMetadata:Array<String>->Metadata):Null<ExprDef> {
	return switch source {
		case EParenthesized(inner, _): EParenthesis(convert(inner));
		case EPrivateAccess(inner, _):
			final child = convert(inner);
			EMeta({name: ":privateAccess", params: [], pos: child.pos}, child);
		case HxExpr.EBinop(token, left, right): EBinop(HxMacroBinaryOperator.parse(token), convert(left), convert(right));
		case ERange(left, right): EBinop(OpInterval, convert(left), convert(right));
		case HxExpr.EWhile(condition, body, bodyIsBlock, _, kind):
			final convertedCondition = convert(condition);
			final convertedBody:Expr = if (bodyIsBlock) {
				{expr: EBlock([for (entry in body) convert(entry)]), pos: convertedCondition.pos};
			} else {
				if (body.length != 1)
					throw "source loop without braces requires one body expression";
				convert(body[0]);
			};
			haxe.macro.Expr.ExprDef.EWhile(convertedCondition, convertedBody, kind == Normal);
		case ESourceTry(catches, bodies, _):
			if (catches.length == 0 || bodies.length != catches.length + 1)
				throw "source try syntax requires ordered handler bodies";
			ETry(convert(bodies[0]), [
				for (index in 0...catches.length) {
					final entry = catches[index];
					{name: entry.getName(), type: entry.getTypeHint().length == 0 ? null : parseType(entry.getTypeHint()), expr: convert(bodies[index + 1])};
				}
			]);
		case ESourceFor(binding, iterable, body, _):
			final convertedIterable = convert(iterable);
			final position = convertedIterable.pos;
			final iterator:Expr = switch binding {
				case Value(name):
					{expr: EBinop(OpIn, {expr: EConst(CIdent(name)), pos: position}, convertedIterable), pos: position};
				case KeyValue(key, value):
					// The public macro tree nests `in` on the arrow's right, as in ordinary source.
					final valueIterator:Expr = {expr: EBinop(OpIn, {expr: EConst(CIdent(value)), pos: position}, convertedIterable), pos: position};
					{expr: EBinop(OpArrow, {expr: EConst(CIdent(key)), pos: position}, valueIterator), pos: position};
			};
			EFor(iterator, convert(body));
		case ESourceIf(condition, whenTrue, whenFalse, _):
			EIf(convert(condition), convert(whenTrue), whenFalse == null ? null : convert(whenFalse));
		case HxExpr.EThrow(value, _):
			haxe.macro.Expr.ExprDef.EThrow(convert(value));
		case ESourceGroup(children, _):
			EBlock([for (child in children) convert(child)]);
		case ESourceFunction(facts, body, defaults, _):
			facts.assertDefaultCount(defaults.length);
			final names = facts.getArguments();
			final parameters = facts.getSignature().getParameters();
			final defaultIndexes = facts.getDefaultParameterIndexes();
			final arguments = new Array<FunctionArg>();
			var defaultCursor = 0;
			for (index in 0...names.length) {
				final parameter = parameters[index];
				final type = parameter.typeHint == null ? null : parseType(parameter.typeHint);
				final argumentType = parameter.isRest && type != null ? TPath({
					pack: ["haxe"],
					name: "Rest",
					params: [TPType(type)]
				}) : type;
				final value = defaultCursor < defaultIndexes.length
					&& defaultIndexes[defaultCursor] == index ? convert(defaults[defaultCursor++]) : null;
				arguments.push({
					name: names[index],
					type: argumentType,
					// Upstream marks defaulted arrows optional, but preserves the written flag on full functions.
					opt: parameter.isOptional || (facts.getKind() == Arrow && parameter.hasDefault),
					value: value,
					meta: null
				});
			}
			final kind:FunctionKind = switch facts.getKind() {
				case Anonymous: FAnonymous;
				case Named(name, isInline): FNamed(name, isInline);
				case Arrow: FArrow;
			};
			final writtenResult = facts.getSignature().getReturnTypeHint();
			final convertedBody = convert(body);
			EFunction(kind, {
				args: arguments,
				ret: writtenResult == null ? null : parseType(writtenResult),
				expr: convertedBody,
				params: HxMacroTypeSyntax.parameterDeclarations(facts.getGenerics().getParameters(), convertedBody.pos, parseMetadata)
			});
		case _:
			null;
	};
}
