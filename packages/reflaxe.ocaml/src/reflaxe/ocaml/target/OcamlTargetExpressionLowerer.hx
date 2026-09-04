package reflaxe.ocaml.target;

import reflaxe.ocaml.OcamlNameTools;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;

/**
	Lowers the first recursive host-neutral expression family into OCaml syntax.

	Both compiler hosts call this target-owned implementation. Revision 1 contains
	no mutation, capture, conversion, null, call, or control-flow decisions; those
	remain unsupported until their existing standalone plans cross the boundary.
**/
class OcamlTargetExpressionLowerer {
	public static function build(expression:OcamlTargetExpressionFact):OcamlExpr {
		if (expression == null)
			throw "OCaml target expression lowering requires a normalized expression";
		expression.validateClosedBindings();
		return buildNode(expression);
	}

	static function buildNode(expression:OcamlTargetExpressionFact):OcamlExpr {
		return switch (expression.kind) {
			case LiteralExpression:
				final literal = expression.literal;
				if (literal == null)
					throw "OCaml target literal expression lost its fact";
				OcamlTargetLiteralLowerer.buildNonNull(literal, Direct);
			case LocalReadExpression:
				OcamlExpr.EIdent(bindingName(requireBinding(expression)));
			case VariableDeclarationExpression:
				final binding = requireBinding(expression);
				final children = expression.copyChildren();
				OcamlExpr.ELet(bindingName(binding), buildNode(children[0]), OcamlExpr.EConst(OcamlConst.CUnit), false);
			case BlockExpression:
				buildBlock(expression.copyChildren());
		};
	}

	static function buildBlock(children:Array<OcamlTargetExpressionFact>):OcamlExpr {
		var result = OcamlExpr.EConst(OcamlConst.CUnit);
		var hasResult = false;
		var index = children.length;
		while (index > 0) {
			index--;
			final child = children[index];
			switch (child.kind) {
				case VariableDeclarationExpression:
					final binding = requireBinding(child);
					final initializer = child.copyChildren()[0];
					result = OcamlExpr.ELet(bindingName(binding), buildNode(initializer), result, false);
					hasResult = true;
				case LiteralExpression | LocalReadExpression | BlockExpression:
					final built = buildNode(child);
					if (!hasResult) {
						result = built;
						hasResult = true;
					} else {
						result = OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [built]), result]);
					}
			}
		}
		return result;
	}

	static function requireBinding(expression:OcamlTargetExpressionFact):OcamlTargetBindingFact {
		final binding = expression.binding;
		if (binding == null)
			throw "OCaml target expression lowering lost a source binding";
		return binding;
	}

	static function bindingName(binding:OcamlTargetBindingFact):String
		return binding.sourceName == "_" ? "_hx" : OcamlNameTools.normalizeValueIdentifier(binding.sourceName);
}
