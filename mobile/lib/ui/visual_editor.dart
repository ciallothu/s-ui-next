import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets.dart';

enum _EditorMode { visual, json }

class VisualEditorDialog extends StatefulWidget {
  const VisualEditorDialog({
    super.key,
    required this.title,
    required this.resource,
    required this.initialValue,
    required this.onSave,
    this.actionLabel = '保存',
  });

  final String title;
  final String resource;
  final dynamic initialValue;
  final Future<void> Function(dynamic value) onSave;
  final String actionLabel;

  @override
  State<VisualEditorDialog> createState() => _VisualEditorDialogState();
}

class _VisualEditorDialogState extends State<VisualEditorDialog> {
  late dynamic value;
  late final TextEditingController jsonController;
  late final VisualEditorSchema schema;
  _EditorMode mode = _EditorMode.visual;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    schema = VisualEditorSchema.forResource(widget.resource);
    value = _copy(widget.initialValue);
    jsonController = TextEditingController(text: prettyJson(value));
  }

  @override
  void dispose() {
    jsonController.dispose();
    super.dispose();
  }

  void changeMode(_EditorMode next) {
    if (next == mode) return;
    if (next == _EditorMode.visual) {
      try {
        value = jsonDecode(jsonController.text);
        error = null;
      } catch (exception) {
        setState(() => error = 'JSON 格式错误：$exception');
        return;
      }
    } else {
      jsonController.text = prettyJson(value);
      error = null;
    }
    setState(() => mode = next);
  }

  Future<void> save() async {
    dynamic next = value;
    if (mode == _EditorMode.json) {
      try {
        next = jsonDecode(jsonController.text);
      } catch (exception) {
        setState(() => error = 'JSON 格式错误：$exception');
        return;
      }
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(next);
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          actions: [
            TextButton.icon(
              onPressed: saving ? null : save,
              icon: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(widget.actionLabel),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: SegmentedButton<_EditorMode>(
                  segments: const [
                    ButtonSegment(value: _EditorMode.visual, icon: Icon(Icons.tune), label: Text('可视化')),
                    ButtonSegment(value: _EditorMode.json, icon: Icon(Icons.data_object), label: Text('JSON')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) => changeMode(selection.first),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Expanded(
                child: mode == _EditorMode.json
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: jsonController,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          decoration: const InputDecoration(hintText: '{}', alignLabelWithHint: true),
                        ),
                      )
                    : value is Map
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                            children: [
                              Text(
                                '使用选项、开关和输入框编辑；未收录的新 sing-box 字段仍可通过“添加字段”或 JSON 模式维护。',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 10),
                              ..._buildMap(value as Map<String, dynamic>, ''),
                              _addFieldButton(value as Map, ''),
                            ],
                          )
                        : const EmptyState(label: '可视化编辑需要 JSON 对象，请切换到 JSON 模式'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMap(Map<String, dynamic> map, String path) {
    final entries = map.entries.toList()
      ..sort((a, b) {
        final byOrder = schema.orderOf(path, a.key).compareTo(schema.orderOf(path, b.key));
        return byOrder == 0 ? a.key.compareTo(b.key) : byOrder;
      });
    return [for (final entry in entries) _buildField(map, entry.key, entry.value, path)];
  }

  Widget _buildField(Map<dynamic, dynamic> parent, String key, dynamic fieldValue, String parentPath) {
    final path = parentPath.isEmpty ? key : '$parentPath.$key';
    final label = schema.labelFor(key);
    final options = schema.optionsFor(path, key, parent);

    if (schema.isStringBoolean(path, key, fieldValue)) {
      final checked = fieldValue.toString().toLowerCase() == 'true';
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: SwitchListTile.adaptive(
          title: Text(label),
          subtitle: Text(key),
          value: checked,
          onChanged: (next) => setState(() => parent[key] = next.toString()),
          secondary: _removeButton(parent, key),
        ),
      );
    }

    if (fieldValue is bool) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: SwitchListTile.adaptive(
          title: Text(label),
          subtitle: Text(key),
          value: fieldValue,
          onChanged: (next) => setState(() => parent[key] = next),
          secondary: _removeButton(parent, key),
        ),
      );
    }

    if (fieldValue is Map) {
      final child = Map<String, dynamic>.from(fieldValue);
      parent[key] = child;
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ExpansionTile(
          initiallyExpanded: schema.expandByDefault(path),
          leading: const Icon(Icons.account_tree_outlined),
          title: Text(label),
          subtitle: Text('$key · ${child.length} 个字段'),
          trailing: _removeButton(parent, key),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [..._buildMap(child, path), _addFieldButton(child, path)],
        ),
      );
    }

    if (fieldValue is List) {
      return _buildList(parent, key, fieldValue, path, label);
    }

    if (options != null && options.isNotEmpty) {
      final current = fieldValue?.toString() ?? '';
      final values = <String>{...options, if (current.isNotEmpty) current}.toList();
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('$path:$current'),
                  initialValue: current,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: label, helperText: key),
                  items: [for (final option in values) DropdownMenuItem(value: option, child: Text(schema.optionLabel(option)))],
                  onChanged: (next) {
                    if (next == null) return;
                    setState(() {
                      if (parentPath.isEmpty && key == 'type' && value is Map) {
                        schema.applyRootType(value as Map<String, dynamic>, next);
                      } else {
                        parent[key] = schema.parseOption(fieldValue, next);
                      }
                    });
                  },
                ),
              ),
              _removeButton(parent, key),
            ],
          ),
        ),
      );
    }

    final isNumber = fieldValue is num || schema.isStringNumber(path, key, fieldValue);
    final multiline = schema.isMultiline(path, key);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('$path:${fieldValue.runtimeType}'),
                initialValue: fieldValue?.toString() ?? '',
                minLines: multiline ? 4 : 1,
                maxLines: multiline ? 12 : 1,
                keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
                inputFormatters: isNumber ? [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'))] : null,
                autocorrect: !schema.isSensitive(key),
                enableSuggestions: !schema.isSensitive(key),
                decoration: InputDecoration(labelText: label, helperText: key, alignLabelWithHint: multiline),
                onChanged: (next) {
                  parent[key] = schema.parseText(fieldValue, path, key, next);
                  if (parentPath.isEmpty && key == 'name' && value is Map<String, dynamic>) {
                    schema.syncClientName(value as Map<String, dynamic>, next);
                  }
                },
              ),
            ),
            _removeButton(parent, key),
          ],
        ),
      ),
    );
  }

  Widget _buildList(Map<dynamic, dynamic> parent, String key, List<dynamic> list, String path, String label) {
    final objectList = list.any((item) => item is Map) || schema.isObjectList(path);
    if (!objectList) {
      final current = list.map((item) => item.toString()).join('\n');
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('$path:${list.length}'),
                  initialValue: current,
                  minLines: 2,
                  maxLines: 8,
                  decoration: InputDecoration(labelText: label, helperText: '$key · 每行一项', alignLabelWithHint: true),
                  onChanged: (next) {
                    final lines = next.split('\n').map((item) => item.trim()).where((item) => item.isNotEmpty);
                    parent[key] = [for (final line in lines) schema.parseListItem(list, line)];
                  },
                ),
              ),
              _removeButton(parent, key),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: list.length <= 3,
        leading: const Icon(Icons.view_list_outlined),
        title: Text(label),
        subtitle: Text('$key · ${list.length} 项'),
        trailing: _removeButton(parent, key),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (var index = 0; index < list.length; index++)
            Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('${schema.singularLabel(key)} ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        IconButton(
                          tooltip: '删除此项',
                          onPressed: () => setState(() => list.removeAt(index)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    if (list[index] is Map) ..._buildMap(Map<String, dynamic>.from(list[index] as Map)..also((map) => list[index] = map), '$path[$index]') else TextFormField(
                      initialValue: list[index]?.toString() ?? '',
                      onChanged: (next) => list[index] = next,
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => list.add(_copy(schema.listItemDefault(path)))),
              icon: const Icon(Icons.add),
              label: Text('添加${schema.singularLabel(key)}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _removeButton(Map<dynamic, dynamic> parent, String key) => IconButton(
        tooltip: '删除字段',
        onPressed: () => setState(() => parent.remove(key)),
        icon: const Icon(Icons.remove_circle_outline),
      );

  Widget _addFieldButton(Map<dynamic, dynamic> parent, String path) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _addField(parent, path),
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('添加字段'),
        ),
      );

  Future<void> _addField(Map<dynamic, dynamic> parent, String path) async {
    final keyController = TextEditingController();
    var kind = 'text';
    final missing = schema.suggestedKeys(path).where((key) => !parent.containsKey(key)).toList();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加配置字段'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (missing.isNotEmpty)
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: '常用字段（可选）'),
                    items: [for (final item in missing) DropdownMenuItem(value: item, child: Text('${schema.labelFor(item)} · $item'))],
                    onChanged: (next) {
                      if (next != null) keyController.text = next;
                    },
                  ),
                const SizedBox(height: 10),
                TextField(controller: keyController, decoration: const InputDecoration(labelText: '字段名')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: '值类型'),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('文本')),
                    DropdownMenuItem(value: 'number', child: Text('数字')),
                    DropdownMenuItem(value: 'bool', child: Text('开关')),
                    DropdownMenuItem(value: 'object', child: Text('对象')),
                    DropdownMenuItem(value: 'list', child: Text('列表')),
                  ],
                  onChanged: (next) => setDialogState(() => kind = next ?? kind),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {'key': keyController.text.trim(), 'kind': kind}),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    keyController.dispose();
    if (result == null || result['key']?.isEmpty != false) return;
    final key = result['key']!;
    setState(() {
      parent[key] = switch (result['kind']) {
        'number' => 0,
        'bool' => false,
        'object' => <String, dynamic>{},
        'list' => <dynamic>[],
        _ => '',
      };
    });
  }
}

extension _Also<T> on T {
  T also(void Function(T value) action) {
    action(this);
    return this;
  }
}

dynamic _copy(dynamic value) => jsonDecode(jsonEncode(value));

class VisualEditorSchema {
  VisualEditorSchema._(this.resource);

  factory VisualEditorSchema.forResource(String resource) => VisualEditorSchema._(resource);

  final String resource;

  static const _typeOptions = <String, List<String>>{
    'inbounds': ['direct', 'mixed', 'socks', 'http', 'shadowsocks', 'vmess', 'trojan', 'naive', 'hysteria', 'shadowtls', 'tuic', 'hysteria2', 'vless', 'anytls', 'tun', 'redirect', 'tproxy'],
    'outbounds': ['direct', 'socks', 'http', 'shadowsocks', 'vmess', 'trojan', 'naive', 'hysteria', 'vless', 'shadowtls', 'tuic', 'hysteria2', 'anytls', 'tor', 'ssh', 'selector', 'urltest'],
    'endpoints': ['wireguard', 'warp', 'tailscale'],
    'services': ['derp', 'resolved', 'ssm-api', 'ocm', 'ccm'],
  };

  static const _labels = <String, String>{
    'id': 'ID', 'type': '类型', 'tag': '标签', 'name': '名称', 'enable': '启用', 'enabled': '启用',
    'listen': '监听地址', 'listen_port': '端口', 'server': '服务器', 'server_port': '服务器端口', 'tls_id': 'TLS 模板',
    'transport': '传输', 'tls': 'TLS', 'client': '客户端', 'config': '协议配置', 'inbounds': '入站', 'outbounds': '出站',
    'volume': '流量配额', 'expiry': '到期时间', 'desc': '描述', 'group': '分组', 'delayStart': '延迟启动',
    'autoReset': '自动重置', 'resetDays': '重置天数', 'nextReset': '下次重置', 'up': '上传', 'down': '下载',
    'username': '用户名', 'user': '用户', 'password': '密码', 'uuid': 'UUID', 'flow': '流控', 'method': '加密方式',
    'network': '网络', 'version': '版本', 'security': '安全选项', 'packet_encoding': '数据包编码', 'alter_id': 'Alter ID',
    'address': '地址', 'private_key': '私钥', 'public_key': '公钥', 'pre_shared_key': '预共享密钥', 'allowed_ips': '允许的 IP',
    'peers': 'Peer 列表', 'users': '用户列表', 'links': '链接', 'remark': '备注', 'uri': '链接地址',
    'headers': '请求头', 'extra_headers': '额外请求头', 'path': '路径', 'domain': '域名', 'rules': '规则', 'rule_set': '规则集',
    'action': '操作', 'mode': '逻辑模式', 'invert': '反选结果', 'final': '默认出站', 'strategy': '策略',
    'level': '日志级别', 'output': '日志文件', 'timestamp': '时间戳', 'disabled': '禁用', 'experimental': '实验性功能',
    'dns': 'DNS', 'route': '路由', 'log': '日志', 'ntp': 'NTP', 'servers': '服务器列表', 'format': '格式', 'url': 'URL',
    'certificate': '证书内容', 'certificate_path': '证书路径', 'key': '密钥内容', 'key_path': '密钥路径', 'server_name': '服务器名称',
    'insecure': '允许不安全', 'disable_sni': '禁用 SNI', 'alpn': 'ALPN', 'min_version': '最低 TLS 版本', 'max_version': '最高 TLS 版本',
    'cipher_suites': '密码套件', 'curve_preferences': '曲线偏好', 'reality': 'Reality', 'acme': 'ACME', 'ech': 'ECH', 'utls': 'uTLS',
    'multiplex': '多路复用', 'brutal': 'Brutal', 'padding': '填充', 'congestion_control': '拥塞控制', 'zero_rtt_handshake': '0-RTT',
    'webListen': '面板监听地址', 'webPort': '面板端口', 'webPath': '面板路径', 'webDomain': '面板域名', 'webCertFile': '面板证书路径',
    'webKeyFile': '面板密钥路径', 'webURI': '面板 URI', 'sessionMaxAge': '会话有效期', 'trafficAge': '流量保留天数', 'timeLocation': '时区',
    'subListen': '订阅监听地址', 'subPort': '订阅端口', 'subPath': '订阅路径', 'subDomain': '订阅域名', 'subCertFile': '订阅证书路径',
    'subKeyFile': '订阅密钥路径', 'subUpdates': '更新间隔', 'subEncode': '启用 Base64', 'subShowInfo': '启用用户信息', 'subURI': '订阅 URI',
    'subJsonExt': 'JSON 订阅扩展', 'subClashExt': 'Clash 订阅扩展',
  };

  static const _order = [
    'id', 'enable', 'enabled', 'type', 'tag', 'name', 'group', 'desc', 'listen', 'listen_port', 'server', 'server_port',
    'username', 'user', 'password', 'uuid', 'method', 'network', 'version', 'tls_id', 'transport', 'tls', 'multiplex',
    'config', 'inbounds', 'outbounds', 'links', 'volume', 'expiry', 'autoReset', 'resetDays', 'delayStart',
  ];

  String labelFor(String key) => _labels[key] ?? key.replaceAll('_', ' ');
  String singularLabel(String key) => const {'peers': 'Peer', 'users': '用户', 'links': '链接', 'rules': '规则', 'rule_set': '规则集', 'servers': '服务器'}[key] ?? '项目';
  String optionLabel(String option) => const {'ws': 'WebSocket', 'grpc': 'gRPC', 'httpupgrade': 'HTTP Upgrade', 'urltest': 'URL Test', 'ssm-api': 'SSM API'}[option] ?? option;
  int orderOf(String path, String key) {
    final index = _order.indexOf(key);
    return index < 0 ? 1000 : index;
  }

  bool expandByDefault(String path) => const ['config', 'server', 'client', 'tls', 'transport'].contains(path) || path.split('.').length <= 1;
  bool isSensitive(String key) => key.contains('password') || key.contains('secret') || key.contains('private_key') || key == 'key';
  bool isMultiline(String path, String key) => key == 'certificate' || key == 'key' || key == 'private_key' || key.endsWith('Ext') || key == 'content';
  bool isStringBoolean(String path, String key, dynamic value) => resource == 'settings' && const {'subEncode', 'subShowInfo'}.contains(key);
  bool isStringNumber(String path, String key, dynamic value) => resource == 'settings' && const {'webPort', 'subPort', 'sessionMaxAge', 'trafficAge', 'subUpdates'}.contains(key);

  List<String>? optionsFor(String path, String key, Map<dynamic, dynamic> parent) {
    if (path == 'type' && _typeOptions.containsKey(resource)) return _typeOptions[resource];
    if (key == 'type' && path.endsWith('transport.type')) return const ['http', 'ws', 'quic', 'grpc', 'httpupgrade'];
    if (key == 'type' && path.contains('dns.servers')) return const ['local', 'hosts', 'tcp', 'udp', 'tls', 'quic', 'https', 'h3', 'dhcp', 'fakeip', 'tailscale', 'resolved'];
    if (key == 'type' && path.contains('rule_set')) return const ['local', 'remote'];
    if (key == 'type' && path.contains('links')) return const ['local', 'external', 'sub'];
    if (key == 'type' && path.contains('rules')) return const ['simple', 'logical'];
    if (key == 'action') return const ['route', 'route-options', 'reject', 'hijack-dns', 'sniff', 'resolve', 'bypass', 'predefined'];
    if (key == 'mode') return const ['and', 'or', 'rule', 'global', 'direct'];
    if (key == 'network') return const ['tcp', 'udp'];
    if (key == 'strategy') return const ['', 'prefer_ipv4', 'prefer_ipv6', 'ipv4_only', 'ipv6_only'];
    if (key == 'level') return const ['trace', 'debug', 'info', 'warn', 'error', 'fatal', 'panic'];
    if (key == 'packet_encoding') return const ['', 'packetaddr', 'xudp'];
    if (key == 'congestion_control' || key == 'quic_congestion_control') return const ['', 'cubic', 'new_reno', 'bbr', 'bbr2', 'reno'];
    if (key == 'method' && (parent['type'] == 'shadowsocks' || path.contains('shadowsocks'))) {
      return const ['none', 'aes-128-gcm', 'aes-256-gcm', 'chacha20-ietf-poly1305', '2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305'];
    }
    if (key == 'flow') return const ['', 'xtls-rprx-vision'];
    if (key == 'fingerprint') return const ['chrome', 'firefox', 'edge', 'safari', 'ios', 'android', 'random', 'randomized'];
    if (key == 'min_version' || key == 'max_version') return const ['1.0', '1.1', '1.2', '1.3'];
    if (key == 'store') return const ['mozilla', 'chrome'];
    if (resource == 'settings' && key == 'timeLocation') return const ['Asia/Shanghai', 'Asia/Tehran', 'UTC', 'Local'];
    return null;
  }

  dynamic parseOption(dynamic oldValue, String next) {
    if (oldValue is int) return int.tryParse(next) ?? oldValue;
    if (oldValue is double) return double.tryParse(next) ?? oldValue;
    return next;
  }

  dynamic parseText(dynamic oldValue, String path, String key, String next) {
    if (isStringNumber(path, key, oldValue)) return next;
    if (oldValue is int) return int.tryParse(next) ?? 0;
    if (oldValue is double) return double.tryParse(next) ?? 0;
    return next;
  }

  dynamic parseListItem(List<dynamic> oldList, String next) {
    if (oldList.isNotEmpty && oldList.first is int) return int.tryParse(next) ?? 0;
    if (oldList.isNotEmpty && oldList.first is double) return double.tryParse(next) ?? 0;
    return next;
  }

  bool isObjectList(String path) => path.endsWith('.peers') || path.endsWith('.users') || path.endsWith('.links') || path.endsWith('.rules') || path.endsWith('.rule_set') || path.endsWith('.servers') || path == 'peers' || path == 'users' || path == 'links' || path == 'rules' || path == 'rule_set' || path == 'servers';

  dynamic listItemDefault(String path) {
    if (path.endsWith('peers') || path == 'peers') return {'server': '', 'server_port': 443, 'public_key': '', 'allowed_ips': <String>[]};
    if (path.endsWith('links') || path == 'links') return {'type': 'external', 'remark': '', 'uri': ''};
    if (path.endsWith('users') || path == 'users') return {'name': '', 'token': ''};
    if (path.endsWith('rule_set') || path == 'rule_set') return {'type': 'remote', 'tag': '', 'format': 'binary', 'url': ''};
    if (path.endsWith('rules') || path == 'rules') return {'action': 'route', 'outbound': '', 'invert': false};
    if (path.endsWith('servers') || path == 'servers') return {'type': 'local', 'tag': ''};
    return <String, dynamic>{};
  }

  List<String> suggestedKeys(String path) {
    if (path.endsWith('tls') || path == 'server' || path == 'client') return ['enabled', 'server_name', 'insecure', 'disable_sni', 'alpn', 'min_version', 'max_version', 'certificate', 'certificate_path', 'key', 'key_path', 'acme', 'reality', 'ech', 'utls'];
    if (path.endsWith('transport')) return ['type', 'host', 'path', 'method', 'headers', 'service_name', 'idle_timeout', 'ping_timeout'];
    if (path.endsWith('multiplex')) return ['enabled', 'protocol', 'padding', 'max_connections', 'min_streams', 'max_streams', 'brutal'];
    if (path.contains('route')) return ['rules', 'rule_set', 'final', 'auto_detect_interface', 'default_interface', 'default_mark', 'default_domain_resolver'];
    if (path.contains('dns')) return ['servers', 'rules', 'final', 'strategy', 'disable_cache', 'independent_cache', 'cache_capacity', 'reverse_mapping'];
    return ['type', 'tag', 'name', 'enabled', 'server', 'server_port', 'listen', 'listen_port', 'network', 'tls', 'transport', 'headers'];
  }

  dynamic defaultValue() {
    if (resource == 'clients') {
      final name = _randomText(8);
      return {
        'id': 0, 'enable': true, 'name': name, 'config': _clientConfig(name), 'inbounds': <int>[], 'links': <dynamic>[],
        'volume': 0, 'expiry': 0, 'up': 0, 'down': 0, 'desc': '', 'group': '', 'delayStart': false,
        'autoReset': false, 'resetDays': 0, 'nextReset': 0, 'totalUp': 0, 'totalDown': 0,
      };
    }
    if (resource == 'tls') return {'id': 0, 'name': '', 'server': {'enabled': true, 'alpn': ['h3', 'h2', 'http/1.1']}, 'client': {'enabled': true, 'utls': {'enabled': true, 'fingerprint': 'chrome'}}};
    final firstType = const {'inbounds': 'vless', 'outbounds': 'direct', 'endpoints': 'wireguard', 'services': 'resolved'}[resource] ?? _typeOptions[resource]?.first;
    return firstType == null ? <String, dynamic>{} : _rootTemplate(firstType);
  }

  void applyRootType(Map<String, dynamic> current, String type) {
    final next = _rootTemplate(type);
    final preserve = switch (resource) {
      'inbounds' => ['id', 'tag', 'listen', 'listen_port', 'tls_id', 'addrs', 'out_json'],
      'outbounds' => ['id', 'tag'],
      'endpoints' => ['id', 'tag'],
      'services' => ['id', 'tag', 'listen', 'listen_port', 'tls_id'],
      _ => <String>[],
    };
    for (final key in preserve) {
      if (current.containsKey(key)) next[key] = current[key];
    }
    current
      ..clear()
      ..addAll(next);
  }

  void syncClientName(Map<String, dynamic> current, String name) {
    if (resource != 'clients' || current['config'] is! Map) return;
    for (final raw in (current['config'] as Map).values) {
      if (raw is! Map) continue;
      if (raw.containsKey('name')) raw['name'] = name;
      if (raw.containsKey('username')) raw['username'] = name;
    }
  }

  Map<String, dynamic> _rootTemplate(String type) {
    if (resource == 'inbounds') {
      final base = <String, dynamic>{'id': 0, 'type': type, 'tag': '', 'listen': '::', 'listen_port': 443, 'tls_id': 0};
      final detail = <String, Map<String, dynamic>>{
        'direct': {'network': 'tcp'}, 'mixed': {}, 'socks': {}, 'http': {},
        'shadowsocks': {'method': 'none', 'password': '', 'network': 'tcp'},
        'vmess': {'transport': <String, dynamic>{}}, 'trojan': {'transport': <String, dynamic>{}},
        'naive': {'quic_congestion_control': ''}, 'hysteria': {'up_mbps': 100, 'down_mbps': 100},
        'shadowtls': {'version': 3, 'password': '', 'handshake': {'server': '', 'server_port': 443}},
        'tuic': {'congestion_control': 'cubic', 'auth_timeout': '3s', 'heartbeat': '10s'},
        'hysteria2': {'up_mbps': 100, 'down_mbps': 100},
        'vless': {'transport': <String, dynamic>{}},
        'anytls': {'padding_scheme': ['stop=8', '0=30-30', '1=100-400']},
        'tun': {'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'], 'mtu': 9000, 'stack': 'system', 'udp_timeout': '5m', 'auto_route': false, 'strict_route': false},
        'redirect': {}, 'tproxy': {'network': 'tcp'},
      };
      return {...base, ...?detail[type]};
    }
    if (resource == 'outbounds') {
      final base = <String, dynamic>{'id': 0, 'type': type, 'tag': ''};
      final server = {'server': '', 'server_port': 443};
      final detail = <String, Map<String, dynamic>>{
        'direct': {}, 'socks': {...server, 'version': '5', 'username': '', 'password': ''},
        'http': {...server, 'username': '', 'password': '', 'tls': <String, dynamic>{}},
        'shadowsocks': {...server, 'method': 'none', 'password': '', 'multiplex': <String, dynamic>{}},
        'vmess': {...server, 'uuid': '', 'security': 'auto', 'alter_id': 0, 'global_padding': false, 'tls': <String, dynamic>{}, 'multiplex': <String, dynamic>{}, 'transport': <String, dynamic>{}},
        'trojan': {...server, 'password': '', 'tls': <String, dynamic>{}, 'multiplex': <String, dynamic>{}, 'transport': <String, dynamic>{}},
        'naive': {...server, 'username': '', 'password': '', 'tls': {'enabled': true}},
        'hysteria': {...server, 'up_mbps': 100, 'down_mbps': 100, 'auth_str': '', 'tls': {'enabled': true}},
        'vless': {...server, 'uuid': '', 'flow': 'xtls-rprx-vision', 'tls': <String, dynamic>{}, 'multiplex': <String, dynamic>{}, 'transport': <String, dynamic>{}},
        'shadowtls': {...server, 'version': 3, 'password': '', 'tls': {'enabled': true}},
        'tuic': {...server, 'uuid': '', 'password': '', 'congestion_control': 'cubic', 'tls': {'enabled': true}},
        'hysteria2': {...server, 'password': '', 'hop_interval': '30s', 'tls': {'enabled': true}},
        'anytls': {...server, 'password': '', 'idle_session_check_interval': '30s', 'idle_session_timeout': '30s', 'min_idle_session': 0, 'tls': {'enabled': true}},
        'tor': {'executable_path': './tor', 'data_directory': r'$HOME/.cache/tor', 'torrc': {'ClientOnly': '1'}},
        'ssh': {...server, 'user': '', 'password': ''},
        'selector': {'outbounds': <String>[], 'default': '', 'interrupt_exist_connections': false},
        'urltest': {'outbounds': <String>[], 'url': 'https://www.gstatic.com/generate_204', 'interval': '3m', 'tolerance': 50},
      };
      return {...base, ...?detail[type]};
    }
    if (resource == 'endpoints') {
      final base = <String, dynamic>{'id': 0, 'type': type, 'tag': ''};
      final detail = <String, Map<String, dynamic>>{
        'wireguard': {'address': ['10.0.0.2/32', 'fe80::2/128'], 'private_key': '', 'listen_port': 0, 'peers': <dynamic>[]},
        'warp': {'address': <String>[], 'private_key': '', 'listen_port': 0, 'mtu': 1420, 'peers': [{'server': '', 'server_port': 0, 'public_key': '', 'allowed_ips': <String>[]}]},
        'tailscale': {'domain_resolver': 'local', 'state_directory': '', 'auth_key': '', 'accept_routes': false, 'advertise_routes': <String>[]},
      };
      return {...base, ...?detail[type]};
    }
    if (resource == 'services') {
      final detail = <String, Map<String, dynamic>>{
        'derp': {'config_path': '', 'tls_id': 0},
        'resolved': {'listen': '::', 'listen_port': 53},
        'ssm-api': {'tls_id': 0, 'servers': <String, dynamic>{}},
        'ocm': {'listen': '::', 'listen_port': 8080, 'tls_id': 0, 'users': <dynamic>[], 'headers': <String, dynamic>{}},
        'ccm': {'listen': '::', 'listen_port': 8080, 'tls_id': 0, 'users': <dynamic>[], 'headers': <String, dynamic>{}},
      };
      return {'id': 0, 'type': type, 'tag': '', ...?detail[type]};
    }
    return {'type': type};
  }

  Map<String, dynamic> _clientConfig(String name) {
    final password = _randomText(12);
    final uuid = _uuid();
    return {
      'mixed': {'username': name, 'password': password}, 'socks': {'username': name, 'password': password}, 'http': {'username': name, 'password': password},
      'shadowsocks': {'name': name, 'password': _randomText(44)}, 'shadowsocks16': {'name': name, 'password': _randomText(24)}, 'shadowtls': {'name': name, 'password': _randomText(44)},
      'vmess': {'name': name, 'uuid': uuid, 'alterId': 0}, 'vless': {'name': name, 'uuid': uuid, 'flow': 'xtls-rprx-vision'},
      'anytls': {'name': name, 'password': password}, 'trojan': {'name': name, 'password': password}, 'naive': {'username': name, 'password': password},
      'hysteria': {'name': name, 'auth_str': password}, 'tuic': {'name': name, 'uuid': _uuid(), 'password': password}, 'hysteria2': {'name': name, 'password': password},
    };
  }

  String _randomText(int length) {
    const alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = math.Random.secure();
    return List.generate(length, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  String _uuid() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
