package backend.cpp;

import TypedBackendClassSemanticFacts.TypedBackendClassFieldFact;

/**
	Allocate one traced program payload with separate slots for exact static fields.
	Slots start unassigned: this layout does not choose Haxe defaults or execute
	initializers. A startup plan must publish storage and assign defaults before
	ordinary source execution. Missing startup cannot silently become a null value.
 */
class CppManagedStaticStorage {
	final program:CppTypedProgramProjection;

	public final nativeName:String;

	final hasStack:Bool;

	final fields:Array<TypedBackendClassFieldFact> = [];
	final slots:haxe.ds.StringMap<Int> = new haxe.ds.StringMap();

	public function new(program:CppTypedProgramProjection, nativeName:String, hasStack:Bool = false) {
		if (program == null || nativeName == null || !~/^hxhx_statics_[A-Za-z0-9_]+$/.match(nativeName))
			throw "managed statics require an exact program and allocated payload symbol";
		this.program = program;
		this.nativeName = nativeName;
		this.hasStack = hasStack;
		program.assertCurrent();
		for (module in program.getModules())
			for (owner in module.projection.getClasses()) {
				final facts = owner.requireSemanticFacts();
				if (facts.getIsExtern())
					continue;
				switch facts.getNominalKind() {
					case EnumValue:
						// Synthetic enum helper fields serve other targets, not source static storage.
						for (constructor in facts.copyEnumConstructors())
							switch constructor.member {
								case Singleton(field): fields.push(field);
								case Callable(_):
							}
					case _:
						for (field in facts.copyFields())
							if (field.isStatic && !field.isInline && field.hasStorage)
								fields.push(field);
				}
			}
		fields.sort((a, b) -> a.canonicalIdentity < b.canonicalIdentity ? -1 : a.canonicalIdentity > b.canonicalIdentity ? 1 : 0);
		for (index in 0...fields.length) {
			final key = fields[index].canonicalIdentity;
			if (slots.exists(key))
				throw "managed static storage repeats a declaration";
			slots.set(key, index);
		}
	}

	/** Only an exact enum owner and its declared singleton can select a startup slot. */
	public function singletonMember(owner:TypedBackendClassProjection, constructorIndex:Int):String {
		program.assertCurrent();
		if (program.requireClass(program.requireClassIdentity(owner.requireSemanticFacts().getClassIdentity())) != owner)
			throw "managed enum startup belongs to another program";
		for (constructor in owner.requireSemanticFacts().copyEnumConstructors())
			if (constructor.index == constructorIndex)
				switch constructor.member {
					case Singleton(field):
						final slot = slots.get(field.canonicalIdentity);
						if (slot != null)
							return "field_" + slot;
					case Callable(_):
				}
		throw "managed enum startup requires an allocated singleton field";
	}

	/** An equally named declaration from another program cannot borrow this storage inventory. */
	public function assertFunction(projection:TypedBackendFunctionProjection):Void {
		program.assertCurrent();
		for (module in program.getModules())
			for (owner in module.projection.getClasses())
				for (candidate in owner.getFunctions())
					if (candidate == projection)
						return;
		throw "managed static access belongs to another program";
	}

	/** Startup can use only an initializer retained in this exact program revision. */
	public function assertInitializer(projection:TypedBackendFieldInitializerProjection):Void {
		program.assertCurrent();
		projection.assertCurrent();
		for (module in program.getModules())
			for (owner in module.projection.getClasses())
				for (candidate in owner.getFieldInitializers())
					if (candidate == projection && candidate.getField().getIsStatic())
						return;
		throw "managed static initializer belongs to another program or an instance";
	}

	/**
		Select the storage slot and completed declaration type together. Inferred fields
		retain unknown header types, so initializer emission must use these published
		facts. Initial publication can assign a final field through its own initializer.
	 */
	public function initializerTarget(projection:TypedBackendFieldInitializerProjection):{member:String, type:TyType} {
		assertInitializer(projection);
		final field = projection.getField();
		final index = slots.get(field.getCanonicalKey());
		final fact = program.requireClass(program.requireClassIdentity(field.getOwner().getCanonicalName())).requireSemanticFacts().requireField(field);
		if (index == null || !fields[index].hasInitializer || fields[index].typeIdentity != fact.typeIdentity)
			throw "managed initializer has no exact static storage slot";
		return {member: "field_" + index, type: fact.semanticType};
	}

	/** Inline reads consume the declaration's initializer and never acquire a mutable static slot. */
	public function inlineInitializer(occurrence:TypedBackendFieldOccurrence):TypedBackendFieldInitializerProjection {
		program.assertCurrent();
		final field = occurrence.getField();
		program.requireFieldDeclaration(field);
		if (!field.getIsStatic() || !field.getIsInline() || occurrence.getReceiver() == ValueReceiver)
			throw "managed inline field requires an exact static declaration and effect-free qualifier";
		final owner = program.requireClass(program.requireClassIdentity(field.getOwner().getCanonicalName()));
		final fact = owner.requireSemanticFacts().requireField(field);
		if (fact.typeIdentity != occurrence.getType().getSemanticKey())
			throw "managed inline field type differs from its declaration";
		for (initializer in owner.getFieldInitializers())
			if (initializer.getField() == field) {
				assertInitializer(initializer);
				return initializer;
			}
		throw "managed inline field lacks its typed initializer";
	}

	/** Validate declaration facts before selecting a native slot; no source spelling selects an owner. */
	public function member(occurrence:TypedBackendFieldOccurrence, writing:Bool = false):String {
		program.assertCurrent();
		final field = occurrence.getField();
		program.requireFieldDeclaration(field);
		final index = slots.get(field.getCanonicalKey());
		if (!field.getIsStatic() || index == null || occurrence.getReceiver() == ValueReceiver)
			throw "managed static access requires an exact field and an effect-free qualifier";
		final fact = fields[index];
		final declared = program.requireClass(program.requireClassIdentity(field.getOwner().getCanonicalName())).requireSemanticFacts().requireField(field);
		if (fact.typeIdentity != declared.typeIdentity
			|| fact.typeIdentity != occurrence.getType().getSemanticKey()
			|| fact.isFinal != field.getIsFinal()
			|| fact.isInline != field.getIsInline()
			|| fact.isPublic != field.getIsPublic()
			|| fact.hasInitializer != field.getHasInitializer()
			|| fact.noImportGlobal != field.getNoImportGlobal()
			|| fact.constantIdentity != field.getConstant().getCanonicalIdentity()
			|| fact.propertyGet != field.getPropertyGet()
			|| fact.propertySet != field.getPropertySet()
			|| fact.hasStorage != field.getHasStorage())
			throw "managed static occurrence conflicts with its declaration";
		if (fact.semanticType.hasUnknownComponent() || fact.semanticType.isUnresolved())
			throw "managed static access requires a complete semantic type";
		final mode = writing ? fact.propertySet : fact.propertyGet;
		if ((writing && fact.isFinal) || (!occurrence.getHasPropertyStorageAccess() && mode != "" && mode != "default" && mode != "null"))
			throw "managed static access requires an explicit property or immutable-field binding";
		return "field_" + index;
	}

	/** Inline cells are ordinary traced edges, never registered roots inside a managed payload. */
	public function render():String {
		program.assertCurrent();
		final lines = hasStack ? ['#include "ManagedStack.hpp"'] : [];
		lines.push("struct " + nativeName + " {");
		if (hasStack)
			lines.push("  hxhx::managed::StackState stack;");
		for (index in 0...fields.length)
			lines.push("  hxhx::managed::CellPayload field_" + index + "{hxhx::managed::CellWriteMode::Replaceable};");
		lines.push("};");
		lines.push("namespace hxhx::managed { template<> struct Trace<" + nativeName + "> {");
		lines.push("  static void visit(const " + nativeName + "& value, Visitor& visitor) noexcept {");
		lines.push("    (void)value; (void)visitor;");
		for (index in 0...fields.length)
			lines.push("    value.field_" + index + ".trace(visitor);");
		lines.push("  }\n}; }");
		return lines.join("\n");
	}

	/** Each program's existing heap-owned storage isolates its synchronous stack context. */
	public function hasStackContext():Bool
		return hasStack;

	/** Each program's existing heap-owned storage isolates its synchronous stack context. */
	public function stackAccess(heap:String):String {
		program.assertCurrent();
		if (!hasStack || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(heap))
			throw "managed stack requires an admitted program context";
		return heap + ".requireStatic<" + nativeName + ">()->stack";
	}

	/** Only the caller's startup plan may decide when this allocation executes. */
	public function renderAllocation(heap:String, destination:String):String {
		if (!~/^[A-Za-z_][A-Za-z0-9_]*$/.match(heap) || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(destination))
			throw "managed static publication requires allocated native symbols";
		program.assertCurrent();
		return heap + ".allocateStaticInto(" + destination + ");";
	}

	/**
		Publish upstream C++ defaults before class startup methods can observe fields.
		Abstract defaults use exact substituted backing types. Float still requires
		its numeric contract; source display names never choose a representation.
	 */
	public function renderDefaults(destination:String):Array<String> {
		if (!~/^[A-Za-z_][A-Za-z0-9_]*$/.match(destination))
			throw "managed static defaults require an allocated destination symbol";
		program.assertCurrent();
		final lines = new Array<String>();
		for (index in 0...fields.length) {
			final value = try CppManagedStaticDefault.render(program, fields[index].semanticType) catch (failure:haxe.Exception) {
				throw new haxe.Exception("managed static default failed for " + fields[index].canonicalIdentity + ": " + failure.message, failure);
			};
			lines.push(destination + ".get()->field_" + index + ".write(" + value + ");");
		}
		return lines;
	}
}
