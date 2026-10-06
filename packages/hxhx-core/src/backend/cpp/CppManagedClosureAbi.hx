package backend.cpp;

/** Leaf values can return directly; a managed result must reach a caller-owned root. */
enum CppManagedResultStorage {
	NoResult;
	DirectResult;
	RootedResult;
}

/** Rooted parameters require registration before the callee's first collecting operation. */
enum CppManagedParameterStorage {
	DirectParameter;
	RootedParameter;
}

/** Target operands are separate from source arity and source default arguments. */
enum CppManagedHiddenParameter {
	HeapContext;
	EnvironmentPointer;
	ReceiverValue;
	ReceiverCell;
	ResultRoot;
}

/** Exact source slot and semantic type remain available to later physical layout selection. */
typedef CppManagedParameter = {
	final slot:Int;
	final type:TyType;
	final storage:CppManagedParameterStorage;
}

/**
	Plan root obligations for one typed closure signature before rendering C++.

	Direct declarations retain scalar transport. Function values transport Int and
	Bool through common roots so generic aliases preserve null and identity without
	allocating adapters. Concrete parameter entry applies scalar conversion. Float
	transport is unchanged. Optional parameters use
	common values so omission and explicit null survive until function entry. String uses common rooted storage
	to preserve null separately from empty text. Other complete types also use
	rooted transport, including nullable leaves,
	generic values, and returned functions. This does not perform numeric coercion
	or select a nominal object's physical layout. Incomplete types fail instead of
	implicitly becoming pointer-free. The caller must root the selected function
	before argument effects and root managed argument temporaries between effects.
	Concrete native signatures must also preserve source optional/rest conventions.
 */
class CppManagedClosureAbi {
	public final signature:TyType;
	public final result:CppManagedResultStorage;

	final parameters:Array<CppManagedParameter> = [];
	final hiddenParameters:Array<CppManagedHiddenParameter> = [HeapContext];

	/** Instance roots add a receiver before result/source operands; closures retain it through their environment. */
	public function new(signature:TyType, hasEnvironment:Bool = true, ?receiver:CppManagedHiddenParameter) {
		if (signature == null || !signature.isFunction())
			throw "managed closure ABI requires a typed function";
		assertComplete(signature);
		this.signature = signature;
		if (receiver != null && receiver != ReceiverValue && receiver != ReceiverCell)
			throw 'managed receiver requires an explicit value or cell operand';
		if (hasEnvironment && receiver != null)
			throw "managed closure receiver must travel through its environment";
		if (hasEnvironment)
			hiddenParameters.push(EnvironmentPointer);
		if (receiver != null)
			hiddenParameters.push(receiver);
		final returned = signature.getFunctionReturn();
		if (returned == null)
			throw "managed closure ABI lacks its result type";
		result = returned.isVoid() ? NoResult : isLeaf(returned)
			&& !(hasEnvironment && CppManagedCallableRepresentation.scalar(returned)) ? DirectResult : RootedResult;
		if (result == RootedResult)
			hiddenParameters.push(ResultRoot);
		final args = signature.getFunctionArguments();
		final declared = signature.getFunctionParameters();
		for (slot in 0...args.length) {
			final type = args[slot];
			if (type.isVoid())
				throw "managed closure ABI cannot transport a Void source argument";
			parameters.push({
				slot: slot,
				type: type,
				storage: isLeaf(type)
				&& !declared[slot].isOptional
				&& !(hasEnvironment && CppManagedCallableRepresentation.scalar(type)) ? DirectParameter : RootedParameter});
		}
	}

	/** Semantic keys identify primitives; source display names cannot establish leaf storage. */
	static function isLeaf(type:TyType):Bool {
		return switch type.getSemanticKey() {
			case "primitive:Bool" | "primitive:Int" | "primitive:Float": true;
			case _: false;
		};
	}

	/** Common-value storage and callable transport both require complete nested semantic types. */
	public static function assertComplete(type:TyType):Void {
		if (type.isUnknown() || type.isUnresolved() || type.isNoNormalCompletion())
			throw "managed closure ABI requires complete semantic types";
		if (type.getNullableInner() != null)
			assertComplete(type.getNullableInner());
		if (type.isFunction()) {
			if (type.getFunctionReturn() == null)
				throw "managed closure ABI lacks its result type";
			assertComplete(type.getFunctionReturn());
		}
		for (part in type.getTypeArguments().concat(type.getFunctionArguments()).concat(type.getAnonymousFieldTypes()))
			assertComplete(part);
	}

	public function getParameters():Array<CppManagedParameter>
		return parameters.copy();

	public function getHiddenParameters():Array<CppManagedHiddenParameter>
		return hiddenParameters.copy();

	/**
		Type argument for the native callable payload. The runtime template prepends
		heap and environment operands; the rooted result, when present, precedes all
		source arguments here. Source optional/default handling remains a call-plan duty.
	 */
	public function nativeSignature():String {
		if (hiddenParameters.contains(ReceiverValue) || hiddenParameters.contains(ReceiverCell))
			throw "managed instance entry is not a closure callable signature";
		final args = new Array<String>();
		if (result == RootedResult)
			args.push("hxhx::managed::Root<hxhx::managed::Value>&");
		for (parameter in parameters)
			args.push(parameter.storage == RootedParameter ? "hxhx::managed::Value" : nativeLeaf(parameter.type));
		return nativeReturnType() + "(" + args.join(", ") + ")";
	}

	/** Managed source results use a caller-owned root and therefore a native Void return. */
	public function nativeReturnType():String
		return result == DirectResult ? nativeLeaf(signature.getFunctionReturn()) : "void";

	/** Reject any mismatch between a direct transport decision and its concrete C++ type. */
	static function nativeLeaf(type:TyType):String {
		return CppManagedLeaf.nativeType(type);
	}
}
