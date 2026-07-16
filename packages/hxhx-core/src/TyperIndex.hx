import haxe.ds.StringMap;
import haxe.io.Path;

/**
	Program-level semantic declaration index for Stage3 typing.

	The index assigns canonical nominal and declaration identities, keeps
	abstracts separate from classes, resolves the supported structural type-hint
	subset, and parses unary `@:op` metadata once. Eager and lazy loading both use
	`addResolvedModules`, preventing identity/catalog drift between paths.

	This class catalogs declarations only. It does not select an overload for an
	expression, inline a body, decide mutation, or expose target carriers.
**/
class TyperIndex {
	final byFullName:StringMap<TyNominalInfo>;
	final byShortName:StringMap<Array<TyNominalInfo>>;
	final identityByFullName:StringMap<TyNominalTypeId>;
	final identityByShortName:StringMap<Array<TyNominalTypeId>>;

	public function new() {
		byFullName = new StringMap();
		byShortName = new StringMap();
		identityByFullName = new StringMap();
		identityByShortName = new StringMap();
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

	/**
		Find the semantic owner for one parser class while constructing typed bodies.

		Source object association is used only at the parser-to-typed boundary. The
		returned nodes and calls carry canonical nominal/declaration identities, so
		backends never depend on allocation identity or traversal position.
	**/
	public function getForSourceClass(source:HxClassDecl):Null<TyNominalInfo> {
		if (source == null)
			return null;
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
		for (classDeclaration in HxModuleDecl.getClasses(declaration)) {
			final shortName = HxClassDecl.getName(classDeclaration);
			if (shortName == null || shortName.length == 0 || shortName == "Unknown")
				continue;
			registerIdentity(classFullNameInModule(packagePath, moduleName, shortName), shortName);
		}
	}

	/** Resolve one nominal path using local-module, import, package, then unique-short-name evidence. **/
	function resolveIdentity(typePath:String, packagePath:String, moduleName:Null<String>, imports:Array<String>):Null<TyNominalTypeId> {
		final raw = typePath == null ? "" : StringTools.trim(typePath);
		if (raw.length == 0)
			return null;
		if (identityByFullName.exists(raw))
			return identityByFullName.get(raw);

		final inModule = classFullNameInModule(packagePath, moduleName, raw);
		if (identityByFullName.exists(inModule))
			return identityByFullName.get(inModule);
		if (imports != null) {
			for (importPath in imports) {
				final cleanImport = importPath == null ? "" : StringTools.trim(importPath);
				if (cleanImport.length == 0)
					continue;
				if (StringTools.endsWith(cleanImport, ".*")) {
					final wildcardCandidate = cleanImport.substr(0, cleanImport.length - 1) + raw;
					if (identityByFullName.exists(wildcardCandidate))
						return identityByFullName.get(wildcardCandidate);
					continue;
				}
				final dot = cleanImport.lastIndexOf(".");
				final importedShortName = dot < 0 ? cleanImport : cleanImport.substr(dot + 1);
				if (importedShortName == raw && identityByFullName.exists(cleanImport))
					return identityByFullName.get(cleanImport);
			}
		}

		final inPackage = packagePath == null
			|| StringTools.trim(packagePath).length == 0 ? raw : StringTools.trim(packagePath) + "." + raw;
		if (identityByFullName.exists(inPackage))
			return identityByFullName.get(inPackage);

		final shortName = raw.indexOf(".") < 0 ? raw : raw.substr(raw.lastIndexOf(".") + 1);
		final candidates = identityByShortName.exists(shortName) ? identityByShortName.get(shortName) : [];
		return candidates.length == 1 ? candidates[0] : null;
	}

	/**
		Replace unresolved type-hint nodes with type parameters or registered nominal
		identities while preserving nested arguments and nullable structure.
	**/
	function resolveSemanticType(type:TyType, packagePath:String, moduleName:Null<String>, imports:Array<String>, parameterNames:StringMap<Bool>):TyType {
		if (type == null)
			return TyType.unknown();
		if (type.isNullable()) {
			final inner = type.getNullableInner();
			return TyType.nullable(resolveSemanticType(inner, packagePath, moduleName, imports, parameterNames), type.getDisplay());
		}
		if (!type.isUnresolved())
			return type;

		final rawPath = type.getUnresolvedPath();
		final args = [
			for (arg in type.getTypeArguments())
				resolveSemanticType(arg, packagePath, moduleName, imports, parameterNames)
		];
		if (args.length == 0 && parameterNames.exists(rawPath))
			return TyType.typeParameter(rawPath);
		final identity = resolveIdentity(rawPath, packagePath, moduleName, imports);
		return identity == null ? TyType.unresolved(rawPath, args, type.getDisplay()) : TyType.nominal(identity, args, type.getDisplay());
	}

	function semanticType(hint:String, packagePath:String, moduleName:Null<String>, imports:Array<String>, typeParams:Array<String>):TyType {
		final names = new StringMap<Bool>();
		for (name in typeParams)
			names.set(name, true);
		return resolveSemanticType(TyType.fromHintText(hint), packagePath, moduleName, imports, names);
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
		final args = [for (arg in signature.getArgs()) arg.getSemanticKey()].join(",");
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
	static function classifyOperatorExpression(expression:HxExpr, filePath:String, position:HxPos,
			metadata:String):Null<{op:HxUnaryOperator, fixity:HxUnaryFixity}> {
		return switch (expression) {
			case EUnop(op, fixity, _):
				{op: op, fixity: fixity};
			case EBinop(_, _, _):
				null;
			case EField(_, _):
				null;
			case ECall(_, _):
				null;
			case EArrayAccess(_, _):
				// Valid binary, array-access, and callable operator metadata is
				// cataloged by later beads; it is not malformed unary metadata.
				null;
			case EArrayDecl(_):
				// Upstream Haxe represents `@:op([])` as an empty array literal.
				// Its declaration semantics remain outside this unary-only catalog.
				null;
			case _:
				throw malformedOperator(filePath, position, metadata);
		};
	}

	/**
		Parse one `@:op` payload through the shared expression parser. Unary forms
		return a structured token/fixity; recognized non-unary forms remain for the
		binary catalog bead, and every other `@:op` shape fails deterministically.
	**/
	static function parseUnaryOperatorMetadata(metadata:String, filePath:String, position:HxPos):Null<{op:HxUnaryOperator, fixity:HxUnaryFixity}> {
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
		Validate unary declaration shape and attach canonical catalog entries.

		No overload is selected here, and static/instance form does not imply
		mutation or writeback.
	**/
	function catalogUnaryOperators(info:TyAbstractInfo, filePath:String):Void {
		for (declaration in info.getDeclarations()) {
			final seen = new StringMap<Bool>();
			for (metadata in declaration.getMetadata()) {
				final parsed = parseUnaryOperatorMetadata(metadata, filePath, declaration.getPosition());
				if (parsed == null)
					continue;
				final key = HxUnaryOperatorTools.sourceToken(parsed.op) + "|" + (parsed.fixity == HxUnaryFixity.Prefix ? "prefix" : "postfix");
				if (seen.exists(key))
					throw new TyperError(filePath, declaration.getPosition(),
						"Duplicate unary @:op metadata on declaration " + declaration.getIdentity().getCanonicalKey());
				seen.set(key, true);

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
					final appliedArgs = [for (name in info.getTypeParameters()) TyType.typeParameter(name)];
					operandType = TyType.nominal(info.getIdentity(), appliedArgs);
				}

				final operandIdentity = operandType.getNominalIdentity();
				if (operandIdentity == null || !operandIdentity.equals(info.getIdentity()))
					throw new TyperError(filePath, declaration.getPosition(),
						"Unary @:op operand must retain owning abstract type "
						+ info.getIdentity().getCanonicalName()
						+ ": "
						+ declaration.getIdentity().getCanonicalKey());
				info.addUnaryOperator(new TyAbstractOperatorInfo(parsed.op, parsed.fixity, declaration, operandType, signature.getReturnType()));
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
		final imports = HxModuleDecl.getImports(moduleDeclaration);

		for (classDeclaration in HxModuleDecl.getClasses(moduleDeclaration)) {
			final shortName = HxClassDecl.getName(classDeclaration);
			if (shortName == null || shortName.length == 0 || shortName == "Unknown")
				continue;
			final fullName = classFullNameInModule(packagePath, moduleName, shortName);
			final identity = identityByFullName.get(fullName);
			final classMetadata = HxClassDecl.getMetadata(classDeclaration);
			final params = typeParameters(classMetadata);

			final fields = new StringMap<TyType>();
			final properties = new StringMap<TyPropertyInfo>();
			for (field in HxClassDecl.getFields(classDeclaration)) {
				final fieldType = semanticType(HxFieldDecl.getTypeHint(field), packagePath, moduleName, imports, params);
				final fieldName = HxFieldDecl.getName(field);
				fields.set(fieldName, fieldType);
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

			for (functionDeclaration in HxClassDecl.getFunctions(classDeclaration)) {
				final functionName = HxFunctionDecl.getName(functionDeclaration);
				final isStatic = HxFunctionDecl.getIsStatic(functionDeclaration);
				final functionMetadata = HxFunctionDecl.getMetadata(functionDeclaration);
				final functionParams = params.concat(HxFunctionTypeParamMetadata.typeParamNames(functionMetadata));
				final args = new Array<TyType>();
				final argNames = new Array<String>();
				final argOptional = new Array<Bool>();
				final argRest = new Array<Bool>();
				for (argument in HxFunctionDecl.getArgs(functionDeclaration)) {
					argNames.push(HxFunctionArg.getName(argument));
					args.push(semanticType(HxFunctionArg.getTypeHint(argument), packagePath, moduleName, imports, functionParams));
					argOptional.push(HxFunctionArg.getIsOptional(argument));
					argRest.push(HxFunctionArg.getIsRest(argument));
				}

				final returnType = functionName == "new" ? TyType.nominal(identity,
					[for (name in params) TyType.typeParameter(name)]) : semanticType(HxFunctionDecl.getReturnTypeHint(functionDeclaration), packagePath,
						moduleName, imports, functionParams);
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
					HxFunctionDecl.getPos(functionDeclaration), hasMetadata(functionMetadata, "inline")));
			}

			if (classMetadata.indexOf("__hxhx_abstract") >= 0) {
				final underlyingHint = metadataValue(classMetadata, "__hxhx_abstract_underlying");
				final underlying = semanticType(underlyingHint == null ? "" : underlyingHint, packagePath, moduleName, imports, params);
				final info = new TyAbstractInfo(identity, shortName, semanticModulePath, fields, properties, statics, instances, staticLists, instanceLists,
					declarations, underlying, params);
				catalogUnaryOperators(info, ResolvedModule.getFilePath(module));
				addNominal(info);
			} else {
				addNominal(new TyClassInfo(identity, shortName, semanticModulePath, fields, properties, statics, instances, staticLists, instanceLists,
					declarations));
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

	public function resolveTypePath(typePath:String, packagePath:String, imports:Array<String>):Null<TyNominalInfo> {
		if (typePath == null)
			return null;
		final raw = StringTools.trim(typePath);
		if (raw.length == 0)
			return null;
		if (raw.indexOf(".") >= 0) {
			final direct = getByFullName(raw);
			if (direct != null)
				return direct;
		}
		if (imports != null) {
			for (importPath in imports) {
				if (importPath == null || importPath.length == 0)
					continue;
				final parts = importPath.split(".");
				final last = parts.length == 0 ? "" : parts[parts.length - 1];
				if (last == raw) {
					final hit = getByFullName(importPath);
					if (hit != null)
						return hit;
				}
			}
		}

		final packageName = packagePath == null ? "" : StringTools.trim(packagePath);
		if (packageName.length > 0) {
			var current = packageName;
			while (true) {
				final hit = getByFullName(current + "." + raw);
				if (hit != null)
					return hit;
				final dot = current.lastIndexOf(".");
				if (dot < 0)
					break;
				current = current.substr(0, dot);
			}
		}
		final alternatives = getByShortName(raw);
		return alternatives.length == 1 ? alternatives[0] : null;
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
			}
		}
		return lines.join("\n");
	}

	static function compareText(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
