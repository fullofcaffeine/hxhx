package reflaxe.ocaml.ast;

/**
	Collects selected free value names from structured target expressions.
	Function parameters, local lets, match patterns, and catch patterns retain
	their lexical scopes. Raw text has no inferred names; its typed children
	remain visible. Callers supply the names whose declaration dependencies matter.
**/
function collect(expr:OcamlExpr, want:Map<String, Bool>):Map<String, Bool> {
	final out:Map<String, Bool> = [];
	final bound:Map<String, Int> = [];

	function boundAdd(n:String):Void {
		final c = bound.exists(n) ? bound.get(n) : 0;
		bound.set(n, c + 1);
	}

	function boundRemove(n:String):Void {
		if (!bound.exists(n))
			return;
		final c = bound.get(n);
		if (c <= 1)
			bound.remove(n)
		else
			bound.set(n, c - 1);
	}

	function isBound(n:String):Bool
		return bound.exists(n);

	function collectPatNames(p:OcamlPat, acc:Array<String>):Void {
		switch (p) {
			case PAny:
			case PVar(n):
				acc.push(n);
			case PTuple(items):
				for (i in items)
					collectPatNames(i, acc);
			case PRecord(fields):
				for (f in fields)
					collectPatNames(f.pat, acc);
			case PConstructor(_, args), PRuntimeConstructor(_, args):
				for (a in args)
					collectPatNames(a, acc);
			case POr(items):
				for (i in items)
					collectPatNames(i, acc);
			case PAnnot(pat, _):
				collectPatNames(pat, acc);
			case PConst(_):
		}
	}

	function visit(e:OcamlExpr):Void {
		switch (e) {
			case EPos(_, inner):
				visit(inner);
			case EConst(_):
			case ERawInjection(injection):
				for (part in injection.segments())
					switch (part) {
						case RawText(_):
						case RawExpression(child):
							visit(child);
					}
			case EAnnot(expr, _):
				visit(expr);
			case ERaise(exn):
				visit(exn);
			case EIdent(n):
				if (!isBound(n) && want.exists(n))
					out.set(n, true);
			case ERuntimeIdent(reference):
				if (!isBound(reference.exactSymbol) && want.exists(reference.exactSymbol))
					out.set(reference.exactSymbol, true);
			case ELet(n, value, body, isRec):
				if (isRec) {
					boundAdd(n);
					visit(value);
					visit(body);
					boundRemove(n);
				} else {
					visit(value);
					boundAdd(n);
					visit(body);
					boundRemove(n);
				}
			case EFun(params, body):
				final names:Array<String> = [];
				for (p in params)
					collectPatNames(p, names);
				for (n in names)
					boundAdd(n);
				visit(body);
				for (n in names)
					boundRemove(n);
			case EApp(fn, args):
				visit(fn);
				for (a in args)
					visit(a);
			case EAppArgs(fn, args):
				visit(fn);
				for (a in args)
					visit(a.expr);
			case EBinop(_, l, r):
				visit(l);
				visit(r);
			case EUnop(_, e1):
				visit(e1);
			case EIf(c, t, f):
				visit(c);
				visit(t);
				visit(f);
			case EMatch(scrutinee, cases):
				visit(scrutinee);
				for (c in cases) {
					final names:Array<String> = [];
					collectPatNames(c.pat, names);
					for (n in names)
						boundAdd(n);
					if (c.guard != null)
						visit(c.guard);
					visit(c.expr);
					for (n in names)
						boundRemove(n);
				}
			case ETry(body, cases):
				visit(body);
				for (c in cases) {
					final names:Array<String> = [];
					collectPatNames(c.pat, names);
					for (n in names)
						boundAdd(n);
					if (c.guard != null)
						visit(c.guard);
					visit(c.expr);
					for (n in names)
						boundRemove(n);
				}
			case ESeq(items):
				for (i in items)
					visit(i);
			case EWhile(c, b):
				visit(c);
				visit(b);
			case EList(items):
				for (i in items)
					visit(i);
			case ERecord(fields):
				for (f in fields)
					visit(f.value);
			case EField(e1, _):
				visit(e1);
			case EAssign(_, l, r):
				visit(l);
				visit(r);
			case ETuple(items):
				for (i in items)
					visit(i);
		}
	}

	visit(expr);
	return out;
}
