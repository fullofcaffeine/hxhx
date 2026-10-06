import backend.cpp.CppManagedCastPlan;
import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppManagedValueTransfer.accepts;
import backend.cpp.CppTypedProgramProjection;

/** A direct generic class literal retains public identity without permitting stored-handle narrowing. */
function check(program:CppTypedProgramProjection):Void {
	final owner = program.requireClass(program.requireClassIdentity('GenericContract'));
	final main = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == 'main')[0];
	final occurrences = main.getRuntimeTypeCatalog()
		.getEntries()
		.filter(value -> value.getValue() == null
			&& value.getTarget().requireDeclarationIdentity().getCanonicalName() == 'GenericContract.GenericBox');
	if (occurrences.length != 5)
		throw 'generic class fixture lost its class-handle or membership literals';
	final occurrence = occurrences[0];
	final identity = occurrence.getTarget().requireDeclarationIdentity();
	final concrete = TyType.nominal(new TyNominalTypeId('Class'), [TyType.nominal(identity, [TyType.fromHintText('Int')])]);
	final other = TyType.nominal(new TyNominalTypeId('Class'), [TyType.nominal(identity, [TyType.fromHintText('String')])]);
	final malformed = TyType.nominal(new TyNominalTypeId('Class'), [TyType.nominal(identity, [])]);
	final unrelated = TyType.nominal(new TyNominalTypeId('Class'), [TyType.fromHintText('String')]);
	final classes = new CppManagedClassStorage(program);
	final casts = new CppManagedCastPlan(program);
	if (!classes.acceptsClassLiteral(occurrence, concrete)
		|| !classes.acceptsClassLiteral(occurrences[1], other)
		|| classes.acceptsClassLiteral(occurrence, unrelated)
		|| accepts(concrete, other, casts)
		|| accepts(concrete, occurrence.getTarget().getValueType(), casts))
		throw 'generic class literal specialization admitted a different identity or stored narrowing';
	if (classes.requireRuntimeDescriptor(occurrence) != classes.requireRuntimeDescriptor(occurrences[1])
		|| classes.render().indexOf('false, 0') < 0
		|| classes.render().indexOf('InstanceDescriptor') >= 0)
		throw 'generic class literal split public identity or allocated an instance layout';
	rejected(() -> classes.acceptsClassLiteral(occurrence, malformed), 'exact type argument arity');
	final copied = new TypedBackendRuntimeTypeOccurrence(main.getStableIdentity(), main.getBodyRevision(), occurrence.getTarget());
	rejected(() -> classes.acceptsClassLiteral(copied, concrete), 'another program or occurrence');
	switch occurrence.getExpression() {
		case ECall(_, arguments):
			arguments.push(EInt(1));
			rejected(() -> classes.acceptsClassLiteral(occurrence, concrete), 'mutat');
			arguments.pop();
		case _:
			throw 'generic class literal lost its marker';
	}
	if (!classes.acceptsClassLiteral(occurrence, concrete))
		throw 'restored generic literal lost its contextual type';
	Sys.println('CPP_GENERIC_CLASS_VALUE_TRANSFER:PASS');
}

private function rejected(action:Void->Void, fragment:String):Void {
	try
		action()
	catch (error:haxe.Exception) {
		if (error.message.indexOf(fragment) < 0)
			throw error;
		return;
	}
	throw 'generic class literal accepted invalid ownership or type arguments';
}
