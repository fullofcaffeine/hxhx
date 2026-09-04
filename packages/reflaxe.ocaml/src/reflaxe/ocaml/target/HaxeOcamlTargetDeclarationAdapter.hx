package reflaxe.ocaml.target;

#if macro
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetArgumentInput;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetClassInput;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetFieldInput;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetMethodInput;
#end

/**
	Copies public Haxe macro facts into the standalone OCaml target input.

	The returned request retains no `Ref<T>`, `ClassType`, `ClassField`, or other
	mutable compiler reflection object. Target behavior can therefore migrate to
	the request without depending on the compiler that supplied it.
**/
class HaxeOcamlTargetDeclarationAdapter {
	#if macro
	public static function fromModuleTypes(hostProgramRevision:String, moduleTypes:Array<ModuleType>):OcamlTargetDeclarationRequest {
		if (moduleTypes == null)
			throw "standalone OCaml target declaration adapter requires module types";
		final classes = new Array<OcamlTargetClassInput>();
		for (moduleType in moduleTypes)
			switch (moduleType) {
				case TClassDecl(reference):
					classes.push(copyClass(reference.get()));
				case _:
			}
		return new OcamlTargetDeclarationRequest(hostProgramRevision, classes);
	}

	static function copyClass(classType:ClassType):OcamlTargetClassInput {
		final typeName = classType.pack.concat([classType.name]).join(".");
		final owner = OcamlTargetDeclarationRequest.classIdentity(classType.module, typeName);
		final fields = new Array<OcamlTargetFieldInput>();
		final methods = new Array<OcamlTargetMethodInput>();
		copyMembers(owner, false, classType.fields.get(), fields, methods);
		copyMembers(owner, true, classType.statics.get(), fields, methods);
		if (classType.constructor != null)
			copyMethod(owner, false, classType.constructor.get(), methods);
		final superType = classType.superClass == null ? null : TInst(classType.superClass.t, classType.superClass.params);
		final superClass = classType.superClass == null ? null : classType.superClass.t.get();
		return {
			canonicalIdentity: owner,
			moduleIdentity: classType.module,
			typeParameters: [for (parameter in classType.params) parameter.name],
			superClassIdentity: superClass == null ? null : OcamlTargetDeclarationRequest.classIdentity(superClass.module,
				superClass.pack.concat([superClass.name]).join(".")),
			superTypeIdentity: superType == null ? null : typeText(superType),
			superTypeDisplay: superType == null ? null : typeText(superType),
			fields: fields,
			methods: methods
		};
	}

	static function copyMembers(owner:String, isStatic:Bool, members:Array<ClassField>, fields:Array<OcamlTargetFieldInput>,
			methods:Array<OcamlTargetMethodInput>):Void {
		for (field in members)
			switch (TypeTools.follow(field.type)) {
				case TFun(_, _):
					copyMethod(owner, isStatic, field, methods);
				case _:
					final display = typeText(field.type);
					final access = switch (field.kind) {
						case FVar(read, write): {get: Std.string(read), set: Std.string(write)};
						case _: {get: "", set: ""};
					};
					fields.push({
						canonicalIdentity: OcamlTargetDeclarationRequest.fieldIdentity(owner, field.name, isStatic),
						name: field.name,
						typeIdentity: display,
						typeDisplay: display,
						isStatic: isStatic,
						isPublic: field.isPublic,
						isFinal: field.isFinal,
						isInline: field.meta.has(":inline"),
						hasInitializer: field.expr() != null,
						propertyGet: access.get,
						propertySet: access.set,
						noImportGlobal: field.meta.has(":noImportGlobal")
					});
			}
	}

	static function copyMethod(owner:String, isStatic:Bool, field:ClassField, methods:Array<OcamlTargetMethodInput>):Void {
		final followed = TypeTools.follow(field.type);
		final functionType = switch (followed) {
			case TFun(arguments, result): {arguments: arguments, result: result};
			case _: throw "standalone OCaml target declaration adapter expected a function type for " + owner + "." + field.name;
		};
		final arguments = new Array<OcamlTargetArgumentInput>();
		for (argument in functionType.arguments) {
			final display = typeText(argument.t);
			arguments.push({
				name: argument.name,
				typeIdentity: display,
				typeDisplay: display,
				isOptional: argument.opt,
				isRest: isRestType(argument.t)
			});
		}
		final resultDisplay = typeText(functionType.result);
		final methodKind = switch (field.kind) {
			case FMethod(kind): kind;
			case _: MethNormal;
		};
		methods.push({
			canonicalIdentity: OcamlTargetDeclarationRequest.methodIdentity(owner, field.name, isStatic,
				[for (argument in arguments) argumentIdentity(argument)], resultDisplay),
			name: field.name,
			typeParameters: [for (parameter in field.params) parameter.name],
			arguments: arguments,
			returnTypeIdentity: resultDisplay,
			returnTypeDisplay: resultDisplay,
			isStatic: isStatic,
			isPublic: field.isPublic,
			isInline: methodKind == MethInline,
			isDynamic: methodKind == MethDynamic,
			hasBody: field.expr() != null,
			isEnumConstructor: false,
			noImportGlobal: field.meta.has(":noImportGlobal")
		});
	}

	static function isRestType(type:Type):Bool
		return switch (TypeTools.follow(type)) {
			case TAbstract(reference, _): final abstractType = reference.get(); abstractType.pack.join(".") == "haxe" && abstractType.name == "Rest";
			case _: false;
		};

	static function typeText(type:Type):String
		return TypeTools.toString(type);

	static function argumentIdentity(argument:OcamlTargetArgumentInput):String
		return argument.typeIdentity + ":optional=" + (argument.isOptional ? "1" : "0") + ":rest=" + (argument.isRest ? "1" : "0");
	#end
}
