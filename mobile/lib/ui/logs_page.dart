import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_locale_context.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final search = TextEditingController();
  final user = TextEditingController();
  DateTime start = DateTime.now().subtract(const Duration(days: 1));
  DateTime end = DateTime.now();
  String level = 'ALL';
  List<dynamic> items = [];
  int total = 0;
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
    user.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = Map<String, dynamic>.from(await context.read<AppState>().api!.get('logs', query: {
        'level': level,
        'user': user.text.trim(),
        'search': search.text.trim(),
        'start': unixStartOfDay(start),
        'end': unixEndOfDay(end),
        'limit': 1000,
      }) as Map);
      if (mounted) {
        setState(() {
          items = List<dynamic>.from(result['items'] as List? ?? const []);
          total = int.tryParse(result['total']?.toString() ?? '') ?? 0;
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pickDate(bool isStart) async {
    final value = await showDatePicker(context: context, initialDate: isStart ? start : end, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (value == null) return;
    if (!mounted) return;
    setState(() {
      if (isStart) {
        start = value;
      } else {
        end = value;
      }
    });
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(title: context.t('logs.title'), subtitle: context.t('logs.subtitle')),
        FilterCard(
          child: Column(
            children: [
              Row(children: [Expanded(child: TextField(controller: search, onSubmitted: (_) => load(), decoration: InputDecoration(labelText: context.t('logs.fullText'), prefixIcon: const Icon(Icons.search)))), const SizedBox(width: 8), IconButton.filledTonal(onPressed: load, icon: const Icon(Icons.refresh))]),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: TextField(controller: user, onSubmitted: (_) => load(), decoration: InputDecoration(labelText: context.t('logs.user'), prefixIcon: const Icon(Icons.person_search_outlined)))), const SizedBox(width: 8), Expanded(child: AnchoredSelect<String>(value: level, label: context.t('logs.level'), options: [for (final value in const ['ALL', 'DEBUG', 'INFO', 'WARNING', 'ERROR']) SelectOption(value, value)], onChanged: (value) { setState(() => level = value); load(); }))]),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => pickDate(true), icon: const Icon(Icons.calendar_today_outlined), label: Text('${context.t('common.from')} ${_date(start)}'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: () => pickDate(false), icon: const Icon(Icons.event_outlined), label: Text('${context.t('common.to')} ${_date(end)}')))]),
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: error != null
              ? EmptyState(label: error!, icon: Icons.error_outline)
              : items.isEmpty
                  ? EmptyState(label: context.t('logs.empty'))
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: items.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) return Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(context.t('logs.count', args: {'count': total})));
                          return _logCard(Map<String, dynamic>.from(items[index - 1] as Map));
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _logCard(Map<String, dynamic> item) {
    final logLevel = item['level']?.toString() ?? 'INFO';
    final color = switch (logLevel) {
      'ERROR' => Colors.red,
      'WARNING' => Colors.orange,
      'DEBUG' => Colors.grey,
      _ => Colors.blue,
    };
    final connection = _connectionFromLog(item);
    final connectionMeta = connection == null
        ? null
        : _endpointSummary(context, _endpointInfo(connection, 'destinationInfo')) ?? _endpointSummary(context, _endpointInfo(connection, 'sourceInfo'));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(radius: 18, backgroundColor: color.withValues(alpha: .15), child: Icon(Icons.receipt_long_outlined, size: 18, color: color)),
        title: Text(item['message']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        subtitle: Text(
          [
            '${item['time'] ?? formatTimestamp(item['timestamp'])} · ${item['source'] ?? 'system'}${item['user']?.toString().isNotEmpty == true ? ' · ${item['user']}' : ''}',
            if (connectionMeta != null) connectionMeta,
          ].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Chip(label: Text(logLevel), side: BorderSide.none),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (connection != null) ..._endpointDetailWidgets(context, connection),
                  SelectableText(item['message']?.toString() ?? '', style: const TextStyle(fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime value) => '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

Map<String, dynamic>? _connectionFromLog(Map<String, dynamic> item) {
  final connection = item['connection'];
  if (connection is Map) return Map<String, dynamic>.from(connection);
  return null;
}

Map<String, dynamic>? _endpointInfo(Map<String, dynamic> item, String key) {
  final raw = item[key];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

String? _endpointSummary(BuildContext context, Map<String, dynamic>? info) {
  if (info == null) return null;
  final ip = info['ip']?.toString();
  final host = info['host']?.toString();
  final attribution = info['attribution']?.toString();
  final isp = info['isp']?.toString();
  final scope = _scopeLabel(context, info['scope']?.toString());
  final parts = <String>[
    if (ip != null && ip.isNotEmpty) ip else if (host != null && host.isNotEmpty) host,
    if (attribution != null && attribution.isNotEmpty) attribution else if (scope.isNotEmpty) scope,
    if (isp != null && isp.isNotEmpty) isp,
  ];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

List<Widget> _endpointDetailWidgets(BuildContext context, Map<String, dynamic> item) {
  final source = _endpointInfo(item, 'sourceInfo');
  final destination = _endpointInfo(item, 'destinationInfo');
  return [
    if (destination != null) ..._endpointLines(context, context.t('analytics.destination'), destination),
    if (source != null) ..._endpointLines(context, context.t('analytics.source'), source),
  ];
}

List<Widget> _endpointLines(BuildContext context, String title, Map<String, dynamic> info) {
  final values = <MapEntry<String, String>>[
    MapEntry(context.t('analytics.ipAddress'), info['ip']?.toString() ?? info['host']?.toString() ?? ''),
    MapEntry(context.t('analytics.ipAttribution'), info['attribution']?.toString() ?? _scopeLabel(context, info['scope']?.toString())),
    MapEntry(context.t('analytics.isp'), info['isp']?.toString() ?? ''),
    MapEntry(context.t('analytics.asn'), info['asn']?.toString() ?? ''),
    MapEntry(context.t('analytics.country'), info['country']?.toString() ?? ''),
    MapEntry(context.t('analytics.network'), info['network']?.toString() ?? ''),
  ].where((entry) => entry.value.isNotEmpty).toList();
  if (values.isEmpty) return const <Widget>[];
  return [
    Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    ),
    for (final value in values)
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 96, child: Text(value.key, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            Expanded(child: SelectableText(value.value)),
          ],
        ),
      ),
  ];
}

String _scopeLabel(BuildContext context, String? scope) {
  if (scope == null || scope.isEmpty) return '';
  final key = switch (scope) {
    'private' => 'analytics.scopePrivate',
    'loopback' => 'analytics.scopeLoopback',
    'link_local' => 'analytics.scopeLinkLocal',
    'multicast' => 'analytics.scopeMulticast',
    'reserved' => 'analytics.scopeReserved',
    'unspecified' => 'analytics.scopeReserved',
    'public' => 'analytics.scopePublic',
    'domain' => 'analytics.scopeDomain',
    _ => 'analytics.scopeUnknown',
  };
  return context.t(key);
}
