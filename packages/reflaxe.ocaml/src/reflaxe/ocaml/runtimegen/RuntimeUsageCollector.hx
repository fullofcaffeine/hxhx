package reflaxe.ocaml.runtimegen;

import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlLetBinding;
import reflaxe.ocaml.ast.OcamlMatchCase;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlTypeDecl;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/**
	Collects compiler-tracked runtime-module usage from generated OCaml AST.

	Why:
	- Metal runtime slicing must not depend on free-form output token scanning.
	- The compiler already has structured OCaml AST; this collector extracts `Hx*` module
	  references from that structure and records them for runtime planning.

	Scope:
	- Captures module roots used by emitted expressions/types/patterns (for example:
	  `HxArray.length`, `HxType.class_`, `HxRuntime.hx_null`).
	- Selection remains filtered by available runtime modules in `RuntimeCopier`.
**/
class RuntimeUsageCollector {
	static function isUpperAscii(code:Int):Bool {
		return code >= "A".code && code <= "Z".code;
	}

	static function modulePrefixFromQualified(name:String):String {
		final dot = name.indexOf(".");
		return dot > 0 ? name.substr(0, dot) : name;
	}

	static function isRuntimeModuleCandidate(name:String):Bool {
		if (name == null || name.length < 3)
			return false;
		if (!StringTools.startsWith(name, "Hx"))
			return false;
		final third = name.charCodeAt(2);
		return third != null && isUpperAscii(third);
	}

	static function markQualifiedName(name:String, markModule:String->Void):Void {
		if (name == null || name.length == 0)
			return;
		final moduleName = modulePrefixFromQualified(name);
		if (isRuntimeModuleCandidate(moduleName))
			markModule(moduleName);
	}

	static function collectTypeExpr(typ:OcamlTypeExpr, markModule:String->Void):Void {
		switch (typ) {
			case TIdent(name):
				markQualifiedName(name, markModule);
			case TApp(name, params):
				markQualifiedName(name, markModule);
				for (param in params)
					collectTypeExpr(param, markModule);
			case TArrow(from, to):
				collectTypeExpr(from, markModule);
				collectTypeExpr(to, markModule);
			case TTuple(items):
				for (item in items)
					collectTypeExpr(item, markModule);
			case TVar(_):
			case TRecord(fields):
				for (field in fields)
					collectTypeExpr(field.typ, markModule);
		}
	}

	static function collectPattern(pat:OcamlPat, markModule:String->Void):Void {
		switch (pat) {
			case PAny:
			case PVar(_):
			case PConst(_):
			case PTuple(items):
				for (item in items)
					collectPattern(item, markModule);
			case POr(items):
				for (item in items)
					collectPattern(item, markModule);
			case PConstructor(name, args):
				markQualifiedName(name, markModule);
				for (arg in args)
					collectPattern(arg, markModule);
			case PRecord(fields):
				for (field in fields)
					collectPattern(field.pat, markModule);
			case PAnnot(inner, typ):
				collectPattern(inner, markModule);
				collectTypeExpr(typ, markModule);
		}
	}

	static function collectMatchCase(matchCase:OcamlMatchCase, markModule:String->Void):Void {
		collectPattern(matchCase.pat, markModule);
		if (matchCase.guard != null)
			collectExpr(matchCase.guard, markModule);
		collectExpr(matchCase.expr, markModule);
	}

	static function collectExpr(expr:OcamlExpr, markModule:String->Void):Void {
		switch (expr) {
			case EConst(_):
			case EIdent(name):
				markQualifiedName(name, markModule);
			case ERaw(_):
				// Raw snippets are intentionally ignored; debug fallback in RuntimeCopier can
				// be enabled explicitly when investigating raw-emission paths.
			case EPos(_, inner):
				collectExpr(inner, markModule);
			case ERaise(exn):
				collectExpr(exn, markModule);
			case ELet(_, value, body, _):
				collectExpr(value, markModule);
				collectExpr(body, markModule);
			case EFun(params, body):
				for (param in params)
					collectPattern(param, markModule);
				collectExpr(body, markModule);
			case EApp(fn, args):
				collectExpr(fn, markModule);
				for (arg in args)
					collectExpr(arg, markModule);
			case EAppArgs(fn, args):
				collectExpr(fn, markModule);
				for (arg in args)
					collectExpr(arg.expr, markModule);
			case EBinop(_, left, right):
				collectExpr(left, markModule);
				collectExpr(right, markModule);
			case EUnop(_, inner):
				collectExpr(inner, markModule);
			case EIf(cond, thenExpr, elseExpr):
				collectExpr(cond, markModule);
				collectExpr(thenExpr, markModule);
				collectExpr(elseExpr, markModule);
			case EMatch(scrutinee, cases):
				collectExpr(scrutinee, markModule);
				for (matchCase in cases)
					collectMatchCase(matchCase, markModule);
			case ETry(body, cases):
				collectExpr(body, markModule);
				for (matchCase in cases)
					collectMatchCase(matchCase, markModule);
			case ESeq(exprs):
				for (item in exprs)
					collectExpr(item, markModule);
			case EWhile(cond, body):
				collectExpr(cond, markModule);
				collectExpr(body, markModule);
			case EList(items):
				for (item in items)
					collectExpr(item, markModule);
			case ERecord(fields):
				for (field in fields)
					collectExpr(field.value, markModule);
			case EField(target, _):
				collectExpr(target, markModule);
			case EAssign(_, lhs, rhs):
				collectExpr(lhs, markModule);
				collectExpr(rhs, markModule);
			case ETuple(items):
				for (item in items)
					collectExpr(item, markModule);
			case EAnnot(inner, typ):
				collectExpr(inner, markModule);
				collectTypeExpr(typ, markModule);
		}
	}

	static function collectTypeDecl(decl:OcamlTypeDecl, markModule:String->Void):Void {
		switch (decl.kind) {
			case Alias(typ):
				collectTypeExpr(typ, markModule);
			case Record(fields):
				for (field in fields)
					collectTypeExpr(field.typ, markModule);
			case Variant(constructors):
				for (constructor in constructors)
					for (arg in constructor.args)
						collectTypeExpr(arg, markModule);
		}
	}

	static function collectLetBinding(binding:OcamlLetBinding, markModule:String->Void):Void {
		collectExpr(binding.expr, markModule);
	}

	public static function collectFromModuleItems(items:Array<OcamlModuleItem>, markModule:String->Void):Void {
		for (item in items) {
			switch (item) {
				case ILet(bindings, _):
					for (binding in bindings)
						collectLetBinding(binding, markModule);
				case IType(decls, _):
					for (decl in decls)
						collectTypeDecl(decl, markModule);
			}
		}
	}
}
