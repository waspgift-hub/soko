typedef AiToolHandler = Future<dynamic> Function(Map<String, dynamic> args);

class AiTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final AiToolHandler execute;

  const AiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });
}

class AiToolRegistry {
  final Map<String, AiTool> _tools = {};

  void register(AiTool tool) {
    _tools[tool.name] = tool;
  }

  void registerAll(List<AiTool> tools) {
    for (final t in tools) {
      register(t);
    }
  }

  AiTool? get(String name) => _tools[name];

  List<AiTool> get all => _tools.values.toList();

  List<Map<String, dynamic>> toApiFormat() => _tools.values.map((t) => {
    'type': 'function',
    'function': {
      'name': t.name,
      'description': t.description,
      'parameters': t.parameters,
    },
  }).toList();

  Future<dynamic> call(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) throw ArgumentError('Tool not found: $name');
    return tool.execute(args);
  }
}
