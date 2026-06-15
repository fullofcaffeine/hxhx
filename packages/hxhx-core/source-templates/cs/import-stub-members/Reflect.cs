public static global::hxhx.__HxArray fields(object obj) {
  if (obj == null) return new global::hxhx.__HxArray(new object[] { });
  var type = obj as System.Type;
  object receiver = type == null ? obj : null;
  if (type == null) type = obj.GetType();
  var flags = System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static;
  var names = new System.Collections.Generic.List<object>();
  foreach (var fieldInfo in type.GetFields(flags)) names.Add(fieldInfo.Name);
  foreach (var property in type.GetProperties(flags)) names.Add(property.Name);
  return new global::hxhx.__HxArray(names.ToArray());
}
public static object field(object obj, object field) {
  if (obj == null) return null;
  string name = System.Convert.ToString(field);
  var flags = System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static;
  var type = obj as System.Type;
  object receiver = type == null ? obj : null;
  if (type == null) type = obj.GetType();
  var property = type.GetProperty(name, flags);
  if (property != null) return property.GetValue(receiver, null);
  var fieldInfo = type.GetField(name, flags);
  if (fieldInfo != null) return fieldInfo.GetValue(receiver);
  return null;
}
public static int compare(object a, object b) {
  return string.Compare(System.Convert.ToString(a), System.Convert.ToString(b), System.StringComparison.Ordinal);
}
public static object setProperty(object obj, object field, object value) {
  if (obj == null) return value;
  string name = System.Convert.ToString(field);
  var flags = System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static;
  var type = obj as System.Type;
  object receiver = type == null ? obj : null;
  if (type == null) type = obj.GetType();
  var readOnly = type.GetMethod("__hxhx_isReadOnlyField", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
  if (readOnly != null && System.Convert.ToBoolean(readOnly.Invoke(null, new object[] { name }))) {
    throw new System.MemberAccessException();
  }
  var property = type.GetProperty(name, flags);
  if (property != null) { property.SetValue(receiver, value, null); return value; }
  var fieldInfo = type.GetField(name, flags);
  if (fieldInfo != null) { fieldInfo.SetValue(receiver, value); return value; }
  return value;
}
