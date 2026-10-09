package backend.cpp;

import backend.cpp.CppManagedSourceCall.CppManagedSourceCallInput;

/** Capture active frames or copy the last explicit Haxe throw snapshot. */
private enum NativeStackOperation {
	CallStack;
	ExceptionStack;
}

/** Bind the exact common stack-capture declaration to opaque managed snapshot storage. */
function owns(declaration:TyDeclarationInfo):Bool {
	return declaration != null
		&& declaration.getModulePath() == "haxe.NativeStackTrace"
		&& declaration.getOwner().getCanonicalName() == "haxe.NativeStackTrace"
		&& switch declaration.getIdentity().getCanonicalKey() {
			case "haxe.NativeStackTrace#static:callStack()->nominal:Any#0" | "haxe.NativeStackTrace#static:exceptionStack()->nominal:Any#0": true;
			case _: false;
		};
}

/** Narrow the checked declaration before selecting any native method spelling. */
private function operation(declaration:TyDeclarationInfo):NativeStackOperation {
	if (!owns(declaration))
		throw "managed stack capture requires the exact NativeStackTrace declaration";
	return switch declaration.getIdentity().getCanonicalKey() {
		case "haxe.NativeStackTrace#static:callStack()->nominal:Any#0": CallStack;
		case "haxe.NativeStackTrace#static:exceptionStack()->nominal:Any#0": ExceptionStack;
		case _: throw "managed stack capture has an unknown declaration";
	};
}

/** Mutable signature facts must still agree with the selected external declaration. */
function requireDeclaration(declaration:TyDeclarationInfo):Void {
	if (!owns(declaration))
		throw "managed stack capture requires the exact NativeStackTrace declaration";
	final signature = declaration.getSignature();
	final name = switch operation(declaration) {
		case CallStack: "callStack";
		case ExceptionStack: "exceptionStack";
	};
	if (!declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getHasBody()
		|| declaration.getTypeParameters().length != 0
		|| signature.getName() != name
		|| signature.getArgs().length != 0
		|| signature.getArgOptional().length != 0
		|| signature.getArgRest().length != 0
		|| signature.getReturnType().getSemanticKey() != "nominal:Any")
		throw "managed stack capture requires no parameters and the public Any result";
}

/** Capture before publishing; the ordinary managed root keeps the opaque result alive. */
function render(declaration:TyDeclarationInfo, storage:CppManagedStaticStorage, input:CppManagedSourceCallInput, indent:String):Array<String> {
	requireDeclaration(declaration);
	if (input.arguments.length != 0)
		throw "managed stack capture requires no operands";
	final snapshot = "hxhx_stack_" + input.prefix + "snapshot";
	final read = switch operation(declaration) {
		case CallStack: "capture";
		case ExceptionStack: "exceptionSnapshot";
	};
	final lines = [indent + "{",
		indent
		+ "  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::StackSnapshotPayload>> "
		+ snapshot
		+ "("
		+ input.heap
		+ ");",
		indent
		+ "  "
		+ input.heap
		+ ".allocateInto("
		+ snapshot
		+ ", "
		+ storage.stackAccess(input.heap)
		+ "."
		+ read
		+ "());"];
	if (input.destination != null)
		lines.push(indent + "  " + input.destination + ".set(hxhx::managed::Value::managed(" + snapshot + ".get()));");
	lines.push(indent + "}");
	return lines;
}
