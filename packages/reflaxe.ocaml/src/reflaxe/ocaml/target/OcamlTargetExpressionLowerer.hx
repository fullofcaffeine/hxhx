package reflaxe.ocaml.target;

import reflaxe.ocaml.OcamlNameTools;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/**
	Lowers the first recursive host-neutral expression family into OCaml syntax.

	Both compiler hosts call this target-owned implementation. Direct static calls
	evaluate arguments once, in Haxe source order. Function statements share the
	same binding allocator as their parameters and value expressions.
**/
class OcamlTargetExpressionLowerer {
	final localNames:Map<String, String>;
	final occupied:Map<String, Bool>;

	/** Reserve called functions before locals, so keyword escaping cannot redirect a call. **/
	function new(expressions:Array<OcamlTargetExpressionFact>, parameters:Array<OcamlTargetBindingFact>) {
		localNames = [];
		occupied = [];
		for (expression in expressions)
			for (call in expression.copyStaticCalls())
				occupied.set(OcamlNameTools.normalizeValueIdentifier(OcamlNameTools.scopedValueName(call.moduleId, call.sourceTypeName,
					call.sourceFunctionName)), true);
		for (parameter in parameters) {
			final used = expressions.filter(expression -> readsBinding(expression, parameter.getCanonicalIdentity())).length != 0;
			assignBindingName(parameter, !used);
		}
		for (expression in expressions)
			assignLocalNames(expression);
	}

	function assignLocalNames(expression:OcamlTargetExpressionFact):Void {
		if (expression.kind == VariableDeclarationExpression)
			assignBindingName(requireBinding(expression));
		for (child in expression.copyChildren())
			assignLocalNames(child);
	}

	function assignBindingName(binding:OcamlTargetBindingFact, unused:Bool = false):Void {
		var base = binding.sourceName == "_" ? "_hx" : OcamlNameTools.normalizeValueIdentifier(binding.sourceName);
		if (unused && !StringTools.startsWith(base, "_"))
			base = "_" + base;
		localNames.set(binding.getCanonicalIdentity(), allocateName(base));
	}

	static function readsBinding(expression:OcamlTargetExpressionFact, identity:String):Bool {
		if (expression.kind == LocalReadExpression && requireBinding(expression).getCanonicalIdentity() == identity)
			return true;
		for (child in expression.copyChildren())
			if (readsBinding(child, identity))
				return true;
		return false;
	}

	function allocateName(base:String):String {
		var name = base;
		var suffix = 2;
		while (occupied.exists(name))
			name = base + "_" + suffix++;
		occupied.set(name, true);
		return name;
	}

	public static function build(expression:OcamlTargetExpressionFact):OcamlExpr {
		if (expression == null)
			throw "OCaml target expression lowering requires a normalized expression";
		expression.validateClosedBindings();
		return new OcamlTargetExpressionLowerer([expression], []).buildNode(expression);
	}

	/** Allocate parameters and locals together, then lower the validated terminal-return body. **/
	public static function buildFunction(fact:OcamlTargetFunctionFact):OcamlExpr {
		final expressions = new Array<OcamlTargetExpressionFact>();
		collectExpressions(fact.body, expressions);
		final parameters = fact.copyParameters();
		final builder = new OcamlTargetExpressionLowerer(expressions, parameters);
		final patterns = [
			for (parameter in parameters)
				OcamlPat.PAnnot(OcamlPat.PVar(builder.bindingName(parameter)), primitiveType(parameter.semanticTypeDisplay))
		];
		if (patterns.length == 0)
			patterns.push(OcamlPat.PConst(OcamlConst.CUnit));
		return OcamlExpr.EFun(patterns, OcamlExpr.EAnnot(builder.buildStatement(fact.body), primitiveType(fact.returnTypeDisplay)));
	}

	static function collectExpressions(statement:OcamlTargetStatementFact, output:Array<OcamlTargetExpressionFact>):Void {
		if (statement.expression != null)
			output.push(statement.expression);
		for (child in statement.copyChildren())
			collectExpressions(child, output);
	}

	static function primitiveType(type:String):OcamlTypeExpr {
		return OcamlTypeExpr.TIdent(switch (type) {
			case "Int": "int";
			case "Bool": "bool";
			case "String": "string";
			case "Void": "unit";
			case _: throw "OCaml target function has an unsupported represented type";
		});
	}

	function buildStatement(statement:OcamlTargetStatementFact):OcamlExpr {
		return switch (statement.kind) {
			case ReturnStatement:
				statement.expression == null ? OcamlExpr.EConst(OcamlConst.CUnit) : buildNode(statement.expression);
			case ExpressionStatement:
				if (statement.expression == null)
					throw "OCaml target expression statement lost its expression";
				OcamlExpr.EApp(OcamlExpr.EIdent("Stdlib.ignore"), [buildNode(statement.expression)]);
			case BlockStatement:
				var result = OcamlExpr.EConst(OcamlConst.CUnit);
				final children = statement.copyChildren();
				children.reverse();
				for (child in children) {
					final expression = child.expression;
					if (child.kind == ExpressionStatement && expression != null && expression.kind == VariableDeclarationExpression) {
						result = OcamlExpr.ELet(bindingName(requireBinding(expression)), buildNode(onlyChild(expression)), result, false);
					} else if (child.endsInReturn()) {
						result = buildStatement(child);
					} else {
						result = OcamlExpr.ESeq([buildStatement(child), result]);
					}
				}
				result;
		};
	}

	function buildNode(expression:OcamlTargetExpressionFact):OcamlExpr {
		return switch (expression.kind) {
			case ConditionalExpression:
				final children = expression.copyChildren();
				OcamlExpr.EIf(buildNode(children[0]), buildNode(children[1]), buildNode(children[2]));
			case StaticCallExpression:
				final call = expression.staticCall;
				if (call == null)
					throw "OCaml target static call lost its declaration";
				final name = OcamlNameTools.normalizeValueIdentifier(OcamlNameTools.scopedValueName(call.moduleId, call.sourceTypeName,
					call.sourceFunctionName));
				final arguments = expression.copyChildren();
				final names = [for (_ in arguments) allocateName("hx_arg")];
				final values = arguments.length == 0 ? [OcamlExpr.EConst(OcamlConst.CUnit)] : [for (name in names) OcamlExpr.EIdent(name)];
				var result = OcamlExpr.EApp(OcamlExpr.EIdent(name), values);
				var index = arguments.length;
				while (index > 0) {
					index--;
					result = OcamlExpr.ELet(names[index], buildNode(arguments[index]), result, false);
				}
				result;
			case LiteralExpression:
				final literal = expression.literal;
				if (literal == null)
					throw "OCaml target literal expression lost its fact";
				OcamlTargetLiteralLowerer.buildNonNull(literal, Direct);
			case LocalReadExpression:
				OcamlExpr.EIdent(bindingName(requireBinding(expression)));
			case VariableDeclarationExpression:
				final binding = requireBinding(expression);
				OcamlExpr.ELet(bindingName(binding), buildNode(onlyChild(expression)), OcamlExpr.EConst(OcamlConst.CUnit), false);
			case BlockExpression:
				buildBlock(expression.copyChildren());
		};
	}

	function buildBlock(children:Array<OcamlTargetExpressionFact>):OcamlExpr {
		var result = OcamlExpr.EConst(OcamlConst.CUnit);
		var hasResult = false;
		final reverseChildren = children.copy();
		reverseChildren.reverse();
		for (child in reverseChildren) {
			switch (child.kind) {
				case VariableDeclarationExpression:
					final binding = requireBinding(child);
					final initializer = onlyChild(child);
					result = OcamlExpr.ELet(bindingName(binding), buildNode(initializer), result, false);
					hasResult = true;
				case LiteralExpression | LocalReadExpression | BlockExpression | StaticCallExpression | ConditionalExpression:
					final built = buildNode(child);
					if (!hasResult) {
						result = built;
						hasResult = true;
					} else {
						result = OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("Stdlib.ignore"), [built]), result]);
					}
			}
		}
		return result;
	}

	static function onlyChild(expression:OcamlTargetExpressionFact):OcamlTargetExpressionFact {
		var selected:Null<OcamlTargetExpressionFact> = null;
		for (child in expression.copyChildren()) {
			if (selected != null)
				throw "OCaml target variable declaration has more than one initializer";
			selected = child;
		}
		if (selected == null)
			throw "OCaml target variable declaration has no initializer";
		return selected;
	}

	static function requireBinding(expression:OcamlTargetExpressionFact):OcamlTargetBindingFact {
		final binding = expression.binding;
		if (binding == null)
			throw "OCaml target expression lowering lost a source binding";
		return binding;
	}

	function bindingName(binding:OcamlTargetBindingFact):String {
		final name = localNames.get(binding.getCanonicalIdentity());
		if (name == null)
			throw "OCaml target local has no allocated name";
		return name;
	}
}
