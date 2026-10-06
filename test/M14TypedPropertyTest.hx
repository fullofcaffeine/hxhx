/** Shared property selection must precede emission and retain exact declaration and storage facts. */
class M14TypedPropertyTest {
	static function typed(source:String):TypedModule {
		final path = "Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function reject(source:String, message:String):Void {
		try {
			typed(source);
		} catch (error:TyperError) {
			if (error.message.indexOf(message) < 0)
				throw error;
			return;
		}
		throw "shared property typing accepted invalid access: " + message;
	}

	static function main():Void {
		final source = sys.io.File.getContent("test/oracle/cpp_property_accessor_seed/Main.hx");
		final module = typed(source);
		var getterCalls = 0;
		var setterCalls = 0;
		function visit(expression:TypedExpr):Void {
			final declaration = expression.getDeclaration();
			if (expression.getTag() == Call && declaration != null) {
				final name = declaration.getSignature().getName();
				if (StringTools.startsWith(name, "get_"))
					getterCalls++;
				if (StringTools.startsWith(name, "set_"))
					setterCalls++;
			}
			final field = expression.getFieldInfo();
			if (field != null && (field.getPropertyGet() == "get" || field.getPropertySet() == "set")) {
				if (!field.getHasStorage() || !expression.getHasPropertyStorageAccess())
					throw "an unlowered property survived into the shared executable body";
			}
			for (child in expression.getExpressions())
				visit(child);
		}
		function statement(value:TypedStmt):Void {
			for (expression in value.getExpressions())
				visit(expression);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in module.getTypedClasses()) {
			final facts = owner.getSemanticInfo();
			for (field in facts.getFieldInfos()) {
				final expected = facts.getShortName() == "Stored"
					|| (field.getName() != "value" && field.getName() != "readOnly" && field.getName() != "global");
				if (field.getHasStorage() != expected)
					throw "property storage does not match its authored declaration: " + field.getCanonicalKey();
			}
			for (fn in owner.getFunctions())
				for (stmt in fn.getBody().getStatements())
					statement(stmt);
		}
		if (getterCalls < 10 || setterCalls < 8)
			throw "property calls were not retained in the shared body";
		reject("class Main { public var value(get,never):Int; public function new() {} function get_value():Int { return 7; } static function main() { new Main().value=4; } }",
			"cannot be accessed for writing");
		reject("class Main { public var value(get,set):Int; public function new() {} function get_value():Int { return value; } function set_value(v:Int):Int { return v; } static function main() {} }",
			"has no real backing variable");
		reject("class Main { static function main() { var value = new Other().hidden; } } class Other { public var hidden(null,default):Int; public function new() {} }",
			"cannot be accessed for reading");
		reject("class Main { public var value(get,set):Int; public function new() {} function get_value():Int { return 7; } function set_value(v:Int):Int { return v; } static function main() { final m=new Main(); (m.value)=4; } }",
			"Invalid assign");
		final generic = typed("class Main { static function read(box:Box<Int>):Int { return box.value; } static function main() {} } class Box<T> { var stored:T; public var value(get,never):T; public function new(value:T) { stored=value; } function get_value():T { return stored; } }");
		var appliedGetter = false;
		for (owner in generic.getTypedClasses())
			for (fn in owner.getFunctions())
				if (fn.getDeclaration().getSignature().getName() == "read")
					for (stmt in fn.getBody().getStatements())
						for (expression in stmt.getExpressions())
							if (expression.getTag() == Call
								&& expression.getDeclaration() != null
								&& expression.getDeclaration().getOwner().getCanonicalName() == "Main.Box"
								&& expression.getType().getSemanticKey() == "primitive:Int")
								appliedGetter = true;
		if (!appliedGetter)
			throw "generic property lost its applied result or exact accessor owner";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final deferred = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]), null, true);
		var rejectedForeign = false;
		try {
			TypedPropertyLowering.lowerClasses(deferred.getTypedClasses(), TyperIndex.build([resolved]), "Main.hx");
		} catch (error:TyperError) {
			if (error.message.indexOf("another declaration index") < 0)
				throw error;
			rejectedForeign = true;
		}
		if (!rejectedForeign)
			throw "property lowering borrowed a field from an independent declaration index";
		Sys.println("TYPED_PROPERTY:PASS");
	}
}
