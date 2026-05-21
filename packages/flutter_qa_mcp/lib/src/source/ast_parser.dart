import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class AstParser {
  static final Map<String, _ParsedFile> _cache = {};

  static String? enclosingFunction({
    required String filePath,
    required int line,
    required int column,
  }) {
    final parsed = _load(filePath);
    if (parsed == null) return null;
    final offset = parsed.offsetFor(line, column);
    if (offset == null) return null;
    final visitor = _EnclosingFunctionVisitor(offset);
    parsed.unit.visitChildren(visitor);
    return visitor.found;
  }

  static _ParsedFile? _load(String filePath) {
    final cached = _cache[filePath];
    final file = File(filePath);
    if (!file.existsSync()) return null;
    final currentMtime = file.lastModifiedSync();
    if (cached != null && cached.mtime.isAtSameMomentAs(currentMtime)) {
      return cached;
    }
    final source = file.readAsStringSync();
    final result = parseString(content: source, throwIfDiagnostics: false);
    final pf = _ParsedFile(result.unit, _LineOffsets(source), currentMtime);
    _cache[filePath] = pf;
    return pf;
  }
}

class _ParsedFile {
  _ParsedFile(this.unit, this.offsets, this.mtime);
  final CompilationUnit unit;
  final _LineOffsets offsets;
  final DateTime mtime;
  int? offsetFor(int line, int column) => offsets.offsetFor(line, column);
}

class _LineOffsets {
  _LineOffsets(String source) {
    int offset = 0;
    _starts.add(0);
    for (final ch in source.codeUnits) {
      offset++;
      if (ch == 10 /* \n */) _starts.add(offset);
    }
  }
  final List<int> _starts = [];
  int? offsetFor(int line, int column) {
    final idx = line - 1;
    if (idx < 0 || idx >= _starts.length) return null;
    return _starts[idx] + (column - 1);
  }
}

class _EnclosingFunctionVisitor extends RecursiveAstVisitor<void> {
  _EnclosingFunctionVisitor(this.offset);
  final int offset;
  String? found;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (_contains(node)) found = node.name.lexeme;
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_contains(node)) found = node.name.lexeme;
    super.visitFunctionDeclaration(node);
  }

  bool _contains(AstNode node) => offset >= node.offset && offset <= node.end;
}
