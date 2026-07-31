import TypedExpr.TypedExprTag;

/**
	Collects module dependency facts from the sealed target-neutral typed program.

	Exact call nodes already retain the declaration chosen by typing, and semantic
	types already retain canonical nominal identities. This collector walks those
	facts after shared typing. Several typed contributions from secondary types in
	one Haxe source module are merged before the graph is sealed. The collector does
	not inspect generated target code and does not decide whether a typed module may
	be reused.
**/
class CompilerDependencyCollector {
	public static function collect(modules:Array<TypedModule>, index:TyperIndex, ?programConfiguration:CompilerProgramConfigurationObservation,
			?macroFileDependencies:haxe.ds.StringMap<CompilerMacroFileDependencyObservation>):CompilerDependencySnapshot {
		final contributionsByModule = new haxe.ds.StringMap<Array<CompilerTypedModuleRevision>>();
		final edgeByKey = new haxe.ds.StringMap<CompilerDependencyEdge>();
		final observedModules = new haxe.ds.StringMap<Bool>();
		if (modules != null) {
			for (module in modules) {
				if (module == null)
					continue;
				final semanticModulePath = CompilerTypedModuleRevision.semanticModulePath(module);
				final contribution = CompilerTypedModuleRevision.fromTypedModule(module,
					macroFileDependencies == null ? null : macroFileDependencies.get(semanticModulePath));
				observedModules.set(contribution.modulePath, true);
				final existing = contributionsByModule.get(contribution.modulePath);
				if (existing == null)
					contributionsByModule.set(contribution.modulePath, [contribution]);
				else
					existing.push(contribution);
				collectModuleEdges(module, contribution.modulePath, index, edgeByKey);
			}
		}
		if (macroFileDependencies != null)
			for (modulePath in macroFileDependencies.keys())
				if (!observedModules.exists(modulePath))
					throw "macro file dependency registration names a module outside the typed program: " + modulePath;
		final modulePaths = [for (modulePath in contributionsByModule.keys()) modulePath];
		modulePaths.sort(compareText);
		final revisions = [
			for (modulePath in modulePaths)
				CompilerTypedModuleRevision.mergeContributions(modulePath, contributionsByModule.get(modulePath))
		];
		final edges = new Array<CompilerDependencyEdge>();
		for (edge in edgeByKey)
			edges.push(edge);
		return new CompilerDependencySnapshot(revisions, edges, programConfiguration);
	}

	static function collectModuleEdges(module:TypedModule, consumerModule:String, index:TyperIndex, edgeByKey:haxe.ds.StringMap<CompilerDependencyEdge>):Void {
		for (directive in module.getEnv().getResolvedDirectives()) {
			for (providerIdentity in directive.getProviders()) {
				final provider = index == null ? null : index.getByFullName(providerIdentity.getCanonicalName());
				if (provider != null)
					addEdge(edgeByKey, consumerModule, provider.getModulePath(), CompilerDependencyPhase.ModuleResolution,
						CompilerDependencyKind.ModuleResolution, directive.canonicalIdentity());
			}
		}

		for (typedClass in module.getTypedClasses()) {
			collectResolvedHeaderType(edgeByKey, consumerModule, index, typedClass.getResolvedExtends(), "extends");
			for (implemented in typedClass.getResolvedImplements())
				collectResolvedHeaderType(edgeByKey, consumerModule, index, implemented, "implements");
			final semanticInfo = typedClass.getSemanticInfo();
			if (semanticInfo != null)
				for (declaration in semanticInfo.getDeclarations()) {
					for (argument in declaration.getSignature().getArgs())
						collectType(edgeByKey, consumerModule, index, argument, "signature:" + declaration.getIdentity().getCanonicalKey());
					collectType(edgeByKey, consumerModule, index, declaration.getSignature().getReturnType(),
						"signature:" + declaration.getIdentity().getCanonicalKey());
				}
			for (fieldInitializer in typedClass.getFieldInitializers()) {
				final field = fieldInitializer.getField();
				collectExpression(edgeByKey, consumerModule, index, semanticInfo, fieldInitializer.getExpression(), field.getIsStatic() ? field : null);
			}
			for (typedFunction in typedClass.getFunctions())
				for (statement in typedFunction.getBody().getStatements())
					collectStatement(edgeByKey, consumerModule, index, semanticInfo, statement);
		}
	}

	static function collectStatement(edgeByKey:haxe.ds.StringMap<CompilerDependencyEdge>, consumerModule:String, index:TyperIndex,
			currentOwner:Null<TyNominalInfo>, statement:TypedStmt, ?staticInitializer:TyFieldInfo):Void {
		if (statement == null)
			return;
		for (expression in statement.getExpressions())
			collectExpression(edgeByKey, consumerModule, index, currentOwner, expression, staticInitializer);
		for (child in statement.getStatements())
			collectStatement(edgeByKey, consumerModule, index, currentOwner, child, staticInitializer);
	}

	static function collectExpression(edgeByKey:haxe.ds.StringMap<CompilerDependencyEdge>, consumerModule:String, index:TyperIndex,
			currentOwner:Null<TyNominalInfo>, expression:TypedExpr, ?staticInitializer:TyFieldInfo):Void {
		if (expression == null)
			return;
		collectType(edgeByKey, consumerModule, index, expression.getType(), "expression-type", staticInitializer);
		collectConstantRead(edgeByKey, consumerModule, index, currentOwner, expression);
		final field = resolvedFieldRead(index, currentOwner, expression);
		if (field != null)
			addStaticInitializationEdge(edgeByKey, consumerModule, staticInitializer, field.getModulePath(), "field:" + field.getCanonicalKey());
		final declaration = expression.getDeclaration();
		if (declaration != null) {
			final provider = index == null ? null : index.getByFullName(declaration.getOwner().getCanonicalName());
			if (provider != null) {
				final kind = declaration.getIsInline() ? CompilerDependencyKind.InlineImplementation : CompilerDependencyKind.PublicInterface;
				addEdge(edgeByKey, consumerModule, provider.getModulePath(), CompilerDependencyPhase.SharedTyping, kind,
					"declaration:" + declaration.getIdentity().getCanonicalKey());
				addStaticInitializationEdge(edgeByKey, consumerModule, staticInitializer, provider.getModulePath(),
					"declaration:" + declaration.getIdentity().getCanonicalKey());
			}
		}
		for (child in expression.getExpressions())
			collectExpression(edgeByKey, consumerModule, index, currentOwner, child, staticInitializer);
	}

	/** Record only fields whose resolved declaration says callers may embed the initializer value. **/
	static function collectConstantRead(edgeByKey:haxe.ds.StringMap<CompilerDependencyEdge>, consumerModule:String, index:TyperIndex,
			currentOwner:Null<TyNominalInfo>, expression:TypedExpr):Void {
		final field = resolvedFieldRead(index, currentOwner, expression);
		if (field != null && field.canEmbedCrossModuleValue())
			addEdge(edgeByKey, consumerModule, field.getModulePath(), CompilerDependencyPhase.SharedTyping, CompilerDependencyKind.ConstantValue,
				"field:" + field.getCanonicalKey());
	}

	/** Return the exact field selected by typing for a field-read expression. **/
	static function resolvedFieldRead(index:TyperIndex, currentOwner:Null<TyNominalInfo>, expression:TypedExpr):Null<TyFieldInfo> {
		final selectedField = expression.getFieldInfo();
		if (selectedField != null)
			return selectedField;
		final texts = expression.getTexts();
		return switch (expression.getTag()) {
			case NameRead: texts.length == 0 || currentOwner == null ? null : currentOwner.fieldInfo(texts[0]);
			case FieldRead:
				final children = expression.getExpressions();
				if (texts.length == 0 || children.length == 0 || index == null) {
					null;
				} else {
					final receiverIdentity = children[0].getType().getNominalIdentity();
					final owner = receiverIdentity == null ? null : index.getByFullName(receiverIdentity.getCanonicalName());
					owner == null ? null : owner.fieldInfo(texts[0]);
				}
			case NullValue:
				null;
			case BoolValue:
				null;
			case StringValue:
				null;
			case IntValue:
				null;
			case FloatValue:
				null;
			case EnumValue:
				null;
			case ThisValue:
				null;
			case SuperValue:
				null;
			case LocalRead:
				null;
			case NullSafeFieldRead:
				null;
			case Call:
				null;
			case MacroExpr:
				null;
			case MacroType:
				null;
			case Lambda:
				null;
			case SwitchExpr:
				null;
			case NewValue:
				null;
			case Unary:
				null;
			case Binary:
				null;
			case Assign:
				null;
			case CompoundAssign:
				null;
			case Ternary:
				null;
			case Anonymous:
				null;
			case ArrayComprehension:
				null;
			case ArrayDecl:
				null;
			case ArrayAccess:
				null;
			case Range:
				null;
			case Cast:
				null;
			case Untyped:
				null;
			case Opaque:
				null;
			case Block:
				null;
			case Temporary:
				null;
			case ReturnExpr:
				null;
			case VariableDeclarations:
				null;
			case VariableDeclaration:
				null;
			case WhileExpr:
				null;
			case BreakExpr:
				null;
			case ContinueExpr:
				null;
		};
	}

	static function collectType(edgeByKey:haxe.ds.StringMap<CompilerDependencyEdge>, consumerModule:String, index:TyperIndex, type:TyType,
			factIdentity:String, ?staticInitializer:TyFieldInfo):Void {
		if (type == null)
			return;
		final identity = type.getNominalIdentity();
		if (identity != null) {
			final provider = index == null ? null : index.getByFullName(identity.getCanonicalName());
			if (provider != null) {
				addEdge(edgeByKey, consumerModule, provider.getModulePath(), CompilerDependencyPhase.SharedTyping, CompilerDependencyKind.PublicInterface,
					factIdentity + ":" + identity.getCanonicalName());
				addStaticInitializationEdge(edgeByKey, consumerModule, staticInitializer, provider.getModulePath(), "type:" + identity.getCanonicalName());
			}
		}
		for (argument in type.getTypeArguments())
			collectType(edgeByKey, consumerModule, index, argument, factIdentity, staticInitializer);
		if (type.isNullable())
			collectType(edgeByKey, consumerModule, index, type.getNullableInner(), factIdentity, staticInitializer);
		if (type.isFunction()) {
			for (argument in type.getFunctionArguments())
				collectType(edgeByKey, consumerModule, index, argument, factIdentity, staticInitializer);
			collectType(edgeByKey, consumerModule, index, type.getFunctionReturn(), factIdentity, staticInitializer);
		}
	}

	/**
		Record one cross-module fact consumed while initializing a static field.

		The ordinary edge still records whether the fact was a type, call, inline
		body, or constant. This additional edge says that the same fact participates
		in program initialization, where provider implementation changes can affect
		order or runtime behavior even when the public signature stays stable.
	**/
	static function addStaticInitializationEdge(edgeByKey:haxe.ds.StringMap<CompilerDependencyEdge>, consumerModule:String,
			staticInitializer:Null<TyFieldInfo>, providerModule:String, consumedFact:String):Void {
		if (staticInitializer == null)
			return;
		addEdge(edgeByKey, consumerModule, providerModule, CompilerDependencyPhase.SharedTyping, CompilerDependencyKind.StaticInitialization,
			"initializer:"
			+ staticInitializer.getCanonicalKey()
			+ "->"
			+ consumedFact);
	}

	/** Record the exact base/interface type selected by shared typing. **/
	static function collectResolvedHeaderType(edgeByKey:haxe.ds.StringMap<CompilerDependencyEdge>, consumerModule:String, index:TyperIndex, type:Null<TyType>,
			label:String):Void {
		if (index == null || type == null)
			return;
		final identity = type.getNominalIdentity();
		final provider = identity == null ? null : index.getByFullName(identity.getCanonicalName());
		if (provider != null)
			addEdge(edgeByKey, consumerModule, provider.getModulePath(), CompilerDependencyPhase.ModuleResolution, CompilerDependencyKind.PublicInterface,
				label + ":" + provider.getIdentity().getCanonicalName());
		for (argument in type.getTypeArguments())
			collectType(edgeByKey, consumerModule, index, argument, label + "-argument");
	}

	static function addEdge(edgeByKey:haxe.ds.StringMap<CompilerDependencyEdge>, consumerModule:String, providerModule:String, phase:CompilerDependencyPhase,
			kind:CompilerDependencyKind, factIdentity:String):Void {
		if (providerModule == null || StringTools.trim(providerModule).length == 0 || consumerModule == providerModule)
			return;
		final edge = new CompilerDependencyEdge(consumerModule, providerModule, phase, kind, factIdentity);
		edgeByKey.set(edge.canonicalKey(), edge);
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
