import haxe.io.Path;
import TypedExpr.TypedExprTag;
import TypedStmt.TypedStmtTag;

/**
	Target-neutral revisions observed for one fully typed Haxe module.

	The source revision identifies the module whose input changed directly. This
	keeps a caller whose typed output changed from pretending to be the cause of
	its own invalidation. The invalidator must reach that caller through an edge.

	The public-interface revision contains the resolved class and member signatures
	that another module can consume. The implementation revision additionally
	contains the complete parsed source and every typed statement and expression,
	including inline function bodies. An explicit inline-call edge decides which
	consumers receive an implementation change; an importer that never calls the
	inline function should not be invalidated merely because the function is public.

	These are exact in-memory identities, not a persistent cache format. A future
	typed-module cache must replace the large implementation identity with a measured
	native digest while retaining enough evidence to reject collisions.
**/
class CompilerTypedModuleRevision {
	public final modulePath:String;
	public final sourceRevision:String;
	public final publicInterfaceRevision:String;
	public final implementationRevision:String;

	public function new(modulePath:String, publicInterfaceRevision:String, implementationRevision:String, ?sourceRevision:String) {
		this.modulePath = normalize(modulePath);
		this.publicInterfaceRevision = publicInterfaceRevision == null ? "" : publicInterfaceRevision;
		this.implementationRevision = implementationRevision == null ? "" : implementationRevision;
		this.sourceRevision = sourceRevision == null ? this.implementationRevision : sourceRevision;
		if (this.modulePath.length == 0)
			throw "typed module revision requires a module path";
	}

	public static function fromTypedModule(module:TypedModule, ?index:TyperIndex):CompilerTypedModuleRevision {
		if (module == null)
			throw "cannot observe a null typed module";
		final parsed = module.getParsed();
		final modulePath = semanticModulePath(module);
		final sourceRevision = CompilerCacheIdentity.encode(["typed-module-source-v1", modulePath, parsed.getSource()]);
		final publicFacts = new Array<Null<String>>();
		publicFacts.push("typed-module-public-interface-v2");
		publicFacts.push(modulePath);
		final declaration = parsed.getDecl();
		publicFacts.push(HxModuleDecl.getPackagePath(declaration));
		final imports = HxModuleDecl.getImports(declaration);
		// Resolved field/base identities below are authoritative. Retaining imports
		// as a conservative fallback also makes an unresolved or ambiguous bootstrap
		// type lookup change the public revision instead of hiding the change.
		addStrings(publicFacts, imports);
		final packagePath = HxModuleDecl.getPackagePath(declaration);
		for (typedClass in module.getTypedClasses())
			addPublicClassFacts(publicFacts, typedClass, index, packagePath, imports);
		final publicRevision = CompilerCacheIdentity.encode(publicFacts);
		final implementationFacts = new Array<Null<String>>();
		implementationFacts.push("typed-module-implementation-v2");
		implementationFacts.push(modulePath);
		implementationFacts.push(publicRevision);
		implementationFacts.push(parsed.getSource());
		for (typedClass in module.getTypedClasses()) {
			implementationFacts.push("typed-class");
			implementationFacts.push(HxClassDecl.getName(typedClass.getSourceDeclaration()));
			for (typedFunction in typedClass.getFunctions()) {
				implementationFacts.push("typed-function");
				implementationFacts.push(typedFunction.getStableIdentity());
				for (statement in typedFunction.getBody().getStatements())
					addTypedStatement(implementationFacts, statement);
			}
		}
		final implementationRevision = CompilerCacheIdentity.encode(implementationFacts);
		return new CompilerTypedModuleRevision(modulePath, publicRevision, implementationRevision, sourceRevision);
	}

	public static function semanticModulePath(module:TypedModule):String {
		for (typedClass in module.getTypedClasses()) {
			final semanticInfo = typedClass.getSemanticInfo();
			if (semanticInfo != null && normalize(semanticInfo.getModulePath()).length > 0)
				return normalize(semanticInfo.getModulePath());
		}
		final parsed = module.getParsed();
		final packagePath = normalize(HxModuleDecl.getPackagePath(parsed.getDecl()));
		final fileName = Path.withoutExtension(Path.withoutDirectory(parsed.getFilePath()));
		return packagePath.length == 0 ? fileName : packagePath + "." + fileName;
	}

	/**
		Combine every typed contribution to one Haxe source module.

		Haxe modules may declare several types. The loader can therefore present the
		same source module more than once while resolving secondary types such as
		`haxe.Function` from `haxe/Constraints.hx`. Each contribution is useful, but
		the dependency graph needs one module revision containing their sorted union.
	**/
	public static function mergeContributions(modulePath:String, contributions:Array<CompilerTypedModuleRevision>):CompilerTypedModuleRevision {
		final normalizedPath = normalize(modulePath);
		if (normalizedPath.length == 0 || contributions == null || contributions.length == 0)
			throw "typed module revision merge requires a module path and at least one contribution";
		final sourceValues = new Array<String>();
		final publicValues = new Array<String>();
		final implementationValues = new Array<String>();
		for (contribution in contributions) {
			if (contribution == null || contribution.modulePath != normalizedPath)
				throw "typed module revision merge received a contribution for a different module";
			sourceValues.push(contribution.sourceRevision);
			publicValues.push(contribution.publicInterfaceRevision);
			implementationValues.push(contribution.implementationRevision);
		}
		final uniqueSourceValues = uniqueSorted(sourceValues);
		if (uniqueSourceValues.length != 1)
			throw 'typed module revision merge received conflicting source revisions for ${normalizedPath}';
		final sourceRevision = uniqueSourceValues[0];
		final publicRevision = CompilerCacheIdentity.encode(["typed-module-public-interface-set-v1", normalizedPath].concat(uniqueSorted(publicValues)));
		final implementationRevision = CompilerCacheIdentity.encode(["typed-module-implementation-set-v1", normalizedPath].concat(uniqueSorted(implementationValues)));
		return new CompilerTypedModuleRevision(normalizedPath, publicRevision, implementationRevision, sourceRevision);
	}

	static function addPublicClassFacts(out:Array<Null<String>>, typedClass:TypedClass, index:Null<TyperIndex>, packagePath:String,
			imports:Array<String>):Void {
		final sourceClass = typedClass.getSourceDeclaration();
		final semanticInfo = typedClass.getSemanticInfo();
		out.push("class");
		out.push(HxClassDecl.getName(sourceClass));
		out.push(HxClassDecl.getIsInterface(sourceClass) ? "interface" : "class");
		addResolvedTypePath(out, "extends", HxClassDecl.getExtendsPath(sourceClass), index, packagePath, imports);
		for (implemented in HxClassDecl.getImplementsPaths(sourceClass))
			addResolvedTypePath(out, "implements", implemented, index, packagePath, imports);
		addStrings(out, HxClassDecl.getMetadata(sourceClass));

		for (field in HxClassDecl.getFields(sourceClass)) {
			if (HxFieldDecl.getVisibility(field) != HxVisibility.Public)
				continue;
			out.push("public-field");
			out.push(HxFieldDecl.getName(field));
			out.push(HxFieldDecl.getIsStatic(field) ? "static" : "instance");
			final resolvedFieldType = semanticInfo == null ? null : semanticInfo.fieldType(HxFieldDecl.getName(field));
			out.push(resolvedFieldType == null ? "unresolved:" + HxFieldDecl.getTypeHint(field) : resolvedFieldType.getSemanticKey());
			out.push(HxFieldDecl.getIsFinal(field) ? "final" : "mutable");
			out.push(HxFieldDecl.getPropertyGet(field));
			out.push(HxFieldDecl.getPropertySet(field));
			addStrings(out, HxFieldDecl.getMetadata(field));
			// Public constants and inline-like fields can be embedded by a consumer.
			// Keep the exact initializer text: the lifecycle fingerprint is only a
			// 32-bit mutation guard and is not safe as a compiler cache identity.
			out.push(HxFieldDecl.getInitText(field));
		}

		for (typedFunction in typedClass.getFunctions()) {
			final sourceFunction = typedFunction.getSourceDeclaration();
			if (HxFunctionDecl.getVisibility(sourceFunction) != HxVisibility.Public)
				continue;
			out.push("public-function");
			out.push(typedFunction.getStableIdentity());
			out.push(HxFunctionDecl.getIsStatic(sourceFunction) ? "static" : "instance");
			out.push(HxFunctionDecl.getReturnTypeHint(sourceFunction));
			addStrings(out, HxFunctionDecl.getMetadata(sourceFunction));
			final declaration = typedFunction.getDeclaration();
			if (declaration != null) {
				final signature = declaration.getSignature();
				addTypes(out, signature.getArgs());
				addBools(out, signature.getArgOptional());
				addBools(out, signature.getArgRest());
				out.push(signature.getReturnType().getSemanticKey());
				out.push(declaration.getIsInline() ? "inline" : "ordinary");
			} else {
				for (argument in HxFunctionDecl.getArgs(sourceFunction)) {
					out.push(HxFunctionArg.getName(argument));
					out.push(HxFunctionArg.getTypeHint(argument));
					out.push(HxFunctionArg.getIsOptional(argument) ? "optional" : "required");
					out.push(HxFunctionArg.getIsRest(argument) ? "rest" : "ordinary");
				}
			}
		}
	}

	static function addResolvedTypePath(out:Array<Null<String>>, label:String, sourcePath:String, index:Null<TyperIndex>, packagePath:String,
			imports:Array<String>):Void {
		out.push(label);
		final resolved = index == null ? null : index.resolveTypePath(sourcePath, packagePath, imports);
		out.push(resolved == null ? "unresolved:" + normalize(sourcePath) : resolved.getIdentity().getCanonicalName());
	}

	static function addTypes(out:Array<Null<String>>, values:Array<TyType>):Void {
		out.push(values == null ? "-1" : Std.string(values.length));
		if (values != null)
			for (value in values)
				out.push(value == null ? "unknown" : value.getSemanticKey());
	}

	static function addBools(out:Array<Null<String>>, values:Array<Bool>):Void {
		out.push(values == null ? "-1" : Std.string(values.length));
		if (values != null)
			for (value in values)
				out.push(value ? "true" : "false");
	}

	static function addTypedStatement(out:Array<Null<String>>, statement:TypedStmt):Void {
		if (statement == null) {
			out.push("null-statement");
			return;
		}
		out.push("statement:" + statementTagName(statement.getTag()));
		addStrings(out, statement.getNames());
		addStrings(out, statement.getCatchNames());
		addStrings(out, statement.getCatchTypeHints());
		addStrings(out, statement.getMetadata());
		for (pattern in statement.getPatterns())
			addPattern(out, pattern);
		for (expression in statement.getExpressions())
			addTypedExpression(out, expression);
		for (child in statement.getStatements())
			addTypedStatement(out, child);
	}

	static function addTypedExpression(out:Array<Null<String>>, expression:TypedExpr):Void {
		if (expression == null) {
			out.push("null-expression");
			return;
		}
		out.push("expression:" + expressionTagName(expression.getTag()));
		out.push(expression.getType().getSemanticKey());
		addStrings(out, expression.getTexts());
		out.push(expression.getBoolValue() ? "true" : "false");
		out.push(Std.string(expression.getIntValue()));
		out.push(Std.string(expression.getFloatValue()));
		final declaration = expression.getDeclaration();
		out.push(declaration == null ? null : declaration.getIdentity().getCanonicalKey());
		out.push(unaryOperatorName(expression.getUnaryOperator()));
		out.push(unaryFixityName(expression.getUnaryFixity()));
		out.push(opaqueKindName(expression.getOpaqueKind()));
		for (pattern in expression.getPatterns())
			addPattern(out, pattern);
		for (child in expression.getExpressions())
			addTypedExpression(out, child);
	}

	static function addPattern(out:Array<Null<String>>, pattern:HxSwitchPattern):Void {
		switch (pattern) {
			case PNull:
				out.push("pattern:null");
			case PWildcard:
				out.push("pattern:wildcard");
			case PBool(value):
				out.push(value ? "pattern:bool:true" : "pattern:bool:false");
			case PString(value):
				out.push("pattern:string");
				out.push(value);
			case PInt(value):
				out.push("pattern:int");
				out.push(Std.string(value));
			case PEnumValue(name):
				out.push("pattern:enum-value");
				out.push(name);
			case PEnumExtract(name, arguments):
				out.push("pattern:enum-extract");
				out.push(name);
				for (argument in arguments)
					addPattern(out, argument);
			case PObject(fieldNames, fieldPatterns):
				out.push("pattern:object");
				addStrings(out, fieldNames);
				for (fieldPattern in fieldPatterns)
					addPattern(out, fieldPattern);
			case PCapture(name, inner):
				out.push("pattern:capture");
				out.push(name);
				addPattern(out, inner);
			case PArray(items):
				out.push("pattern:array");
				for (item in items)
					addPattern(out, item);
			case PExtractor(extractorText, resultPattern):
				out.push("pattern:extractor");
				out.push(extractorText);
				addPattern(out, resultPattern);
			case PLengthGuard(inner, bindingName, length):
				out.push("pattern:length-guard");
				out.push(bindingName);
				out.push(Std.string(length));
				addPattern(out, inner);
			case PStartsWithGuard(inner, bindingName, prefix):
				out.push("pattern:starts-with-guard");
				out.push(bindingName);
				out.push(prefix);
				addPattern(out, inner);
			case PIntEqualsGuard(inner, bindingName, value):
				out.push("pattern:int-equals-guard");
				out.push(bindingName);
				out.push(Std.string(value));
				addPattern(out, inner);
			case PIntCompareGuard(inner, bindingName, op, value):
				out.push("pattern:int-compare-guard");
				out.push(bindingName);
				out.push(op);
				out.push(Std.string(value));
				addPattern(out, inner);
			case PParsedIntSwitchGuard(inner, bindingName, multiplier, matchValue):
				out.push("pattern:parsed-int-switch-guard");
				out.push(bindingName);
				out.push(Std.string(multiplier));
				out.push(Std.string(matchValue));
				addPattern(out, inner);
			case PUnsupportedGuard(inner):
				out.push("pattern:unsupported-guard");
				addPattern(out, inner);
			case PBind(name):
				out.push("pattern:bind");
				out.push(name);
			case POr(patterns):
				out.push("pattern:or");
				for (child in patterns)
					addPattern(out, child);
		}
	}

	static function statementTagName(tag:TypedStmtTag):String {
		return switch (tag) {
			case Block: "block";
			case Var: "var";
			case If: "if";
			case ForIn: "for-in";
			case ForKeyValue: "for-key-value";
			case While: "while";
			case DoWhile: "do-while";
			case Switch: "switch";
			case Try: "try";
			case Break: "break";
			case Continue: "continue";
			case Throw: "throw";
			case ReturnVoid: "return-void";
			case Return: "return";
			case Expression: "expression";
		};
	}

	static function expressionTagName(tag:TypedExprTag):String {
		return switch (tag) {
			case NullValue: "null";
			case BoolValue: "bool";
			case StringValue: "string";
			case IntValue: "int";
			case FloatValue: "float";
			case EnumValue: "enum";
			case ThisValue: "this";
			case SuperValue: "super";
			case LocalRead: "local-read";
			case NameRead: "name-read";
			case FieldRead: "field-read";
			case NullSafeFieldRead: "null-safe-field-read";
			case Call: "call";
			case MacroExpr: "macro-expr";
			case MacroType: "macro-type";
			case Lambda: "lambda";
			case SwitchExpr: "switch";
			case NewValue: "new";
			case Unary: "unary";
			case Binary: "binary";
			case Assign: "assign";
			case CompoundAssign: "compound-assign";
			case Ternary: "ternary";
			case Anonymous: "anonymous";
			case ArrayComprehension: "array-comprehension";
			case ArrayDecl: "array";
			case ArrayAccess: "array-access";
			case Range: "range";
			case Cast: "cast";
			case Untyped: "untyped";
			case Opaque: "opaque";
			case Block: "block";
			case Temporary: "temporary";
			case ReturnExpr: "return";
			case VariableDeclarations: "variable-declarations";
			case VariableDeclaration: "variable-declaration";
			case WhileExpr: "while";
			case BreakExpr: "break";
			case ContinueExpr: "continue";
		};
	}

	static function unaryOperatorName(unaryOperator:Null<HxUnaryOperator>):Null<String> {
		return switch (unaryOperator) {
			case null: null;
			case Increment: "increment";
			case Decrement: "decrement";
			case Negate: "negate";
			case LogicalNot: "logical-not";
			case BitwiseNot: "bitwise-not";
		};
	}

	static function unaryFixityName(fixity:Null<HxUnaryFixity>):Null<String> {
		return switch (fixity) {
			case null: null;
			case Prefix: "prefix";
			case Postfix: "postfix";
		};
	}

	static function opaqueKindName(kind:Null<TypedOpaqueExprKind>):Null<String> {
		return switch (kind) {
			case null: null;
			case TryCatch: "try-catch";
			case Switch: "switch";
			case Unsupported: "unsupported";
		};
	}

	static function addStrings(out:Array<Null<String>>, values:Array<String>):Void {
		out.push(values == null ? "-1" : Std.string(values.length));
		if (values != null)
			for (value in values)
				out.push(value);
	}

	static function uniqueSorted(values:Array<String>):Array<String> {
		final seen = new haxe.ds.StringMap<Bool>();
		for (value in values)
			seen.set(value == null ? "" : value, true);
		final out = [for (value in seen.keys()) value];
		out.sort(compareText);
		return out;
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);
}
