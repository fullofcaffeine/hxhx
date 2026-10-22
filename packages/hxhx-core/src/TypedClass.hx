/**
	A source class/abstract declaration paired with its resolved header, typed
	functions, and field initializers.
	The field inventory belongs to this revision. An emission copy can remove fields
	while preserving the original source declaration for diagnostics and ownership.

	The resolved header keeps the exact parent and interfaces selected during
	typing. This matters when the source uses a local import alias: target
	projection must receive the provider type, not repeat Haxe name lookup from a
	name that only existed in the source module.
**/
class TypedClass {
	final sourceDeclaration:HxClassDecl;
	final semanticInfo:Null<TyNominalInfo>;
	final resolvedExtends:Null<TyType>;
	final resolvedImplements:Array<TyType>;
	final resolvedInterfaceExtends:Array<TyType>;
	final functions:Array<TypedFunction>;
	final fieldInitializers:Array<TypedFieldInitializer>;
	final fields:Array<HxFieldDecl>;
	final declaredFieldTypes:Null<TypedDeclaredFieldTypes>;

	public function new(sourceDeclaration:HxClassDecl, semanticInfo:Null<TyNominalInfo>, functions:Array<TypedFunction>,
			?fieldInitializers:Array<TypedFieldInitializer>, ?resolvedExtends:TyType, ?resolvedImplements:Array<TyType>,
			?resolvedInterfaceExtends:Array<TyType>, ?fields:Array<HxFieldDecl>, ?declaredFieldTypes:TypedDeclaredFieldTypes) {
		this.declaredFieldTypes = declaredFieldTypes;
		if (declaredFieldTypes != null)
			declaredFieldTypes.assertOwner(semanticInfo);
		this.sourceDeclaration = sourceDeclaration;
		this.semanticInfo = semanticInfo;
		this.resolvedExtends = resolvedExtends;
		this.resolvedImplements = resolvedImplements == null ? [] : resolvedImplements.copy();
		this.resolvedInterfaceExtends = resolvedInterfaceExtends == null ? [] : resolvedInterfaceExtends.copy();
		this.functions = functions == null ? [] : functions.copy();
		this.fieldInitializers = fieldInitializers == null ? [] : fieldInitializers.copy();
		this.fields = (fields == null ? HxClassDecl.getFields(sourceDeclaration) : fields).copy();
		final sourceFields = HxClassDecl.getFields(sourceDeclaration);
		final seen = new haxe.ds.ObjectMap<HxFieldDecl, Bool>();
		for (field in this.fields) {
			if (sourceFields.indexOf(field) < 0 || seen.exists(field))
				throw "typed class requires distinct owned field declarations";
			seen.set(field, true);
		}
		for (initializer in this.fieldInitializers) {
			var found = false;
			for (field in this.fields)
				if (semanticInfo != null && semanticInfo.fieldInfo(HxFieldDecl.getName(field)) == initializer.getField())
					found = true;
			if (!found)
				throw "typed initializer requires a retained field declaration";
		}
	}

	public function getSourceDeclaration():HxClassDecl
		return sourceDeclaration;

	public function getDeclaredFieldTypes():Null<TypedDeclaredFieldTypes>
		return declaredFieldTypes;

	public function getSemanticInfo():Null<TyNominalInfo>
		return semanticInfo;

	public function getResolvedExtends():Null<TyType>
		return resolvedExtends;

	public function getResolvedImplements():Array<TyType>
		return resolvedImplements.copy();

	/** Exact parents of an interface, kept separate from the class parent. */
	public function getResolvedInterfaceExtends():Array<TyType>
		return resolvedInterfaceExtends.copy();

	public function getFunctions():Array<TypedFunction>
		return functions.copy();

	public function getFieldInitializers():Array<TypedFieldInitializer>
		return fieldInitializers.copy();

	/** Fields present in this revision; emission copies can omit unused source fields. */
	public function getFields():Array<HxFieldDecl>
		return fields.copy();

	/** Keep source ownership and resolved headers while replacing the executable member inventory. */
	public function withMembers(members:{functions:Array<TypedFunction>, fields:Array<HxFieldDecl>, initializers:Array<TypedFieldInitializer>}):TypedClass
		return new TypedClass(sourceDeclaration, semanticInfo, members.functions, members.initializers, resolvedExtends, resolvedImplements,
			resolvedInterfaceExtends, members.fields, declaredFieldTypes);

	/** Return the same source/semantic class paired with rewritten typed functions. **/
	public function withFunctions(loweredFunctions:Array<TypedFunction>):TypedClass
		return new TypedClass(sourceDeclaration, semanticInfo, loweredFunctions, fieldInitializers, resolvedExtends, resolvedImplements,
			resolvedInterfaceExtends, fields, declaredFieldTypes);
}
