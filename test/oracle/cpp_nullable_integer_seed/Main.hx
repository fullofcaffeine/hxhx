/** Native C++ integer assertions derived from upstream black-box execution. */
class Main {
	static function main():Void {
		var absent:Null<Int> = null;
		var present:Null<Int> = 7;
		if (absent == 0 || 0 == absent || absent != absent || !(absent <= absent) || !(absent >= absent) || absent < absent || absent > absent
			|| absent <= 0 || 0 <= absent || absent >= 0 || 0 >= absent)
			throw "nullable comparison lost absence";
		if (present != 7 || 7 != present || !(present > 0) || !(0 < present))
			throw "present nullable comparison changed";
		if (absent + 1 != 1 || 1 + absent != 1 || absent - 1 != -1 || absent * 2 != 0 || -absent != 0)
			throw "native null numeric conversion changed";
		var post:Null<Int> = null;
		final before = post++;
		if (before != 0 || post != 1)
			throw "nullable postfix changed";
		var pre:Null<Int> = null;
		final after = ++pre;
		if (after != 1 || pre != 1)
			throw "nullable prefix changed";
		absent += 3;
		if (absent != 3)
			throw "nullable compound assignment changed";
		var order = 0;
		final left = () -> {
			order = order * 10 + 1;
			return present;
		};
		final right = () -> {
			order = order * 10 + 2;
			return 7;
		};
		if (left() != right() || order != 12)
			throw "operand order or count changed";
		var captured:Null<Int> = null;
		final update = () -> captured++;
		if (update() != 0 || update() != 1 || captured != 2)
			throw "captured nullable update changed";
		var maximum:Null<Int> = 2147483647;
		if (maximum + 1 != -2147483648)
			throw "nullable integer overflow changed";
	}
}
