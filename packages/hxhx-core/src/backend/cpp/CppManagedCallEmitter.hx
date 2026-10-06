package backend.cpp;

/** Setup statements publish a value before its native transport expression is consumed. */
typedef CppManagedCallArgument = {
	final setup:Array<String>;
	final value:String;
}

/** Already adapted operands: source defaults, rest arguments, and conversions precede this boundary. */
typedef CppManagedCallOperands = {
	final heap:String;
	final calleeSetup:Array<String>;
	final callee:String;
	final arguments:Array<CppManagedCallArgument>;

	/** Existing leaf variable or Root<Value>; absent only for Void calls. */
	final ?destination:String;

	/** Unique temporary prefix allocated by the enclosing target scope. */
	final temporaryPrefix:String;
}

/**
	Emit one call with explicit lifetime and left-to-right evaluation boundaries.
	The selected callable is rooted before any argument executes. Every managed
	argument gets a root before the next operand, and a managed result stays rooted
	until it reaches the caller's destination. Exceptions preserve that destination
	and unwind all call-local roots. This component does not discover source calls,
	adapt source arity, or allow an unrooted managed result to escape its block.
 */
class CppManagedCallEmitter {
	final plan:CppManagedStoragePlan;
	final closure:HxExpr;

	public function new(plan:CppManagedStoragePlan, closure:HxExpr) {
		if (plan == null || closure == null)
			throw "managed call requires an exact closure plan";
		this.plan = plan;
		this.closure = closure;
		plan.requireClosure(closure);
	}

	public function render(operands:CppManagedCallOperands):String {
		return renderAbi(plan.requireClosure(closure).abi, operands);
	}

	/** The typed caller owns signature selection; this shared emitter owns native sequencing. */
	public static function renderAbi(abi:CppManagedClosureAbi, operands:CppManagedCallOperands):String {
		if (abi == null)
			throw "managed call requires an exact typed ABI";
		if (abi.getHiddenParameters().contains(ReceiverValue) || abi.getHiddenParameters().contains(ReceiverCell))
			throw "managed instance invocation requires explicit receiver operands";
		final parameters = abi.getParameters();
		if (operands == null
			|| operands.calleeSetup == null
			|| operands.arguments == null
			|| operands.arguments.length != parameters.length)
			throw "managed call requires every adapted source argument";
		if (!identifier(operands.heap)
			|| !identifier(operands.temporaryPrefix)
			|| !StringTools.startsWith(operands.temporaryPrefix, "hxhx_call_"))
			throw "managed call requires stable heap and allocated temporary names";
		if (abi.result == NoResult ? operands.destination != null : !identifier(operands.destination))
			throw "managed call destination disagrees with its result storage";
		if (operands.callee == null || operands.callee.length == 0)
			throw "managed call requires a selected callable expression";
		final hasEnvironment = abi.getHiddenParameters().contains(EnvironmentPointer);
		if (!hasEnvironment && (!identifier(operands.callee) || operands.calleeSetup.length != 0))
			throw "managed static invocation requires an allocated entry without runtime callee setup";
		final prefix = operands.temporaryPrefix;
		final lines = ["{"];
		for (line in operands.calleeSetup)
			lines.push("  " + line);
		if (hasEnvironment)
			lines.push("  hxhx::managed::ActiveCall<"
				+ abi.nativeSignature()
				+ "> "
				+ prefix
				+ "selected("
				+ operands.heap
				+ ", ("
				+ operands.callee
				+ "));");
		final arguments = new Array<String>();
		for (parameter in parameters) {
			final argument = operands.arguments[parameter.slot];
			if (argument == null || argument.setup == null || argument.value == null || argument.value.length == 0)
				throw "managed call requires a rendered argument expression";
			for (line in argument.setup)
				lines.push("  " + line);
			final expression = argument.value;
			final name = prefix + "arg" + parameter.slot;
			if (parameter.storage == RootedParameter) {
				lines.push("  hxhx::managed::Root<hxhx::managed::Value> " + name + "(" + operands.heap + ", (" + expression + "));");
				arguments.push(name + ".get()");
			} else {
				lines.push("  const auto " + name + " = (" + expression + ");");
				arguments.push(name);
			}
		}
		if (abi.result == RootedResult) {
			lines.push("  hxhx::managed::Root<hxhx::managed::Value> " + prefix + "result(" + operands.heap + ");");
			arguments.unshift(prefix + "result");
		}
		final invocation = hasEnvironment ? prefix + "selected.invoke(" + arguments.join(", ") + ")" : operands.callee
			+ "("
			+ [operands.heap].concat(arguments).join(", ") + ")";
		switch abi.result {
			case NoResult:
				lines.push("  " + invocation + ";");
			case DirectResult:
				lines.push("  " + operands.destination + " = " + invocation + ";");
			case RootedResult:
				lines.push("  " + invocation + ";");
				lines.push("  " + operands.destination + ".set(" + prefix + "result.get());");
		}
		lines.push("}");
		return lines.join("\n");
	}

	static function identifier(value:Null<String>):Bool
		return value != null && ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(value);
}
