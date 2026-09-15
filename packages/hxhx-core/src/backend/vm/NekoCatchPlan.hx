package backend.vm;

/** Preserves the source handler form after its exact catch binding is selected. */
enum NekoCatchBody {
	Statement(body:HxStmt);
	Expression(body:HxExpr);
}

/** One source-ordered handler with the semantic type selected by the shared typer. */
typedef NekoCatchCase = {
	final local:TypedBackendLocalProjection;
	final body:NekoCatchBody;
}

/**
	Joins source-shaped catch clauses to one exact typed function or initializer.

	Catch names only locate entries in that body's local catalog. Their spelling
	and written hints do not establish types. Both statement and expression
	handlers retain source order and the same exact binding contract.
**/
class NekoCatchPlan {
	public final executableIdentity:String;
	public final bodyRevision:String;

	final cases:Array<NekoCatchCase>;

	function new(program:NekoTypedProgramProjection, selected:Null<NekoExecutableProjection>, clauses:Array<{name:String, body:NekoCatchBody}>) {
		if (selected == null)
			throw "Neko catch planning requires an exact current executable";
		final exact = switch (selected) {
			case FunctionBody(functionProjection):
				final current = program.requireDeclaredFunction(functionProjection.body.getDeclaration());
				if (current.body != functionProjection.body || current.owner != functionProjection.owner)
					throw "Neko catch planning received a foreign function projection";
				{identity: current.body.getStableIdentity(), revision: current.body.getBodyRevision(), locals: current.body.getLocalCatalog()};
			case FieldInitializer(initializer):
				final current = program.requireDeclaredInitializer(initializer.getDeclaration());
				if (current != initializer)
					throw "Neko catch planning received a foreign initializer projection";
				{identity: current.getStableIdentity(), revision: current.getBodyRevision(), locals: current.getLocalCatalog()};
		};
		executableIdentity = exact.identity;
		bodyRevision = exact.revision;
		cases = [];
		final seen = new haxe.ds.StringMap<Bool>();
		for (clause in clauses) {
			final local = exact.locals.findByProjectedName(clause.name);
			if (local == null || !local.getBinding().getKind().match(CatchVariable))
				throw "Neko catch planning cannot find exact catch binding " + clause.name + " in " + executableIdentity;
			final type = local.getBinding().getType();
			if (type.isUnknown() || type.isUnresolved())
				throw "Neko catch planning requires a resolved catch type for " + clause.name;
			final identity = local.getBinding().getIdentity().getCanonicalKey();
			if (seen.exists(identity))
				throw "Neko catch planning received duplicate catch binding " + identity;
			seen.set(identity, true);
			cases.push({local: local, body: clause.body});
		}
	}

	/** Returns handlers in source order without exposing the owned array. */
	public function getCases():Array<NekoCatchCase>
		return cases.copy();

	/** Match projected statement binders to their exact local facts, preserving source order. */
	public static function forStatement(program:NekoTypedProgramProjection, selected:Null<NekoExecutableProjection>,
			clauses:Array<{name:String, typeHint:String, body:HxStmt}>):NekoCatchPlan {
		return new NekoCatchPlan(program, selected, [for (clause in clauses) {name: clause.name, body: Statement(clause.body)}]);
	}

	/**
		Reads the projected lambda parameter, which names the exact catch binding.
		The string fields retain the original source name and hint, so a shadowed
		catch can legitimately have a different projected parameter spelling.
	**/
	public static function forExpression(program:NekoTypedProgramProjection, selected:Null<NekoExecutableProjection>, entries:Array<HxExpr>):NekoCatchPlan {
		final clauses = new Array<{name:String, body:NekoCatchBody}>();
		for (entry in entries) {
			switch (entry) {
				case EArrayDecl([EString(_), EString(_), ELambda([argument], body)]):
					clauses.push({name: argument, body: Expression(body)});
				case _:
					throw "Neko catch planning received a malformed expression handler";
			}
		}
		return new NekoCatchPlan(program, selected, clauses);
	}
}
