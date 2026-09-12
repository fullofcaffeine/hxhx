package reflaxe.ocaml.ast;

/** References in retained declarations; other generated files need their own facts. */
typedef OcamlModuleReferenceSummary = {
	final functionModules:Array<String>;
	final initializationModules:Array<String>;
	final typeModules:Array<String>;
	final hasOpaqueText:Bool;
}

/**
	Finds qualified module names before target declarations become text.

	A top-level function body runs later. Other initializers are conservatively
	classified as eager, including closures nested inside those initializers.
	These reference sets do not prove effect order or safe recursive initialization.
	Raw fragments remain explicitly opaque even when their typed children are visible.
**/
class OcamlModuleReferences {
	final functions:Map<String, Bool> = [];
	final initialization:Map<String, Bool> = [];
	final types:Map<String, Bool> = [];
	var opaque:Bool = false;

	function new() {}

	public static function collect(items:Array<OcamlModuleItem>):OcamlModuleReferenceSummary {
		final collector = new OcamlModuleReferences();
		for (item in items)
			switch (item) {
				case ILet(bindings, _):
					for (binding in bindings) {
						collector.expression(binding.expr, isFunction(binding.expr) ? collector.functions : collector.initialization);
						if (binding.signature != null)
							collector.type(binding.signature);
					}
				case IType(declarations, _):
					for (declaration in declarations)
						switch (declaration.kind) {
							case Alias(type): collector.type(type);
							case Record(fields): for (field in fields)
									collector.type(field.typ);
							case Variant(constructors): for (constructor in constructors)
									for (argument in constructor.args)
										collector.type(argument);
						}
			}
		return {
			functionModules: sorted(collector.functions),
			initializationModules: sorted(collector.initialization),
			typeModules: sorted(collector.types),
			hasOpaqueText: collector.opaque
		};
	}

	/** Source and type annotations do not make constructing a function execute its body. */
	static function isFunction(expression:OcamlExpr):Bool {
		var current = expression;
		while (true)
			switch (current) {
				case EPos(_, inner), EAnnot(inner, _):
					current = inner;
				case EFun(_, _):
					return true;
				case _:
					return false;
			}
	}

	function expression(value:OcamlExpr, modules:Map<String, Bool>):Void {
		OcamlASTTraversal.walkExprPre(value, current -> switch (current) {
			case EIdent(name): qualified(name, modules);
			case ERuntimeIdent(reference): qualified(reference.exactSymbol, modules);
			case EField(root, field):
				qualified(field, modules);
				switch (root) {
					case EIdent(name): qualified(name + "." + field, modules);
					case _:
				}
			case ERecord(fields): for (field in fields)
					qualified(field.name, modules);
			case ERawInjection(_): opaque = true;
			case EConst(_), EPos(_, _), ERaise(_), ELet(_, _, _, _), EFun(_, _), EApp(_, _), EAppArgs(_, _), EBinop(_, _, _), EUnop(_, _), EIf(_, _, _),
				EMatch(_, _), ETry(_, _), ESeq(_), EWhile(_, _), EList(_), EAssign(_, _, _), ETuple(_), EAnnot(_, _):
		}, current -> switch (current) {
			case PConstructor(name, _): qualified(name, modules);
			case PRuntimeConstructor(reference, _): qualified(reference.exactSymbol, modules);
			case PRecord(fields): for (field in fields)
					qualified(field.name, modules);
			case PAny, PVar(_), PConst(_), PTuple(_), POr(_), PAnnot(_, _):
		}, typeNode);
	}

	function type(value:OcamlTypeExpr):Void {
		OcamlASTTraversal.walkTypePre(value, typeNode);
	}

	function typeNode(value:OcamlTypeExpr):Void {
		switch (value) {
			case TIdent(name), TApp(name, _):
				qualified(name, types);
			case TRuntimeIdent(reference), TRuntimeApp(reference, _):
				qualified(reference.exactSymbol, types);
			case TArrow(_, _), TTuple(_), TVar(_), TRecord(_):
		}
	}

	/** Reads a qualified AST identifier, never an OCaml expression or raw fragment. */
	static function qualified(name:String, modules:Map<String, Bool>):Void {
		final dot = name.indexOf(".");
		if (dot <= 0)
			return;
		final first = name.charCodeAt(0);
		if (first != null && first >= "A".code && first <= "Z".code)
			modules.set(name.substr(0, dot), true);
	}

	static function sorted(modules:Map<String, Bool>):Array<String> {
		final names = [for (name in modules.keys()) name];
		names.sort((left, right) -> left < right ? -1 : (left == right ? 0 : 1));
		return names;
	}
}
