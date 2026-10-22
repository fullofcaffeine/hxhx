package backend.cpp;

/**
	Read the standard Math constants without inventing mutable storage for an extern.
	Typing owns alias resolution and access permission. This binding requires its
	exact declaration and Float contract; a user field with the same short name
	remains ordinary storage. The caller must admit the exact executable occurrence.
	Math functions and numeric operations keep their separate owners.
 */
function render(program:CppTypedProgramProjection, occurrence:Null<TypedBackendFieldOccurrence>):Null<String> {
	if (occurrence == null)
		return null;
	final field = occurrence.getField();
	if (field.getModulePath() != "Math" || field.getOwner().getCanonicalName() != "Math")
		return null;
	final number:Float = switch field.getCanonicalKey() {
		case "Math#static#PI": Math.PI;
		case "Math#static#NaN": Math.NaN;
		case "Math#static#POSITIVE_INFINITY": Math.POSITIVE_INFINITY;
		case "Math#static#NEGATIVE_INFINITY": Math.NEGATIVE_INFINITY;
		case _: return null;
	};
	program.assertCurrent();
	program.requireFieldDeclaration(field);
	final facts = program.requireClass(program.requireClassIdentity("Math")).requireSemanticFacts();
	final declared = facts.requireField(field);
	if (!facts.getIsExtern()
		|| !facts.getNominalKind().match(ClassInstance)
		|| facts.getTypeParameterIds().length != 0
		|| !field.getIsStatic()
		|| field.getIsInline()
		|| field.getHasInitializer()
		|| field.getPropertyGet() != "default"
		|| field.getPropertySet() != "null"
		|| field.getType().getSemanticKey() != "primitive:Float"
		|| declared.typeIdentity != "primitive:Float"
		|| occurrence.getType().getSemanticKey() != "primitive:Float"
		|| occurrence.getReceiver() == ValueReceiver)
		throw "managed Math constant requires its exact extern Float field contract";
	return CppManagedFloatLiteral.boxed(number);
}
