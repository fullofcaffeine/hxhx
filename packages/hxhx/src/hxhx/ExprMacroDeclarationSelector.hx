package hxhx;

/** Names visible at one source point; production lexical traversal must supply this contract. */
typedef ExprMacroSelectionScope = {
	final visibility:ExprMacroScopeVisibility;
	final isStaticContext:Bool;
}

/**
	Find an unambiguous static macro (public, or private from its own class)
	through existing declaration lookup. Only a callee is inspected: receiver
	values and syntax arguments are never inferred or executed, and a receiver
	path whose last segment is not type-shaped is never resolved as a type.
	Null leaves ordinary/unresolved calls to normal typing. The caller owns module
	preparation and exact lexical visibility. Production expansion reaches this
	through `Stage3ExprMacroPass`; executing the selected macro is a later owner.
	Mixed field/method imports fail explicitly until their shared lookup owner
	provides one ordered member result; independent queries cannot prove a winner.
**/
function select(callee:HxExpr, context:TyperContext, scope:ExprMacroSelectionScope):Null<TyDeclarationInfo> {
	final names = switch scope.visibility {
		case Known(names): names;
		case Unavailable(reason): throw reason;
	};
	return switch callee {
		case EParenthesized(inner, _): select(inner, context, scope);
		case EIdent(name):
			if (names.indexOf(name) >= 0) {
				null;
			} else {
				final owner = context.currentClass();
				final field = owner == null ? null : owner.fieldInfo(name);
				if ((!scope.isStaticContext && (context.instanceMethodOwner(name) != null || context.instanceField(name, owner) != null))
					|| (field != null && (field.getIsStatic() || !scope.isStaticContext))) {
					null;
				} else if (owner != null && owner.staticMethodCandidates(name).length > 0) {
					declaration(owner, owner.staticMethodCandidates(name), true);
				} else if (context.moduleEnumConstructorMethod(name) != null) {
					null;
				} else {
					final imported = context.importedStaticMethod(name);
					final selected = imported == null ? null : declaration(imported.getProvider(), imported.getCandidates(), false);
					if (selected != null && context.importedStaticField(name) != null)
						throw "expression macro selection does not yet resolve mixed field and method imports";
					selected;
				}
			}
		case EField(receiver, name):
			final path = typePath(receiver);
			final segments = path == null ? [] : path.split(".");
			if (path == null
				|| valueRoot(segments[0], context, scope, names)
				|| !TyperStage.isUpperStartName(segments[segments.length - 1])) {
				null;
			} else {
				final owner = context.resolveType(path);
				if (owner == null || owner.fieldInfo(name) != null) {
					null;
				} else {
					final current = context.currentClass();
					final ownClass = current != null && current.getFullName() == owner.getFullName();
					declaration(owner, owner.staticMethodCandidates(name), ownClass);
				}
			}
		case _: null;
	};
}

/** A value-bound root must stay on ordinary typing, without inferring its receiver. */
private function valueRoot(name:String, context:TyperContext, scope:ExprMacroSelectionScope, names:Array<String>):Bool {
	if (names.indexOf(name) >= 0)
		return true;
	final owner = context.currentClass();
	final field = owner == null ? null : owner.fieldInfo(name);
	return (field != null && (field.getIsStatic() || !scope.isStaticContext))
		|| (owner != null && owner.staticMethodCandidates(name).length > 0)
		|| (!scope.isStaticContext && (context.instanceField(name, owner) != null || context.instanceMethodOwner(name) != null))
		|| context.importedStaticField(name) != null
		|| context.importedStaticMethod(name) != null
		|| context.moduleEnumConstructorMethod(name) != null;
}

/** Capture before recursion; parameter matching and runtime dispatch are later owners. */
function capture(call:HxExpr, context:TyperContext, scope:ExprMacroSelectionScope):Null<SelectedExprMacroCall> {
	return switch call {
		case ECall(callee, arguments):
			final selected = select(callee, context, scope);
			selected == null ? null : new SelectedExprMacroCall(selected, call, arguments);
		case _: null;
	};
}

/**
	Pick the one macro declaration among a method group. A private static macro is
	legal when the call is made from its own class (`ownClass`), matching upstream
	visibility; from any other class only a public static macro is selectable.
**/
private function declaration(owner:TyNominalInfo, candidates:Array<TyFunSig>, ownClass:Bool):Null<TyDeclarationInfo> {
	final declarations = [for (candidate in candidates) owner.declarationForSignature(candidate)];
	final macros = declarations.filter(value -> value != null && value.getMetadata().indexOf("macro") >= 0);
	if (macros.length == 0)
		return null;
	if (declarations.length != 1)
		throw "expression macro selection requires one exact declaration before argument typing";
	final selected = macros[0];
	if (!selected.getIsStatic())
		throw "expression macro selection requires a static declaration";
	if (!selected.getIsPublic() && !ownClass)
		throw "expression macro selection requires a public declaration when called outside its class";
	return selected;
}

/** Resolve only source type paths; a receiver-producing expression is never evaluated. */
private function typePath(value:HxExpr):Null<String> {
	return switch value {
		case EIdent(name): name;
		case EField(parent, name):
			final prefix = typePath(parent);
			prefix == null ? null : prefix + "." + name;
		case EParenthesized(inner, _): typePath(inner);
		case _: null;
	};
}
