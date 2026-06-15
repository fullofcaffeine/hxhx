public static class __HxArray implements Iterable<Object> {
  private final java.util.ArrayList<Object> items = new java.util.ArrayList<Object>();
  public __HxArray(Object[] values) {
    for (Object value : values) {
      items.add(value);
    }
  }
  public void push(Object value) {
    items.add(value);
  }
  public java.util.Iterator<Object> iterator() {
    return items.iterator();
  }
}
