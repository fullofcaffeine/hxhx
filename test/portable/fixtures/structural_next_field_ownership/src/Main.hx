private typedef LinkedNode = {
	var rank:Int;
	var next:LinkedNode;
}

private typedef FlagField = {
	var hasNext:Bool;
}

/**
	Exercises an ordinary structural field named `next` through a real generic
	standard-library consumer.

	The field stores another linked node; it is not an Iterator method. Taking
	`ListSort.sortSingleLinked` as a value keeps the generic implementation as a
	real generated function, so the test observes the same `q.next` reads and
	`tail.next = value` writes that previously became Iterator closures or no-ops.
**/
class Main {
	static function emit(line:String):Void {
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function node(rank:Int, next:LinkedNode):LinkedNode {
		return {rank: rank, next: next};
	}

	static function values(head:LinkedNode):String {
		final out:Array<String> = [];
		var current = head;
		while (current != null) {
			out.push(Std.string(current.rank));
			current = current.next;
		}
		return out.join(",");
	}

	static function nestedNextRank(head:LinkedNode):Int {
		final readNext = () -> head.next.rank;
		return readNext();
	}

	static function enableFlag(flag:FlagField):Bool {
		flag.hasNext = true;
		return flag.hasNext;
	}

	static function main():Void {
		final third = node(3, null);
		final first = node(2, node(1, third));
		emit("field.read=" + first.next.rank);
		emit("field.nested=" + nestedNextRank(first));
		emit("field.hasNext=" + enableFlag({hasNext: false}));

		final sort:LinkedNode->(LinkedNode->LinkedNode->Int) -> LinkedNode = haxe.ds.ListSort.sortSingleLinked;
		final sorted = sort(first, (left, right) -> left.rank - right.rank);
		emit("listsort.values=" + values(sorted));
	}
}
