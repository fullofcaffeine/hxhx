import reflaxe.ocaml.ast.OcamlModuleGroups.plan as planModules;
import reflaxe.ocaml.ast.OcamlModuleGroups.OcamlModuleDependencyNode;

/** Checks graph grouping against an independent transitive-reachability specification. */
class OcamlModuleGroupsTest {
	public static function run():Void {
		for (mask in 0...512)
			checkGraph(mask);
		final unknown = planModules([{name: "Main", dependencies: ["Z", "A", "Z"]}]);
		if (unknown.unresolvedModules.join(",") != "A,Z")
			throw "unresolved module names were lost or reordered";
		var duplicateRejected = false;
		try {
			planModules([{name: "A", dependencies: []}, {name: "A", dependencies: []}]);
		} catch (message:String) {
			duplicateRejected = message.indexOf("ocaml-module-plan:duplicate-owner") >= 0;
		}
		if (!duplicateRejected)
			throw "duplicate module ownership was accepted";
		if (planModules([]).groups.length != 0)
			throw "empty graph has a group";
		final chain:Array<OcamlModuleDependencyNode> = [
			for (index in 0...20000)
				{name: "M" + index, dependencies: index == 0 ? [] : ["M" + (index - 1)]}
		];
		final groups = planModules(chain).groups;
		for (index in 0...chain.length)
			if (groups[index].members.join(",") != "M" + index || groups[index].recursive)
				throw "long chain lost dependency order";
	}

	/** All nine possible edges include self references and disconnected components. */
	static function checkGraph(mask:Int):Void {
		final names = ["A", "B", "C"];
		final reachable = [
			for (left in 0...3) [for (right in 0...3) (mask & (1 << (left * 3 + right))) != 0]
		];
		final nodes:Array<OcamlModuleDependencyNode> = [
			for (left in 0...3)
				{name: names[left], dependencies: [for (right in 0...3) if (reachable[left][right]) names[right]]}
		];
		for (via in 0...3)
			for (left in 0...3)
				for (right in 0...3)
					reachable[left][right] = reachable[left][right] || (reachable[left][via] && reachable[via][right]);
		final plan = planModules(nodes);
		final owner = [-1, -1, -1];
		for (index in 0...plan.groups.length) {
			final group = plan.groups[index];
			for (name in group.members) {
				final member = names.indexOf(name);
				if (member < 0 || owner[member] != -1)
					throw "member duplicated or invented";
				owner[member] = index;
				if (group.recursive != reachable[member][member])
					throw "recursion flag differs from reachability";
			}
		}
		for (left in 0...3) {
			if (owner[left] < 0)
				throw "module missing from plan";
			for (right in 0...3) {
				if ((owner[left] == owner[right]) != (left == right || (reachable[left][right] && reachable[right][left])))
					throw "group differs from mutual reachability";
				if (reachable[left][right] && owner[right] > owner[left])
					throw "dependency appears after its user";
			}
		}
		final expected = plan.groups.map(group -> group.members.join(",")).join(";");
		for (permutation in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]) {
			final reordered = [
				for (index in permutation) {
					final dependencies = nodes[index].dependencies.copy();
					dependencies.reverse();
					{name: nodes[index].name, dependencies: dependencies.concat(dependencies)};
				}
			];
			final actual = planModules(reordered).groups.map(group -> group.members.join(",")).join(";");
			if (actual != expected)
				throw "input ordering or repeated edges changed the plan";
		}
	}
}
