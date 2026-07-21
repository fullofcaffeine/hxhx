class A {
	public static var first:Int = InitLog.record("A.first", 1);
	public static var fromB:Int = InitLog.record("A.fromB", B.value);
}
