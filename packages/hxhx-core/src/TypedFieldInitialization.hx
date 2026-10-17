/**
	Enum constants select their initializer conversion from their owning declaration.
	Infer their source first: a literal has the backing type, while an alias already
	has the enum-abstract type. Ordinary fields retain their written expected type.
 */
function expectedType(field:TyFieldInfo):Null<TyType>
	return field.getConstant().isEnumValue() ? null : field.getType();

/**
	Retain a declared abstract conversion before projecting a field initializer.
	An enum constant alone may introduce its abstract from the validated backing
	value without a public `from` conversion. The exact field and constant evidence
	bound this permission; ordinary assignments still use declared conversions.
 */
function adapt(index:TyperIndex, field:TyFieldInfo, expression:TypedExpr, filePath:String):TypedExpr {
	if (!field.getIsStatic())
		rejectInstanceReceiver(expression, filePath);
	if (field.getConstant().isEnumValue()) {
		final owner = index == null ? null : index.getAbstractByFullName(field.getOwner().getCanonicalName());
		if (owner == null || owner.getEnumDomain() == null || owner.fieldInfo(field.getName()) != field)
			throw "enum initializer requires its exact indexed constant declaration";
		switch (field.getConstant().getKind()) {
			case Unresolved(reason):
				throw new TyperError(filePath, expression.getPosition(), "Unresolved enum-abstract constant: " + reason);
			case _:
		}
		if (expression.getType().getSemanticKey() == field.getType().getSemanticKey())
			return expression;
		if (expression.getType().getSemanticKey() != owner.getUnderlyingType().getSemanticKey())
			throw new TyperError(filePath, expression.getPosition(), "Enum constant initializer does not match its backing type");
		return TypedExpr.castValue(expression, field.getType().getDisplay(), field.getType(), expression.getPosition(), true);
	}
	final conversion = TyImplicitConversionPlan.select(index, field.getType(), expression.getType());
	return conversion != null && conversion.isRepresentationPreservingAbstractConversion() ? conversion.apply(expression) : expression;
}

/** Typed identities distinguish an implicit receiver from a shadowing local or another object's field. */
private function rejectInstanceReceiver(expression:TypedExpr, filePath:String):Void {
	final field = expression.getFieldInfo();
	if (expression.getTag() == ThisValue
		|| expression.getTag() == SuperValue
		|| (expression.getTag() == NameRead && field != null && !field.getIsStatic()))
		throw new TyperError(filePath, expression.getPosition(), "Cannot access this or other member field in variable initialization");
	for (child in expression.getExpressions())
		rejectInstanceReceiver(child, filePath);
}
