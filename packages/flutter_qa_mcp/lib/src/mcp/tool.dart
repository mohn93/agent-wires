typedef ToolHandler = Future<Map<String, dynamic>> Function(Map<String, dynamic> args);

class Tool {
  Tool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final ToolHandler handler;

  Map<String, dynamic> toDescriptor() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
      };
}
