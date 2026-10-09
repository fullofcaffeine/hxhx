package reflaxe.ocaml.ast;

/** A caller-owned compilation unit and the qualified modules its declarations use. */
typedef OcamlModuleDependencyNode = {
	final name:String;
	final dependencies:Array<String>;
}

/** Mutually reachable units; recursion still requires signatures and initialization checks. */
typedef OcamlModuleDependencyGroup = {
	final members:Array<String>;
	final recursive:Bool;
}

/** Unknown names stay visible for the caller to resolve against other artifact owners. */
typedef OcamlModuleDependencyPlan = {
	final groups:Array<OcamlModuleDependencyGroup>;
	final unresolvedModules:Array<String>;
}

private typedef ModuleVisit = {
	final node:Int;
	var next:Int;
}

/**
	Groups mutually dependent compilation units without reading generated text.

	Edges point from a user to its dependencies. Groups appear dependency first;
	members are sorted, and input order does not affect the result. Two explicit
	graph walks keep long module chains off the host call stack.
	The supplied node names define the owned graph. Unresolved names are reported,
	not assumed safe or external. This plan does not authorize code publication.
**/
function plan(input:Array<OcamlModuleDependencyNode>):OcamlModuleDependencyPlan {
	final nodes = input.copy();
	nodes.sort((left, right) -> compare(left.name, right.name));
	final indices:Map<String, Int> = [];
	for (index in 0...nodes.length) {
		final name = nodes[index].name;
		if (indices.exists(name))
			throw "reflaxe.ocaml [ocaml-module-plan:duplicate-owner]: " + name;
		indices.set(name, index);
	}
	final edges:Array<Array<Int>> = [for (_ in nodes) []];
	final reverse:Array<Array<Int>> = [for (_ in nodes) []];
	final unresolved:Map<String, Bool> = [];
	for (index in 0...nodes.length) {
		final unique:Map<Int, Bool> = [];
		for (name in nodes[index].dependencies) {
			final dependency = indices.get(name);
			if (dependency == null) {
				unresolved.set(name, true);
			} else if (!unique.exists(dependency)) {
				unique.set(dependency, true);
				edges[index].push(dependency);
				reverse[dependency].push(index);
			}
		}
		edges[index].sort((left, right) -> left - right);
	}

	final visited = [for (_ in nodes) false];
	final finished:Array<Int> = [];
	for (start in 0...nodes.length) {
		if (visited[start])
			continue;
		visited[start] = true;
		final pending:Array<ModuleVisit> = [{node: start, next: 0}];
		while (pending.length > 0) {
			final current = pending[pending.length - 1];
			if (current.next == edges[current.node].length) {
				finished.push(current.node);
				pending.pop();
			} else {
				final dependency = edges[current.node][current.next++];
				if (!visited[dependency]) {
					visited[dependency] = true;
					pending.push({node: dependency, next: 0});
				}
			}
		}
	}

	final assigned = [for (_ in nodes) false];
	final groups:Array<OcamlModuleDependencyGroup> = [];
	finished.reverse();
	for (start in finished) {
		if (assigned[start])
			continue;
		assigned[start] = true;
		final pending = [start];
		final members:Array<String> = [];
		while (pending.length > 0) {
			final current = pending[pending.length - 1];
			pending.pop();
			members.push(nodes[current].name);
			for (user in reverse[current])
				if (!assigned[user]) {
					assigned[user] = true;
					pending.push(user);
				}
		}
		members.sort(compare);
		groups.push({members: members, recursive: members.length > 1 || edges[start].indexOf(start) >= 0});
	}
	groups.reverse();
	final unresolvedModules = [for (name in unresolved.keys()) name];
	unresolvedModules.sort(compare);
	return {groups: groups, unresolvedModules: unresolvedModules};
}

private function compare(left:String, right:String):Int {
	return left < right ? -1 : (left == right ? 0 : 1);
}
