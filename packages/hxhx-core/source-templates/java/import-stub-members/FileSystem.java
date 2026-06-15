public static boolean exists(Object path) {
  return java.nio.file.Files.exists(java.nio.file.Paths.get(String.valueOf(path)));
}
public static boolean isDirectory(Object path) {
  return java.nio.file.Files.isDirectory(java.nio.file.Paths.get(String.valueOf(path)));
}
public static java.util.ArrayList<String> readDirectory(Object path) {
  java.util.ArrayList<String> out = new java.util.ArrayList<String>();
  try (java.nio.file.DirectoryStream<java.nio.file.Path> stream = java.nio.file.Files.newDirectoryStream(java.nio.file.Paths.get(String.valueOf(path)))) {
    for (java.nio.file.Path entry : stream) out.add(entry.getFileName().toString());
  } catch (Exception e) {
    throw new RuntimeException(e);
  }
  return out;
}
public static void createDirectory(Object path) {
  try { java.nio.file.Files.createDirectories(java.nio.file.Paths.get(String.valueOf(path))); }
  catch (Exception e) { throw new RuntimeException(e); }
}
public static void deleteFile(Object path) {
  try { java.nio.file.Files.deleteIfExists(java.nio.file.Paths.get(String.valueOf(path))); }
  catch (Exception e) { throw new RuntimeException(e); }
}
public static void deleteDirectory(Object path) {
  deleteFile(path);
}
public static void rename(Object from, Object to) {
  try { java.nio.file.Files.move(java.nio.file.Paths.get(String.valueOf(from)), java.nio.file.Paths.get(String.valueOf(to)), java.nio.file.StandardCopyOption.REPLACE_EXISTING); }
  catch (Exception e) { throw new RuntimeException(e); }
}
public static Object stat(Object path) {
  return exists(path) ? new Object() : null;
}
public static String absolutePath(Object path) {
  return java.nio.file.Paths.get(String.valueOf(path)).toAbsolutePath().normalize().toString();
}
public static String fullPath(Object path) {
  try { return java.nio.file.Paths.get(String.valueOf(path)).toRealPath().toString(); }
  catch (Exception e) { return absolutePath(path); }
}
