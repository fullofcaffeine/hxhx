package backend.cpp;

typedef CppAbstractRepresentationServices = {
	var primitiveUnderlying:HxClassDecl->Null<String>;
	var renderedClassName:HxClassDecl->CppClassLookup->String;
	var lookupForScope:CppRenderScope->CppClassLookup;
	var lookupClassForTypeHint:String->CppRenderScope->CppClassLookup->Null<HxClassDecl>;
	var abstractUnderlying:HxClassDecl->Null<String>;
	var renderExpression:HxExpr->CppRenderScope->String;
	var wrapUnderlying:HxClassDecl->String->CppRenderScope->String;
	var classNameFromCppType:String->Null<String>;
	var sanitizeTypePath:String->String;
	var typeBaseName:String->String;
};

/**
	C++ representation contract for one direct-carrier Haxe abstract.

	Semantic operator selection has already happened in the shared typer. This
	descriptor only records how C++ names the erased carrier and invokes an exact
	instance-semantic helper through a generated static ABI. The wrapper/direct
	choice is therefore downstream of binding and can evolve without changing
	which declaration was selected.
**/
class CppAbstractRepresentation {
	public static inline final ERASED_THIS_NAME = "__hxhx_abstract_this";

	final ownerCppName:String;
	final carrierCppType:String;

	public function new(ownerCppName:String, carrierCppType:String) {
		this.ownerCppName = ownerCppName;
		this.carrierCppType = carrierCppType;
	}

	public function getOwnerCppName():String
		return ownerCppName;

	public function getCarrierCppType():String
		return carrierCppType;

	public function usesDirectUnderlyingCarrier():Bool
		return true;

	public function helperReceiverParameter():String
		return carrierCppType + " " + ERASED_THIS_NAME;

	public function instanceHelperCall(methodName:String, renderedReceiver:String, renderedArguments:Array<String>):String {
		final arguments = [renderedReceiver].concat(renderedArguments == null ? [] : renderedArguments);
		return ownerCppName + "::" + methodName + "(" + arguments.join(", ") + ")";
	}

	public static function forPrimitiveClass(cls:HxClassDecl, classLookup:CppClassLookup,
			services:CppAbstractRepresentationServices):Null<CppAbstractRepresentation> {
		if (cls == null)
			return null;
		final carrier = services.primitiveUnderlying(cls);
		return carrier == null ? null : new CppAbstractRepresentation(services.renderedClassName(cls, classLookup), carrier);
	}

	/** Rewrap an exact call result when C++ currently represents its abstract with a class wrapper. **/
	public static function classBackedCastExpression(inner:HxExpr, typeHint:String, scope:CppRenderScope,
			services:CppAbstractRepresentationServices):Null<String> {
		if (scope == null || typeHint == null || typeHint.length == 0)
			return null;
		final lookup = services.lookupForScope(scope);
		final cls = services.lookupClassForTypeHint(typeHint, scope, lookup);
		if (cls == null || services.abstractUnderlying(cls) == null || services.primitiveUnderlying(cls) != null)
			return null;
		return services.wrapUnderlying(cls, services.renderExpression(inner, scope), scope);
	}

	/** Apply wrapper reconstruction only when the caller expects that exact represented class. **/
	public static function classBackedCastForExpectedType(expr:HxExpr, expectedType:String, scope:CppRenderScope,
			services:CppAbstractRepresentationServices):Null<String> {
		if (scope == null || expectedType == null || expectedType.length == 0)
			return null;
		return switch (expr) {
			case ECast(inner, typeHint):
				final lookup = services.lookupForScope(scope);
				final cls = services.lookupClassForTypeHint(typeHint, scope, lookup);
				final expectedClass = services.classNameFromCppType(expectedType);
				if (cls == null
					|| expectedClass == null
					|| services.renderedClassName(cls, lookup) != services.sanitizeTypePath(services.typeBaseName(expectedClass))) {
					null;
				} else {
					classBackedCastExpression(inner, typeHint, scope, services);
				}
			case _:
				null;
		};
	}

	/** Build the temporary wrapper expression from representation facts supplied by C++. **/
	public static function wrapClassBackedValue(className:String, underlyingClass:String, argumentNames:Array<String>, valueExpression:String):String {
		if (underlyingClass.length == 0 || argumentNames.length == 0)
			return valueExpression;
		final temporary = "__hxhx_" + className + "_underlying";
		return "([&]() { auto "
			+ temporary
			+ " = "
			+ valueExpression
			+ "; return std::make_shared<"
			+ className
			+ ">("
			+ [for (argument in argumentNames) temporary + "->" + argument].join(", ") + "); })()";
	}
}
