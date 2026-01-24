class ArrayMain {
	static function main() {
		final a = [];

		a.push(1);
		a.push(2);
		if (a.length != 2) throw "len2";
		if (a[0] != 1) throw "idx0";
		if (a[1] != 2) throw "idx1";

		a[1] = 3;
		if (a[1] != 3) throw "set";

		final p = a.pop();
		if (p != 3) throw "pop";
		if (a.length != 1) throw "len1";

		a.unshift(0);
		if (a[0] != 0) throw "unshift";

		final s = a.shift();
		if (s != 0) throw "shift";

		a.insert(0, 9);
		if (a[0] != 9) throw "insert";

		final removed = a.splice(0, 1);
		if (removed.length != 1) throw "splice_len";
		if (removed[0] != 9) throw "splice_val";

		final b = [1, 2, 3, 4];
		final c = b.slice(1, 3);
		if (c.length != 2) throw "slice_len";
		if (c[0] != 2) throw "slice0";
		if (c[1] != 3) throw "slice1";
	}
}

