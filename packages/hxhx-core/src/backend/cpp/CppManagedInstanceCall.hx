package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;
import backend.cpp.CppManagedInstanceMethod.CppManagedInstanceMethodTarget;

/**
	Evaluate the receiver once, then root arguments in source order. Each selected
	override uses its own native signature: generic values can retain null while
	a concrete implementation uses direct scalars. Convert rooted copies at that
	boundary without repeating source effects or changing the original arguments.
 */
function render(input:{
	call:TypedBackendInstanceCallOccurrence,
	context:Null<CppManagedEnclosingApplication>,
	target:CppManagedInstanceMethodTarget,
	?superReceiver:String,
	classes:CppManagedClassStorage,
	heap:String,
	prefix:String,
	destination:Null<String>,
	acceptsStoredTransfer:(HxExpr, TyType) -> Bool,
	valueType:HxExpr->TyType,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	final projection = input.classes.methods.requireInstanceMethod(input.call, input.context);
	final application = input.classes.methods.instanceApplication(input.call, input.context);
	if (input.target == null || input.target.projection != projection || input.target.application.identity != application.identity)
		throw 'managed instance call resolved another method entry';
	input.target.application.assertCurrent();
	final expectedDispatch = input.classes.methods.instanceDispatch(input.call, input.context);
	final dispatch = input.target.dispatch;
	final direct = input.target.entry;
	if (projection.requireSemanticDeclaration().getHasBody() != (direct != null)
		|| (direct != null && (direct.projection != projection || direct.application.identity != application.identity)))
		throw "managed call contract changed its direct implementation";
	if ((expectedDispatch == null) != (dispatch == null) || (dispatch != null && expectedDispatch.length != dispatch.length))
		throw "managed instance dispatch differs from its reachable allocations";
	if (dispatch != null)
		for (index in 0...dispatch.length) {
			final entry = dispatch[index];
			final expected = expectedDispatch[index];
			entry.target.application.assertCurrent();
			if (entry.descriptor != expected.descriptor
				|| entry.target.application.identity != expected.application.identity
				|| entry.target.projection != expected.application.projection)
				throw "managed instance dispatch selected a foreign implementation";
		}
	// Caller transport depends on the signature, even when the declaration has
	// no body. Concrete implementations retain their own full storage plans.
	final abi = new CppManagedClosureAbi(CppManagedFunctionSignature.resolve(projection, application.resolveStorageType), false, ReceiverValue);
	if (!abi.getHiddenParameters().contains(ReceiverValue))
		throw 'managed method call requires value receiver transport';
	if (abi.result == NoResult && input.destination != null)
		throw 'Void managed instance call cannot publish a value';
	final receiver = input.prefix + 'receiver';
	final returned = input.prefix + 'returned';
	final call = input.call.getCall();
	final lines = [
		indent + '{',
		indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + receiver + '(' + input.heap + ');'
	];
	if (call.receiver.match(ESuper)) {
		if (input.superReceiver == null)
			throw "super method lacks its validated enclosing receiver";
		lines.push(indent + '  ' + receiver + '.set(' + input.superReceiver + ');');
	} else {
		if (input.superReceiver != null)
			throw "ordinary call cannot borrow a super receiver";
		for (line in input.renderValue(call.receiver, receiver, indent + '  '))
			lines.push(line);
	}
	if (dispatch == null && direct == null)
		throw "managed call contract lacks an executable target";
	final targets = dispatch == null ? [direct] : [for (entry in dispatch) entry.target];
	for (target in targets)
		if (!target.projection.requireSemanticDeclaration().getHasBody() || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(target.symbol))
			throw "managed instance call requires a concrete native entry";
	final nativeAbis = [
		for (target in targets)
			target.application.identity == application.identity ? abi : new CppManagedStoragePlan(target.projection, input.classes,
				target.application).requireFunction(Root(target.projection)).abi
	];
	final roots = new Array<String>();
	final declared = abi.signature.getFunctionParameters();
	if (nativeAbis.filter(selected -> selected.result == RootedResult).length != 0)
		lines.push(indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + returned + '(' + input.heap + ');');
	for (parameter in abi.getParameters()) {
		final expression = parameter.slot < call.arguments.length ? call.arguments[parameter.slot] : null;
		final acceptedType = declared[parameter.slot].isOptional
			&& !parameter.type.isNullable() ? TyType.nullable(parameter.type) : parameter.type;
		if (expression != null
			&& !input.acceptsStoredTransfer(expression, acceptedType)
			&& !CppManagedValueTransfer.needsConversion(acceptedType, input.valueType(expression), input.classes.casts))
			throw 'managed instance argument requires an explicit typed conversion';
		final root = input.prefix + 'argument' + parameter.slot;
		lines.push(indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + root + '(' + input.heap + ');');
		// Keep omitted optional values null until the authored method applies its defaults.
		if (expression != null) {
			for (line in input.renderValue(expression, root, indent + '  '))
				lines.push(line);
			for (line in CppManagedValueTransfer.convertRoot(acceptedType, input.valueType(expression), root, indent + '  ', input.classes.casts))
				lines.push(line);
		}
		roots.push(root);
	}
	// Source operands are already rooted. Only the chosen implementation may
	// convert their copies or choose a direct versus caller-rooted result.
	function invoke(index:Int, callIndent:String):Void {
		final target = targets[index];
		final nativeAbi = nativeAbis[index];
		final parameters = nativeAbi.getParameters();
		final nativeDeclared = nativeAbi.signature.getFunctionParameters();
		if (parameters.length != roots.length || (nativeAbi.result == NoResult) != (abi.result == NoResult))
			throw "managed override changed its source arity or Void result";
		final arguments = [input.heap, receiver + '.get()'];
		if (nativeAbi.result == RootedResult)
			arguments.push(returned);
		for (parameter in parameters) {
			final slot = parameter.slot;
			final source = declared[slot].isOptional
				&& !declared[slot].type.isNullable() ? TyType.nullable(declared[slot].type) : declared[slot].type;
			final accepted = nativeDeclared[slot].isOptional
				&& !parameter.type.isNullable() ? TyType.nullable(parameter.type) : parameter.type;
			if (!CppManagedValueTransfer.supports(accepted, source, input.classes.casts))
				throw "managed override argument requires an explicit storage adaptation";
			var root = roots[slot];
			if (CppManagedValueTransfer.needsConversion(accepted, source, input.classes.casts)) {
				root = input.prefix + "override_argument" + slot;
				lines.push(callIndent + "hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ", " + roots[slot] + ".get());");
				for (line in CppManagedValueTransfer.convertRoot(accepted, source, root, callIndent, input.classes.casts))
					lines.push(line);
			}
			arguments.push(parameter.storage == RootedParameter ? root + ".get()" : CppManagedLeaf.read(parameter.type, root + ".get()"));
		}
		final produced = nativeAbi.signature.getFunctionReturn();
		final expected = abi.signature.getFunctionReturn();
		if (input.destination != null && !CppManagedValueTransfer.supports(expected, produced, input.classes.casts))
			throw "managed override result requires an explicit storage adaptation";
		final invocation = target.symbol + '(' + arguments.join(', ') + ')';
		if (nativeAbi.result == DirectResult && input.destination != null)
			lines.push(callIndent + input.destination + '.set(' + CppManagedLeaf.box(produced, invocation) + ');');
		else {
			lines.push(callIndent + invocation + ';');
			if (nativeAbi.result == RootedResult && input.destination != null)
				lines.push(callIndent + input.destination + '.set(' + returned + '.get());');
		}
		if (input.destination != null)
			for (line in CppManagedValueTransfer.convertRoot(expected, produced, input.destination, callIndent, input.classes.casts))
				lines.push(line);
	}
	if (dispatch == null)
		invoke(0, indent + '  ');
	else if (dispatch.length == 0)
		lines.push(indent + '  throw std::invalid_argument("managed call has no reachable receiver allocation");');
	else {
		final descriptor = input.prefix + 'descriptor';
		lines.push(indent
			+ '  const auto* '
			+ descriptor
			+ ' = &'
			+ receiver
			+ '.get().asManaged().as<hxhx::managed::InstancePayload>()->instanceDescriptor();');
		for (index in 0...dispatch.length) {
			final entry = dispatch[index];
			lines.push(indent + '  ' + (index == 0 ? 'if' : 'else if') + ' (' + descriptor + ' == &' + entry.descriptor + ') {');
			invoke(index, indent + '    ');
			lines.push(indent + '  }');
		}
		lines.push(indent + '  else { throw std::invalid_argument("managed call received an unplanned receiver descriptor"); }');
	}
	lines.push(indent + '}');
	return lines;
}
