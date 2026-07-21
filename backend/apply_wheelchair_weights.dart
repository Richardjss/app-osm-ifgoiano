import 'dart:io';

void main() async {
  final file = File('campus_clean.osm');
  if (!await file.exists()) {
    print('campus_clean.osm not found');
    return;
  }

  String content = await file.readAsString();
  
  // Substitui wheelchair=limited por ele mesmo + track_type=grade3 (peso 0.5)
  content = content.replaceAll(
    RegExp(r'<tag k=["\x27]wheelchair["\x27] v=["\x27]limited["\x27]\s*/>'),
    '<tag k="wheelchair" v="limited" />\n    <tag k="tracktype" v="grade3" />'
  );
  
  // Substitui wheelchair=bad por ele mesmo + track_type=grade4 (peso 0.2)
  content = content.replaceAll(
    RegExp(r'<tag k=["\x27]wheelchair["\x27] v=["\x27]bad["\x27]\s*/>'),
    '<tag k="wheelchair" v="bad" />\n    <tag k="tracktype" v="grade4" />'
  );
  
  // Substitui wheelchair=no por ele mesmo + track_type=grade5 (peso 0.0 - bloqueado)
  content = content.replaceAll(
    RegExp(r'<tag k=["\x27]wheelchair["\x27] v=["\x27]no["\x27]\s*/>'),
    '<tag k="wheelchair" v="no" />\n    <tag k="tracktype" v="grade5" />'
  );
  
  await file.writeAsString(content);
  print('Pesos do cadeirante aplicados com sucesso via track_type proxy no campus_clean.osm!');
}
