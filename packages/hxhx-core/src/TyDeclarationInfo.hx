/**
	Shared semantic record for a function declaration, including bodyless native
	or extern operator helpers.

	This record keeps the exact declaration identity, resolved signature,
	metadata, position, and parsed source declaration together. The parsed node
	is provenance/body input for later shared typing; it is not a backend binding
	key.
**/
class TyDeclarationInfo {
	final identity:TyDeclarationId;
	final owner:TyNominalTypeId;
	final signature:TyFunSig;
	final metadata:Array<String>;
	final sourceDeclaration:HxFunctionDecl;
	final position:HxPos;
	final isInline:Bool;
	final isPublic:Bool;
	final modulePath:String;
	final isEnumConstructor:Bool;
	final typeParameters:Array<TyTypeParameterId>;

	public function new(identity:TyDeclarationId, owner:TyNominalTypeId, signature:TyFunSig, metadata:Array<String>, sourceDeclaration:HxFunctionDecl,
			position:HxPos, isInline:Bool, isPublic:Bool, modulePath:String, isEnumConstructor:Bool = false, ?typeParameters:Array<TyTypeParameterId>) {
		this.identity = identity;
		this.owner = owner;
		this.signature = signature;
		this.metadata = metadata == null ? [] : metadata.copy();
		this.sourceDeclaration = sourceDeclaration;
		this.position = position == null ? HxPos.unknown() : position;
		this.isInline = isInline;
		this.isPublic = isPublic;
		this.modulePath = modulePath == null ? "" : StringTools.trim(modulePath);
		this.isEnumConstructor = isEnumConstructor;
		this.typeParameters = typeParameters == null ? [] : typeParameters.copy();
		if (this.modulePath.length == 0)
			throw "typed declaration information requires a module identity";
		if (isEnumConstructor && !signature.getIsStatic())
			throw "typed enum constructor declaration must be static";
	}

	public function getIdentity():TyDeclarationId
		return identity;

	public function getOwner():TyNominalTypeId
		return owner;

	public function getSignature():TyFunSig
		return signature;

	public function getMetadata():Array<String>
		return metadata;

	public function getSourceDeclaration():HxFunctionDecl
		return sourceDeclaration;

	public function getPosition():HxPos
		return position;

	public function getIsStatic():Bool
		return signature.getIsStatic();

	public function getIsInline():Bool
		return isInline;

	/** Whether Haxe permits the method implementation to be replaced per instance. **/
	public function getIsDynamic():Bool {
		for (entry in metadata) {
			var clean = entry == null ? "" : StringTools.trim(entry);
			while (StringTools.startsWith(clean, "@") || StringTools.startsWith(clean, ":"))
				clean = clean.substr(1);
			if (clean == "dynamic")
				return true;
		}
		return false;
	}

	/** Whether code in another module may name this declaration. **/
	public function getIsPublic():Bool
		return isPublic;

	/** Haxe module that owns the declaration, distinct from a secondary type's canonical path. **/
	public function getModulePath():String
		return modulePath;

	/** Whether this exact static declaration constructs a value of its owning enum. **/
	public function getIsEnumConstructor():Bool
		return isEnumConstructor;

	/** Whether `import Owner.*` must withhold this method from bare-name lookup. **/
	public function getNoImportGlobal():Bool {
		for (entry in metadata) {
			var clean = entry == null ? "" : StringTools.trim(entry);
			while (StringTools.startsWith(clean, "@") || StringTools.startsWith(clean, ":"))
				clean = clean.substr(1);
			if (clean == "noImportGlobal")
				return true;
		}
		return false;
	}

	/** Whether the declaration supplies Haxe code instead of target-native `;` behavior. */
	public function getHasBody():Bool
		return HxFunctionDecl.getHasBody(sourceDeclaration);

	/** Method-level generic parameters retained for overload diagnostics/binding. **/
	public function getTypeParameters():Array<String>
		return [for (parameter in typeParameters) parameter.getName()];

	/** Exact method-level generic binder identities in declared order. **/
	public function getTypeParameterIds():Array<TyTypeParameterId>
		return typeParameters.copy();

	/** Source-level method type-parameter constraints retained by the shared parser bridge. **/
	public function getTypeParameterConstraints():haxe.ds.StringMap<String>
		return HxFunctionTypeParamMetadata.constraints(metadata);
}
