
class Std {
  public static int int_(Object value) {
    return value instanceof Number ? ((Number)value).intValue() : 0;
  }
  public static int parseInt(String value) {
    try { return Integer.parseInt(value); } catch (Exception e) { return 0; }
  }
  public static Object add_(Object left, Object right) {
    if (left instanceof String || right instanceof String) return String.valueOf(left) + String.valueOf(right);
    return int_(left) + int_(right);
  }
}

class Sys {
  public static String[] __hxhx_args = new String[0];
  private static java.util.HashMap<String, String> __hxhx_env = new java.util.HashMap<String, String>();
  public static String[] args() {
    return __hxhx_args;
  }
  public static String getEnv(String name) {
    if (__hxhx_env.containsKey(name)) return __hxhx_env.get(name);
    String value = System.getenv(name);
    if (value != null) return value;
    return System.getProperty(name);
  }
  public static void putEnv(String name, String value) {
    if (value == null) __hxhx_env.remove(name); else __hxhx_env.put(name, value);
  }
  public static __HxStringMap environment() {
    java.util.HashMap<String, String> env = new java.util.HashMap<String, String>(System.getenv());
    env.putAll(__hxhx_env);
    return new __HxStringMap(env);
  }
  public static String getCwd() {
    return System.getProperty("user.dir", "");
  }
  public static String programPath() {
    try { return new java.io.File(Sys.class.getProtectionDomain().getCodeSource().getLocation().toURI()).getPath(); }
    catch (Exception e) { return System.getProperty("java.class.path", ""); }
  }
  public static void print(Object value) {
    System.out.print(String.valueOf(value));
  }
  public static void println(Object value) {
    System.out.println(String.valueOf(value));
  }
  public static int command(Object... args) {
    if (args == null || args.length == 0 || args[0] == null) return 0;
    try {
      java.util.ArrayList<String> command = new java.util.ArrayList<String>();
      if (args.length == 1) {
        for (String item : __hxhx_shellCommand(String.valueOf(args[0]))) command.add(item);
      } else {
        command.add(String.valueOf(args[0]));
        if (args.length > 1 && args[1] instanceof Iterable) {
          for (Object item : (Iterable<?>)args[1]) command.add(String.valueOf(item));
        }
      }
      java.lang.ProcessBuilder builder = new ProcessBuilder(command).inheritIO();
      builder.environment().putAll(__hxhx_env);
      java.lang.Process process = builder.start();
      return process.waitFor();
    } catch (Exception e) {
      return -1;
    }
  }
  public static String systemName() {
    String os = System.getProperty("os.name", "").toLowerCase();
    if (os.contains("win")) return "Windows";
    if (os.contains("mac")) return "Mac";
    return "Linux";
  }
  public static void exit(Object code) {
    System.exit(code instanceof Number ? ((Number)code).intValue() : 0);
  }
  private static String[] __hxhx_shellCommand(String command) {
    if ("Windows".equals(systemName())) return new String[] {"cmd", "/c", command};
    return new String[] {"sh", "-c", command};
  }
}

class __HxStringMap {
  private final java.util.HashMap<String, String> values;
  public __HxStringMap(java.util.HashMap<String, String> values) {
    this.values = values;
  }
  public String get(String key) {
    return values.get(key);
  }
}
