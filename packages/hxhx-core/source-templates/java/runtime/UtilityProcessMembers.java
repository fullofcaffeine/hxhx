private static void __hxhx_runUtility(String[] args) throws Exception {
  if (args == null || args.length == 0) return;
  String command = args[0];
  if ("putEnv".equals(command)) {
    if (args.length >= 5) {
      Sys.putEnv(args[1], __hxhx_sequenceArg(args, 2));
      String[] tail = java.util.Arrays.copyOfRange(args, 4, args.length);
      __hxhx_runUtility(tail);
    }
    return;
  }
  if ("getCwd".equals(command)) { System.out.println(Sys.getCwd()); return; }
  if ("getEnv".equals(command) && args.length > 1) { System.out.println(__hxhx_nullToEmpty(Sys.getEnv(args[1]))); return; }
  if ("checkEnv".equals(command) && args.length > 2) { System.exit(java.util.Objects.equals(args[2], Sys.getEnv(args[1])) ? 0 : 1); return; }
  if ("environment".equals(command) && args.length > 1) { System.out.println(__hxhx_nullToEmpty(Sys.environment().get(args[1]))); return; }
  if ("exitCode".equals(command) && args.length > 1) { System.exit(__hxhx_parseInt(args[1])); return; }
  if ("args".equals(command) && args.length > 1) { System.out.println(args[1]); return; }
  if ("println".equals(command)) { System.out.println(__hxhx_sequenceArg(args, 1)); return; }
  if ("print".equals(command)) { System.out.print(__hxhx_sequenceArg(args, 1)); return; }
  if ("trace".equals(command)) { System.out.println(__hxhx_sequenceArg(args, 1)); return; }
  if ("stdin.readLine".equals(command)) {
    java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(System.in, java.nio.charset.StandardCharsets.UTF_8));
    String line = reader.readLine();
    System.out.println(line == null ? "" : line);
    return;
  }
  if ("stdin.readString".equals(command) && args.length > 1) {
    System.out.println(__hxhx_readChars(__hxhx_parseInt(args[1])));
    return;
  }
  if ("stdin.readUntil".equals(command) && args.length > 1) {
    System.out.println(__hxhx_readUntil(__hxhx_parseInt(args[1])));
    return;
  }
  if ("stderr.writeString".equals(command)) { System.err.print(__hxhx_sequenceArg(args, 1)); System.err.flush(); return; }
  if ("stdout.writeString".equals(command)) { System.out.print(__hxhx_sequenceArg(args, 1)); System.out.flush(); return; }
  if ("programPath".equals(command)) { System.out.println(__hxhx_programPath()); return; }
}
private static String __hxhx_sequenceArg(String[] args, int index) {
  if (args.length <= index) return "";
  String token = args[index];
  String mode = args.length > index + 1 ? args[index + 1] : "";
  try { return __hxhx_unicodeSequence(Integer.parseInt(token), "nfc".equals(mode)); }
  catch (Exception e) { return token; }
}
private static String __hxhx_unicodeSequence(int index, boolean nfc) {
  switch (index) {
    case 0: return __hxhx_codepoints(0x0001);
    case 1: return __hxhx_codepoints(0x007F);
    case 2: return __hxhx_codepoints(0x0080);
    case 3: return __hxhx_codepoints(0x07FF);
    case 4: return __hxhx_codepoints(0x0800);
    case 5: return __hxhx_codepoints(0xD7FF);
    case 6: return __hxhx_codepoints(0xE000);
    case 7: return __hxhx_codepoints(0xFFFD);
    case 8: return __hxhx_codepoints(0x10000);
    case 9: return __hxhx_codepoints(0x1FFFF);
    case 10: return __hxhx_codepoints(0xFFFFF);
    case 11: return __hxhx_codepoints(0x100000);
    case 12: return __hxhx_codepoints(0x10FFFF);
    case 13: return __hxhx_codepoints(0x1F602, 0x1F604, 0x1F619);
    case 14: return nfc ? __hxhx_codepoints(0x0227) : __hxhx_codepoints(0x0061, 0x0307);
    case 15: return nfc ? __hxhx_codepoints(0x4E2D, 0x6587, 0xFF0C, 0x306B, 0x307B, 0x3093, 0x3054) : __hxhx_codepoints(0x4E2D, 0x6587, 0xFF0C, 0x306B, 0x307B, 0x3093, 0x3053, 0x3099);
    default: return "";
  }
}
private static String __hxhx_codepoints(int... codepoints) {
  StringBuilder builder = new StringBuilder();
  for (int codepoint : codepoints) builder.appendCodePoint(codepoint);
  return builder.toString();
}
private static String __hxhx_nullToEmpty(String value) {
  return value == null ? "" : value;
}
private static int __hxhx_parseInt(String value) {
  try { return value != null && value.startsWith("0x") ? Integer.parseInt(value.substring(2), 16) : Integer.parseInt(String.valueOf(value)); }
  catch (Exception e) { return 0; }
}
private static String __hxhx_readChars(int len) throws Exception {
  java.io.InputStreamReader reader = new java.io.InputStreamReader(System.in, java.nio.charset.StandardCharsets.UTF_8);
  StringBuilder builder = new StringBuilder();
  for (int i = 0; i < len; i++) {
    int ch = reader.read();
    if (ch < 0) break;
    builder.append((char)ch);
  }
  return builder.toString();
}
private static String __hxhx_readUntil(int end) throws Exception {
  java.io.InputStreamReader reader = new java.io.InputStreamReader(System.in, java.nio.charset.StandardCharsets.UTF_8);
  StringBuilder builder = new StringBuilder();
  while (true) {
    int ch = reader.read();
    if (ch < 0 || ch == end) break;
    builder.append((char)ch);
  }
  return builder.toString();
}
