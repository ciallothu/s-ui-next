import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'visual_editor.dart';
import 'widgets.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> with SingleTickerProviderStateMixin {
  late final TabController tabs;
  Map<String, dynamic> config = {};
  Map<String, dynamic> settings = {};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 5, vsync: this);
    load();
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final state = context.read<AppState>();
      final values = await Future.wait([state.getResource('config'), state.getResource('settings')]);
      if (mounted) {
        setState(() {
          config = Map<String, dynamic>.from(values[0] as Map);
          settings = Map<String, dynamic>.from(values[1] as Map);
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> editConfigSection(String title, List<String> keys) async {
    final section = <String, dynamic>{for (final key in keys) key: config[key]};
    await showDialog<bool>(
      context: context,
      builder: (_) => VisualEditorDialog(
        title: title,
        resource: 'config',
        initialValue: section,
        onSave: (value) async {
          if (value is! Map) throw const FormatException('配置必须是 JSON 对象');
          final next = Map<String, dynamic>.from(config);
          for (final key in keys) {
            if (value.containsKey(key)) {
              next[key] = value[key];
            } else {
              next.remove(key);
            }
          }
          await context.read<AppState>().saveResource('config', 'set', next);
        },
      ),
    );
    await load();
  }

  Future<void> editSettings() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => VisualEditorDialog(
        title: '面板与订阅设置',
        resource: 'settings',
        initialValue: settings,
        onSave: (value) async {
          if (value is! Map) throw const FormatException('设置必须是 JSON 对象');
          await context.read<AppState>().saveResource('settings', 'set', value);
        },
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return EmptyState(label: error!, icon: Icons.error_outline);
    return Column(
      children: [
        const PageHeader(title: '核心配置', subtitle: '基础、DNS、路由和面板设置保持与 Web 版同一份数据'),
        TabBar(
          controller: tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: '基础'),
            Tab(text: 'DNS'),
            Tab(text: '路由'),
            Tab(text: '实验性'),
            Tab(text: '面板设置'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: tabs,
            children: [
              _section('基础信息', ['log', 'ntp'], Icons.settings_input_component_outlined),
              _section('DNS', ['dns'], Icons.dns_outlined),
              _section('路由与规则集', ['route'], Icons.route_outlined),
              _section('Experimental', ['experimental'], Icons.science_outlined),
              _settingsSection(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String title, List<String> keys, IconData icon) {
    final value = <String, dynamic>{for (final key in keys) key: config[key]};
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(icon), const SizedBox(width: 10), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))), FilledButton.tonalIcon(onPressed: () => editConfigSection(title, keys), icon: const Icon(Icons.edit_outlined), label: const Text('编辑'))]),
                const SizedBox(height: 16),
                SelectableText(const JsonEncoder.withIndent('  ').convert(value), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingsSection() {
    final groups = <String, List<String>>{
      '面板接口': ['webListen', 'webPort', 'webPath', 'webDomain', 'webCertFile', 'webKeyFile', 'webURI', 'sessionMaxAge', 'trafficAge', 'timeLocation'],
      '订阅服务': ['subListen', 'subPort', 'subPath', 'subDomain', 'subCertFile', 'subKeyFile', 'subUpdates', 'subEncode', 'subShowInfo', 'subInfoUpload', 'subInfoDownload', 'subInfoTotal', 'subInfoExpire', 'subInfoRemaining', 'subURI'],
      '订阅扩展': ['subJsonExt', 'subClashExt'],
	  '登录与身份': ['oidcEnabled', 'oidcIssuer', 'oidcClientId', 'oidcClientSecret', 'oidcRedirectUrl', 'oidcScopes', 'oidcUsernameClaim', 'oidcAllowedUsers', 'passkeyEnabled', 'passkeyRpId', 'passkeyOrigins'],
    };
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: editSettings, icon: const Icon(Icons.edit_outlined), label: const Text('编辑全部设置'))),
        const SizedBox(height: 8),
        for (final group in groups.entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.key, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Divider(),
                  for (final key in group.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 130, child: Text(key, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))), Expanded(child: SelectableText(settings[key]?.toString() ?? ''))]),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
