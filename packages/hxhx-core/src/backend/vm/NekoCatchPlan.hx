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
	final use:Null<TypedCatchUse>;
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
	public final occurrenceIdentity:String;

	final cases:Array<NekoCatchCase>;

	function new(program:NekoTypedProgramProjection, selected:Null<NekoExecutableProjection>, clauses:Array<{name:String, body:NekoCatchBody}>, ordinal:Int) {
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
		occurrenceIdentity = CompilerCacheIdentity.encode(["neko-catch-v1", executableIdentity, bodyRevision, Std.string(ordinal)]);
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
			cases.push({local: local, body: clause.body, use: exact.locals.findCatchUse(identity)});
		}
	}

	/** Validate implicit providers against this program before executable pruning or layout emission. */
	public function validate(program:NekoTypedProgramProjection):Void {
		for (entry in getCases()) {
			final use = entry.use;
			if (use == null || use.binding.getCanonicalIdentity() != entry.local.getBinding().getCanonicalIdentity())
				throw "Neko catch dispatch requires exact shared implicit-use facts";
			if (use.target != null) {
				NekoRuntimeTypeRegistry.requireTarget(program, use.target);
				if (use.target.getKind().match(Nominal(_))) {
					final ancestors = program.classGraph.requireAssignableTypes(use.target.requireDeclarationIdentity().getCanonicalName());
					final isException = Lambda.exists(ancestors, node -> node.classIdentity == "haxe.Exception");
					if (isException != use.view.match(ExceptionSubtype))
						throw "Neko catch classification disagrees with the exact class graph";
				}
			}
			if (use.conversion != null)
				program.requireFunction(use.conversion.getOwner().getCanonicalName(), use.conversion.getIdentity().getCanonicalKey());
			if (use.payload != null) {
				final owner = program.requireClass(use.payload.getOwner().getCanonicalName());
				final field = owner.requireSemanticFacts().findField(use.payload.getCanonicalKey());
				if (field == null || field.typeIdentity != use.payload.getType().getSemanticKey())
					throw "Neko catch dispatch lost its exact payload field";
				NekoRuntimeTypeRegistry.requireTarget(program, new TypedRuntimeTypeTarget(Nominal(use.payload.getOwner())));
			}
		}
	}

	/** Detect mutation of the source-ordered binding/body join after preparation. */
	public function assertStatement(node:HxStmt):Void {
		switch (node) {
			case STry(_, clauses, _):
				if (clauses.length != cases.length)
					throw "Neko catch occurrence changed after preparation";
				for (index in 0...clauses.length) {
					final expected = cases[index];
					if (clauses[index].name != expected.local.getProjectedName())
						throw "Neko catch occurrence changed after preparation";
					switch (expected.body) {
						case Statement(body) if (body == clauses[index].body):
						case _: throw "Neko catch occurrence changed after preparation";
					}
				}
			case _:
				throw "Neko catch occurrence is not a statement try";
		}
	}

	public function assertExpression(node:HxExpr):Void {
		switch (node) {
			case ECall(EIdent("__hxhx_try"), [ELambda([], _), EArrayDecl(entries), _]):
				if (entries.length != cases.length)
					throw "Neko catch occurrence changed after preparation";
				for (index in 0...entries.length) {
					final expected = cases[index];
					switch (entries[index]) {
						case EArrayDecl([EString(_), EString(_), ELambda([name], body)]) if (name == expected.local.getProjectedName()):
							switch (expected.body) {
								case Expression(original) if (body == original):
								case _: throw "Neko catch occurrence changed after preparation";
							}
						case _: throw "Neko catch occurrence changed after preparation";
					}
				}
			case _:
				throw "Neko catch occurrence is not an expression try";
		}
	}

	/** Returns handlers in source order without exposing the owned array. */
	public function getCases():Array<NekoCatchCase>
		return cases.copy();

	/** Match projected statement binders to their exact local facts, preserving source order. */
	public static function forStatement(program:NekoTypedProgramProjection, selected:Null<NekoExecutableProjection>, node:HxStmt):NekoCatchPlan {
		return program.requireCatchCatalog(selected).forStatement(node);
	}

	@:allow(backend.vm.NekoCatchCatalog)
	static function prepareStatement(program:NekoTypedProgramProjection, selected:NekoExecutableProjection,
			clauses:Array<{name:String, typeHint:String, body:HxStmt}>, ordinal:Int):NekoCatchPlan {
		return new NekoCatchPlan(program, selected, [for (clause in clauses) {name: clause.name, body: Statement(clause.body)}], ordinal);
	}

	/**
		Reads the projected lambda parameter, which names the exact catch binding.
		The string fields retain the original source name and hint, so a shadowed
		catch can legitimately have a different projected parameter spelling.
	**/
	public static function forExpression(program:NekoTypedProgramProjection, selected:Null<NekoExecutableProjection>, node:HxExpr):NekoCatchPlan {
		return program.requireCatchCatalog(selected).forExpression(node);
	}

	@:allow(backend.vm.NekoCatchCatalog)
	static function prepareExpression(program:NekoTypedProgramProjection, selected:NekoExecutableProjection, entries:Array<HxExpr>, ordinal:Int):NekoCatchPlan {
		final clauses = new Array<{name:String, body:NekoCatchBody}>();
		for (entry in entries) {
			switch (entry) {
				case EArrayDecl([EString(_), EString(_), ELambda([argument], body)]):
					clauses.push({name: argument, body: Expression(body)});
				case _:
					throw "Neko catch planning received a malformed expression handler";
			}
		}
		return new NekoCatchPlan(program, selected, clauses, ordinal);
	}
}
