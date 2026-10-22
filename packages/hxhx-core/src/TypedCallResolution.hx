/**
	Records the exact declaration and shared typed-tree adjustments for one call.

	For example, `import model.Api.twice as double; double(2)` selects `Api.twice`
	and requires owner qualification when the typed body is projected. An ordinary
	bare call to a method on the current class keeps its original source shape.
	An aligned argument conversion records a proven representation cast without
	requiring each target backend to infer it again.
**/
class TypedCallResolution {
	final declaration:Null<TyDeclarationInfo>;
	final requiresOwnerQualification:Bool;
	final extensionProvider:Null<TyNominalTypeId>;
	final argumentConversions:Array<Null<TyImplicitConversionPlan>>;
	final expectedArguments:Array<TyType>;
	final namedArguments:Null<TypedNamedCallPlan>;
	final targetScope:Null<HxTargetScopeKind>;

	public function new(?declaration:TyDeclarationInfo, requiresOwnerQualification:Bool = false, ?extensionProvider:TyNominalTypeId,
			?argumentConversions:Array<Null<TyImplicitConversionPlan>>, ?expectedArguments:Array<TyType>, ?namedArguments:TypedNamedCallPlan,
			?targetScope:HxTargetScopeKind) {
		this.declaration = declaration;
		this.requiresOwnerQualification = requiresOwnerQualification;
		this.extensionProvider = extensionProvider;
		this.argumentConversions = argumentConversions == null ? [] : argumentConversions.copy();
		this.expectedArguments = expectedArguments == null ? [] : expectedArguments.copy();
		this.namedArguments = namedArguments;
		this.targetScope = targetScope;
		if (targetScope != null && (TypedTargetScope.select(declaration, true) != targetScope || namedArguments != null))
			throw "native syntax scope cannot carry an ordinary call plan";
		if (this.expectedArguments.length > 0 && declaration == null)
			throw "call argument contexts require an exact declaration";
		if (requiresOwnerQualification && declaration == null)
			throw "owner-qualified call resolution requires an exact declaration";
		if (extensionProvider != null && (declaration == null || !declaration.getIsStatic()))
			throw "extension call resolution requires an exact static declaration";
		if (this.argumentConversions.length > 0 && declaration == null)
			throw "call argument conversions require an exact declaration";
	}

	public function getDeclaration():Null<TyDeclarationInfo>
		return declaration;

	public function getRequiresOwnerQualification():Bool
		return requiresOwnerQualification;

	/** Type named by the winning `using` directive, when this is an extension call. **/
	public function getExtensionProvider():Null<TyNominalTypeId>
		return extensionProvider;

	/** Shared conversions aligned with the explicit source arguments. **/
	public function getArgumentConversions():Array<Null<TyImplicitConversionPlan>>
		return argumentConversions.copy();

	/** Selected parameter types aligned with explicit source arguments, after method-generic binding. */
	public function getExpectedArguments():Array<TyType>
		return expectedArguments.copy();

	public function getNamedArguments():Null<TypedNamedCallPlan>
		return namedArguments;

	public function getTargetScope():Null<HxTargetScopeKind>
		return targetScope;
}
