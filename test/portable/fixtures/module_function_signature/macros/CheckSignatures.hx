import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlBuiltFunction.signatureFromTypes;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.ast.OcamlModuleReferences;
import reflaxe.ocaml.ast.OcamlModuleGroups.plan as planModules;
import reflaxe.ocaml.ast.OcamlRecursiveModuleCheck.checkRecursiveModule;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Checks metadata from actual function lowering, before relying on module signatures. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckSignatures {
	public static function install():Void {
		inspectDeclarationTypes();
		Context.onAfterGenerate(() -> {
			check("CycleLeft", "value", "int -> int");
			check("CycleRight", "value", "int -> int");
			check("Main", "main", "unit -> unit");
			check("CycleLeft", "create", "unit -> t");
			check("CycleLeft", "__empty", "unit -> t");
			check("ConstructorProbe", "create", "int -> int -> t");
			check("ConstructorProbe", "__empty", "unit -> t");
			check("ArrayConstructorProbe", "create", "int -> int HxArray.t -> t");
			check("UnrepresentedConstructorProbe", "create", "int -> (int -> int) -> t");
			check("Int32ConstructorProbe", "create", "int -> int -> t");
			check("Int32ConstructorProbe", "retain", "int -> int");
			for (name in [
				"Main",
				"CycleLeft",
				"CycleRight",
				"ConstructorProbe",
				"ArrayConstructorProbe",
				"UnrepresentedConstructorProbe",
				"Int32ConstructorProbe"
			]) {
				final items = OcamlCompiler.instance.moduleChunks.itemsFor(name, name);
				if (items == null)
					throw "missing module syntax: " + name;
				switch (checkRecursiveModule(items)) {
					case RecursiveModuleReady(_, _):
					case RecursiveModuleRejected(problem): throw "incomplete function module " + name + ": " + Std.string(problem);
				}
			}
			final nodes = [
				for (name in ["Main", "CycleLeft", "CycleRight"]) {
					final items = OcamlCompiler.instance.moduleChunks.itemsFor(name, name);
					if (items == null) throw "missing module syntax: " + name;
					final references = OcamlModuleReferences.collect(items);
					{
						name: name,
						dependencies: references.functionModules.concat(references.initializationModules).concat(references.typeModules)
					};
				}
			];
			final groups = planModules(nodes).groups;
			if (groups.map(group -> group.members.join(",")).join(";") != "CycleRight;CycleLeft;Main")
				throw "retained declarations lost module dependency order";
		});
	}

	/** Also exposes the declaration checks without running target generation. */
	public static function inspectDeclarationTypes():Void
		Context.onAfterTyping(_ -> checkInt32DeclarationTypes());

	/** The real Int64 constructor needs declaration carriers, not optimized Int permissions. */
	static function checkInt32DeclarationTypes():Void {
		final context = new CompilationContext();
		final registry = new OcamlRepresentationRegistry();
		final word = Context.getType("haxe.Int32");
		final alias = Context.getType("Int32ConstructorProbe.Word");
		final userWord = Context.getType("custom.Int32");
		final voidType = Context.getType("Void");
		function mapped(_:Type):OcamlTypeExpr
			return TIdent("int");
		final retained = projectDeclarationSignature([word, alias], word, registry, mapped, context);
		if (retained == null
			|| new OcamlASTPrinter().printType(signatureFromTypes(retained.parameters, retained.result)) != "int -> int -> int")
			throw "standard Int32 or transparent alias lost its declaration carrier";
		if (OcamlRepresentationRegistry.isExactInt(word))
			throw "Int32 incorrectly acquired optimized core Int identity";
		for (excluded in [userWord, Context.resolveType(macro :Null<haxe.Int32>, Context.currentPos())]) {
			if (projectDeclarationSignature([excluded], voidType, registry, mapped, context) != null)
				throw "unsupported abstract acquired Int32 declaration permission";
		}
		if (projectDeclarationSignature([word], voidType, registry, _ -> TIdent("Obj.t"), context) != null)
			throw "Int32 declaration ignored its actual target mapping";
		final malformed = switch word {
			case TAbstract(reference, []): TAbstract(reference, [Context.getType("Int")]);
			case _: throw "standard Int32 was not an unapplied abstract";
		};
		if (projectDeclarationSignature([malformed], voidType, registry, mapped, context) != null)
			throw "nonempty Int32 application acquired declaration permission";
		var checkedConstructor = false;
		for (type in Context.getModule("haxe.Int64"))
			switch type {
				case TInst(reference, []):
					final owner = reference.get();
					if (owner.module != "haxe.Int64" || owner.pack.join(".") != "haxe._Int64" || owner.name != "___Int64")
						continue;
					final declaration = owner.constructor.get();
					final signature = switch TypeTools.follow(declaration.type) {
						case TFun(parameters, result): {parameters: parameters, result: result};
						case _: throw "internal Int64 constructor lost its exact signature";
					};
					if (signature.parameters.length != 2
						|| signature.parameters[0].name != "high"
						|| signature.parameters[1].name != "low"
						|| Lambda.exists(signature.parameters, parameter -> TypeTools.toString(parameter.t) != "haxe.Int32"))
						throw "internal Int64 constructor parameters changed";
					final projected = projectDeclarationSignature(signature.parameters.map(parameter -> parameter.t), signature.result, registry, mapped,
						context);
					if (projected == null
						|| new OcamlASTPrinter().printType(signatureFromTypes(projected.parameters, TIdent("___int64_t"))) != "int -> int -> ___int64_t")
						throw "actual Int64 constructor lost its represented parameter signature";
					checkedConstructor = true;
				case _:
			}
		if (!checkedConstructor)
			throw "exact internal Int64 constructor was not checked";
		Sys.println("INT32_DECLARATION_TYPES:PASS");
	}

	/** Test-only access checks the target's retained declarations, not generated text. */
	static function check(moduleId:String, name:String, expected:String):Void {
		final items = OcamlCompiler.instance.moduleChunks.itemsFor(moduleId, moduleId);
		if (items == null)
			throw "missing module syntax: " + moduleId;
		final references = OcamlModuleReferences.collect(items);
		if (moduleId == "CycleLeft" && references.functionModules.indexOf("CycleRight") < 0)
			throw "lowered static call lost its module dependency";
		if (moduleId == "CycleLeft" && references.initializationModules.indexOf("CycleRight") >= 0)
			throw "delayed static call became an initializer dependency";
		for (item in items)
			switch (item) {
				case ILet(bindings, _):
					for (binding in bindings)
						if (binding.name == name) {
							if (binding.signature == null)
								throw "missing callable signature: " + moduleId + "." + name;
							final actual = new OcamlASTPrinter().printType(binding.signature);
							if (actual != expected)
								throw "wrong callable signature: " + actual + " expected " + expected;
							return;
						}
				case IType(_, _):
			}
		throw "missing callable binding: " + moduleId + "." + name;
	}
}
