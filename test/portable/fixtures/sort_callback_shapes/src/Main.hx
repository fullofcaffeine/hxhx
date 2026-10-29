/**
	Sorts arrays with three callback forms that once produced invalid OCaml.

	1. A comparator that reads `Int` fields from anonymous records.
	2. A block-bodied comparator that reads captured arrays, binds locals,
	   returns early, and only then reaches its final comparison.
	3. A comparator whose `String` parameters are both passed to a typed lookup
	   method and compared with `Reflect.compare`.

	Each printed order must match upstream Haxe 4.3.7.
**/
class Main {
	final labels:Array<String>;
	final weights:Array<Int>;

	function new() {
		labels = ["pear", "apple", "fig", "kiwi"];
		weights = [2, 2, 1, 5];
	}

	function weightOf(label:String):Int {
		return weights[labels.indexOf(label)];
	}

	function byWeightThenName():Array<String> {
		final ordered = labels.copy();
		final self = this;
		ordered.sort(function(first, second) {
			final firstWeight = self.weightOf(first);
			final secondWeight = self.weightOf(second);
			if (firstWeight == secondWeight)
				return Reflect.compare(first, second);
			return Reflect.compare(firstWeight, secondWeight);
		});
		return ordered;
	}

	static function main():Void {
		final entries = new Array<{key:String, tick:Int}>();
		entries.push({key: "late", tick: 30});
		entries.push({key: "early", tick: 10});
		entries.push({key: "middle", tick: 20});
		entries.sort((left, right) -> left.tick - right.tick);
		Sys.println([for (entry in entries) entry.key + "=" + entry.tick].join(","));

		final ranked = ["gamma", "beta", "alpha"];
		final ranks = [1, 2, 2];
		final names = ["beta", "unranked", "gamma", "alpha"];
		names.sort((left, right) -> {
			final leftIndex = ranked.indexOf(left);
			final rightIndex = ranked.indexOf(right);
			final leftRank = leftIndex >= 0 ? ranks[leftIndex] : 99;
			final rightRank = rightIndex >= 0 ? ranks[rightIndex] : 99;
			if (leftRank < rightRank)
				return -1;
			if (leftRank > rightRank)
				return 1;
			return left < right ? -1 : (left > right ? 1 : 0);
		});
		Sys.println(names.join(","));

		Sys.println(new Main().byWeightThenName().join(","));
	}
}
