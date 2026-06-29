import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_localizations.dart';
import '../core/app_locale_context.dart';
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
          title: Text(context.t('tools.exportDbTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('tools.excludeStats')), value: excludeStats, onChanged: (value) => setDialogState(() => excludeStats = value ?? false)),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('tools.excludeChanges')), value: excludeChanges, onChanged: (value) => setDialogState(() => excludeChanges = value ?? false)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.t('common.cancel'))),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                final excluded = [if (excludeStats) 'stats', if (excludeChanges) 'changes'].join(',');
                await run(() => download('backup/database', 's-ui-backup.db', query: {'exclude': excluded}));
              },
              child: Text(context.t('tools.export')),
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
    if (!mounted || !await confirm(context, title: context.tr('tools.restoreDatabase'), message: context.tr('tools.restoreConfirm'), action: context.tr('tools.restoreDatabase'))) return;
    if (!mounted) return;
    await context.read<AppState>().api!.uploadDatabase('backup/database', path);
    if (mounted) showMessage(context, context.tr('tools.restoreDone'));
  }

  Future<void> restart(String action, String label) async {
    if (!await confirm(context, title: label, message: context.tr('tools.serviceUnavailable'), action: label)) return;
    if (!mounted) return;
    await context.read<AppState>().api!.post('actions/$action');
    if (mounted) showMessage(context, context.tr('tools.submitted', args: {'action': label}));
  }

  Future<void> textTool({required String title, required String hint, required String endpoint, required String field}) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 560, child: TextField(controller: controller, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: hint))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.t('common.cancel'))),
          FilledButton(
            onPressed: () async {
              try {
                final result = await context.read<AppState>().api!.post(endpoint, data: {field: controller.text.trim()});
                if (!mounted) return;
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  await showDialog<void>(context: context, builder: (resultContext) => AlertDialog(title: Text('${context.t('common.result')} · $title'), content: SizedBox(width: 620, child: SelectableText(prettyJson(result), style: const TextStyle(fontFamily: 'monospace'))), actions: [FilledButton(onPressed: () => Navigator.pop(resultContext), child: Text(context.t('common.close')))]));
                }
              } catch (exception) {
                if (dialogContext.mounted) showMessage(dialogContext, exception.toString(), error: true);
              }
            },
            child: Text(context.t('common.confirm')),
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
          title: Text(context.t('tools.keypair')),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [AnchoredSelect<String>(value: type, label: context.t('tools.keyType'), options: [for (final value in const ['reality', 'wireguard', 'wireguard-psk', 'tls', 'ech']) SelectOption(value, value)], onChanged: (value) => setDialogState(() => type = value)), const SizedBox(height: 10), TextField(controller: options, decoration: InputDecoration(labelText: context.t('tools.optionsServer')))]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.t('common.cancel'))),
            FilledButton(
              onPressed: () async {
                try {
                  final result = await this.context.read<AppState>().api!.post('tools/keypair', data: {'type': type, 'options': options.text});
                  if (!mounted) return;
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    await showDialog<void>(context: this.context, builder: (resultContext) => AlertDialog(title: Text(context.t('tools.keypair')), content: SizedBox(width: 620, child: SelectableText((result as List).join('\n'), style: const TextStyle(fontFamily: 'monospace'))), actions: [FilledButton(onPressed: () => Navigator.pop(resultContext), child: Text(context.t('common.close')))]));
                  }
                } catch (exception) {
                  if (dialogContext.mounted) showMessage(dialogContext, exception.toString(), error: true);
                }
              },
              child: Text(context.t('tools.generate')),
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
            PageHeader(title: context.t('tools.title'), subtitle: context.t('tools.subtitle')),
            _group(
              context.t('tools.currentConnection'),
              [
                ListTile(leading: const Icon(Icons.link), title: Text(state.profile?.name ?? 'S-UI'), subtitle: Text(state.profile?.normalizedBaseUrl ?? '')),
                ListTile(leading: const Icon(Icons.translate), title: Text(context.t('common.language')), trailing: SizedBox(width: 160, child: AnchoredSelect<String>(value: state.localeCode, compact: true, options: [for (final language in AppLocalizations.languages) SelectOption(language.code, language.label)], onChanged: state.setLocale))),
                ListTile(leading: const Icon(Icons.http), title: Text(context.t('tools.customHeaders')), subtitle: Text(state.profile?.activeHeaders.keys.join('\n') ?? context.t('tools.noHeaders'))),
                ListTile(leading: const Icon(Icons.edit_outlined), title: Text(context.t('tools.reconfigure')), subtitle: Text(context.t('tools.reconfigureHint')), onTap: state.reconfigure),
              ],
            ),
            _group(
              context.t('tools.backupRestore'),
              [
                ListTile(leading: const Icon(Icons.download_outlined), title: Text(context.t('tools.exportDatabase')), onTap: backupDatabase),
                ListTile(leading: const Icon(Icons.settings_backup_restore), title: Text(context.t('tools.restoreDatabase')), onTap: () => run(restoreDatabase)),
                ListTile(leading: const Icon(Icons.data_object), title: Text(context.t('tools.exportSingbox')), onTap: () => run(() => download('backup/singbox', 'sing-box-config.json'))),
              ],
            ),
            _group(
              context.t('tools.conversionKeys'),
              [
                ListTile(leading: const Icon(Icons.swap_horiz), title: Text(context.t('tools.linkConvert')), onTap: () => textTool(title: context.t('tools.linkConvertTitle'), hint: context.t('tools.shareLink'), endpoint: 'tools/link-convert', field: 'link')),
                ListTile(leading: const Icon(Icons.playlist_add), title: Text(context.t('tools.subConvert')), onTap: () => textTool(title: context.t('tools.subConvertTitle'), hint: context.t('tools.subscriptionUrl'), endpoint: 'tools/sub-convert', field: 'link')),
                ListTile(leading: const Icon(Icons.key_outlined), title: Text(context.t('tools.keypair')), onTap: keypair),
              ],
            ),
            _group(
              context.t('tools.serviceActions'),
              [
                ListTile(leading: const Icon(Icons.restart_alt), title: Text(context.t('tools.restartCore')), onTap: () => run(() => restart('restart-core', context.t('tools.restartCore')))),
                ListTile(leading: const Icon(Icons.power_settings_new), title: Text(context.t('tools.restartPanel')), onTap: () => run(() => restart('restart-panel', context.t('tools.restartPanel')))),
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
