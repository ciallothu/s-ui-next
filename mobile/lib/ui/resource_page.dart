import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/app_state.dart';
import 'visual_editor.dart';
import 'widgets.dart';

class ResourcePage extends StatefulWidget {
  const ResourcePage({super.key, required this.resource, required this.title, required this.icon});

  final String resource;
  final String title;
  final IconData icon;

  @override
  State<ResourcePage> createState() => _ResourcePageState();
}

class _ResourcePageState extends State<ResourcePage> {
  final search = TextEditingController();
  List<dynamic> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await context.read<AppState>().getResource(widget.resource);
      final value = result is List ? result : const [];
      if (mounted) setState(() => items = List<dynamic>.from(value));
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<dynamic> get filtered {
    final query = search.text.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items.where((item) => jsonEncode(item).toLowerCase().contains(query)).toList();
  }

  dynamic template() => VisualEditorSchema.forResource(widget.resource).defaultValue();

  Future<void> edit(dynamic item, String action) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => VisualEditorDialog(
        title: '${widget.title} · ${_actionName(action)}',
        resource: widget.resource,
        initialValue: item,
        onSave: (value) async {
          await context.read<AppState>().saveResource(widget.resource, action, value);
        },
      ),
    );
    await load();
  }

  Future<void> remove(dynamic item) async {
    if (!await confirm(context, title: '删除${widget.title}', message: '此操作会立即更新 sing-box 配置。', action: '删除')) return;
    if (!mounted) return;
    try {
      final value = item is Map
          ? (widget.resource == 'clients' || widget.resource == 'tls' ? item['id'] : item['tag'])
          : item;
      await context.read<AppState>().saveResource(widget.resource, 'del', value);
      await load();
      if (mounted) showMessage(context, '已删除');
    } catch (exception) {
      if (mounted) showMessage(context, exception.toString(), error: true);
    }
  }

  Future<void> bulk() async {
    var action = 'addbulk';
    final controller = TextEditingController(text: '[]');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('批量操作'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: action,
                  items: const [
                    DropdownMenuItem(value: 'addbulk', child: Text('批量添加')),
                    DropdownMenuItem(value: 'editbulk', child: Text('批量编辑')),
                    DropdownMenuItem(value: 'delbulk', child: Text('批量删除')),
                  ],
                  onChanged: (value) => setDialogState(() => action = value ?? action),
                  decoration: const InputDecoration(labelText: '操作'),
                ),
                const SizedBox(height: 12),
                TextField(controller: controller, minLines: 8, maxLines: 16, style: const TextStyle(fontFamily: 'monospace'), decoration: const InputDecoration(labelText: 'JSON 数组')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                try {
                  final value = jsonDecode(controller.text);
                  await this.context.read<AppState>().saveResource(widget.resource, action, value);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await load();
                } catch (exception) {
                  if (dialogContext.mounted) showMessage(dialogContext, exception.toString(), error: true);
                }
              },
              child: const Text('执行'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> checkOutbound(Map<String, dynamic> item) async {
    try {
      final result = Map<String, dynamic>.from(await context.read<AppState>().api!.get('tools/check-outbound', query: {'tag': item['tag']}) as Map);
      if (!mounted) return;
      final ok = result['OK'] == true;
      final delay = result['Delay'];
      showMessage(context, ok ? '连接正常${delay == null ? '' : ' · ${delay}ms'}' : result['Error']?.toString() ?? '测试失败', error: !ok);
    } catch (exception) {
      if (mounted) showMessage(context, exception.toString(), error: true);
    }
  }

  Future<void> showClientQr(Map<String, dynamic> summary) async {
    try {
      final result = await context.read<AppState>().getResource('clients', id: summary['id']?.toString());
      final list = result is List ? result : const [];
      if (list.isEmpty) throw const FormatException('找不到用户详情');
      final client = Map<String, dynamic>.from(list.first as Map);
      if (!mounted) return;
      final state = context.read<AppState>();
      final panel = state.bootstrap['panel'];
      final subBase = panel is Map ? panel['subURI']?.toString() ?? '' : '';
      final values = <_QrValue>[];
      if (subBase.isNotEmpty) {
        final subscription = '$subBase${client['name']}';
        values.addAll([
          _QrValue('订阅', subscription),
          _QrValue('JSON 订阅', '$subscription?format=json'),
          _QrValue('Clash 订阅', '$subscription?format=clash'),
          _QrValue('Sing-box 导入', 'sing-box://import-remote-profile?url=${Uri.encodeComponent('$subscription?format=json')}#${client['name']}'),
        ]);
      }
      final links = client['links'];
      if (links is List) {
        for (final raw in links) {
          if (raw is Map && raw['uri'] != null) values.add(_QrValue(raw['remark']?.toString() ?? raw['type']?.toString() ?? '分享链接', raw['uri'].toString()));
        }
      }
      if (!mounted) return;
      await _showQrValues('${client['name']} · 二维码', values);
    } catch (exception) {
      if (mounted) showMessage(context, exception.toString(), error: true);
    }
  }

  Future<void> showWireguardQr(Map<String, dynamic> item) async {
    final peers = item['peers'];
    final ext = item['ext'];
    if (peers is! List || ext is! Map) {
      showMessage(context, '节点没有可用的 WireGuard Peer 配置', error: true);
      return;
    }
    final host = Uri.tryParse(context.read<AppState>().profile?.normalizedBaseUrl ?? '')?.host ?? '';
    final values = <_QrValue>[];
    for (var index = 0; index < peers.length; index++) {
      final peer = peers[index];
      if (peer is! Map) continue;
      final keys = ext['keys'];
      Map? keyPair;
      if (keys is List) {
        for (final key in keys) {
          if (key is Map && key['public_key'] == peer['public_key']) keyPair = key;
        }
      }
      if (keyPair == null || ext['public_key'] == null) continue;
      final buffer = StringBuffer()
        ..writeln('[Interface]')
        ..writeln('PrivateKey = ${keyPair['private_key']}')
        ..writeln('Address = ${(peer['allowed_ips'] as List? ?? const []).join(',')}')
        ..writeln('DNS = ${ext['dns'] ?? '1.1.1.1, 9.9.9.9'}');
      if (item['mtu'] != null) buffer.writeln('MTU = ${item['mtu']}');
      buffer
        ..writeln('\n[Peer]')
        ..writeln('PublicKey = ${ext['public_key']}')
        ..writeln('AllowedIPs = 0.0.0.0/0, ::/0')
        ..writeln('Endpoint = $host:${item['listen_port']}');
      if (peer['pre_shared_key'] != null) buffer.writeln('PresharedKey = ${peer['pre_shared_key']}');
      if (peer['persistent_keepalive_interval'] != null) buffer.writeln('PersistentKeepalive = ${peer['persistent_keepalive_interval']}');
      values.add(_QrValue('Peer ${index + 1}', buffer.toString()));
    }
    await _showQrValues('${item['tag']} · WireGuard', values);
  }

  Future<void> _showQrValues(String title, List<_QrValue> values) async {
    if (values.isEmpty) {
      showMessage(context, '没有可展示的链接', error: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: Text(title), leading: IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final value in values)
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(value.label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        ColoredBox(color: Colors.white, child: Padding(padding: const EdgeInsets.all(10), child: QrImageView(data: value.value, size: 260))),
                        const SizedBox(height: 10),
                        SelectableText(value.value, maxLines: 4),
                        TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: value.value)); showMessage(context, '已复制'); }, icon: const Icon(Icons.copy), label: const Text('复制')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: widget.title,
          subtitle: '完整字段编辑与搜索，兼容 sing-box 新协议字段',
          actions: [
            IconButton.filledTonal(tooltip: '批量操作', onPressed: bulk, icon: const Icon(Icons.playlist_add)),
            const SizedBox(width: 8),
            IconButton.filled(tooltip: '新建', onPressed: () => edit(template(), 'new'), icon: const Icon(Icons.add)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: '搜索${widget.title}', prefixIcon: const Icon(Icons.search), suffixIcon: search.text.isEmpty ? null : IconButton(onPressed: () => setState(search.clear), icon: const Icon(Icons.clear))),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? EmptyState(label: error!, icon: Icons.error_outline)
                  : filtered.isEmpty
                      ? const EmptyState(label: '没有匹配的数据')
                      : RefreshIndicator(
                          onRefresh: load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) => _resourceCard(filtered[index]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _resourceCard(dynamic raw) {
    final item = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{'value': raw};
    final title = item['name']?.toString().isNotEmpty == true ? item['name'].toString() : item['tag']?.toString().isNotEmpty == true ? item['tag'].toString() : '#${item['id'] ?? '—'}';
    final subtitle = [item['type'], if (item['group']?.toString().isNotEmpty == true) item['group'], if (item['listen_port'] != null) ':${item['listen_port']}'].where((value) => value != null).join(' · ');
    final enabled = item['enable'];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: CircleAvatar(
          backgroundColor: enabled == false ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.primaryContainer,
          child: Icon(widget.icon, color: enabled == false ? Theme.of(context).colorScheme.onErrorContainer : Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            switch (action) {
              case 'edit':
                edit(item, 'edit');
                return;
              case 'clone':
                final clone = Map<String, dynamic>.from(item)..['id'] = 0;
                edit(clone, 'new');
                return;
              case 'copy':
                Clipboard.setData(ClipboardData(text: prettyJson(item)));
                showMessage(context, 'JSON 已复制');
                return;
              case 'delete':
                remove(item);
                return;
              case 'test':
                checkOutbound(item);
                return;
              case 'qr-client':
                showClientQr(item);
                return;
              case 'qr-wireguard':
                showWireguardQr(item);
                return;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('编辑'))),
            const PopupMenuItem(value: 'clone', child: ListTile(leading: Icon(Icons.copy_all_outlined), title: Text('克隆'))),
            if (widget.resource == 'outbounds') const PopupMenuItem(value: 'test', child: ListTile(leading: Icon(Icons.speed_outlined), title: Text('连接测试'))),
            if (widget.resource == 'clients') const PopupMenuItem(value: 'qr-client', child: ListTile(leading: Icon(Icons.qr_code), title: Text('订阅与二维码'))),
            if (widget.resource == 'endpoints' && item['type'] == 'wireguard') const PopupMenuItem(value: 'qr-wireguard', child: ListTile(leading: Icon(Icons.qr_code), title: Text('WireGuard 二维码'))),
            const PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.content_copy), title: Text('复制 JSON'))),
            const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('删除'))),
          ],
        ),
        onTap: () => edit(item, 'edit'),
      ),
    );
  }

  String _actionName(String action) => const {'new': '新建', 'edit': '编辑'}[action] ?? action;
}

class _QrValue {
  const _QrValue(this.label, this.value);
  final String label;
  final String value;
}
