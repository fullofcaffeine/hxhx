package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.ast.OcamlExpr.OcamlUnop;

using StringTools;

private enum OcamlExpressionPrintWork {
	EmitText(value:String);
	EmitExpression(expression:OcamlExpr, contextPrecedence:Int, indentation:Int);
}

/**
 * Pretty-printer for OcamlAST.
 *
 * Goal (M1): render valid OCaml with stable formatting and correct precedence.
 * This is intentionally conservative about parentheses to avoid precedence bugs.
 *
 * Expression rendering uses an explicit work stack. Generated compiler code can
 * contain thousands of nested `let ... in` expressions, which are valid OCaml
 * syntax but exceed the Haxe evaluator's function-call stack when printed by a
 * recursive visitor. The work stack preserves the same output order without
 * making one Haxe function call per syntax-tree level.
 */
class OcamlASTPrinter {
	static inline final INDENT = "  ";
	static final indentCache:Array<String> = [""];

	public function new() {}

	static function indent(level:Int):String {
		if (level <= 0)
			return "";
		while (indentCache.length <= level) {
			indentCache.push(indentCache[indentCache.length - 1] + INDENT);
		}
		return indentCache[level];
	}

	static function escapeLineDirectiveFile(file:String):String {
		if (file == null)
			return "";
		return file.replace("\\", "\\\\").replace("\"", "\\\"");
	}

	public function printModule(items:Array<OcamlModuleItem>):String {
		if (items.length == 0)
			return "";
		if (items.length == 1)
			return printItem(items[0]);
		final buf = new StringBuf();
		for (i in 0...items.length) {
			if (i != 0)
				buf.add("\n\n");
			buf.add(printItem(items[i]));
		}
		return buf.toString();
	}

	public function printItem(item:OcamlModuleItem):String {
		return switch (item) {
			case ILet(bindings, isRec):
				printLetBindings(bindings, isRec);
			case IType(decls, isRec):
				printTypeDecls(decls, isRec);
		}
	}

	public function printExpr(expr:OcamlExpr):String {
		return printExprCtx(expr, 0, 0);
	}

	// =========================================================
	// Expressions
	// =========================================================
	static inline final PREC_TOP = 0;
	static inline final PREC_LET = 1;
	static inline final PREC_SEQ = 2;
	static inline final PREC_IF = 3;
	static inline final PREC_OR = 10;
	static inline final PREC_AND = 11;
	static inline final PREC_CMP = 20;
	static inline final PREC_CONS = 25;
	static inline final PREC_ADD = 30;
	static inline final PREC_CONCAT = 29;
	static inline final PREC_MUL = 40;
	static inline final PREC_ASSIGN = 5;
	static inline final PREC_APP = 80;
	static inline final PREC_FIELD = 90;
	static inline final PREC_ATOM = 100;

	function exprPrec(e:OcamlExpr):Int {
		var current = e;
		while (true) {
			switch (current) {
				case EPos(_, inner):
					current = inner;
				case EConst(_), EIdent(_), ERaw(_), ETuple(_), ERecord(_), EList(_), EAnnot(_, _):
					return PREC_ATOM;
				case EField(_, _):
					return PREC_FIELD;
				case EApp(_, _), EAppArgs(_, _):
					return PREC_APP;
				case EUnop(_, _):
					return PREC_MUL;
				case EBinop(op, _, _):
					return switch (op) {
						case Or: PREC_OR;
						case And: PREC_AND;
						case Eq, Neq, PhysEq, PhysNeq, Lt, Lte, Gt, Gte: PREC_CMP;
						case Cons: PREC_CONS;
						case Concat: PREC_CONCAT;
						case Add, AddF, Sub, SubF: PREC_ADD;
						case Mul, MulF, Div, DivF, Mod: PREC_MUL;
					};
				case EAssign(_, _, _):
					return PREC_ASSIGN;
				case ESeq(_), EWhile(_, _):
					return PREC_SEQ;
				case ELet(_, _, _, _), EFun(_, _), EIf(_, _, _), EMatch(_, _), ETry(_, _), ERaise(_):
					return PREC_LET;
			}
		}
		return PREC_TOP;
	}

	function printExprCtx(e:OcamlExpr, ctxPrec:Int, indentLevel:Int):String {
		final buffer = new StringBuf();
		final work:Array<OcamlExpressionPrintWork> = [EmitExpression(e, ctxPrec, indentLevel)];
		while (work.length > 0) {
			switch (work.pop()) {
				case EmitText(value):
					buffer.add(value);
				case EmitExpression(expression, contextPrecedence, indentation):
					final needsContextParens = exprPrec(expression) < contextPrecedence;
					if (needsContextParens)
						work.push(EmitText(")"));
					pushExpressionContent(work, expression, contextPrecedence, indentation);
					if (needsContextParens)
						work.push(EmitText("("));
			}
		}
		return buffer.toString();
	}

	function pushExpressionContent(work:Array<OcamlExpressionPrintWork>, expression:OcamlExpr, contextPrecedence:Int, indentation:Int):Void {
		switch (expression) {
			case EConst(constant):
				work.push(EmitText(printConst(constant)));
			case EIdent(name), ERaw(name):
				work.push(EmitText(name));
			case EPos(position, inner):
				pushExpression(work, inner, contextPrecedence, indentation);
				work.push(EmitText("\n# " + Std.string(position.line) + " \"" + escapeLineDirectiveFile(position.file) + "\"\n" + indent(indentation)));
			case ERaise(exception):
				work.push(EmitText(")"));
				pushExpression(work, exception, PREC_TOP, indentation);
				work.push(EmitText("raise ("));
			case ETuple(items):
				work.push(EmitText(")"));
				pushExpressionArray(work, items, ", ", PREC_TOP, indentation, needsTupleElementParens);
				work.push(EmitText("("));
			case EAnnot(inner, type):
				work.push(EmitText(")"));
				work.push(EmitText(printType(type)));
				work.push(EmitText(" : "));
				pushExpression(work, inner, PREC_TOP, indentation);
				work.push(EmitText("("));
			case ERecord(fields):
				if (fields.length == 0) {
					work.push(EmitText("{}"));
				} else {
					work.push(EmitText(" }"));
					var index = fields.length;
					while (index > 0) {
						index--;
						if (index < fields.length - 1)
							work.push(EmitText("; "));
						final field = fields[index];
						pushExpression(work, field.value, PREC_TOP, indentation, recordFunctionValueNeedsParens(field.value));
						work.push(EmitText(field.name + " = "));
					}
					work.push(EmitText("{ "));
				}
			case EField(owner, field):
				work.push(EmitText("." + field));
				pushExpression(work, owner, PREC_FIELD, indentation);
			case EApp(functionExpression, arguments):
				var index = arguments.length;
				while (index > 0) {
					index--;
					final argument = arguments[index];
					pushExpression(work, argument, PREC_ATOM, indentation, needsExprParensInApp(argument));
					work.push(EmitText(" "));
				}
				pushExpression(work, functionExpression, PREC_APP, indentation);
			case EAppArgs(functionExpression, arguments):
				var index = arguments.length;
				while (index > 0) {
					index--;
					final argument = arguments[index];
					if (argument.label == null) {
						pushExpression(work, argument.expr, PREC_ATOM, indentation, needsExprParensInApp(argument.expr));
					} else {
						pushExpression(work, argument.expr, PREC_TOP, indentation, labelledArgumentNeedsParens(argument.expr));
						work.push(EmitText((argument.isOptional ? "?" : "~") + argument.label + ":"));
					}
					work.push(EmitText(" "));
				}
				pushExpression(work, functionExpression, PREC_APP, indentation);
			case EBinop(op, left, right):
				final precedence = binaryPrecedence(op);
				final isRightAssociative = op == Cons || op == Concat;
				pushExpression(work, right, isRightAssociative ? precedence : precedence + 1, indentation);
				work.push(EmitText(" " + binaryOperatorText(op) + " "));
				pushExpression(work, left, isRightAssociative ? precedence + 1 : precedence, indentation);
			case EUnop(op, inner):
				switch (op) {
					case Not:
						work.push(EmitText(")"));
						pushExpression(work, inner, PREC_TOP, indentation);
						work.push(EmitText("not ("));
					case Neg, NegF, Deref:
						final prefix = switch (op) {
							case Neg: "-";
							case NegF: "-.";
							case Deref: "!";
							case Not: "not ";
						};
						final needsParens = needsParensAfterPrefix(inner);
						pushExpression(work, inner, needsParens ? PREC_TOP : (op == Deref ? PREC_FIELD : PREC_MUL), indentation, needsParens);
						work.push(EmitText(prefix));
				}
			case EAssign(op, left, right):
				pushExpression(work, right, PREC_ASSIGN + 1, indentation);
				work.push(EmitText(switch (op) {
					case RefSet: " := ";
					case FieldSet: " <- ";
				}));
				pushExpression(work, left, PREC_ASSIGN + 1, indentation);
			case ESeq(expressions):
				if (expressions.length == 0) {
					work.push(EmitText("()"));
				} else if (expressions.length == 1) {
					pushExpression(work, expressions[0], PREC_TOP, indentation);
				} else {
					work.push(EmitText("\n" + indent(indentation) + ")"));
					var index = expressions.length;
					while (index > 0) {
						index--;
						pushExpression(work, expressions[index], PREC_TOP, indentation + 1);
						work.push(EmitText(index == 0 ? "(\n" + indent(indentation + 1) : ";\n" + indent(indentation + 1)));
					}
				}
			case EWhile(condition, body):
				work.push(EmitText(" done"));
				pushExpression(work, body, PREC_TOP, indentation);
				work.push(EmitText(" do "));
				pushExpression(work, condition, PREC_TOP, indentation);
				work.push(EmitText("while "));
			case EList(items):
				work.push(EmitText("]"));
				pushExpressionArray(work, items, "; ", PREC_TOP, indentation, _ -> false);
				work.push(EmitText("["));
			case ELet(name, value, body, isRecursive):
				pushExpression(work, body, PREC_TOP, indentation);
				work.push(EmitText(" in "));
				pushExpression(work, value, PREC_TOP, indentation);
				work.push(EmitText("let" + (isRecursive ? " rec" : "") + " " + name + " = "));
			case EFun(parameters, body):
				pushExpression(work, body, PREC_TOP, indentation);
				work.push(EmitText("fun " + parameters.map(printPat).join(" ") + " -> "));
			case EIf(condition, thenExpression, elseExpression):
				pushExpression(work, elseExpression, PREC_TOP, indentation);
				work.push(EmitText(" else "));
				pushExpression(work, thenExpression, PREC_TOP, indentation);
				work.push(EmitText(" then "));
				pushExpression(work, condition, PREC_TOP, indentation);
				work.push(EmitText("if "));
			case EMatch(scrutinee, cases):
				pushMatchCases(work, cases, indentation);
				work.push(EmitText(" with\n"));
				pushExpression(work, scrutinee, PREC_TOP, indentation);
				work.push(EmitText("match "));
			case ETry(body, cases):
				pushMatchCases(work, cases, indentation);
				work.push(EmitText(" with\n"));
				pushExpression(work, body, PREC_TOP, indentation);
				work.push(EmitText("try "));
		}
	}

	static function pushExpression(work:Array<OcamlExpressionPrintWork>, expression:OcamlExpr, contextPrecedence:Int, indentation:Int,
			explicitParens:Bool = false):Void {
		if (explicitParens)
			work.push(EmitText(")"));
		work.push(EmitExpression(expression, contextPrecedence, indentation));
		if (explicitParens)
			work.push(EmitText("("));
	}

	static function pushExpressionArray(work:Array<OcamlExpressionPrintWork>, expressions:Array<OcamlExpr>, separator:String, contextPrecedence:Int,
			indentation:Int, needsExplicitParens:OcamlExpr->Bool):Void {
		var index = expressions.length;
		while (index > 0) {
			index--;
			if (index < expressions.length - 1)
				work.push(EmitText(separator));
			final expression = expressions[index];
			pushExpression(work, expression, contextPrecedence, indentation, needsExplicitParens(expression));
		}
	}

	function pushMatchCases(work:Array<OcamlExpressionPrintWork>, cases:Array<OcamlMatchCase>, indentation:Int):Void {
		var index = cases.length;
		while (index > 0) {
			index--;
			final matchCase = cases[index];
			pushExpression(work, matchCase.expr, PREC_TOP, indentation + 1, needsGroupingInMatchArmExpr(matchCase.expr));
			work.push(EmitText(" -> "));
			if (matchCase.guard != null) {
				pushExpression(work, matchCase.guard, PREC_TOP, indentation + 1);
				work.push(EmitText(" when "));
			}
			work.push(EmitText(indent(indentation + 1) + "| " + printPat(matchCase.pat)));
			if (index > 0)
				work.push(EmitText("\n"));
		}
	}

	static function binaryPrecedence(op:OcamlBinop):Int {
		return switch (op) {
			case Or: PREC_OR;
			case And: PREC_AND;
			case Eq, Neq, PhysEq, PhysNeq, Lt, Lte, Gt, Gte: PREC_CMP;
			case Cons: PREC_CONS;
			case Concat: PREC_CONCAT;
			case Add, AddF, Sub, SubF: PREC_ADD;
			case Mul, MulF, Div, DivF, Mod: PREC_MUL;
		}
	}

	static function binaryOperatorText(op:OcamlBinop):String {
		return switch (op) {
			case Add: "+";
			case AddF: "+.";
			case Concat: "^";
			case Sub: "-";
			case SubF: "-.";
			case Mul: "*";
			case MulF: "*.";
			case Div: "/";
			case DivF: "/.";
			case Mod: "mod";
			case Cons: "::";
			case Eq: "=";
			case Neq: "<>";
			case PhysEq: "==";
			case PhysNeq: "!=";
			case Lt: "<";
			case Lte: "<=";
			case Gt: ">";
			case Gte: ">=";
			case And: "&&";
			case Or: "||";
		}
	}

	static function needsTupleElementParens(expression:OcamlExpr):Bool {
		var current = expression;
		while (true) {
			switch (current) {
				case EPos(_, inner):
					current = inner;
				case ELet(_, _, _, _) | EFun(_, _) | EIf(_, _, _) | EMatch(_, _) | ETry(_, _) | ESeq(_) | EWhile(_, _) | EAssign(_, _, _) | ERaise(_):
					return true;
				case _:
					return false;
			}
		}
		return false;
	}

	static function recordFunctionValueNeedsParens(expression:OcamlExpr):Bool {
		return switch (expression) {
			case EPos(_, inner):
				switch (inner) {
					case EFun(_, _): true;
					case _: false;
				}
			case EFun(_, _): true;
			case _: false;
		}
	}

	static function labelledArgumentNeedsParens(expression:OcamlExpr):Bool {
		return switch (expression) {
			case EPos(_, inner):
				switch (inner) {
					case EConst(_), EIdent(_), EField(_, _), ETuple(_), ERecord(_), EList(_): false;
					case _: true;
				}
			case EConst(_), EIdent(_), EField(_, _), ETuple(_), ERecord(_), EList(_): false;
			case _: true;
		}
	}

	static function needsParensAfterPrefix(expression:OcamlExpr):Bool {
		var current = expression;
		while (true) {
			switch (current) {
				case EPos(_, inner):
					current = inner;
				case EConst(_), EIdent(_), EField(_, _):
					return false;
				case _:
					return true;
			}
		}
		return true;
	}

	function printConst(c:OcamlConst):String {
		return switch (c) {
			case CInt(v): Std.string(v);
			case CFloat(v): v;
			case CString(v): "\"" + escapeString(v) + "\"";
			case CBool(true): "true";
			case CBool(false): "false";
			case CUnit: "()";
		}
	}

	function escapeString(s:String):String {
		// Use `StringTools.replace` (not `String.replace`) so escaping is stable across
		// macro/eval runtimes and replaces all occurrences.
		//
		// This is correctness-critical: failing to escape `"` yields invalid OCaml
		// (e.g. `""HELLO""`), which breaks macro-host builds and any code that embeds
		// quotes in string literals.
		var out = s;
		out = StringTools.replace(out, "\\", "\\\\");
		out = StringTools.replace(out, "\"", "\\\"");
		out = StringTools.replace(out, "\n", "\\n");
		out = StringTools.replace(out, "\r", "\\r");
		out = StringTools.replace(out, "\t", "\\t");
		return out;
	}

	function needsExprParensInApp(e:OcamlExpr):Bool {
		var current = e;
		while (true) {
			switch (current) {
				case EPos(_, inner):
					current = inner;
				case EConst(CInt(value)):
					return value < 0;
				case EConst(CFloat(value)):
					return value.startsWith("-");
				case _:
					return false;
			}
		}
		return false;
	}

	function needsGroupingInMatchArmExpr(e:OcamlExpr):Bool {
		// OCaml parsing gotcha:
		// `| pat -> <expr ending in match/try> | nextPat -> ...` can cause the `| nextPat`
		// to be parsed as an additional case of the *inner* match/try expression.
		//
		// We only need to parenthesize when the RHS *ends with* an unparenthesized `match`/`try`
		// in tail position (so an immediately following `|` token would be legal as another case).
		//
		// This is intentionally more precise than “contains match/try anywhere” so that snapshot
		// output stays stable (nested matches in subexpressions are already parenthesized by
		// precedence rules in their respective printer contexts).
		function endsWithBranchyTail(expr:OcamlExpr):Bool {
			var cur = expr;
			while (true) {
				switch (cur) {
					case EPos(_, inner):
						cur = inner;
					case EMatch(_, _), ETry(_, _):
						return true;
					case ELet(_, _, body, _):
						cur = body;
					case EFun(_, body):
						cur = body;
					case EIf(_, _, elseExpr):
						cur = elseExpr;
					case ESeq(exprs):
						if (exprs.length == 1) {
							cur = exprs[0];
						} else {
							// Multi-expr sequences are always printed as `(<e1>; <e2>; ...)`,
							// so they already delimit any inner `match`/`try`.
							return false;
						}
					case _:
						return false;
				}
			}
			return false;
		}

		return endsWithBranchyTail(e);
	}

	// =========================================================
	// Patterns
	// =========================================================

	public function printPat(p:OcamlPat):String {
		return switch (p) {
			case PAny: "_";
			case PVar(name): name;
			case PConst(c): printConst(c);
			case PTuple(items):
				"(" + items.map(printPat).join(", ") + ")";
			case POr(items):
				items.map(printPat).join(" | ");
			case PConstructor(name, args):
				if (name == "[]" && args.length == 0) {
					"[]";
				} else if (name == "::" && args.length == 2) {
					printPatCtx(args[0], true) + " :: " + printPatCtx(args[1], true);
				} else if (args.length == 0) {
					name;
				} else if (args.length == 1) {
					name + " " + printPatCtx(args[0], true);
				} else {
					name + " (" + args.map(printPat).join(", ") + ")";
				}
			case PRecord(fields):
				"{ " + fields.map(f -> f.name + " = " + printPat(f.pat)).join("; ") + " }";
			case PAnnot(pat, typ):
				"(" + printPat(pat) + " : " + printType(typ) + ")";
		}
	}

	function printPatCtx(p:OcamlPat, inApp:Bool):String {
		final rendered = printPat(p);
		return (inApp && needsPatParensInApp(p)) ? ("(" + rendered + ")") : rendered;
	}

	function needsPatParensInApp(p:OcamlPat):Bool {
		return switch (p) {
			case PConstructor(_, _): true;
			case PRecord(_): true;
			case PTuple(_): true;
			case POr(_): true;
			case PAnnot(_, _): true;
			case _: false;
		}
	}

	// =========================================================
	// Types / module items
	// =========================================================

	public function printType(t:OcamlTypeExpr):String {
		return printTypeCtx(t, 0);
	}

	static inline final TPREC_TOP = 0;
	static inline final TPREC_ARROW = 1;
	static inline final TPREC_TUPLE = 2;
	static inline final TPREC_APP = 3;
	static inline final TPREC_ATOM_T = 4;

	function typePrec(t:OcamlTypeExpr):Int {
		return switch (t) {
			case TArrow(_, _): TPREC_ARROW;
			case TTuple(_): TPREC_TUPLE;
			case TApp(_, _): TPREC_APP;
			case TIdent(_), TVar(_), TRecord(_): TPREC_ATOM_T;
		}
	}

	function printTypeCtx(t:OcamlTypeExpr, ctxPrec:Int):String {
		final p = typePrec(t);
		final s = switch (t) {
			case TIdent(name):
				name;
			case TVar(name):
				"'" + name;
			case TTuple(items):
				items.map(i -> printTypeCtx(i, TPREC_TUPLE)).join(" * ");
			case TArrow(from, to):
				final left = printTypeCtx(from, TPREC_ARROW + 1);
				final right = printTypeCtx(to, TPREC_ARROW);
				left + " -> " + right;
			case TApp(name, params):
				if (params.length == 0) {
					name;
				} else if (params.length == 1) {
					printTypeCtx(params[0], TPREC_APP) + " " + name;
				} else {
					"(" + params.map(p -> printTypeCtx(p, TPREC_TOP)).join(", ") + ") " + name;
				}
			case TRecord(fields):
				"{ " + fields.map(function(f) {
					final mut = f.isMutable ? "mutable " : "";
					return mut + f.name + " : " + printTypeCtx(f.typ, TPREC_TOP);
				}).join("; ") + " }";
		}

		return (p < ctxPrec) ? ("(" + s + ")") : s;
	}

	function printTypeDecls(decls:Array<OcamlTypeDecl>, isRec:Bool):String {
		final recStr = isRec ? " rec" : "";
		final parts:Array<String> = [];
		for (i in 0...decls.length) {
			final d = decls[i];
			final headKw = (i == 0) ? ("type" + recStr) : "and";
			final params = switch (d.params.length) {
				case 0:
					"";
				case 1:
					"'" + d.params[0] + " ";
				case _:
					"(" + d.params.map(p -> "'" + p).join(", ") + ") ";
			}
			final rhs = switch (d.kind) {
				case Alias(t):
					printType(t);
				case Record(fields):
					printType(TRecord(fields));
				case Variant(constructors):
					printVariantConstructors(constructors, 0);
			}
			final eqSep = StringTools.startsWith(rhs, "\n") ? " =" : " = ";
			parts.push(headKw + " " + params + d.name + eqSep + rhs);
		}
		return parts.join("\n");
	}

	function printVariantConstructors(constructors:Array<OcamlVariantConstructor>, indentLevel:Int):String {
		if (constructors.length == 0)
			return "|";
		final indent0 = indent(indentLevel);
		final parts = constructors.map(function(c) {
			if (c.args.length == 0)
				return indent0 + "| " + c.name;
			final args = c.args.length == 1 ? printTypeCtx(c.args[0], TPREC_TUPLE) : c.args.map(a -> printTypeCtx(a, TPREC_TUPLE)).join(" * ");
			return indent0 + "| " + c.name + " of " + args;
		});
		return "\n" + parts.join("\n");
	}

	function printLetBindings(bindings:Array<OcamlLetBinding>, isRec:Bool):String {
		final recStr = isRec ? " rec" : "";
		final parts:Array<String> = [];
		for (i in 0...bindings.length) {
			final b = bindings[i];
			final headKw = (i == 0) ? ("let" + recStr) : "and";
			parts.push(headKw + " " + b.name + " = " + printExprCtx(b.expr, PREC_TOP, 0));
		}
		return parts.join("\n");
	}
}
