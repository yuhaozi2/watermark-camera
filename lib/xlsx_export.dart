import 'dart:convert';
import 'dart:typed_data';

// 纯 Dart 的 xlsx 生成器：不引第三方库，自己写 zip（存储方式）+ CRC32。
// 单元格用 inlineStr，不用 sharedStrings，Word/Excel/WPS 都能打开；首行加粗。
String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xff] ^ (crc >> 8);
  }
  return crc ^ 0xffffffff;
}

void _u16(BytesBuilder out, int v) {
  final b = ByteData(2)..setUint16(0, v, Endian.little);
  out.add(b.buffer.asUint8List());
}

void _u32(BytesBuilder out, int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  out.add(b.buffer.asUint8List());
}

String _colName(int index) {
  var name = '';
  var i = index;
  do {
    name = String.fromCharCode(65 + (i % 26)) + name;
    i = i ~/ 26 - 1;
  } while (i >= 0);
  return name;
}

Uint8List buildXlsx({required List<List<String>> rows}) {
  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\n<sheetData>\n');
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final ref = '${_colName(c)}${r + 1}';
      final style = r == 0 ? ' s="1"' : '';
      sheet.write('<c r="$ref" t="inlineStr"$style><is><t>${_xmlEscape(rows[r][c])}</t></is></c>');
    }
    sheet.write('</row>\n');
  }
  sheet.write('</sheetData></worksheet>\n');

  const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
''';
  const packageRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
''';
  const workbook = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="考勤统计" sheetId="1" r:id="rId1"/></sheets>
</workbook>
''';
  const workbookRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
''';
  const styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts><font><sz val="11"/></font><font><b/><sz val="11"/></font></fonts>
<fills><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
<borders><border/></borders>
<cellStyleXfs><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>
</styleSheet>
''';

  final files = <String, List<int>>{
    '[Content_Types].xml': utf8.encode(contentTypes),
    '_rels/.rels': utf8.encode(packageRels),
    'xl/workbook.xml': utf8.encode(workbook),
    'xl/_rels/workbook.xml.rels': utf8.encode(workbookRels),
    'xl/worksheets/sheet1.xml': utf8.encode(sheet.toString()),
    'xl/styles.xml': utf8.encode(styles),
  };

  final out = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;
  for (final entry in files.entries) {
    final nameBytes = utf8.encode(entry.key);
    final data = entry.value;
    final crc = _crc32(data);
    out.add([0x50, 0x4b, 0x03, 0x04]);
    _u16(out, 20);
    _u16(out, 0);
    _u16(out, 0);
    _u16(out, 0);
    _u16(out, 0);
    _u32(out, crc);
    _u32(out, data.length);
    _u32(out, data.length);
    _u16(out, nameBytes.length);
    _u16(out, 0);
    out.add(nameBytes);
    out.add(data);
    central.add([0x50, 0x4b, 0x01, 0x02]);
    _u16(central, 20);
    _u16(central, 20);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, crc);
    _u32(central, data.length);
    _u32(central, data.length);
    _u16(central, nameBytes.length);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, 0);
    _u32(central, offset);
    central.add(nameBytes);
    offset += 30 + nameBytes.length + data.length;
  }
  final cdStart = offset;
  final cdBytes = central.toBytes();
  out.add(cdBytes);
  out.add([0x50, 0x4b, 0x05, 0x06]);
  _u16(out, 0);
  _u16(out, 0);
  _u16(out, files.length);
  _u16(out, files.length);
  _u32(out, cdBytes.length);
  _u32(out, cdStart);
  _u16(out, 0);
  return out.toBytes();
}
