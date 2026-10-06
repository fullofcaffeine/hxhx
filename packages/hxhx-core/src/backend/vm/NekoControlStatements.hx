package backend.vm;

/** Route shared control regions through ordinary Neko statements under their exact method owner. */
function project(input:HxStmt, context:NekoEmitContext):Null<HxStmt> {
	return switch input {
		case SExpr(expression, _) if (expression.match(ELoweredControl(_, _, _, _))):
			switch context.currentExecutable {
				case FunctionBody(selected): TypedControlStatements.methodStatement(expression, selected.body.requireRootControlIdentity(), observer(context));
				case _: throw "Neko lowered statement requires a declared method owner";
			}
		case _: null;
	};
}

/** Bind adapter-created statements to their original, exact cataloged try expressions. */
private function observer(context:NekoEmitContext):(HxExpr, HxStmt) -> Void {
	return (source, statement) -> context.typedProgram.requireCatchCatalog(context.currentExecutable).recordAdaptation(source, statement);
}

/** A closure keeps its lexical executable catalog while establishing its own return destination. */
function functionBody(body:HxExpr, context:NekoEmitContext):Array<HxStmt>
	return TypedControlStatements.functionBody(body, observer(context));

/** An initializer retains its exact field owner and cannot acquire a function return destination. */
function initializerBody(body:HxExpr, owner:String, context:NekoEmitContext):TypedControlStatements.InitializerStatements
	return TypedControlStatements.initializerBody(body, owner, observer(context));
