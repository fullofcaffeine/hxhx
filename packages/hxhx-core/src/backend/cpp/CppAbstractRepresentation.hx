package backend.cpp;

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

	/** Derive one direct-carrier descriptor from the already selected Haxe abstract. **/
	public static function forPrimitiveClass(cls:HxClassDecl, classLookup:CppClassLookup):Null<CppAbstractRepresentation> {
		if (cls == null)
			return null;
		final carrier = @:privateAccess CppTargetCore.primitiveAbstractUnderlyingCppType(cls);
		return carrier == null ? null : new CppAbstractRepresentation(@:privateAccess CppTargetCore.renderedClassName(cls, classLookup), carrier);
	}

	/** Rewrap an exact call result when C++ currently represents its abstract with a class wrapper. **/
	public static function classBackedCastExpression(inner:HxExpr, typeHint:String, ?scope:CppRenderScope):Null<String> {
		if (scope == null || typeHint == null || typeHint.length == 0)
			return null;
		final lookup = @:privateAccess CppTargetCore.lookupForScope(scope);
		final cls = @:privateAccess CppTargetCore.lookupClassForTypeHint(typeHint, scope, lookup);
		if (cls == null
			|| @:privateAccess CppTargetCore.abstractUnderlyingTypeHint(cls) == null
			|| @:privateAccess CppTargetCore.primitiveAbstractUnderlyingCppType(cls) != null)
			return null;
		final rendered = @:privateAccess CppTargetCore.renderExpr(inner, scope);
		return @:privateAccess CppTargetCore.classBackedAbstractWrapUnderlyingExpr(cls, rendered, scope);
	}

	/** Apply wrapper reconstruction only when the caller expects that exact represented class. **/
	public static function classBackedCastForExpectedType(expr:HxExpr, expectedType:String, ?scope:CppRenderScope):Null<String> {
		if (scope == null || expectedType == null || expectedType.length == 0)
			return null;
		return switch (expr) {
			case ECast(inner, typeHint):
				final lookup = @:privateAccess CppTargetCore.lookupForScope(scope);
				final cls = @:privateAccess CppTargetCore.lookupClassForTypeHint(typeHint, scope, lookup);
				final expectedClass = @:privateAccess CppTargetCore.classNameFromCppType(expectedType);
				if (cls == null || expectedClass == null || @:privateAccess CppTargetCore.renderedClassName(cls,
					lookup) != @:privateAccess CppTargetCore.sanitizeTypePath(@:privateAccess CppTargetCore.typeBaseName(expectedClass))) {
					null;
				} else {
					classBackedCastExpression(inner, typeHint, scope);
				}
			case _:
				null;
		};
	}
}
