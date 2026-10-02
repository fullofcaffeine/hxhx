package backend.source;

/** A validated PHP runtime operation; zero arguments means a class value, one means a type test. */
typedef PhpRuntimeTypeOperation = {
	final typeName:String;
	final arguments:Array<HxExpr>;
};

private final marker = "\x00hxhx.php.runtime.type";

/**
	Validate every typed operand before PHP publishes an output file.

	The closed core kinds select existing runtime representations. Nominal
	operands must belong to the sealed emitted-type catalog; display spelling
	cannot supply a missing declaration. Other source targets keep their own
	admission guards.
**/
function validateProgram(projections:PhpTypedProgramProjection, facts:PhpProgramRenderFacts):Void {
	for (module in projections.getModules())
		for (cls in module.projection.getClasses()) {
			for (fn in cls.getFunctions()) {
				fn.getRuntimeTypeCatalog().assertMarkers(TypedRuntimeTypeSource.inStatements(fn.getBody()));
				validateCatalog(fn.getRuntimeTypeCatalog(), facts);
			}
			for (field in cls.getFieldInitializers()) {
				field.getRuntimeTypeCatalog().assertMarkers(TypedRuntimeTypeSource.inExpression(field.getExpression()));
				validateCatalog(field.getRuntimeTypeCatalog(), facts);
			}
		}
}

private function validateCatalog(catalog:TypedBackendRuntimeTypeCatalog, facts:PhpProgramRenderFacts):Void {
	for (entry in catalog.getEntries()) {
		entry.assertCurrent();
		targetName(entry.getTarget(), facts);
	}
}

/** Consume original occurrence identities before subsequent PHP rewrites copy syntax nodes. */
function body(renderer:PhpFunctionBodyRenderer, statements:Array<HxStmt>):Array<HxStmt>
	return SourceFunctionBodyRewriter.bodyWithOriginal(statements, (original, rebuilt) -> lower(renderer, original, rebuilt));

/** Field initializers share the function plan's exact occurrence and revision checks. */
function expression(renderer:PhpFunctionBodyRenderer, value:HxExpr):HxExpr
	return SourceFunctionBodyRewriter.expressionWithOriginal(value, (original, rebuilt) -> lower(renderer, original, rebuilt));

private function lower(renderer:PhpFunctionBodyRenderer, original:HxExpr, rebuilt:HxExpr):HxExpr {
	if (!TypedRuntimeTypeSource.isMarker(original))
		return rebuilt;
	final occurrence = renderer.getPlan().requireRuntimeType(original);
	final name = targetName(occurrence.getTarget(), renderer.getProgramFacts());
	final arguments = switch (rebuilt) {
		case ECall(_, arguments): arguments;
		case _: throw "PHP runtime type lowering lost its validated operation";
	};
	if (arguments.length != (occurrence.getValue() == null ? 0 : 1))
		throw "PHP runtime type lowering changed operand arity";
	return ECall(EUnsupported(marker), [EString(name), EArrayDecl(arguments)]);
}

private function targetName(target:TypedRuntimeTypeTarget, facts:PhpProgramRenderFacts):String {
	return switch (target.getKind()) {
		case StringCore: "String";
		case ArrayCore: "Array";
		case IntCore: "Int";
		case FloatCore: "Float";
		case BoolCore: "Bool";
		case Nominal(identity):
			final emitted = facts.findEmittedTypeName(identity.getCanonicalName());
			if (emitted == null || emitted.length == 0)
				throw "PHP runtime type operand has no emitted declaration: " + identity.getCanonicalName();
			emitted;
	};
}

/** Read only the target operation produced after exact occurrence validation. */
function decode(value:HxExpr):Null<PhpRuntimeTypeOperation> {
	return switch (value) {
		case ECall(EUnsupported(tag), [EString(name), EArrayDecl(arguments)]) if (tag == marker):
			if (name.length == 0 || arguments.length > 1)
				throw "PHP runtime type operation has invalid target data";
			{typeName: name, arguments: arguments};
		case ECall(EUnsupported(tag), _) if (tag == marker):
			throw "PHP runtime type operation is malformed";
		case _: null;
	};
}
