package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.ast.OcamlExpr.OcamlUnop;

using StringTools;

/**
 * Pretty-printer for OcamlAST.
 *
 * Goal (M1): render valid OCaml with stable formatting and correct precedence.
 * This is intentionally conservative about parentheses to avoid precedence bugs.
 */
class OcamlASTPrinter {
	static inline final INDENT = "  ";

	public function new() {}

	static function indent(level:Int):String {
		var s = "";
		for (_ in 0...level) s += INDENT;
		return s;
	}

	public function printModule(items:Array<OcamlModuleItem>):String {
		final parts:Array<String> = [];
		for (item in items) {
			parts.push(printItem(item));
		}
		return parts.join("\n\n");
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
	static inline final PREC_ADD = 30;
	static inline final PREC_MUL = 40;
	static inline final PREC_ASSIGN = 5;
	static inline final PREC_APP = 80;
	static inline final PREC_FIELD = 90;
	static inline final PREC_ATOM = 100;

	function exprPrec(e:OcamlExpr):Int {
		return switch (e) {
			case EConst(_), EIdent(_), ETuple(_), ERecord(_), EList(_):
				PREC_ATOM;
			case EField(_, _):
				PREC_FIELD;
			case EApp(_, _):
				PREC_APP;
			case EUnop(_, _):
				PREC_MUL;
			case EBinop(op, _, _):
				switch (op) {
					case Or: PREC_OR;
					case And: PREC_AND;
					case Eq, Neq, Lt, Lte, Gt, Gte: PREC_CMP;
					case Add, Sub: PREC_ADD;
					case Mul, Div, Mod: PREC_MUL;
				}
			case EAssign(_, _, _):
				PREC_ASSIGN;
			case ESeq(_):
				PREC_SEQ;
			case EWhile(_, _):
				PREC_SEQ;
			case ELet(_, _, _, _), EFun(_, _), EIf(_, _, _), EMatch(_, _):
				PREC_LET;
		}
	}

	function printExprCtx(e:OcamlExpr, ctxPrec:Int, indentLevel:Int):String {
		final p = exprPrec(e);
		final s = switch (e) {
			case EConst(c):
				printConst(c);
			case EIdent(name):
				name;
			case ETuple(items):
				"(" + items.map(i -> printExprCtx(i, PREC_TOP, indentLevel)).join(", ") + ")";
			case ERecord(fields):
				printRecord(fields, indentLevel);
			case EField(expr, field):
				final left = printExprCtx(expr, PREC_FIELD, indentLevel);
				left + "." + field;
			case EApp(fn, args):
				printApp(fn, args, indentLevel);
			case EBinop(op, left, right):
				printBinop(op, left, right, indentLevel);
			case EUnop(op, expr):
				printUnop(op, expr, indentLevel);
			case EAssign(op, lhs, rhs):
				final opStr = switch (op) {
					case RefSet: ":=";
					case FieldSet: "<-";
				}
				final l = printExprCtx(lhs, PREC_ASSIGN + 1, indentLevel);
				final r = printExprCtx(rhs, PREC_ASSIGN + 1, indentLevel);
				l + " " + opStr + " " + r;
			case ESeq(exprs):
				printSeq(exprs, indentLevel);
			case EWhile(cond, body):
				"while " + printExprCtx(cond, PREC_TOP, indentLevel)
				+ " do " + printExprCtx(body, PREC_TOP, indentLevel)
				+ " done";
			case EList(items):
				"[" + items.map(i -> printExprCtx(i, PREC_TOP, indentLevel)).join("; ") + "]";
			case ELet(name, value, body, isRec):
				printLetIn(name, value, body, isRec, indentLevel);
			case EFun(params, body):
				final ps = params.map(printPat).join(" ");
				"fun " + ps + " -> " + printExprCtx(body, PREC_TOP, indentLevel);
			case EIf(cond, thenExpr, elseExpr):
				"if " + printExprCtx(cond, PREC_TOP, indentLevel)
				+ " then " + printExprCtx(thenExpr, PREC_TOP, indentLevel)
				+ " else " + printExprCtx(elseExpr, PREC_TOP, indentLevel);
			case EMatch(scrutinee, cases):
				printMatch(scrutinee, cases, indentLevel);
		}

		return (p < ctxPrec) ? ("(" + s + ")") : s;
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
		return s
			.replace("\\", "\\\\")
			.replace("\"", "\\\"")
			.replace("\n", "\\n")
			.replace("\r", "\\r")
			.replace("\t", "\\t");
	}

	function printSeq(exprs:Array<OcamlExpr>, indentLevel:Int):String {
		if (exprs.length == 0) return "()";
		if (exprs.length == 1) return printExprCtx(exprs[0], PREC_TOP, indentLevel);

		final indent0 = indent(indentLevel);
		final indent1 = indent(indentLevel + 1);
		final parts = exprs.map(e -> indent1 + printExprCtx(e, PREC_TOP, indentLevel + 1));
		return "(\n" + parts.join(";\n") + "\n" + indent0 + ")";
	}

	function printBinop(op:OcamlBinop, left:OcamlExpr, right:OcamlExpr, indentLevel:Int):String {
		final opStr = switch (op) {
			case Add: "+";
			case Sub: "-";
			case Mul: "*";
			case Div: "/";
			case Mod: "mod";
			case Eq: "=";
			case Neq: "<>";
			case Lt: "<";
			case Lte: "<=";
			case Gt: ">";
			case Gte: ">=";
			case And: "&&";
			case Or: "||";
		}

		final p = exprPrec(OcamlExpr.EBinop(op, left, right));
		final l = printExprCtx(left, p, indentLevel);
		final r = printExprCtx(right, p + 1, indentLevel);
		return l + " " + opStr + " " + r;
	}

	function printUnop(op:OcamlUnop, expr:OcamlExpr, indentLevel:Int):String {
		return switch (op) {
			case Not: "not " + printExprCtx(expr, PREC_MUL, indentLevel);
			case Neg: "-" + printExprCtx(expr, PREC_MUL, indentLevel);
			case Deref: "!" + printExprCtx(expr, PREC_FIELD, indentLevel);
		}
	}

	function printRecord(fields:Array<OcamlRecordField>, indentLevel:Int):String {
		if (fields.length == 0) return "{}";
		final parts = fields.map(function(f) {
			return f.name + " = " + printExprCtx(f.value, PREC_TOP, indentLevel);
		});
		return "{ " + parts.join("; ") + " }";
	}

	function printApp(fn:OcamlExpr, args:Array<OcamlExpr>, indentLevel:Int):String {
		final f = printExprCtx(fn, PREC_APP, indentLevel);
		if (args.length == 0) return f;
		final renderedArgs = args.map(a -> printExprCtx(a, PREC_ATOM, indentLevel)).join(" ");
		return f + " " + renderedArgs;
	}

	function printLetIn(name:String, value:OcamlExpr, body:OcamlExpr, isRec:Bool, indentLevel:Int):String {
		final recStr = isRec ? " rec" : "";
		return "let" + recStr + " " + name + " = " + printExprCtx(value, PREC_TOP, indentLevel)
			+ " in " + printExprCtx(body, PREC_TOP, indentLevel);
	}

	function printMatch(scrutinee:OcamlExpr, cases:Array<OcamlMatchCase>, indentLevel:Int):String {
		final caseIndent = indent(indentLevel + 1);
		final head = "match " + printExprCtx(scrutinee, PREC_TOP, indentLevel) + " with";
		final arms = cases.map(function(c) {
			final guardStr = c.guard != null ? (" when " + printExprCtx(c.guard, PREC_TOP, indentLevel + 1)) : "";
			return caseIndent + "| " + printPat(c.pat) + guardStr + " -> " + printExprCtx(c.expr, PREC_TOP, indentLevel + 1);
		});
		return head + "\n" + arms.join("\n");
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
				if (args.length == 0) {
					name;
				} else if (args.length == 1) {
					name + " " + printPatCtx(args[0], true);
				} else {
					name + " (" + args.map(printPat).join(", ") + ")";
				}
			case PRecord(fields):
				"{ " + fields.map(f -> f.name + " = " + printPat(f.pat)).join("; ") + " }";
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
			final params = d.params.length > 0 ? (d.params.map(p -> "'" + p).join(" ") + " ") : "";
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
		if (constructors.length == 0) return "|";
		final indent0 = indent(indentLevel);
		final parts = constructors.map(function(c) {
			if (c.args.length == 0) return indent0 + "| " + c.name;
			final args = c.args.length == 1
				? printTypeCtx(c.args[0], TPREC_TOP)
				: c.args.map(a -> printTypeCtx(a, TPREC_TOP)).join(" * ");
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
