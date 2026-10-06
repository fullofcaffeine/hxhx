package backend.js;

/**
	Run retained class startup functions once after all class methods exist.
	The target calls this phase before static field values, as Haxe initialization
	requires. The supplied projection contains only declarations selected for emission.
**/
function emit(writer:JsWriter, projection:TypedBackendClassProjection, reference:String):Void {
	for (functionProjection in projection.getFunctions()) {
		final declaration = functionProjection.getDeclaration();
		if (HxFunctionDecl.getIsStatic(declaration) && HxFunctionDecl.getName(declaration) == "__init__")
			writer.writeln(reference + JsNameMangler.propertySuffix("__init__") + "();");
	}
}

/**
	Order startup after classes used by its eager calls. Follow exact typed callees
	so a helper can expose a further dependency. Function values and quotations stay
	lazy; constructing them does not execute their bodies.
**/
function dependencies(program:MacroExpandedProgram):haxe.ds.StringMap<Array<String>> {
	final functions = new haxe.ds.ObjectMap<TyDeclarationInfo, TypedFunction>();
	for (module in program.getTypedModules())
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions())
				if (fn.getDeclaration() != null)
					functions.set(fn.getDeclaration(), fn);
	final result = new haxe.ds.StringMap<Array<String>>();
	for (module in program.getTypedModules())
		for (owner in module.getTypedClasses()) {
			final info = owner.getSemanticInfo();
			if (info == null)
				continue;
			final identity = info.getIdentity().getCanonicalName();
			final deps = new Array<String>();
			final pending = [
				for (fn in owner.getFunctions())
					if (fn.getDeclaration() != null
						&& fn.getDeclaration().getIsStatic()
						&& fn.getDeclaration().getSignature().getName() == "__init__") fn
			];
			final seen = new haxe.ds.ObjectMap<TypedFunction, Bool>();
			function add(target:String):Void {
				if (target != identity && deps.indexOf(target) < 0)
					deps.push(target);
			}
			function expression(node:TypedExpr):Void {
				switch (node.getTag()) {
					case MacroExpr | MacroType | SourceFunction | Lambda:
						return;
					case _:
				}
				final declaration = node.getDeclaration();
				if (declaration != null && (node.getTag() == Call || node.getTag() == NewValue)) {
					add(declaration.getOwner().getCanonicalName());
					final callee = functions.get(declaration);
					if (callee != null && !seen.exists(callee))
						pending.push(callee);
				}
				final field = node.getFieldInfo();
				if (field != null && field.getIsStatic())
					add(field.getOwner().getCanonicalName());
				for (child in node.getExpressions())
					expression(child);
			}
			function statement(node:TypedStmt):Void {
				for (child in node.getExpressions())
					expression(child);
				for (child in node.getStatements())
					statement(child);
			}
			var cursor = 0;
			while (cursor < pending.length) {
				final fn = pending[cursor++];
				if (seen.exists(fn))
					continue;
				seen.set(fn, true);
				for (body in fn.getBody().getStatements())
					statement(body);
			}
			result.set(identity, deps);
		}
	return result;
}
