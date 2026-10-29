package backend.js;

/** Target-owned constructor data copied after exact enum declaration validation. */
typedef JsEnumConstructorPlan = {
	final index:Int;
	final name:String;

	/** Null denotes a singleton; a callable carries its declared payload field names. */
	final parameters:Null<Array<String>>;

	final optional:Array<Bool>;
};

/** Construct through one admitted enum member, preserving its declared payload order and omission rules. */
function construct(owner:JsClassInheritancePlan.JsClassInheritanceNode, name:String, arguments:Array<String>):String {
	if (owner == null || owner.enumConstructors == null)
		throw "JavaScript enum construction requires an exact enum provider";
	final matches = owner.enumConstructors.filter(constructor -> constructor.name == name);
	if (matches.length != 1)
		throw "JavaScript enum constructor is absent or ambiguous: " + owner.identity + "." + name;
	final constructor = matches[0];
	final reference = owner.reference + JsNameMangler.propertySuffix(name);
	if (constructor.parameters == null) {
		if (arguments.length != 0)
			throw "JavaScript singleton enum constructor cannot receive arguments";
		return reference;
	}
	if (arguments.length > constructor.parameters.length || constructor.optional.length != constructor.parameters.length)
		throw "JavaScript enum constructor argument count differs from its declaration";
	final supplied = arguments.copy();
	for (index in arguments.length...constructor.parameters.length) {
		if (!constructor.optional[index])
			throw "JavaScript enum constructor is missing a required argument: " + owner.identity + "." + name;
		supplied.push("null");
	}
	return reference + "(" + supplied.join(", ") + ")";
}

/**
	Emit the object layout consumed by the authored JavaScript Type provider.
	Constructor order and argument names come from the checked declaration. Singleton
	values are created with the declaration, before any user initializer can read them.
	This replaces the shared parser's provisional constructor bodies only for JavaScript.
 */
function emit(writer:JsWriter, input:{constructors:Array<JsEnumConstructorPlan>, reference:String, runtimeName:String}):Void {
	final reference = input.reference;
	final name = JsNameMangler.quoteString(input.runtimeName);
	writer.writeln("var " + reference + " = {__ename__: " + name + "};");
	writer.writeln("$hxEnums[" + name + "] = " + reference + ";");
	final constructors = new Array<String>();
	final empty = new Array<String>();
	for (constructor in input.constructors) {
		final member = reference + JsNameMangler.propertySuffix(constructor.name);
		final fields = ["__enum__: " + name, "_hx_index: " + constructor.index];
		switch (constructor.parameters) {
			case null:
				writer.writeln(member + " = {" + fields.join(", ") + "};");
				empty.push(member);
			case parameters:
				final arguments = [for (index in 0...parameters.length) "$arg" + index];
				for (index in 0...parameters.length)
					fields.push(JsNameMangler.quoteString(parameters[index]) + ": " + arguments[index]);
				writer.writeln(member + " = function(" + arguments.join(", ") + ") { return {" + fields.join(", ") + "}; };");
				writer.writeln(member + ".__params__ = [" + parameters.map(JsNameMangler.quoteString).join(", ") + "];");
		}
		writer.writeln(member + "._hx_name = " + JsNameMangler.quoteString(constructor.name) + ";");
		constructors.push(member);
	}
	writer.writeln(reference + ".__constructs__ = [" + constructors.join(", ") + "];");
	writer.writeln(reference + ".__empty_constructs__ = [" + empty.join(", ") + "];");
}
