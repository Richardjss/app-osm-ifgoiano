import 'dart:io';

void main() {
  var c = File('campus_clean.osm').readAsStringSync();
  var r = RegExp(r'k=["\x27]motorcycle["\x27]\s+v=["\x27]([^"\x27]+)["\x27]');
  for (var m in r.allMatches(c)) {
    print(m.group(0));
  }
}
