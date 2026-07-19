package reflaxe.ocaml.runtimegen;

import reflaxe.ocaml.ast.OcamlASTTraversal;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlLetBinding;
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
		OcamlASTTraversal.walkTypePre(typ, current -> switch (current) {
			case TIdent(name), TApp(name, _): markQualifiedName(name, markModule);
			case TArrow(_, _), TTuple(_), TVar(_), TRecord(_):
		});
	}

	static function collectExpr(expr:OcamlExpr, markModule:String->Void):Void {
		OcamlASTTraversal.walkExprPre(expr, current -> switch (current) {
			case EIdent(name): markQualifiedName(name, markModule);
			case EConst(_), ERaw(_), EPos(_, _), ERaise(_), ELet(_, _, _, _), EFun(_, _), EApp(_, _), EAppArgs(_, _), EBinop(_, _, _), EUnop(_, _),
				EIf(_, _, _), EMatch(_, _), ETry(_, _), ESeq(_), EWhile(_, _), EList(_), ERecord(_), EField(_, _), EAssign(_, _, _), ETuple(_), EAnnot(_, _):
		}, current -> switch (current) {
			case PConstructor(name, _): markQualifiedName(name, markModule);
			case PAny, PVar(_), PConst(_), PTuple(_), POr(_), PRecord(_), PAnnot(_, _):
		}, current -> switch (current) {
			case TIdent(name), TApp(name, _): markQualifiedName(name, markModule);
			case TArrow(_, _), TTuple(_), TVar(_), TRecord(_):
		});
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
