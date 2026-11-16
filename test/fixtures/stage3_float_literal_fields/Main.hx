/**
	Int values entering Float fields of anonymous structure literals.

	Each line reads the field through Float arithmetic, because a native slot that
	still holds an OCaml int crashes (or misprints) on that read. Upstream Haxe
	4.3.7 prints the expected values. Int and Dynamic fields are controls: their
	Int values must stay Int.
**/
typedef Point = {x:Float, y:Float};
typedef PointAlias = Point;
typedef Line = {from:Point, to:PointAlias, label:String};
typedef Box<T> = {value:T};
typedef Optional = {?f:Float, g:Int};
typedef OptionalMeta = {@:optional var f:Float; var g:Int;};
typedef Mixed = {f:Float, i:Int, d:Dynamic};
typedef NullableField = {n:Null<Float>};

class Store {
	public static var shared:Point = {x: 1, y: 2};

	public var point:Point = {x: 3, y: 4};
	public var line:Line;

	public function new() {
		line = {from: {x: 5, y: 6}, to: {x: 7, y: 8}, label: "ctor"};
	}

	public function reset():Void {
		this.point = {x: 9, y: 10};
		point = {x: point.x + 1, y: 12};
	}

	public function sum(p:Point):Float
		return p.x + p.y + 0.5;
}

class Main {
	static var ticks = 0;

	static function tick():Int
		return ++ticks;

	static function total(p:Point):Float
		return p.x * 1000 + p.y;

	static function totalLine(l:Line):Float
		return total(l.from) + total(l.to);

	static function totalBox(b:Box<Float>):Float
		return b.value * 1000;

	static function optionalArg(?p:Point):Float
		return p == null ? -1.5 : p.x + 0.5;

	static function made():Point
		return {x: 1, y: 2};

	static function madeBranch(flag:Bool):Point {
		if (flag)
			return {x: 3, y: 4};
		return flag ? {x: 5, y: 6} : {x: 7, y: 8};
	}

	static function madeBox():Box<Float> {
		return {value: 9};
	}

	static function main():Void {
		// Variable declarations, with an Int literal, the original report.
		var o:{f:Float} = {f: 1};
		Sys.println("decl multiply: " + (o.f * 1000));
		o.f = o.f + 0.5;
		Sys.println("decl update: " + o.f);
		final negative:{f:Float} = {f: -2};
		Sys.println("decl negative: " + (negative.f * 1.5));

		// Int-typed expressions, not only literals.
		final count = 4;
		final ints = [20, 30];
		final counted:{a:Float, b:Float, c:Float, d:Float, e:Float, f:Float} = {
			a: count,
			b: count + 1,
			c: tick(),
			d: ints[1],
			e: ints.length,
			f: -count
		};
		Sys.println("int expressions: " + (counted.a + counted.b + counted.c + counted.d + counted.e + counted.f + 0.5));

		// The written order runs, and each operand runs once.
		final ordered:Point = {y: tick(), x: tick()};
		Sys.println("written order: " + (ordered.x * 10 + ordered.y) + " ticks " + ticks);

		// Float values and mixed fields keep their value.
		final kept:Point = {x: 1.25, y: 2};
		Sys.println("mixed literal: " + (kept.x + kept.y));

		// Conditional field values.
		final flag = count > 1;
		final conditional:Point = {x: flag ? 1 : 2, y: flag ? 1.5 : 2};
		Sys.println("conditional field: " + (conditional.x * 2.5 + conditional.y));

		// Assignment to locals, fields, statics, and elements.
		var assigned:Point = {x: 0.5, y: 0.5};
		assigned = {x: 1, y: 2};
		Sys.println("assign local: " + total(assigned));
		final store = new Store();
		Sys.println("field initializer: " + total(store.point));
		Sys.println("static initializer: " + total(Store.shared));
		Sys.println("constructor assign: " + totalLine(store.line));
		store.reset();
		Sys.println("method assign: " + total(store.point));
		store.point = {x: 13, y: 14};
		Sys.println("receiver assign: " + total(store.point));
		Store.shared = {x: 15, y: 16};
		Sys.println("static assign: " + total(Store.shared));
		final value:Point = (assigned = {x: 17, y: 18});
		Sys.println("assign value: " + total(value));

		// Call arguments.
		Sys.println("static call: " + total({x: 1, y: 2}));
		Sys.println("method call: " + store.sum({x: 3, y: 4}));
		Sys.println("optional argument: " + optionalArg({x: 5, y: 6}) + " " + optionalArg());
		final local = (p:Point) -> Std.int(p.x * 2.5 + p.y);
		Sys.println("local function: " + local({x: 7, y: 8}));
		Sys.println("generic typedef argument: " + totalBox({value: 3}));

		// Returns.
		Sys.println("return: " + total(made()));
		Sys.println("return branch: " + total(madeBranch(true)) + " " + total(madeBranch(false)));
		Sys.println("return generic typedef: " + totalBox(madeBox()));

		// Nested structures.
		final nested:{outer:{inner:{f:Float}, g:Float}} = {outer: {inner: {f: 1}, g: 2}};
		Sys.println("nested: " + (nested.outer.inner.f * 2.5 + nested.outer.g));
		final line:Line = {from: {x: 1, y: 2}, to: {x: 3, y: 4}, label: "typedef"};
		Sys.println("nested typedef: " + totalLine(line) + " " + line.label);

		// Arrays of structures.
		final points:Array<Point> = [{x: 1, y: 2}, {x: 3.5, y: 4}];
		Sys.println("array literal: " + total(points[0]) + " " + total(points[1]));
		points.push({x: 5, y: 6});
		Sys.println("array push: " + total(points[2]));
		points[0] = {x: 7, y: 8};
		Sys.println("array write: " + total(points[0]));
		final grid:Array<Array<Point>> = [[{x: 1, y: 2}], [{x: 3, y: 4}]];
		Sys.println("array of arrays: " + total(grid[1][0]));
		final holder:{points:Array<Point>} = {points: [{x: 6, y: 7}]};
		Sys.println("array inside structure: " + total(holder.points[0]));

		// Map values.
		final byName:Map<String, Point> = ["a" => {x: 1, y: 2}];
		byName.set("b", {x: 3, y: 4});
		Sys.println("map: " + total(byName.get("a")) + " " + total(byName.get("b")));

		// Typedef-named structures and their aliases.
		final alias:PointAlias = {x: 1, y: 2};
		Sys.println("typedef alias: " + total(alias));
		final box:Box<Float> = {value: 2};
		Sys.println("generic typedef: " + (box.value * 2.5));

		// Optional fields.
		final optional:Optional = {f: 1, g: 2};
		Sys.println("optional field: " + (optional.f * 2.5));
		final optionalMeta:OptionalMeta = {f: 2, g: 3};
		Sys.println("optional metadata field: " + (optionalMeta.f * 2.5));
		final omitted:Optional = {g: 3};
		Sys.println("omitted optional field: " + omitted.f + " " + omitted.g);
		final nullable:NullableField = {n: 3};
		Sys.println("nullable field: " + (nullable.n * 2.5));
		final nullableCount:NullableField = {n: count};
		Sys.println("nullable field from Int: " + (nullableCount.n * 2.5));
		final nullValue:NullableField = {n: null};
		Sys.println("null field: " + nullValue.n);

		// Expected structure reaches through wrappers.
		final maybe:Null<Point> = {x: 1, y: 2};
		Sys.println("nullable structure: " + total(maybe));
		final branch:Point = flag ? {x: 2, y: 3} : {x: 4, y: 5};
		Sys.println("conditional structure: " + total(branch));
		final blockValue:Point = if (flag) {x: 6, y: 7} else {x: 8, y: 9};
		Sys.println("if value: " + total(blockValue));

		// Controls: destinations that are not Float keep the Int.
		final mixed:Mixed = {f: 1, i: 2, d: 3};
		Sys.println("mixed controls: " + (mixed.f * 2.5) + " " + (mixed.i + 1) + " " + (mixed.d + 1));
		Sys.println("Int division stays Float: " + (mixed.i / 4));
		final inferred = {f: 1, g: 2.5};
		Sys.println("inferred Int field: " + (inferred.f + 1) + " " + (inferred.g * 2));
		final boxInt:Box<Int> = {value: 7};
		Sys.println("Int box: " + (boxInt.value + 1));
		final boxDynamic:Box<Dynamic> = {value: 8};
		Sys.println("Dynamic box: " + boxDynamic.value);
	}
}
