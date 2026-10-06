import backend.cpp.CppManagedCastPlan;
import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppManagedValueTransfer.accepts;
import backend.cpp.CppTypedProgramProjection;

/** Preserve the distinction between an owned polymorphic literal and a stored erased class value. */
function check(program:CppTypedProgramProjection):Void {
	final owner = program.requireClass(program.requireClassIdentity('Main'));
	final initializers = owner.getFieldInitializers().filter(value -> value.getField().getName() == 'selected');
	if (initializers.length != 1)
		throw 'Array class fixture lost its selected initializer';
	final initializer = initializers[0];
	final occurrences = initializer.getRuntimeTypeCatalog().getEntries();
	if (occurrences.length != 1)
		throw 'Array class fixture lost its literal occurrence';
	final occurrence = occurrences[0];
	final concrete = initializer.getField().getType();
	final erased = occurrence.getTarget().getValueType();
	final casts = new CppManagedCastPlan(program);
	final classes = new CppManagedClassStorage(program);
	if (!classes.acceptsClassLiteral(occurrence, concrete) || !accepts(erased, concrete, casts) || accepts(concrete, erased, casts))
		throw 'Array class transfer confused literal specialization with stored narrowing';
	if (accepts(concrete.getTypeArguments()[0], erased.getTypeArguments()[0], casts))
		throw 'Array class transfer incorrectly admitted array-value conversion';
	final stringArray = TyType.nominal(new TyNominalTypeId('Class'), [TyType.nominal(new TyNominalTypeId('Array'), [TyType.fromHintText('String')])]);
	final stringClass = TyType.nominal(new TyNominalTypeId('Class'), [TyType.fromHintText('String')]);
	if (accepts(stringArray, concrete, casts) || classes.acceptsClassLiteral(occurrence, stringClass))
		throw 'Array class transfer admitted unrelated concrete arguments or class identities';
	final copied = new TypedBackendRuntimeTypeOccurrence(initializer.getStableIdentity(), initializer.getBodyRevision(), occurrence.getTarget());
	rejected(() -> classes.acceptsClassLiteral(copied, concrete), 'another program or occurrence');
	Sys.println('CPP_ARRAY_CLASS_VALUE_TRANSFER:PASS');
}

private function rejected(action:Void->Void, expected:String):Void {
	try
		action()
	catch (error:haxe.Exception) {
		if (error.message.indexOf(expected) < 0)
			throw error;
		return;
	}
	throw 'Array class transfer accepted copied runtime facts';
}
