package backend.vm;

/**
	Render reserved Neko module values from their authored binding names.

	Upstream Neko reserves __dollar__loader and __dollar__exports even when either names a typed local or
	parameter. Backend transport renaming must not turn that intrinsic into a
	scalar local read. Exact local facts recover the source name; ordinary names
	and field accesses keep their normal resolution. Exports belong to the entry
	module, so authored classes share them even when emission creates several VM
	modules. The VM owns the loader and exports objects.
**/
function renderValue(context:NekoEmitContext, projectedName:String):Null<String> {
	var sourceName = projectedName;
	if (context != null && context.currentExecutable != null) {
		final catalog = switch context.currentExecutable {
			case FunctionBody(selected):
				final current = context.typedProgram.requireDeclaredFunction(selected.body.getDeclaration());
				if (current.body != selected.body || current.owner != selected.owner)
					throw "Neko loader read belongs to another function projection";
				current.body.getLocalCatalog();
			case FieldInitializer(selected):
				if (context.typedProgram.requireDeclaredInitializer(selected.getDeclaration()) != selected)
					throw "Neko loader read belongs to another initializer projection";
				selected.getLocalCatalog();
		};
		final local = catalog.findByProjectedName(projectedName);
		if (local != null)
			sourceName = local.getBinding().getSourceName();
	}
	return switch sourceName {
		case "__dollar__loader": "$loader";
		case "__dollar__exports":
			if (context == null || context.symbolTable == null)
				throw "Neko exports read requires the program symbol table";
			context.symbolTable + "." + context.typedProgram.runtimeHelperName("__hxhx_entry_exports");
		case _: null;
	};
}

/** Capture the VM entry exports before support modules or authored startup can observe them. */
function renderEntryExports(out:Array<String>, symbols:String, program:NekoTypedProgramProjection):Void {
	out.push(symbols + "." + program.runtimeHelperName("__hxhx_entry_exports") + " = $exports;");
}
