package backend.cpp;

/** Program-owned calls select authored code or an explicitly bound native operation. */
enum CppManagedStaticTarget {
	Source(projection:TypedBackendFunctionProjection, symbol:String);
	Output(declaration:TyDeclarationInfo);
	RuntimePredicate(declaration:TyDeclarationInfo);
	StandardString(declaration:TyDeclarationInfo);
	Downcast(declaration:TyDeclarationInfo);
	NativeStack(declaration:TyDeclarationInfo, storage:CppManagedStaticStorage);
}

/** Derive call transport from the selected semantic declaration, never the marker's display type. */
function abi(target:CppManagedStaticTarget):CppManagedClosureAbi {
	if (target == null)
		throw "managed static call requires an exact allocated target";
	return switch target {
		case Downcast(_): throw "managed downcast transport requires its exact call application";
		case Source(projection, symbol):
			if (projection == null || symbol == null || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(symbol))
				throw "managed static call requires an exact allocated target";
			projection.requireCaptureCatalog().assertCurrent();
			if (!HxFunctionDecl.getIsStatic(projection.getDeclaration()))
				throw "managed static call cannot select an instance declaration";
			new CppManagedClosureAbi(CppManagedFunctionSignature.resolve(projection, type -> type), false);
		case Output(declaration):
			CppManagedOutput.requireDeclaration(declaration);
			final signature = declaration.getSignature();
			new CppManagedClosureAbi(TyType.functionType(signature.getArgs(), signature.getReturnType()), false);
		case RuntimePredicate(declaration):
			CppManagedRuntimePredicate.requireDeclaration(declaration);
			final signature = declaration.getSignature();
			new CppManagedClosureAbi(TyType.functionType(signature.getArgs(), signature.getReturnType()), false);
		case StandardString(declaration):
			CppManagedStandardString.requireDeclaration(declaration);
			final signature = declaration.getSignature();
			new CppManagedClosureAbi(TyType.functionType(signature.getArgs(), signature.getReturnType()), false);
		case NativeStack(declaration, storage):
			CppManagedNativeStack.requireDeclaration(declaration);
			storage.stackAccess("hxhx_heap");
			final signature = declaration.getSignature();
			new CppManagedClosureAbi(TyType.functionType(signature.getArgs(), signature.getReturnType()), false);
	};
}

/** Generic native operations validate their declaration without inventing an erased function signature. */
function validate(target:CppManagedStaticTarget):Void {
	switch target {
		case Downcast(declaration):
			CppManagedDowncast.requireDeclaration(declaration);
		case _:
			abi(target);
	}
}

/** Validate the declaration before exposing its program-local identity. */
function identity(target:CppManagedStaticTarget):String {
	validate(target);
	return switch target {
		case Source(projection, _): projection.getStableIdentity();
		case Output(declaration) | RuntimePredicate(declaration) | StandardString(declaration) | Downcast(declaration) | NativeStack(declaration,
			_): declaration.getIdentity().getCanonicalKey();
	};
}

/** Only authored functions have an allocated entry symbol. */
function sourceSymbol(target:CppManagedStaticTarget):String {
	return switch target {
		case Source(_, symbol): symbol;
		case Output(_): throw "managed output has no authored entry symbol";
		case RuntimePredicate(_): throw "managed runtime predicate has no authored entry symbol";
		case StandardString(_): throw "managed standard string has no authored entry symbol";
		case Downcast(_): throw "managed downcast has no authored entry symbol";
		case NativeStack(_, _): throw "managed stack capture has no authored entry symbol";
	};
}
