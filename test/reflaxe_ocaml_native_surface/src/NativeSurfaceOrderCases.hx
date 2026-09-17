/** A pure expression keeps strict validation active without requesting native types. */
class PureOrderCase {
	public static final value = 1;
	public static final other = 2;
}

/** The initializer is a real typed reflection call that strict validation must reject first. */
class StrictOrderCase {
	public static final value = Reflect.fields({value: 1});
}

/** An otherwise unused declaration makes inventory reads visible to the boundary fixture. */
enum InventoryOrderCase {
	Value;
}
