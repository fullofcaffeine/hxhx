/**
	Common semantic surface shared by classes and abstracts.

	Classes and abstracts remain distinct subclasses, while ordinary lookup can
	use their common fields and method signatures. This avoids pretending an
	abstract is a class merely to reuse bootstrap indexing code.
**/
class TyNominalInfo {
	final identity:TyNominalTypeId;
	final shortName:String;
	final modulePath:String;
	final fields:haxe.ds.StringMap<TyType>;
	final properties:haxe.ds.StringMap<TyPropertyInfo>;
	final staticMethods:haxe.ds.StringMap<TyFunSig>;
	final instanceMethods:haxe.ds.StringMap<TyFunSig>;
	final staticMethodLists:haxe.ds.StringMap<Array<TyFunSig>>;
	final instanceMethodLists:haxe.ds.StringMap<Array<TyFunSig>>;
	final declarations:Array<TyDeclarationInfo>;

	public function new(identity:TyNominalTypeId, shortName:String, modulePath:String, fields:haxe.ds.StringMap<TyType>,
			properties:haxe.ds.StringMap<TyPropertyInfo>, staticMethods:haxe.ds.StringMap<TyFunSig>, instanceMethods:haxe.ds.StringMap<TyFunSig>,
			staticMethodLists:haxe.ds.StringMap<Array<TyFunSig>>, instanceMethodLists:haxe.ds.StringMap<Array<TyFunSig>>,
			declarations:Array<TyDeclarationInfo>) {
		this.identity = identity;
		this.shortName = shortName;
		this.modulePath = modulePath;
		// Callers intentionally provide concrete empty collections. Avoiding
		// conditional generic initialization keeps the OCaml bootstrap stable.
		this.fields = fields;
		this.properties = properties;
		this.staticMethods = staticMethods;
		this.instanceMethods = instanceMethods;
		this.staticMethodLists = staticMethodLists;
		this.instanceMethodLists = instanceMethodLists;
		this.declarations = declarations;
	}

	public function getIdentity():TyNominalTypeId
		return identity;

	public function getFullName():String
		return identity.getCanonicalName();

	public function getShortName():String
		return shortName;

	public function getModulePath():String
		return modulePath;

	public function getDeclarations():Array<TyDeclarationInfo>
		return declarations;

	/** Resolve the stable declaration record that owns one indexed signature. **/
	public function declarationForSignature(signature:TyFunSig):Null<TyDeclarationInfo> {
		if (signature == null)
			return null;
		for (declaration in declarations)
			if (declaration.getSignature() == signature)
				return declaration;
		return null;
	}

	/** Associate the parser declaration with its already stable semantic record during typing. **/
	public function declarationForSource(source:HxFunctionDecl):Null<TyDeclarationInfo> {
		if (source == null)
			return null;
		for (declaration in declarations)
			if (declaration.getSourceDeclaration() == source)
				return declaration;
		return null;
	}

	public function hasField(name:String):Bool
		return fields.exists(name);

	public function fieldType(name:String):Null<TyType>
		return fields.exists(name) ? fields.get(name) : null;

	public function propertyInfo(name:String):Null<TyPropertyInfo>
		return properties.exists(name) ? properties.get(name) : null;

	public function staticMethod(name:String):Null<TyFunSig>
		return staticMethods.exists(name) ? staticMethods.get(name) : null;

	public function instanceMethod(name:String):Null<TyFunSig>
		return instanceMethods.exists(name) ? instanceMethods.get(name) : null;

	public function staticMethodCandidates(name:String):Array<TyFunSig>
		return staticMethodLists.exists(name) ? staticMethodLists.get(name) : [];

	public function instanceMethodCandidates(name:String):Array<TyFunSig>
		return instanceMethodLists.exists(name) ? instanceMethodLists.get(name) : [];
}
