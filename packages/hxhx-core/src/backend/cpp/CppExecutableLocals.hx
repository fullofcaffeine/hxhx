package backend.cpp;

import haxe.ds.StringMap;

/** The declaration whose sealed catalogs authorize this executable's local reads. */
enum CppExecutableOwner {
	FunctionBody(projection:TypedBackendFunctionProjection);
	FieldInitializer(projection:TypedBackendFieldInitializerProjection);
}

/**
	Assigns one C++ symbol to each exact local in a function or field initializer.

	Shared projection gives each binding a unique transport name within its body.
	That raw name selects the binding; escaping it only chooses an output symbol.
	Planning finishes before rendering, so repeated symbol lookups cannot
	change names. Representation facts and movable target helpers belong to later
	rendering scopes, not this immutable authored-local inventory.
**/
@:allow(backend.cpp.CppTypedProgramProjection)
class CppExecutableLocals {
	final owner:CppExecutableOwner;
	final stableIdentity:String;
	final bodyRevision:String;
	final catalog:TypedBackendLocalCatalog;
	final fields:TypedBackendFieldReadCatalog;
	final parameters:Array<TypedBackendLocalProjection>;
	final symbols = new StringMap<String>();
	final occupied = new StringMap<Bool>();

	function new(owner:CppExecutableOwner, fixedSymbols:Array<String>) {
		this.owner = owner;
		switch (owner) {
			case FunctionBody(projection):
				stableIdentity = projection.getStableIdentity();
				bodyRevision = projection.getBodyRevision();
				catalog = projection.getLocalCatalog();
				fields = projection.getFieldReadCatalog();
				parameters = projection.getParameters();
			case FieldInitializer(projection):
				stableIdentity = projection.getStableIdentity();
				bodyRevision = projection.getBodyRevision();
				catalog = projection.getLocalCatalog();
				fields = projection.getFieldReadCatalog();
				parameters = [];
		}
		if (fixedSymbols != null)
			for (symbol in fixedSymbols) {
				if (symbol == null || symbol.length == 0 || candidate(symbol) != symbol)
					throw "C++ local plan requires a valid fixed environment symbol";
				occupied.set(symbol, true);
			}
		// Reserve every unchanged spelling before a keyword can consume its suffix.
		final entries = catalog.getEntries();
		for (local in entries) {
			final name = local.getProjectedName();
			if (candidate(name) == name && !occupied.exists(name)) {
				symbols.set(name, name);
				occupied.set(name, true);
			}
		}
		for (local in entries) {
			final name = local.getProjectedName();
			if (symbols.exists(name))
				continue;
			final base = candidate(name);
			var symbol = base;
			var suffix = 1;
			while (occupied.exists(symbol)) {
				suffix++;
				symbol = base + "_" + suffix;
			}
			symbols.set(name, symbol);
			occupied.set(symbol, true);
		}
	}

	public function getStableIdentity():String
		return stableIdentity;

	public function getBodyRevision():String
		return bodyRevision;

	/** Runtime operations retain the same function or initializer owner as this local-symbol plan. */
	public function requireRuntimeType(expression:HxExpr):TypedBackendRuntimeTypeOccurrence {
		return switch owner {
			case FunctionBody(projection): projection.requireRuntimeType(expression);
			case FieldInitializer(projection): projection.requireRuntimeType(expression);
		};
	}

	/** Construction facts must come from the same current executable as its runtime test. */
	public function requireConstructor(expression:HxExpr):TypedBackendConstructorOccurrence {
		return switch owner {
			case FunctionBody(projection): projection.requireConstructor(expression);
			case FieldInitializer(projection): projection.requireConstructor(expression);
		};
	}

	/** Include fixed environment symbols so temporary allocation cannot shadow them. */
	public function getOccupiedSymbols():Array<String>
		return [for (symbol in occupied.keys()) symbol];

	public function getFieldReadCatalog():TypedBackendFieldReadCatalog
		return fields;

	/** Parameters retain signature order, independent of catalog identity sorting. */
	public function getParameters():Array<TypedBackendLocalProjection>
		return parameters.copy();

	/** Signature ownership follows the exact projected declaration, not its parameter spelling. */
	public function ownsArgument(argument:HxFunctionArg):Bool {
		return switch (owner) {
			case FunctionBody(projection): HxFunctionDecl.getArgs(projection.getDeclaration()).indexOf(argument) >= 0;
			case FieldInitializer(_): false;
		};
	}

	public function requireFunction():TypedBackendFunctionProjection {
		return switch (owner) {
			case FunctionBody(projection): projection;
			case FieldInitializer(_): throw "C++ initializer locals cannot authorize a function";
		};
	}

	public function requireInitializer():TypedBackendFieldInitializerProjection {
		return switch (owner) {
			case FieldInitializer(projection): projection;
			case FunctionBody(_): throw "C++ function locals cannot authorize an initializer";
		};
	}

	/** A miss is not permission to infer a field or synthetic binding from spelling. */
	public function findLocal(transportName:String):Null<TypedBackendLocalProjection>
		return catalog.findByProjectedName(transportName);

	/** Require the exact identity object held by this executable's sealed catalog. */
	public function requireIdentity(identity:TyLocalId):TypedBackendLocalProjection {
		final local = identity == null ? null : catalog.findByIdentity(identity.getCanonicalKey());
		if (local == null || local.getBinding().getIdentity() != identity)
			throw "C++ local identity belongs to another executable catalog";
		return local;
	}

	public function symbol(transportName:String):String {
		final symbol = transportName == null ? null : symbols.get(transportName);
		if (symbol == null)
			throw "C++ local plan cannot find transport name " + transportName;
		return symbol;
	}

	/** Escaping chooses a candidate only; it never selects a source binding. */
	static function candidate(name:String):String {
		final buffer = new StringBuf();
		for (index in 0...name.length) {
			final character = name.charAt(index);
			final valid = (character >= "a" && character <= "z")
				|| (character >= "A" && character <= "Z")
				|| character == "_"
				|| (index > 0 && character >= "0" && character <= "9");
			buffer.add(valid ? character : "_");
		}
		final escaped = buffer.toString();
		return switch (escaped) {
			case "alignas" | "alignof" | "and" | "and_eq" | "asm" | "auto" | "bitand" | "bitor" | "bool" | "break" | "case" | "catch" | "char" | "char16_t" |
				"char32_t" | "class" | "compl" | "const" | "constexpr" | "const_cast" | "continue" | "decltype" | "default" | "delete" | "do" | "double" |
				"dynamic_cast" | "else" | "enum" | "explicit" | "export" | "extern" | "false" | "float" | "for" | "friend" | "goto" | "if" | "inline" |
				"int" | "long" | "mutable" | "namespace" | "new" | "noexcept" | "not" | "not_eq" | "nullptr" | "operator" | "or" | "or_eq" | "private" |
				"protected" | "public" | "register" | "reinterpret_cast" | "return" | "short" | "signed" | "sizeof" | "static" | "static_assert" |
				"static_cast" | "std" | "struct" | "switch" | "template" | "this" | "thread_local" | "throw" | "true" | "try" | "typedef" | "typeid" |
				"typename" | "union" | "unsigned" | "using" | "virtual" | "void" | "volatile" | "wchar_t" | "while" | "xor" | "xor_eq":
				escaped
				+ "_";
			case _: escaped;
		};
	}
}
