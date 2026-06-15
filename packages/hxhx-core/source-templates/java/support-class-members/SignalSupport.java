@FunctionalInterface
public static interface __HxCallback {
  Object apply(__HxEvent value);
}
public static class __HxSignal {
  public void add(__HxCallback callback) {
  }
}
public static class __HxEvent {
  public __HxResult result = new __HxResult();
}
public static class __HxResult {
  public __HxArray assertations = new __HxArray(new Object[0]);
}
