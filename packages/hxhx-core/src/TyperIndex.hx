import haxe.ds.StringMap;
import haxe.ds.ObjectMap;
import haxe.io.Path;

private typedef TyParsedAbstractOperatorMetadata = {
	final unaryOperator:Null<HxUnaryOperator>;
	final unaryFixity:Null<HxUnaryFixity>;
	final binaryOperator:Null<String>;
};

/**
	Program-level semantic declaration index for Stage3 typing.

	The index assigns canonical nominal and declaration identities, keeps
	abstracts separate from classes, resolves the supported structural type-hint
	subset, and parses `@:op` metadata once. Eager and lazy loading both use
	`addResolvedModules`, preventing identity/catalog drift between paths.

	This class catalogs declarations only. It does not select an overload for an
	expression, inline a body, decide mutation, or expose target carriers.
**/
class TyperIndex {
	final byFullName:StringMap<TyNominalInfo>;
	final byShortName:StringMap<Array<TyNominalInfo>>;
	final identityByFullName:StringMap<TyNominalTypeId>;
	final identityByShortName:StringMap<Array<TyNominalTypeId>>;
	final identitiesByModulePath:StringMap<Array<TyNominalTypeId>>;
	final visibilityByFullName:StringMap<HxVisibility>;
	final bySourceClass:ObjectMap<HxClassDecl, TyNominalInfo>;

	public function new() {
		byFullName = new StringMap();
		byShortName = new StringMap();
		identityByFullName = new StringMap();
		identityByShortName = new StringMap();
		identitiesByModulePath = new StringMap();
		visibilityByFullName = new StringMap();
		bySourceClass = new ObjectMap();
	}

	public function getByFullName(fullName:String):Null<TyNominalInfo> {
		return byFullName.exists(fullName) ? byFullName.get(fullName) : null;
	}

	public function getAbstractByFullName(fullName:String):Null<TyAbstractInfo> {
		final info = getByFullName(fullName);
		return info != null && Std.isOfType(info, TyAbstractInfo) ? cast info : null;
	}

	public function getByShortName(shortName:String):Array<TyNominalInfo> {
		return byShortName.exists(shortName) ? byShortName.get(shortName) : [];
	}

	/** Return every indexed type declared by one Haxe module in stable order. **/
	public function getByModulePath(modulePath:String):Array<TyNominalInfo> {
		if (modulePath == null || modulePath.length == 0)
			return [];
		final out = new Array<TyNominalInfo>();
		if (!identitiesByModulePath.exists(modulePath))
			return out;
		for (identity in identitiesByModulePath.get(modulePath)) {
			final info = byFullName.get(identity.getCanonicalName());
			if (info != null && info.getVisibility() == HxVisibility.Public)
				out.push(info);
		}
		return out;
	}

	/**
		Return every type declared by one module, including private secondary types.

		Code inside that same Haxe module may name private declarations and enum
		constructors. External module lookup must continue to use `getByModulePath`,
		which exposes only public types.
	**/
	public function getDeclaredByModulePath(modulePath:String):Array<TyNominalInfo> {
		if (modulePath == null || modulePath.length == 0 || !identitiesByModulePath.exists(modulePath))
			return [];
		final out = new Array<TyNominalInfo>();
		for (identity in identitiesByModulePath.get(modulePath)) {
			final info = byFullName.get(identity.getCanonicalName());
			if (info != null)
				out.push(info);
		}
		return out;
	}

	/**
		Find the semantic owner for one parser class while constructing typed bodies.

		Source object association is used only at the parser-to-typed boundary. The
		returned nodes and calls carry canonical nominal/declaration identities, so
		backends never depend on allocation identity or traversal position.
	**/
	public function getForSourceClass(source:HxClassDecl):Null<TyNominalInfo> {
		if (source == null)
			return null;
		final exact = bySourceClass.get(source);
		if (exact != null)
			return exact;
		final candidates = getByShortName(HxClassDecl.getName(source));
		if (candidates.length == 1)
			return candidates[0];
		final sourceFunctions = HxClassDecl.getFunctions(source);
		for (candidate in candidates)
			for (declaration in candidate.getDeclarations())
				for (sourceFunction in sourceFunctions)
					if (declaration.getSourceDeclaration() == sourceFunction)
						return candidate;
		return null;
	}

	public function addNominal(info:TyNominalInfo):Void {
		if (info == null)
			return;
		final fullName = info.getFullName();
		final shortName = info.getShortName();
		byFullName.set(fullName, info);

		final existing = byShortName.exists(shortName) ? byShortName.get(shortName) : [];
		var replaced = false;
		for (i in 0...existing.length) {
			if (existing[i].getFullName() == fullName) {
				existing[i] = info;
				replaced = true;
				break;
			}
		}
		if (!replaced)
			existing.push(info);
		byShortName.set(shortName, existing);
	}

	static function expectedModuleNameFromFile(filePath:Null<String>):Null<String> {
		if (filePath == null || filePath.length == 0)
			return null;
		final name = Path.withoutDirectory(filePath);
		final dot = name.lastIndexOf(".");
		return dot <= 0 ? name : name.substr(0, dot);
	}

	static function classFullNameInModule(pkg:String, moduleName:Null<String>, className:String):String {
		final packagePath = pkg == null ? "" : StringTools.trim(pkg);
		final rawModule = moduleName == null ? "" : StringTools.trim(moduleName);
		final modulePath = rawModule.length == 0 || rawModule == "Unknown" ? "" : rawModule;
		final shortName = className == null ? "" : StringTools.trim(className);
		var prefix = packagePath;
		if (modulePath.length > 0 && shortName.length > 0 && shortName != modulePath)
			prefix = prefix.length == 0 ? modulePath : prefix + "." + modulePath;
		return prefix.length == 0 ? shortName : prefix + "." + shortName;
	}

	static function canonicalModulePath(pkg:String, moduleName:Null<String>):String {
		final packagePath = pkg == null ? "" : StringTools.trim(pkg);
		final name = moduleName == null ? "" : StringTools.trim(moduleName);
		return packagePath.length == 0 ? name : (name.length == 0 ? packagePath : packagePath + "." + name);
	}

	static function metadataValue(metadata:Array<String>, name:String):Null<String> {
		if (metadata == null)
			return null;
		final prefix = name + "=";
		for (entry in metadata) {
			if (entry != null && StringTools.startsWith(entry, prefix))
				return entry.substr(prefix.length);
		}
		return null;
	}

	static function metadataValues(metadata:Array<String>, name:String):Array<String> {
		if (metadata == null)
			return [];
		final prefix = name + "=";
		return [
			for (entry in metadata)
				if (entry != null && StringTools.startsWith(entry, prefix)) entry.substr(prefix.length)
		];
	}

	static function hasMetadata(metadata:Array<String>, name:String):Bool {
		if (metadata == null)
			return false;
		for (entry in metadata) {
			var clean = entry == null ? "" : StringTools.trim(entry);
			while (StringTools.startsWith(clean, "@") || StringTools.startsWith(clean, ":"))
				clean = clean.substr(1);
			if (clean == name)
				return true;
		}
		return false;
	}

	static function typeParameters(metadata:Array<String>):Array<String> {
		final encoded = metadataValue(metadata, "__hxhx_type_params");
		if (encoded == null || StringTools.trim(encoded).length == 0)
			return [];
		return [
			for (part in encoded.split(","))
				if (StringTools.trim(part).length > 0) StringTools.trim(part)
		];
	}

	function registerIdentity(fullName:String, shortName:String):TyNominalTypeId {
		if (identityByFullName.exists(fullName))
			return identityByFullName.get(fullName);
		final identity = new TyNominalTypeId(fullName);
		identityByFullName.set(fullName, identity);
		final candidates = identityByShortName.exists(shortName) ? identityByShortName.get(shortName) : [];
		candidates.push(identity);
		identityByShortName.set(shortName, candidates);
		return identity;
	}

	function registerModuleIdentities(module:ResolvedModule):Void {
		if (module == null || ResolvedModule.getParsed(module) == null)
			return;
		final declaration = ResolvedModule.getParsed(module).getDecl();
		final packagePath = HxModuleDecl.getPackagePath(declaration);
		final moduleName = expectedModuleNameFromFile(ResolvedModule.getFilePath(module));
		final modulePath = canonicalModulePath(packagePath, moduleName);
		for (classDeclaration in HxModuleDecl.getClasses(declaration)) {
			final shortName = HxClassDecl.getName(classDeclaration);
			if (shortName == null || shortName.length == 0 || shortName == "Unknown")
				continue;
			final identity = registerIdentity(classFullNameInModule(packagePath, moduleName, shortName), shortName);
			visibilityByFullName.set(identity.getCanonicalName(), HxClassDecl.getVisibility(classDeclaration));
			final moduleIdentities = identitiesByModulePath.exists(modulePath) ? identitiesByModulePath.get(modulePath) : [];
			var alreadyRegistered = false;
			for (candidate in moduleIdentities)
				if (candidate.equals(identity)) {
					alreadyRegistered = true;
					break;
				}
			if (!alreadyRegistered)
				moduleIdentities.push(identity);
			identitiesByModulePath.set(modulePath, moduleIdentities);
		}
	}

	function identityFromModuleByShortName(modulePath:String, shortName:String, publicOnly:Bool = false):Null<TyNominalTypeId> {
		if (!identitiesByModulePath.exists(modulePath))
			return null;
		for (identity in identitiesByModulePath.get(modulePath)) {
			final canonical = identity.getCanonicalName();
			final dot = canonical.lastIndexOf(".");
			final candidateShort = dot < 0 ? canonical : canonical.substr(dot + 1);
			if (candidateShort == shortName && (!publicOnly || identityIsPublic(identity)))
				return identity;
		}
		return null;
	}

	function identityIsPublic(identity:Null<TyNominalTypeId>):Bool
		return identity != null
			&& visibilityByFullName.exists(identity.getCanonicalName())
			&& visibilityByFullName.get(identity.getCanonicalName()) == HxVisibility.Public;

	function identityVisibleFromModule(identity:Null<TyNominalTypeId>, modulePath:String):Bool {
		if (identity == null)
			return false;
		if (identityIsPublic(identity))
			return true;
		if (modulePath == null || modulePath.length == 0 || !identitiesByModulePath.exists(modulePath))
			return false;
		for (candidate in identitiesByModulePath.get(modulePath))
			if (candidate.equals(identity))
				return true;
		return false;
	}

	/**
		Whether an alias import deliberately withholds a provider's original short
		name from this module. For example, `import model.User as Account` introduces
		`Account`, not `User`. This prevents the compiler's temporary global
		unique-name fallback from silently making `User` visible anyway.
	**/
	static function hidesOriginalNameBehindAlias(raw:String, directives:Array<HxModuleDirective>):Bool {
		if (raw == null || raw.indexOf(".") >= 0 || directives == null)
			return false;
		for (directive in directives) {
			switch (HxModuleDirective.getKind(directive)) {
				case ImportAlias(alias):
					final path = HxModuleDirective.getPath(directive);
					final dot = path.lastIndexOf(".");
					final originalName = dot < 0 ? path : path.substr(dot + 1);
					if (originalName == raw && alias != raw)
						return true;
				case ImportNormal | ImportAll | Using:
			}
		}
		return false;
	}

	/** Prevent the temporary unique-name fallback from widening a type wildcard. **/
	function rawStaticWildcardHidesType(raw:String, directives:Array<HxModuleDirective>):Bool {
		if (raw == null || directives == null)
			return false;
		for (directive in directives)
			if (HxModuleDirective.getKind(directive).match(ImportAll)) {
				final providerPath = HxModuleDirective.getPath(directive);
				if (identityByFullName.exists(providerPath) && identityFromModuleByShortName(providerPath, raw) != null)
					return true;
			}
		return false;
	}

	function resolvedStaticWildcardHidesType(raw:String, directives:Array<TyModuleDirective>):Bool {
		if (raw == null || directives == null)
			return false;
		for (directive in directives)
			if (directive.getKind().match(StaticWildcardImport)) {
				final provider = directive.getSingleProvider();
				final providerInfo = provider == null ? null : getByFullName(provider.getCanonicalName());
				if (providerInfo != null)
					for (moduleType in getByModulePath(providerInfo.getModulePath()))
						if (moduleType.getShortName() == raw)
							return true;
			}
		return false;
	}

	/** Resolve one nominal path using local-module, import, package, then unique-short-name evidence. **/
	function resolveIdentity(typePath:String, packagePath:String, moduleName:Null<String>, directives:Array<HxModuleDirective>):Null<TyNominalTypeId> {
		final raw = typePath == null ? "" : StringTools.trim(typePath);
		if (raw.length == 0)
			return null;
		final currentModulePath = canonicalModulePath(packagePath, moduleName);
		if (identityByFullName.exists(raw)) {
			final direct = identityByFullName.get(raw);
			if (identityVisibleFromModule(direct, currentModulePath))
				return direct;
		}

		final inModule = classFullNameInModule(packagePath, moduleName, raw);
		if (identityByFullName.exists(inModule))
			return identityByFullName.get(inModule);
		if (directives != null) {
			for (offset in 0...directives.length) {
				final directive = directives[directives.length - 1 - offset];
				final importPath = HxModuleDirective.getPath(directive);
				switch (HxModuleDirective.getKind(directive)) {
					case ImportNormal:
						if (HxModuleDirective.getImportedLocalName(directive) == raw && identityByFullName.exists(importPath)) {
							final imported = identityByFullName.get(importPath);
							if (identityIsPublic(imported))
								return imported;
						}
						// A plain import of a module's main type also exposes the
						// other public types declared by that module. Class statics
						// are a different namespace and are not exposed here.
						final moduleType = identityFromModuleByShortName(importPath, raw, true);
						if (moduleType != null)
							return moduleType;
					case ImportAlias(_):
						if (HxModuleDirective.getImportedLocalName(directive) == raw && identityByFullName.exists(importPath)) {
							final imported = identityByFullName.get(importPath);
							if (identityIsPublic(imported))
								return imported;
						}
					case ImportAll:
						// `import Type.*` exposes the type's static members, not
						// secondary types declared in the same module. Only a path
						// that is not an exact known type is a package wildcard here.
						if (!identityByFullName.exists(importPath)) {
							final wildcardCandidate = importPath + "." + raw;
							if (identityByFullName.exists(wildcardCandidate)) {
								final imported = identityByFullName.get(wildcardCandidate);
								if (identityIsPublic(imported))
									return imported;
							}
						}
					case Using:
				}
			}
		}

		final inPackage = packagePath == null
			|| StringTools.trim(packagePath).length == 0 ? raw : StringTools.trim(packagePath) + "." + raw;
		if (identityByFullName.exists(inPackage)) {
			final packageIdentity = identityByFullName.get(inPackage);
			if (identityVisibleFromModule(packageIdentity, currentModulePath))
				return packageIdentity;
		}
		if (hidesOriginalNameBehindAlias(raw, directives) || rawStaticWildcardHidesType(raw, directives))
			return null;

		final shortName = raw.indexOf(".") < 0 ? raw : raw.substr(raw.lastIndexOf(".") + 1);
		final candidates = identityByShortName.exists(shortName) ? [
			for (candidate in identityByShortName.get(shortName))
				if (identityVisibleFromModule(candidate, currentModulePath)) candidate
		] : [];
		return candidates.length == 1 ? candidates[0] : null;
	}

	/**
		Replace unresolved type-hint nodes with type parameters or registered nominal
		identities while preserving nested arguments and nullable structure.
	**/
	function resolveSemanticType(type:TyType, packagePath:String, moduleName:Null<String>, directives:Array<HxModuleDirective>,
			parameters:StringMap<TyTypeParameterId>):TyType {
		if (type == null)
			return TyType.unknown();
		if (type.isNullable()) {
			final inner = type.getNullableInner();
			return TyType.nullable(resolveSemanticType(inner, packagePath, moduleName, directives, parameters), type.getDisplay());
		}
		if (type.isFunction()) {
			final result = type.getFunctionReturn();
			return TyType.functionType([
				for (argument in type.getFunctionArguments())
					resolveSemanticType(argument, packagePath, moduleName, directives, parameters)
			],
				result == null ? TyType.unknown() : resolveSemanticType(result, packagePath, moduleName, directives, parameters), type.getDisplay());
		}
		if (!type.isUnresolved())
			return type;

		final rawPath = type.getUnresolvedPath();
		final args = [
			for (arg in type.getTypeArguments())
				resolveSemanticType(arg, packagePath, moduleName, directives, parameters)
		];
		if (args.length == 0 && parameters.exists(rawPath))
			return TyType.typeParameter(parameters.get(rawPath));
		final identity = resolveIdentity(rawPath, packagePath, moduleName, directives);
		return identity == null ? TyType.unresolved(rawPath, args, type.getDisplay()) : TyType.nominal(identity, args, type.getDisplay());
	}

	function semanticType(hint:String, packagePath:String, moduleName:Null<String>, directives:Array<HxModuleDirective>,
			typeParams:Array<TyTypeParameterId>):TyType {
		final parameters = new StringMap<TyTypeParameterId>();
		for (parameter in typeParams)
			parameters.set(parameter.getName(), parameter);
		return resolveSemanticType(TyType.fromHintText(hint), packagePath, moduleName, directives, parameters);
	}

	static function addMethod(primary:StringMap<TyFunSig>, all:StringMap<Array<TyFunSig>>, signature:TyFunSig):Void {
		final name = signature.getName();
		final candidates = all.exists(name) ? all.get(name) : [];
		candidates.push(signature);
		all.set(name, candidates);
		if (!primary.exists(name))
			primary.set(name, signature);
	}

	static function declarationSignatureKey(signature:TyFunSig):String {
		final form = signature.getIsStatic() ? "static" : "instance";
		final optional = signature.getArgOptional();
		final rest = signature.getArgRest();
		final signatureArgs = signature.getArgs();
		final args = [
			for (index in 0...signatureArgs.length) {
				final argumentForm = index < rest.length
					&& rest[index] ? "rest" : (index < optional.length && optional[index] ? "optional" : "required");
				argumentForm + ":" + signatureArgs[index].getSemanticKey();
			}
		].join(",");
		return form + ":" + signature.getName() + "(" + args + ")->" + signature.getReturnType().getSemanticKey();
	}

	static function malformedOperator(filePath:String, position:HxPos, metadata:String):TyperError {
		return new TyperError(filePath, position, "Malformed @:op metadata: " + metadata);
	}

	/**
		Classify one fully parsed `@:op` expression without making its operand a
		semantic key.

		Upstream Haxe 4.3.7 records the unary token and fixity and validates the
		operator declaration against its owning abstract; the placeholder spelling
		inside metadata is not significant (`A` and `a` both occur in the stdlib).
	**/
	static function classifyOperatorExpression(expression:HxExpr, filePath:String, position:HxPos, metadata:String):TyParsedAbstractOperatorMetadata {
		return switch (expression) {
			case EUnop(op, fixity, _):
				{unaryOperator: op, unaryFixity: fixity, binaryOperator: null};
			case EBinop(op, EIdent(_), EIdent(_)) if (HxBinaryOperatorTools.isAbstractOverloadable(op)):
				{unaryOperator: null, unaryFixity: null, binaryOperator: op};
			case EBinop(_, _, _):
				throw malformedOperator(filePath, position, metadata);
			case EField(_, _):
				{unaryOperator: null, unaryFixity: null, binaryOperator: null};
			case ECall(_, _):
				{unaryOperator: null, unaryFixity: null, binaryOperator: null};
			case EArrayAccess(_, _):
				{unaryOperator: null, unaryFixity: null, binaryOperator: null};
			case EArrayDecl(_):
				// Upstream Haxe represents `@:op([])` as an empty array literal.
				// Its declaration semantics remain outside this operator slice.
				{unaryOperator: null, unaryFixity: null, binaryOperator: null};
			case _:
				throw malformedOperator(filePath, position, metadata);
		};
	}

	/**
		Parse one `@:op` payload through the shared expression parser. Unary and
		binary forms return canonical semantic descriptors; recognized array/call
		forms remain deferred, and every other shape fails deterministically.
	**/
	static function parseOperatorMetadata(metadata:String, filePath:String, position:HxPos):Null<TyParsedAbstractOperatorMetadata> {
		var clean = metadata == null ? "" : StringTools.trim(metadata);
		while (StringTools.startsWith(clean, "@") || StringTools.startsWith(clean, ":"))
			clean = clean.substr(1);
		if (clean != "op" && !StringTools.startsWith(clean, "op("))
			return null;
		if (clean.length <= 2 || clean.charAt(2) != "(" || !StringTools.endsWith(clean, ")"))
			throw malformedOperator(filePath, position, metadata);
		final payload = StringTools.trim(clean.substring(3, clean.length - 1));
		if (payload.length == 0)
			throw malformedOperator(filePath, position, metadata);

		try {
			return classifyOperatorExpression(HxParser.parseCompleteExprText(payload), filePath, position, metadata);
		} catch (_:HxParseError) {
			throw malformedOperator(filePath, position, metadata);
		}
	}

	/**
		Validate operator declaration shapes and attach canonical catalog entries.

		No overload is selected here, and static/instance form does not imply
		mutation or writeback.
	**/
	function catalogOperators(info:TyAbstractInfo, filePath:String):Void {
		for (declaration in info.getDeclarations()) {
			final seenUnary = new StringMap<Bool>();
			final seenBinary = new StringMap<Bool>();
			for (metadata in declaration.getMetadata()) {
				final parsed = parseOperatorMetadata(metadata, filePath, declaration.getPosition());
				if (parsed == null)
					continue;
				if (parsed.unaryOperator != null && parsed.unaryFixity != null) {
					final key = HxUnaryOperatorTools.sourceToken(parsed.unaryOperator)
						+ "|"
						+ (parsed.unaryFixity == HxUnaryFixity.Prefix ? "prefix" : "postfix");
					if (seenUnary.exists(key))
						throw new TyperError(filePath, declaration.getPosition(),
							"Duplicate unary @:op metadata on declaration " + declaration.getIdentity().getCanonicalKey());
					seenUnary.set(key, true);

					final signature = declaration.getSignature();
					final args = signature.getArgs();
					var operandType:TyType;
					if (signature.getIsStatic()) {
						final optional = signature.getArgOptional();
						final rest = signature.getArgRest();
						if (args.length != 1 || (optional.length > 0 && optional[0]) || (rest.length > 0 && rest[0]))
							throw new TyperError(filePath, declaration.getPosition(),
								"Unary static @:op declaration requires exactly one explicit argument: " + declaration.getIdentity().getCanonicalKey());
						operandType = args[0];
					} else {
						if (args.length != 0)
							throw new TyperError(filePath, declaration.getPosition(),
								"Unary instance @:op declaration requires no explicit arguments: " + declaration.getIdentity().getCanonicalKey());
						final appliedArgs = [for (parameter in info.getTypeParameterIds()) TyType.typeParameter(parameter)];
						operandType = TyType.nominal(info.getIdentity(), appliedArgs);
					}

					final operandIdentity = operandType.getNominalIdentity();
					if (operandIdentity == null || !operandIdentity.equals(info.getIdentity()))
						throw new TyperError(filePath, declaration.getPosition(),
							"Unary @:op operand must retain owning abstract type "
							+ info.getIdentity().getCanonicalName()
							+ ": "
							+ declaration.getIdentity().getCanonicalKey());
					info.addUnaryOperator(new TyAbstractOperatorInfo(parsed.unaryOperator, parsed.unaryFixity, declaration, operandType,
						signature.getReturnType()));
				}

				if (parsed.binaryOperator != null) {
					final op = parsed.binaryOperator;
					if (seenBinary.exists(op))
						throw new TyperError(filePath, declaration.getPosition(),
							"Duplicate binary @:op metadata on declaration " + declaration.getIdentity().getCanonicalKey());
					seenBinary.set(op, true);
					final signature = declaration.getSignature();
					final args = signature.getArgs();
					final optional = signature.getArgOptional();
					final rest = signature.getArgRest();
					for (index in 0...args.length)
						if ((index < optional.length && optional[index]) || (index < rest.length && rest[index]))
							throw new TyperError(filePath, declaration.getPosition(),
								"Binary @:op declaration cannot use optional or rest arguments: " + declaration.getIdentity().getCanonicalKey());

					var leftType:TyType;
					var rightType:TyType;
					if (signature.getIsStatic()) {
						if (args.length != 2)
							throw new TyperError(filePath, declaration.getPosition(),
								"Binary static @:op declaration requires exactly two explicit arguments: " + declaration.getIdentity().getCanonicalKey());
						leftType = args[0];
						rightType = args[1];
					} else {
						if (args.length != 1)
							throw new TyperError(filePath, declaration.getPosition(),
								"Binary instance @:op declaration requires exactly one explicit argument: " + declaration.getIdentity().getCanonicalKey());
						final appliedArgs = [for (parameter in info.getTypeParameterIds()) TyType.typeParameter(parameter)];
						leftType = TyType.nominal(info.getIdentity(), appliedArgs);
						rightType = args[0];
					}

					final leftIdentity = leftType.getNominalIdentity();
					final rightIdentity = rightType.getNominalIdentity();
					final ownsLeft = leftIdentity != null && leftIdentity.equals(info.getIdentity());
					final ownsRight = rightIdentity != null && rightIdentity.equals(info.getIdentity());
					if (!ownsLeft && !ownsRight)
						throw new TyperError(filePath, declaration.getPosition(),
							"Binary @:op declaration must retain owning abstract type "
							+ info.getIdentity().getCanonicalName()
							+ " in one operand: "
							+ declaration.getIdentity().getCanonicalKey());
					info.addBinaryOperator(new TyAbstractBinaryOperatorInfo(op, declaration, leftType, rightType, signature.getReturnType(),
						hasMetadata(declaration.getMetadata(), "commutative")));
				}
			}
		}
	}

	/** Build resolved fields, signatures, declaration records, and abstract catalog entries for one registered module. **/
	function indexModule(module:ResolvedModule):Void {
		if (module == null || ResolvedModule.getParsed(module) == null)
			return;
		final parsedModule = ResolvedModule.getParsed(module);
		final moduleDeclaration = parsedModule.getDecl();
		final packagePath = HxModuleDecl.getPackagePath(moduleDeclaration);
		final moduleName = expectedModuleNameFromFile(ResolvedModule.getFilePath(module));
		final semanticModulePath = canonicalModulePath(packagePath, moduleName);
		final directives = HxModuleDecl.getDirectives(moduleDeclaration);

		for (classDeclaration in HxModuleDecl.getClasses(moduleDeclaration)) {
			final shortName = HxClassDecl.getName(classDeclaration);
			if (shortName == null || shortName.length == 0 || shortName == "Unknown")
				continue;
			final fullName = classFullNameInModule(packagePath, moduleName, shortName);
			final identity = identityByFullName.get(fullName);
			final classMetadata = HxClassDecl.getMetadata(classDeclaration);
			final params = typeParameters(classMetadata);
			final parameterIds = [
				for (index in 0...params.length)
					TyTypeParameterId.nominal(identity, index, params[index])
			];
			var isEnum = false;
			for (sourceField in HxClassDecl.getFields(classDeclaration))
				if (HxFieldDecl.getName(sourceField) == "__hx_is_enum") {
					isEnum = true;
					break;
				}

			final fields = new StringMap<TyFieldInfo>();
			final properties = new StringMap<TyPropertyInfo>();
			for (field in HxClassDecl.getFields(classDeclaration)) {
				final fieldType = semanticType(HxFieldDecl.getTypeHint(field), packagePath, moduleName, directives, parameterIds);
				final fieldName = HxFieldDecl.getName(field);
				fields.set(fieldName,
					new TyFieldInfo(identity, semanticModulePath, fieldName, fieldType, HxFieldDecl.getIsStatic(field),
						HxFieldDecl.getVisibility(field) == HxVisibility.Public, HxFieldDecl.getIsFinal(field),
						hasMetadata(HxFieldDecl.getMetadata(field), "inline"), HxFieldDecl.getInit(field) != null || StringTools.trim(HxFieldDecl.getInitText(field))
						.length > 0,
						hasMetadata(HxFieldDecl.getMetadata(field), "noImportGlobal"), HxFieldDecl.getPropertyGet(field), HxFieldDecl.getPropertySet(field)));
				final getter = HxFieldDecl.getPropertyGet(field);
				final setter = HxFieldDecl.getPropertySet(field);
				if (getter.length > 0 || setter.length > 0)
					properties.set(fieldName, new TyPropertyInfo(fieldName, fieldType, HxFieldDecl.getIsStatic(field), getter, setter));
			}

			final statics = new StringMap<TyFunSig>();
			final instances = new StringMap<TyFunSig>();
			final staticLists = new StringMap<Array<TyFunSig>>();
			final instanceLists = new StringMap<Array<TyFunSig>>();
			final declarations = new Array<TyDeclarationInfo>();
			final signatureOccurrences = new StringMap<Int>();
			final methodOccurrences = new StringMap<Int>();

			for (functionDeclaration in HxClassDecl.getFunctions(classDeclaration)) {
				final functionName = HxFunctionDecl.getName(functionDeclaration);
				final isStatic = HxFunctionDecl.getIsStatic(functionDeclaration);
				final functionMetadata = HxFunctionDecl.getMetadata(functionDeclaration);
				final methodOccurrenceKey = (isStatic ? "static|" : "instance|") + functionName;
				final methodOccurrence = methodOccurrences.exists(methodOccurrenceKey) ? methodOccurrences.get(methodOccurrenceKey) : 0;
				methodOccurrences.set(methodOccurrenceKey, methodOccurrence + 1);
				final methodParameterNames = HxFunctionTypeParamMetadata.typeParamNames(functionMetadata);
				final methodParameterIds = [
					for (index in 0...methodParameterNames.length)
						TyTypeParameterId.method(identity, isStatic, functionName, methodOccurrence, index, methodParameterNames[index])
				];
				final functionParams = parameterIds.concat(methodParameterIds);
				final args = new Array<TyType>();
				final argNames = new Array<String>();
				final argOptional = new Array<Bool>();
				final argRest = new Array<Bool>();
				for (argument in HxFunctionDecl.getArgs(functionDeclaration)) {
					argNames.push(HxFunctionArg.getName(argument));
					args.push(semanticType(HxFunctionArg.getTypeHint(argument), packagePath, moduleName, directives, functionParams));
					argOptional.push(HxFunctionArg.getIsOptional(argument));
					argRest.push(HxFunctionArg.getIsRest(argument));
				}

				final returnType = functionName == "new" ? TyType.nominal(identity,
					[for (parameter in parameterIds) TyType.typeParameter(parameter)]) : semanticType(HxFunctionDecl.getReturnTypeHint(functionDeclaration),
						packagePath, moduleName, directives, functionParams);
				final signature = new TyFunSig(functionName, isStatic, argNames, args, argOptional, argRest, returnType,
					HxFunctionDecl.getPos(functionDeclaration));
				if (isStatic)
					addMethod(statics, staticLists, signature)
				else
					addMethod(instances, instanceLists, signature);

				final signatureKey = declarationSignatureKey(signature);
				final occurrence = signatureOccurrences.exists(signatureKey) ? signatureOccurrences.get(signatureKey) : 0;
				signatureOccurrences.set(signatureKey, occurrence + 1);
				final declarationId = new TyDeclarationId(identity.getCanonicalName() + "#" + signatureKey + "#" + occurrence);
				declarations.push(new TyDeclarationInfo(declarationId, identity, signature, functionMetadata, functionDeclaration,
					HxFunctionDecl.getPos(functionDeclaration), hasMetadata(functionMetadata, "inline"),
					HxFunctionDecl.getVisibility(functionDeclaration) == HxVisibility.Public,
					semanticModulePath, isEnum && isStatic && !StringTools.startsWith(functionName, "__hx_"), methodParameterIds));
			}

			if (classMetadata.indexOf("__hxhx_abstract") >= 0) {
				final underlyingHint = metadataValue(classMetadata, "__hxhx_abstract_underlying");
				final underlying = semanticType(underlyingHint == null ? "" : underlyingHint, packagePath, moduleName, directives, parameterIds);
				final implicitFromTypes = [
					for (hint in metadataValues(classMetadata, "__hxhx_abstract_from"))
						semanticType(hint, packagePath, moduleName, directives, parameterIds)
				];
				final implicitToTypes = [
					for (hint in metadataValues(classMetadata, "__hxhx_abstract_to"))
						semanticType(hint, packagePath, moduleName, directives, parameterIds)
				];
				final info = new TyAbstractInfo(identity, shortName, semanticModulePath, fields, properties, statics, instances, staticLists, instanceLists,
					declarations, underlying, parameterIds, implicitFromTypes, implicitToTypes, HxClassDecl.getVisibility(classDeclaration));
				catalogOperators(info, ResolvedModule.getFilePath(module));
				addNominal(info);
				bySourceClass.set(classDeclaration, info);
			} else {
				final extendsPath = HxClassDecl.getExtendsPath(classDeclaration);
				final superType = extendsPath == null
					|| StringTools.trim(extendsPath).length == 0 ? null : semanticType(extendsPath, packagePath, moduleName, directives, parameterIds);
				final info = new TyClassInfo(identity, shortName, semanticModulePath, fields, properties, statics, instances, staticLists, instanceLists,
					declarations, HxClassDecl.getVisibility(classDeclaration), isEnum, superType, parameterIds);
				addNominal(info);
				bySourceClass.set(classDeclaration, info);
			}
		}
	}

	/** Add one module through the same two-pass identity/surface path as eager builds. **/
	public function addResolvedModule(module:ResolvedModule):Void {
		addResolvedModules([module]);
	}

	/**
		Register all nominal identities before resolving any signature in the batch,
		then build semantic surfaces and operator catalogs.
	**/
	public function addResolvedModules(modules:Array<ResolvedModule>):Void {
		if (modules == null)
			return;
		for (module in modules)
			registerModuleIdentities(module);
		for (module in modules)
			indexModule(module);
	}

	public static function build(resolved:Array<ResolvedModule>):TyperIndex {
		final index = new TyperIndex();
		index.addResolvedModules(resolved);
		return index;
	}

	public function getUnaryOperators(identity:TyNominalTypeId, op:HxUnaryOperator, fixity:HxUnaryFixity):Array<TyAbstractOperatorInfo> {
		if (identity == null)
			return [];
		final info = getAbstractByFullName(identity.getCanonicalName());
		return info == null ? [] : info.getUnaryOperators(op, fixity);
	}

	public function getBinaryOperators(identity:TyNominalTypeId, op:String):Array<TyAbstractBinaryOperatorInfo> {
		if (identity == null)
			return [];
		final info = getAbstractByFullName(identity.getCanonicalName());
		return info == null ? [] : info.getBinaryOperators(op);
	}

	public function resolveTypePath(typePath:String, packagePath:String, directives:Array<HxModuleDirective>, ?resolvedDirectives:Array<TyModuleDirective>,
			?currentModulePath:String):Null<TyNominalInfo> {
		if (typePath == null)
			return null;
		final raw = StringTools.trim(typePath);
		if (raw.length == 0)
			return null;
		if (raw.indexOf(".") >= 0) {
			final direct = getByFullName(raw);
			if (typeVisibleFromModule(direct, currentModulePath))
				return direct;
		}
		if (resolvedDirectives != null) {
			for (offset in 0...resolvedDirectives.length) {
				final directive = resolvedDirectives[resolvedDirectives.length - 1 - offset];
				final source = directive.getSource();
				switch (directive.getKind()) {
					case TypeImport:
						if (HxModuleDirective.getImportedLocalName(source) == raw) {
							final sourcePath = HxModuleDirective.getPath(source);
							final hit = getByFullName(sourcePath);
							if (typeVisibleFromModule(hit, currentModulePath))
								return hit;
						}
						if (HxModuleDirective.getKind(source).match(ImportNormal))
							for (provider in directive.getProviders()) {
								final providerInfo = getByFullName(provider.getCanonicalName());
								if (providerInfo != null && providerInfo.getShortName() == raw)
									return providerInfo;
							}
					case PackageWildcardImport:
						final hit = getByFullName(HxModuleDirective.getPath(source) + "." + raw);
						if (typeVisibleFromModule(hit, currentModulePath))
							return hit;
					case StaticMemberImport(_) | StaticWildcardImport | UsingType | Unresolved:
				}
			}
		} else if (directives != null) {
			for (offset in 0...directives.length) {
				final directive = directives[directives.length - 1 - offset];
				final importPath = HxModuleDirective.getPath(directive);
				switch (HxModuleDirective.getKind(directive)) {
					case ImportNormal:
						if (HxModuleDirective.getImportedLocalName(directive) == raw) {
							final hit = getByFullName(importPath);
							if (typeVisibleFromModule(hit, currentModulePath))
								return hit;
						}
						for (moduleType in getByModulePath(importPath))
							if (moduleType.getShortName() == raw)
								return moduleType;
					case ImportAlias(_):
						if (HxModuleDirective.getImportedLocalName(directive) == raw) {
							final hit = getByFullName(importPath);
							if (typeVisibleFromModule(hit, currentModulePath))
								return hit;
						}
					case ImportAll:
						if (getByFullName(importPath) == null) {
							final hit = getByFullName(importPath + "." + raw);
							if (typeVisibleFromModule(hit, currentModulePath))
								return hit;
						}
					case Using:
				}
			}
		}

		final packageName = packagePath == null ? "" : StringTools.trim(packagePath);
		if (packageName.length > 0) {
			var current = packageName;
			while (true) {
				final hit = getByFullName(current + "." + raw);
				if (typeVisibleFromModule(hit, currentModulePath))
					return hit;
				final dot = current.lastIndexOf(".");
				if (dot < 0)
					break;
				current = current.substr(0, dot);
			}
		}
		if (hidesOriginalNameBehindAlias(raw, directives)
			|| rawStaticWildcardHidesType(raw, directives)
			|| resolvedStaticWildcardHidesType(raw, resolvedDirectives))
			return null;
		final alternatives = [
			for (candidate in getByShortName(raw))
				if (typeVisibleFromModule(candidate, currentModulePath)) candidate
		];
		return alternatives.length == 1 ? alternatives[0] : null;
	}

	static function typeVisibleFromModule(info:Null<TyNominalInfo>, currentModulePath:Null<String>):Bool {
		if (info == null)
			return false;
		if (info.getVisibility() == HxVisibility.Public)
			return true;
		return currentModulePath != null && currentModulePath.length > 0 && info.getModulePath() == currentModulePath;
	}

	/** Deterministic backend-independent summary used by focused identity tests. **/
	public function semanticDump():String {
		final names = [for (name in byFullName.keys()) name];
		names.sort(compareText);
		final lines = new Array<String>();
		for (name in names) {
			final info = byFullName.get(name);
			final kind = Std.isOfType(info, TyAbstractInfo) ? "abstract" : "class";
			lines.push("nominal " + kind + " " + info.getIdentity().getCanonicalName());
			if (Std.isOfType(info, TyAbstractInfo)) {
				final abstractInfo:TyAbstractInfo = cast info;
				lines.push("  underlying " + abstractInfo.getUnderlyingType().getSemanticKey());
				lines.push("  type-params " + abstractInfo.getTypeParameters().join(","));
				final conversionLines = [
					for (type in abstractInfo.getImplicitFromTypes())
						"  from " + type.getSemanticKey()
				].concat([for (type in abstractInfo.getImplicitToTypes()) "  to " + type.getSemanticKey()]);
				conversionLines.sort(compareText);
				for (line in conversionLines)
					lines.push(line);
			}
			final declarationLines = [
				for (declaration in info.getDeclarations())
					"  declaration " + declaration.getIdentity().getCanonicalKey() + (declaration.getIsInline() ? " inline" : "")
			];
			declarationLines.sort(compareText);
			for (line in declarationLines)
				lines.push(line);
			if (Std.isOfType(info, TyAbstractInfo)) {
				final abstractInfo:TyAbstractInfo = cast info;
				final operatorLines = [
					for (operatorInfo in abstractInfo.getAllUnaryOperators())
						"  unary "
						+ HxUnaryOperatorTools.sourceToken(operatorInfo.getOperator())
						+ " "
						+ (operatorInfo.getFixity() == HxUnaryFixity.Prefix ? "prefix" : "postfix")
						+ " "
						+ operatorInfo.getDeclaration().getIdentity().getCanonicalKey()
						+ " operand="
						+ operatorInfo.getOperandType().getSemanticKey()
						+ " result="
						+ operatorInfo.getResultType().getSemanticKey()];
				operatorLines.sort(compareText);
				for (line in operatorLines)
					lines.push(line);
				final binaryOperatorLines = [
					for (operatorInfo in abstractInfo.getAllBinaryOperators())
						"  binary "
						+ operatorInfo.getOperator()
						+ (operatorInfo.getIsCommutative() ? " commutative " : " ")
						+ operatorInfo.getDeclaration().getIdentity().getCanonicalKey()
						+ " left="
						+ operatorInfo.getLeftType().getSemanticKey()
						+ " right="
						+ operatorInfo.getRightType().getSemanticKey()
						+ " result="
						+ operatorInfo.getResultType().getSemanticKey()];
				binaryOperatorLines.sort(compareText);
				for (line in binaryOperatorLines)
					lines.push(line);
			}
		}
		return lines.join("\n");
	}

	static function compareText(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
