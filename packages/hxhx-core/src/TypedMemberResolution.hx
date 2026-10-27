/** Exact alternatives for data fields and unambiguous method selections. */
private enum MemberValue {
	DataField(field:TyFieldInfo, qualifyOwner:Bool);
	StaticMethod(declaration:TyDeclarationInfo, qualifyOwner:Bool, nonRuntimeQualifier:Bool);
	InstanceMethod(declaration:TyDeclarationInfo, implicitReceiver:Null<TyType>);
	UnresolvedAbstractField;
}

/**
	Preserve the member selected by shared typing, including imported aliases.
	Projection consumes this selection instead of repeating name lookup in a target.
 */
class TypedMemberResolution {
	final value:MemberValue;

	function new(value:MemberValue) {
		this.value = value;
	}

	/** Retain the receiver's abstract category without inventing a field or callable declaration. */
	public static function unresolvedAbstractField():TypedMemberResolution {
		return new TypedMemberResolution(UnresolvedAbstractField);
	}

	public static function field(field:TyFieldInfo, qualifyOwner:Bool):TypedMemberResolution {
		if (field == null || (qualifyOwner && !field.getIsStatic()))
			throw "member field resolution requires an exact field and a valid qualifier";
		return new TypedMemberResolution(DataField(field, qualifyOwner));
	}

	/** The typer alone can prove that an explicit abstract qualifier names a declaration rather than a value. */
	public static function method(declaration:TyDeclarationInfo, qualifyOwner:Bool, nonRuntimeQualifier:Bool = false):TypedMemberResolution {
		if (declaration == null || !declaration.getIsStatic() || declaration.getIsEnumConstructor())
			throw "member method resolution requires an exact static method";
		return new TypedMemberResolution(StaticMethod(declaration, qualifyOwner, nonRuntimeQualifier));
	}

	/**
		An abstract can own a static method without having a runtime class object.
		Use its exact selected owner before building the qualifier's module path as
		an expression. Ordinary class qualifiers and all value receivers keep their
		existing children and evaluation behavior.
	 */
	public function nonRuntimeQualifierRead(name:String, type:TyType, position:Null<HxPos>):Null<TypedExpr> {
		return switch (value) {
			case StaticMethod(declaration, _, true): TypedExpr.staticMethodRead(name, declaration, type, position, true);
			case _: null;
		};
	}

	/** Instance selections keep their value receiver; targets still decide how to bind a method value. */
	public static function instanceMethod(declaration:TyDeclarationInfo, ?implicitReceiver:TyType):TypedMemberResolution {
		if (declaration == null || declaration.getIsStatic() || declaration.getIsEnumConstructor())
			throw "instance method resolution requires an exact instance method";
		return new TypedMemberResolution(InstanceMethod(declaration, implicitReceiver));
	}

	/** Imported aliases use the selected owner; same-class reads retain their lexical form. */
	public function nameRead(name:String, type:TyType, position:Null<HxPos>):TypedExpr {
		return switch (value) {
			case UnresolvedAbstractField: throw "unresolved abstract member requires an explicit receiver";
			case DataField(field, qualify): TypedExpr.nameRead(name, type, position, field, qualify);
			case StaticMethod(declaration, qualify, _): TypedExpr.staticMethodRead(name, declaration, type, position, qualify);
			case InstanceMethod(declaration, receiver):
				if (receiver == null || receiver.isUnknown())
					throw "instance method selection requires its receiver";
				TypedExpr.instanceMethodRead(TypedExpr.thisValue(receiver, position), name, declaration, type, position);
		};
	}

	/** Retain the receiver child so value evaluation is never discarded by member projection. */
	public function fieldRead(object:TypedExpr, name:String, type:TyType, position:Null<HxPos>):TypedExpr {
		return switch (value) {
			case UnresolvedAbstractField: TypedExpr.unresolvedAbstractFieldRead(object, name, type, position);
			case DataField(field, _): TypedExpr.fieldRead(object, name, type, position, field);
			case StaticMethod(declaration, _, _): TypedExpr.staticMethodRead(name, declaration, type, position, false, object);
			case InstanceMethod(declaration, _): TypedExpr.instanceMethodRead(object, name, declaration, type, position);
		};
	}
}
