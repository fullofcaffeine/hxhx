package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlModuleAssembly.OcamlModulePart;
import reflaxe.ocaml.ast.OcamlModuleGroups;
import reflaxe.ocaml.ast.OcamlFreeValues.collect;

private typedef ValueDeclaration = {
	final key:String;
	final ordinal:Int;
	final region:Int;
	final header:String;
	final bindings:Array<OcamlLetBinding>;
	final recursive:Bool;
	final functionsOnly:Bool;
	final dependencies:Map<String, Bool>;
}

private enum DeclarationEntry {
	Value(node:ValueDeclaration);
	Fixed(part:OcamlModulePart);
}

/**
	Orders same-module values while retaining initializer execution order.

	Class chunks can refer to functions in later chunks. Their structured free
	value names select dependencies before printing. Function-only cycles become
	one recursive binding group. Non-function declarations keep their relative
	order, and types or opaque text remain barriers. A cycle through an initializer
	cannot be repaired by changing its effects and is rejected.
	Already valid declaration order returns the original parts unchanged.
**/
function order(moduleName:String, parts:Array<OcamlModulePart>):Array<OcamlModulePart> {
	final entries:Array<DeclarationEntry> = [];
	final nodes:Array<ValueDeclaration> = [];
	final owners:Map<String, Array<ValueDeclaration>> = [];
	var region = 0;
	for (part in parts) {
		switch (part) {
			case OpaqueModuleText(_):
				entries.push(Fixed(part));
				region++;
			case ModuleDeclarations(header, items):
				if (items.length == 0) {
					entries.push(Fixed(part));
					region++;
				}
				for (item in items) {
					switch (item) {
						case IType(_, _):
							entries.push(Fixed(ModuleDeclarations(header, [item])));
							region++;
						case ILet(bindings, recursive):
							final node:ValueDeclaration = {
								key: StringTools.lpad(Std.string(nodes.length), "0", 10),
								ordinal: nodes.length,
								region: region,
								header: header,
								bindings: bindings,
								recursive: recursive,
								functionsOnly: bindings.length > 0 && bindings.filter(binding -> !isFunction(binding.expr)).length == 0,
								dependencies: []
							};
							nodes.push(node);
							entries.push(Value(node));
							for (binding in bindings) {
								var declarations = owners.get(binding.name);
								if (declarations == null) {
									declarations = [];
									owners.set(binding.name, declarations);
								}
								declarations.push(node);
							}
					}
				}
		}
	}
	final wanted:Map<String, Bool> = [for (name in owners.keys()) name => true];
	final shadowed:Map<String, Bool> = [];
	var needsOrder = false;
	var crossedBarrier = false;
	for (node in nodes) {
		for (binding in node.bindings) {
			for (name in collect(binding.expr, wanted).keys()) {
				final declarations = owners.get(name);
				if (declarations == null)
					throw "Missing local value owner: " + name;
				if (declarations.length != 1) {
					shadowed.set(name, true);
					continue;
				}
				final owner = declarations[0];
				if (owner == node && node.recursive)
					continue;
				if (owner.ordinal >= node.ordinal) {
					needsOrder = true;
					if (owner.region != node.region)
						crossedBarrier = true;
				}
				if (owner.region == node.region)
					node.dependencies.set(owner.key, true);
			}
		}
	}
	if (!needsOrder)
		return parts;
	if (crossedBarrier)
		fail(moduleName, "declaration-barrier", "a forward value dependency crosses a type or opaque declaration");
	var opaqueValue = false;
	for (node in nodes)
		for (binding in node.bindings)
			OcamlASTTraversal.walkExprPre(binding.expr, expression -> switch (expression) {
				case ERawInjection(_): opaqueValue = true;
				case _:
			}, _ -> {}, _ -> {});
	if (opaqueValue)
		fail(moduleName, "opaque-value-dependency", "raw target text cannot provide complete local value dependencies");
	final ambiguous = [for (name in shadowed.keys()) name];
	ambiguous.sort(compare);
	if (ambiguous.length > 0)
		fail(moduleName, "shadowed-owner", ambiguous.join(", "));

	final output:Array<OcamlModulePart> = [];
	var pending:Array<ValueDeclaration> = [];
	function flush():Void {
		if (pending.length > 0) {
			for (part in orderRegion(moduleName, pending))
				output.push(part);
			pending = [];
		}
	}
	for (entry in entries)
		switch (entry) {
			case Value(node):
				pending.push(node);
			case Fixed(part):
				flush();
				output.push(part);
		}
	flush();
	return output;
}

/** Adds initializer-order constraints, then emits stable dependency-first groups. */
private function orderRegion(moduleName:String, nodes:Array<ValueDeclaration>):Array<OcamlModulePart> {
	final byKey:Map<String, ValueDeclaration> = [for (node in nodes) node.key => node];
	var previousInitializer:Null<String> = null;
	for (node in nodes)
		if (!node.functionsOnly) {
			if (previousInitializer != null)
				node.dependencies.set(previousInitializer, true);
			previousInitializer = node.key;
		}
	final groups = OcamlModuleGroups.plan([
		for (node in nodes)
			{name: node.key, dependencies: [for (key in node.dependencies.keys()) key]}
	]).groups;
	final groupByKey:Map<String, Int> = [];
	for (index in 0...groups.length)
		for (key in groups[index].members)
			groupByKey.set(key, index);
	final users:Array<Map<Int, Bool>> = [for (_ in groups) []];
	final remaining = [for (_ in groups) 0];
	for (node in nodes) {
		final user = groupByKey.get(node.key);
		for (key in node.dependencies.keys()) {
			final dependency = groupByKey.get(key);
			if (dependency != user && !users[dependency].exists(user)) {
				users[dependency].set(user, true);
				remaining[user]++;
			}
		}
	}
	final ready = [for (index in 0...groups.length) if (remaining[index] == 0) index];
	final output:Array<OcamlModulePart> = [];
	var currentHeader:Null<String> = null;
	var currentItems:Array<OcamlModuleItem> = [];
	while (ready.length > 0) {
		ready.sort((left, right) -> compare(groups[left].members[0], groups[right].members[0]));
		final index = ready.shift();
		final group = groups[index];
		final members = group.members.map(key -> byKey.get(key));
		if (group.recursive && members.filter(node -> !node.functionsOnly).length > 0)
			fail(moduleName, "initializer-cycle", [for (node in members) for (binding in node.bindings) binding.name].join(", "));
		final headers:Array<String> = [];
		final bindings:Array<OcamlLetBinding> = [];
		for (node in members) {
			if (node.header.length > 0 && headers.indexOf(node.header) < 0)
				headers.push(node.header);
			for (binding in node.bindings)
				bindings.push(binding);
		}
		final header = headers.join("\n");
		if (currentHeader != header) {
			currentHeader = header;
			currentItems = [];
			output.push(ModuleDeclarations(header, currentItems));
		}
		currentItems.push(ILet(bindings, group.recursive || members[0].recursive));
		for (user in users[index].keys()) {
			remaining[user]--;
			if (remaining[user] == 0)
				ready.push(user);
		}
	}
	return output;
}

private function isFunction(expression:OcamlExpr):Bool {
	return switch (expression) {
		case EFun(_, _): true;
		case EAnnot(inner, _), EPos(_, inner): isFunction(inner);
		case _: false;
	}
}

private function compare(left:String, right:String):Int {
	return left < right ? -1 : left > right ? 1 : 0;
}

private function fail(moduleName:String, code:String, detail:String):Void {
	throw 'reflaxe.ocaml [ocaml-module-values:$code]: $moduleName: $detail';
}
