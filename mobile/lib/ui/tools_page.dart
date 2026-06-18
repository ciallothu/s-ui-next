import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../state/app_state.dart';
import 'widgets.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  bool busy = false;

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (exception) {
      if (mounted) showMessage(context, exception.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download(String path, String filename, {Map<String, dynamic>? query}) async {
    final bytes = await context.read<AppState>().api!.download(path, query: query);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: filename));
  }

  Future<void> backupDatabase() async {
    var excludeStats = false;
    var excludeChanges = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('导出数据库'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('排除统计历史'), value: excludeStats, onChanged: (value) => setDialogState(() => excludeStats = value ?? false)),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('排除变更记录'), value: excludeChanges, onChanged: (value) => setDialogState(() => excludeChanges = value ?? false)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                final excluded = [if (excludeStats) 'stats', if (excludeChanges) 'changes'].join(',');
                await run(() => download('backup/database', 's-ui-backup.db', query: {'exclude': excluded}));
              },
              child: const Text('导出'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> restoreDatabase() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['db']);
    final path = result?.files.single.path;
    if (path == null) return;
    if (!mounted || !await confirm(context, title: '恢复数据库', message: '恢复会替换当前面板数据库，请先确认已有可用备份。', action: '恢复')) return;
    if (!mounted) return;
    await context.read<AppState>().api!.uploadDatabase('backup/database', path);
    if (mounted) showMessage(context, '数据库已恢复，建议重启面板');
  }

  Future<void> restart(String action, String label) async {
    if (!await confirm(context, title: label, message: '服务会短暂不可用。', action: label)) return;
    if (!mounted) return;
    await context.read<AppState>().api!.post('actions/$action');
    if (mounted) showMessage(context, '已提交$label');
  }

  Future<void> textTool({required String title, required String hint, required String endpoint, required String field}) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 560, child: TextField(controller: controller, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: hint))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              try {
                final result = await context.read<AppState>().api!.post(endpoint, data: {field: controller.text.trim()});
                if (!mounted) return;
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  await showDialog<void>(context: context, builder: (resultContext) => AlertDialog(title: Text('$title结果'), content: SizedBox(width: 620, child: SelectableText(prettyJson(result), style: const TextStyle(fontFamily: 'monospace'))), actions: [FilledButton(onPressed: () => Navigator.pop(resultContext), child: const Text('关闭'))]));
                }
              } catch (exception) {
                if (dialogContext.mounted) showMessage(dialogContext, exception.toString(), error: true);
              }
            },
            child: const Text('执行'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> keypair() async {
    var type = 'reality';
    final options = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('生成密钥'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: '类型'), items: const ['reality', 'wireguard', 'tls', 'ech'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setDialogState(() => type = value ?? type)), const SizedBox(height: 10), TextField(controller: options, decoration: const InputDecoration(labelText: '选项 / Server Name（可选）'))]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                try {
                  final result = await this.context.read<AppState>().api!.post('tools/keypair', data: {'type': type, 'options': options.text});
                  if (!mounted) return;
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    await showDialog<void>(context: this.context, builder: (resultContext) => AlertDialog(title: const Text('密钥'), content: SizedBox(width: 620, child: SelectableText((result as List).join('\n'), style: const TextStyle(fontFamily: 'monospace'))), actions: [FilledButton(onPressed: () => Navigator.pop(resultContext), child: const Text('关闭'))]));
                  }
                } catch (exception) {
                  if (dialogContext.mounted) showMessage(dialogContext, exception.toString(), error: true);
                }
              },
              child: const Text('生成'),
            ),
          ],
        ),
      ),
    );
    options.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const PageHeader(title: '设置与工具', subtitle: '连接信息、备份恢复、转换器和服务操作'),
            _group(
              '当前连接',
              [
                ListTile(leading: const Icon(Icons.link), title: Text(state.profile?.name ?? 'S-UI'), subtitle: Text(state.profile?.normalizedBaseUrl ?? '')),
                ListTile(leading: const Icon(Icons.http), title: const Text('自定义 Header'), subtitle: Text(state.profile?.activeHeaders.keys.join('\n') ?? '未配置')),
                ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('重新配置连接'), subtitle: const Text('返回连接页修改地址、Token 或 Cloudflare Header'), onTap: state.reconfigure),
              ],
            ),
            _group(
              '备份与恢复',
              [
                ListTile(leading: const Icon(Icons.download_outlined), title: const Text('导出数据库'), onTap: backupDatabase),
                ListTile(leading: const Icon(Icons.settings_backup_restore), title: const Text('恢复数据库'), onTap: () => run(restoreDatabase)),
                ListTile(leading: const Icon(Icons.data_object), title: const Text('导出 sing-box 配置'), onTap: () => run(() => download('backup/singbox', 'sing-box-config.json'))),
              ],
            ),
            _group(
              '转换与密钥',
              [
                ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('分享链接转出站'), onTap: () => textTool(title: '链接转换', hint: '分享链接', endpoint: 'tools/link-convert', field: 'link')),
                ListTile(leading: const Icon(Icons.playlist_add), title: const Text('外部订阅转换'), onTap: () => textTool(title: '订阅转换', hint: '订阅 URL', endpoint: 'tools/sub-convert', field: 'link')),
                ListTile(leading: const Icon(Icons.key_outlined), title: const Text('生成密钥对'), onTap: keypair),
              ],
            ),
            _group(
              '服务操作',
              [
                ListTile(leading: const Icon(Icons.restart_alt), title: const Text('重启 sing-box'), onTap: () => run(() => restart('restart-core', '重启 sing-box'))),
                ListTile(leading: const Icon(Icons.power_settings_new), title: const Text('重启 S-UI 面板'), onTap: () => run(() => restart('restart-panel', '重启面板'))),
              ],
            ),
          ],
        ),
        if (busy) const Positioned.fill(child: ColoredBox(color: Color(0x33000000), child: Center(child: CircularProgressIndicator()))),
      ],
    );
  }

  Widget _group(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))), ...children]),
      );
}
