package backend.source;

import backend.GenIrProgram;
import haxe.ds.StringMap;

/** Closed storage choice selected from a typed field before text emission. */
enum LuaFieldDefault {
	Zero;
	False;
	Nil;
}

typedef LuaStoredField = {
	final name:String;
	final isStatic:Bool;
	final initial:LuaFieldDefault;
};

/** A validated class table, exact body owner, and its admitted storage members. */
typedef LuaClassOwner = {
	final projection:TypedBackendClassProjection;
	final identity:String;
	final declaredName:String;
	final parentIdentity:Null<String>;
	final isInterface:Bool;
	final reference:String;
	final packagePath:String;
	final fields:Array<LuaStoredField>;
};

/**
	Admit one Lua class graph before rendering any executable text.
	Typed facts select the exact parent and stored fields. This plan closes those
	decisions into table references and defaults, rejects absent or cyclic parents,
	and keeps each function paired with its original typed class projection.
**/
@:access(backend.source.SourceTargetCommon)
class LuaClassPlan {
	public final tableName:String;
	public final receiverName:String;
	public final runtimeName:String;

	final classes:Array<LuaClassOwner> = [];
	final byIdentity:StringMap<LuaClassOwner> = new StringMap();

	public function new(program:GenIrProgram) {
		tableName = freshName(program, "__hx_lua_classes");
		receiverName = freshName(program, "__hx_lua_receiver");
		runtimeName = freshName(program, "__hx_lua_runtime");
		for (module in program.getTypedModules()) {
			if (SourceTargetCommon.isStdSourceFile(module.getParsed().getFilePath()))
				continue;
			final projection = module.getBackendProjection();
			for (owner in projection.getClasses()) {
				final declaration = owner.getDeclaration();
				if (SourceTargetCommon.isCompileTimeOnlySupportClass(declaration) || HxClassDecl.getIsExtern(declaration))
					continue;
				final facts = owner.requireSemanticFacts();
				if (!facts.getNominalKind().match(ClassInstance))
					throw "Lua class plan requires an ordinary class: " + facts.getClassIdentity();
				final fields:Array<LuaStoredField> = [];
				for (field in facts.copyFields())
					if (field.hasStorage)
						fields.push({
							name: field.name,
							isStatic: field.isStatic,
							initial: switch field.semanticType.getSemanticKey() {
								case "primitive:Int" | "primitive:Float": Zero;
								case "primitive:Bool": False;
								case _: Nil;
							}
						});
				final entry:LuaClassOwner = {
					projection: owner,
					identity: facts.getClassIdentity(),
					declaredName: facts.getDeclaredName(),
					parentIdentity: facts.getSuperClassIdentity(),
					isInterface: facts.getIsInterface(),
					reference: tableName + ".c" + classes.length,
					packagePath: HxModuleDecl.getPackagePath(projection.getDeclaration()),
					fields: fields
				};
				if (byIdentity.exists(entry.identity))
					throw "Lua class identity is duplicated: " + entry.identity;
				classes.push(entry);
				byIdentity.set(entry.identity, entry);
			}
		}
		for (owner in classes) {
			final seen = new StringMap<Bool>();
			var current = owner;
			while (current != null) {
				if (seen.exists(current.identity))
					throw "Lua class hierarchy is cyclic: " + owner.identity;
				seen.set(current.identity, true);
				current = current.parentIdentity == null ? null : requireOwner(current.parentIdentity);
			}
		}
	}

	/** Generated receiver and runtime bindings cannot capture an authored parameter or local. */
	static function freshName(program:GenIrProgram, base:String):String {
		var suffix = 0;
		while (true) {
			final candidate = base + (suffix == 0 ? "" : "_" + suffix);
			var occupied = false;
			for (module in program.getTypedModules())
				for (owner in module.getBackendProjection().getClasses()) {
					if (HxClassDecl.getName(owner.getDeclaration()) == candidate)
						occupied = true;
					for (body in owner.getFunctions())
						if (body.getLocalCatalog().findByProjectedName(candidate) != null)
							occupied = true;
					for (initializer in owner.getFieldInitializers())
						if (initializer.getLocalCatalog().findByProjectedName(candidate) != null)
							occupied = true;
				}
			if (!occupied)
				return candidate;
			suffix++;
		}
	}

	public function copyClasses():Array<LuaClassOwner>
		return classes.copy();

	public function findOwner(identity:String):Null<LuaClassOwner>
		return byIdentity.get(identity);

	public function requireOwner(identity:String):LuaClassOwner {
		final owner = findOwner(identity);
		if (owner == null)
			throw "Lua class has no emitted typed owner: " + identity;
		return owner;
	}

	/** Entry selection must supply the same immutable projection admitted by this plan. */
	public function requireProjection(projection:TypedBackendClassProjection):LuaClassOwner {
		for (owner in classes)
			if (owner.projection == projection)
				return owner;
		throw "Lua entry class is absent from the admitted program";
	}
}
