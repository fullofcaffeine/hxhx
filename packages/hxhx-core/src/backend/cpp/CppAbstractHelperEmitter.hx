package backend.cpp;

typedef CppAbstractInstanceHelperServices = {
	var representation:HxClassDecl->CppClassLookup->Null<CppAbstractRepresentation>;
	var returnType:HxFunctionDecl->HxClassDecl->CppClassLookup->String;
	var renderScope:HxClassDecl->CppClassLookup->String->CppRenderScope;
	var prepareScope:CppRenderScope->HxFunctionDecl->Void;
	var renderArguments:Array<HxFunctionArg>->CppRenderScope->String;
	var renderBody:Array<HxStmt>->String->CppRenderScope->Array<String>;
	var sanitizeIdentifier:String->String;
};

typedef CppAbstractMethodCallServices = {
	var primitiveIntLike:HxExpr->String->CppRenderScope->Null<String>;
	var classForExpression:HxExpr->CppRenderScope->Null<HxClassDecl>;
	var classForReceiverMethod:HxExpr->String->CppRenderScope->Null<HxClassDecl>;
	var classMethod:String->String->Bool->CppRenderScope->Null<HxFunctionDecl>;
	var primitiveUnderlying:HxClassDecl->Null<String>;
	var hasMetadata:HxFunctionDecl->String->Bool;
	var representation:HxClassDecl->CppClassLookup->Null<CppAbstractRepresentation>;
	var lookupForScope:CppRenderScope->CppClassLookup;
	var valueForExpectedType:HxExpr->String->CppRenderScope->String;
	var inferredArgumentTypes:HxFunctionDecl->HxClassDecl->CppRenderScope->Array<String>;
	var renderCallArguments:Array<HxFunctionArg>->Array<HxExpr>->CppRenderScope->Array<String>->Array<String>;
	var inlineBody:HxExpr->HxFunctionDecl->CppRenderScope->Null<String>;
	var sanitizeIdentifier:String->String;
	var sanitizeTypePath:String->String;
};

/**
	Emits callable helpers for direct-carrier abstracts after shared binding.

	This module owns the synthetic receiver ABI. It does not inspect `@:op`, rank
	candidates, or infer mutation. The legacy ordinary-method entry points at the
	bottom remain quarantined here until the carrier-cleanup bead removes their
	method-name and tiny-body recognizers; resolved abstract unary operators do not
	use those paths.
**/
class CppAbstractHelperEmitter {
	/** Configure a render scope for the synthetic erased receiver. **/
	public static function configureReceiver(scope:CppRenderScope, representation:CppAbstractRepresentation, ownerHaxeName:String):Void {
		scope.erasedAbstractThisName = CppAbstractRepresentation.ERASED_THIS_NAME;
		scope.localTypes.set(CppAbstractRepresentation.ERASED_THIS_NAME, representation.getCarrierCppType());
		scope.localTypeHints.set(CppAbstractRepresentation.ERASED_THIS_NAME, ownerHaxeName);
		scope.localNames.set(CppAbstractRepresentation.ERASED_THIS_NAME, CppAbstractRepresentation.ERASED_THIS_NAME);
		scope.localNameCounts.set(CppAbstractRepresentation.ERASED_THIS_NAME, 1);
	}

	/** Emit one prepared non-inline instance method with its erased receiver explicit. **/
	public static function renderInstanceHelper(representation:CppAbstractRepresentation, returnType:String, helperName:String, sourceParameters:String,
			bodyLines:Array<String>):Array<String> {
		final parameters = [representation.helperReceiverParameter()];
		if (sourceParameters.length > 0)
			parameters.push(sourceParameters);
		final out = [
			"  static " + returnType + " " + helperName + "(" + parameters.join(", ") + ") {"
		];
		for (line in bodyLines)
			out.push(line);
		out.push("  }");
		return out;
	}

	/** Prepare and emit one non-inline instance helper through supplied target services. **/
	public static function renderPreparedInstanceHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup,
			services:CppAbstractInstanceHelperServices):Array<String> {
		final representation = services.representation(owner, classLookup);
		if (representation == null)
			return [];
		final returnType = services.returnType(fn, owner, classLookup);
		final scope = services.renderScope(owner, classLookup, returnType);
		configureReceiver(scope, representation, HxClassDecl.getName(owner));
		services.prepareScope(scope, fn);
		final parameters = services.renderArguments(HxFunctionDecl.getArgs(fn), scope);
		final body = services.renderBody(HxFunctionDecl.getBody(fn), "    ", scope);
		return renderInstanceHelper(representation, returnType, services.sanitizeIdentifier(HxFunctionDecl.getName(fn)), parameters, body);
	}

	/** Render a legacy primitive-abstract ordinary method against its direct carrier. **/
	public static function renderMethodCall(receiver:HxExpr, method:String, args:Array<HxExpr>, scope:CppRenderScope,
			services:CppAbstractMethodCallServices):Null<String> {
		final intLikeFloat = method == "toFloat" ? services.primitiveIntLike(receiver, method, scope) : null;
		if (intLikeFloat != null)
			return intLikeFloat;
		var cls = services.classForExpression(receiver, scope);
		if (cls == null)
			cls = services.classForReceiverMethod(receiver, method, scope);
		if (cls == null)
			return services.primitiveIntLike(receiver, method, scope);
		final fn = services.classMethod(services.sanitizeTypePath(HxClassDecl.getName(cls)), method, false, scope);
		if (fn == null)
			return null;
		final underlying = services.primitiveUnderlying(cls);
		if (underlying == null || underlying.length == 0)
			return null;
		if (!services.hasMetadata(fn, "inline")) {
			final representation = services.representation(cls, services.lookupForScope(scope));
			if (representation == null)
				return null;
			final renderedReceiver = services.valueForExpectedType(receiver, representation.getCarrierCppType(), scope);
			final parameterTypes = services.inferredArgumentTypes(fn, cls, scope);
			final renderedArguments = services.renderCallArguments(HxFunctionDecl.getArgs(fn), args, scope, parameterTypes);
			return representation.instanceHelperCall(services.sanitizeIdentifier(method), renderedReceiver, renderedArguments);
		}
		if (args.length != 0)
			return null;
		return services.inlineBody(receiver, fn, scope);
	}

	/**
		Render the frozen legacy inline-method subset against a pre-rendered carrier.

		Shared abstract-operator lowering must never enter this compatibility path.
	**/
	public static function renderInlineMethodBody(receiver:String, fn:HxFunctionDecl, renderExpression:HxExpr->String):Null<String> {
		return switch (HxFunctionDecl.getBody(fn)) {
			case [SReturn(EThis, _)]:
				receiver;
			case [SReturn(ECast(EThis, _), _)]:
				receiver;
			case [SReturn(EBinop(op, EThis, right), _)] if (isInlineBinaryOperator(op)):
				"("
				+ receiver
				+ " "
				+ op
				+ " "
				+ renderExpression(right)
				+ ")";
			case [SExpr(EUnop(op, fixity, EThis), _)] if (op == HxUnaryOperator.Increment || op == HxUnaryOperator.Decrement):
				final token = HxUnaryOperatorTools.sourceToken(op);
				fixity == HxUnaryFixity.Postfix ? "("
					+ receiver
					+ token
					+ ")" : "("
					+ token
					+ receiver
					+ ")";
			case [SExpr(EBinop("+=", EThis, right), _)]:
				receiver + " += " + renderExpression(right);
			case [SExpr(EBinop("-=", EThis, right), _)]:
				receiver + " -= " + renderExpression(right);
			case _:
				null;
		};
	}

	static function isInlineBinaryOperator(op:String):Bool {
		return switch (op) {
			case "+" | "-" | "*" | "/" | "%": true;
			case _: false;
		};
	}

	/** Render the frozen primitive method-name compatibility cases pending carrier cleanup. **/
	public static function renderPrimitiveIntLike(method:String, receiverIsIntLike:Bool, receiver:String):Null<String> {
		if (!receiverIsIntLike)
			return null;
		return switch (method) {
			case "toInt": receiver;
			case "toFloat": "static_cast<double>(" + receiver + ")";
			case "incr": "(" + receiver + "++)";
			case _: null;
		};
	}
}
