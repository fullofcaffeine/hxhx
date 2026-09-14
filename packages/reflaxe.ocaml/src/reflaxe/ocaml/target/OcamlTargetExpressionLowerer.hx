package reflaxe.ocaml.target;

import reflaxe.ocaml.OcamlNameTools;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;

/**
	Lowers the first recursive host-neutral expression family into OCaml syntax.

	Both compiler hosts call this target-owned implementation. Direct calls have
	no receiver, arguments, or represented result. Other call families, mutation,
	capture, conversions, null, and control flow remain unsupported here.
**/
class OcamlTargetExpressionLowerer {
	final localNames:Map<String, String>;

	/** Reserve called functions before locals, so keyword escaping cannot redirect a call. **/
	function new(expression:OcamlTargetExpressionFact) {
		localNames = [];
		final occupied:Map<String, Bool> = [];
		for (call in expression.copyStaticCalls())
			occupied.set(OcamlNameTools.normalizeValueIdentifier(OcamlNameTools.scopedValueName(call.moduleId, call.sourceTypeName, call.sourceFunctionName)),
				true);
		assignLocalNames(expression, occupied);
	}

	function assignLocalNames(expression:OcamlTargetExpressionFact, occupied:Map<String, Bool>):Void {
		if (expression.kind == VariableDeclarationExpression) {
			final binding = requireBinding(expression);
			final base = binding.sourceName == "_" ? "_hx" : OcamlNameTools.normalizeValueIdentifier(binding.sourceName);
			var name = base;
			var suffix = 2;
			while (occupied.exists(name))
				name = base + "_" + suffix++;
			occupied.set(name, true);
			localNames.set(binding.getCanonicalIdentity(), name);
		}
		for (child in expression.copyChildren())
			assignLocalNames(child, occupied);
	}

	public static function build(expression:OcamlTargetExpressionFact):OcamlExpr {
		if (expression == null)
			throw "OCaml target expression lowering requires a normalized expression";
		expression.validateClosedBindings();
		return new OcamlTargetExpressionLowerer(expression).buildNode(expression);
	}

	function buildNode(expression:OcamlTargetExpressionFact):OcamlExpr {
		return switch (expression.kind) {
			case StaticCallExpression:
				final call = expression.staticCall;
				if (call == null)
					throw "OCaml target static call lost its declaration";
				final name = OcamlNameTools.normalizeValueIdentifier(OcamlNameTools.scopedValueName(call.moduleId, call.sourceTypeName,
					call.sourceFunctionName));
				OcamlExpr.EApp(OcamlExpr.EIdent(name), [OcamlExpr.EConst(OcamlConst.CUnit)]);
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
				case LiteralExpression | LocalReadExpression | BlockExpression | StaticCallExpression:
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
