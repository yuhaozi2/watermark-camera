import 'dart:convert';
import 'dart:typed_data';

// 纯 Dart 的 docx 生成器：不引第三方库，自己写 zip（存储方式，不压缩）+ CRC32。
// 用途：拼图导出 Word。Word 对中文是原生支持的，文档里直接写 UTF-8 中文。
class DocxImage {
  final String filename;
  final List<int> bytes;
  final int width;
  final int height;
  const DocxImage({required this.filename, required this.bytes, required this.width, required this.height});

  String get contentType {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }
}

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

/// 生成一个最小但 Word 能正常打开的 docx 文件字节。
Uint8List buildDocx({
  required String title,
  required Map<String, String> fields,
  required List<DocxImage> images,
}) {
  const emuPerInch = 914400;
  const maxWidthEmu = 6 * emuPerInch; // 正文宽约 6 英寸（A4 左右各 1 英寸边距）
  const maxHeightEmu = 9 * emuPerInch;

  final doc = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
    ..write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\n<w:body>\n')
    ..write('<w:p><w:r><w:rPr><w:b/><w:sz w:val="44"/></w:rPr><w:t>${_xmlEscape(title)}</w:t></w:r></w:p>\n');
  for (final entry in fields.entries) {
    if (entry.value.isEmpty) continue;
    doc.write('<w:p><w:r><w:t>${_xmlEscape('${entry.key}：${entry.value}')}</w:t></w:r></w:p>\n');
  }
  for (var i = 0; i < images.length; i++) {
    final img = images[i];
    var scale = 1.0;
    if (img.width > 0 && img.height > 0) {
      final wScale = maxWidthEmu / (img.width * emuPerInch / 96);
      final hScale = maxHeightEmu / (img.height * emuPerInch / 96);
      // 只缩小不放大：小图保持原尺寸，大图等比缩到正文宽内
      scale = wScale < 1 || hScale < 1 ? (wScale < hScale ? wScale : hScale) : 1.0;
    }
    final cx = (img.width * emuPerInch / 96 * scale).round();
    final cy = (img.height * emuPerInch / 96 * scale).round();
    final rid = 'rId${i + 2}';
    final id = i + 1;
    doc.write('<w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$id" name="图片$id"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="图片$id"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>\n');
  }
  doc.write('<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>\n'
      '</w:body></w:document>\n');

  final rels = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
    ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\n')
    ..write('<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\n');
  for (var i = 0; i < images.length; i++) {
    rels.write('<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${images[i].filename}"/>\n');
  }
  rels.write('</Relationships>\n');

  const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="jpeg" ContentType="image/jpeg"/>
<Default Extension="jpg" ContentType="image/jpeg"/>
<Default Extension="png" ContentType="image/png"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>
''';
  const packageRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
''';
  const styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
</w:styles>
''';
  const coreProps = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"><cp:title>拼图</cp:title></cp:coreProperties>
''';
  const appProps = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>水印相机</Application></Properties>
''';

  final files = <String, List<int>>{
    '[Content_Types].xml': utf8.encode(contentTypes),
    '_rels/.rels': utf8.encode(packageRels),
    'word/document.xml': utf8.encode(doc.toString()),
    'word/_rels/document.xml.rels': utf8.encode(rels.toString()),
    'word/styles.xml': utf8.encode(styles),
    'docProps/core.xml': utf8.encode(coreProps),
    'docProps/app.xml': utf8.encode(appProps),
  };
  for (final img in images) {
    files['word/media/${img.filename}'] = img.bytes;
  }

  // zip（存储方式）：本地头 + 中央目录 + 结束记录
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
