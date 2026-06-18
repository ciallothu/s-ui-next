import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'widgets.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> with SingleTickerProviderStateMixin {
  late final TabController tabs;
  final search = TextEditingController();
  final user = TextEditingController();
  DateTime start = DateTime.now().subtract(const Duration(days: 7));
  DateTime end = DateTime.now();
  String resource = 'user';
  bool loading = false;
  List<dynamic> usageItems = [];
  List<dynamic> statItems = [];
  int usageTotal = 0;
  int upload = 0;
  int download = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 2, vsync: this)..addListener(() {
        if (!tabs.indexIsChanging) load();
      });
    load();
  }

  @override
  void dispose() {
    tabs.dispose();
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
      final query = <String, dynamic>{
        'start': unixStartOfDay(start),
        'end': unixEndOfDay(end),
        'search': search.text.trim(),
        'limit': tabs.index == 0 ? 500 : 2000,
      };
      final api = context.read<AppState>().api!;
      if (tabs.index == 0) {
        if (user.text.trim().isNotEmpty) query['user'] = user.text.trim();
        final result = Map<String, dynamic>.from(await api.get('analytics/usage', query: query) as Map);
        if (mounted) {
          setState(() {
            usageItems = List<dynamic>.from(result['items'] as List? ?? const []);
            usageTotal = int.tryParse(result['total']?.toString() ?? '') ?? 0;
            upload = int.tryParse(result['upload']?.toString() ?? '') ?? 0;
            download = int.tryParse(result['download']?.toString() ?? '') ?? 0;
          });
        }
      } else {
        query['resource'] = resource;
        if (user.text.trim().isNotEmpty) query['tag'] = user.text.trim();
        final result = Map<String, dynamic>.from(await api.get('analytics/stats', query: query) as Map);
        if (mounted) setState(() => statItems = List<dynamic>.from(result['items'] as List? ?? const []));
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pickDate(bool isStart) async {
    final value = await showDatePicker(
      context: context,
      initialDate: isStart ? start : end,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (value == null) return;
    if (!mounted) return;
    setState(() {
      if (isStart) {
        start = value;
        if (start.isAfter(end)) end = start;
      } else {
        end = value;
        if (end.isBefore(start)) start = end;
      }
    });
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PageHeader(title: '用量与统计', subtitle: '按用户、日期与关键词筛选，支持流量汇总和原始趋势'),
        TabBar(controller: tabs, tabs: const [Tab(text: '用户用量'), Tab(text: '流量趋势')]),
        FilterCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: TextField(controller: search, onSubmitted: (_) => load(), decoration: const InputDecoration(labelText: '搜索', prefixIcon: Icon(Icons.search)))),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: loading ? null : load, icon: const Icon(Icons.refresh)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: user, onSubmitted: (_) => load(), decoration: InputDecoration(labelText: tabs.index == 0 ? '用户（精确，可留空）' : 'Tag（精确，可留空）', prefixIcon: const Icon(Icons.person_search_outlined)))),
                  if (tabs.index == 1) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: resource,
                        decoration: const InputDecoration(labelText: '资源'),
                        items: const [
                          DropdownMenuItem(value: 'user', child: Text('用户')),
                          DropdownMenuItem(value: 'inbound', child: Text('入站')),
                          DropdownMenuItem(value: 'outbound', child: Text('出站')),
                          DropdownMenuItem(value: 'endpoint', child: Text('节点')),
                          DropdownMenuItem(value: 'all', child: Text('全部')),
                        ],
                        onChanged: (value) {
                          setState(() => resource = value ?? 'user');
                          load();
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: OutlinedButton.icon(onPressed: () => pickDate(true), icon: const Icon(Icons.calendar_today_outlined), label: Text('起 ${_date(start)}'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: () => pickDate(false), icon: const Icon(Icons.event_outlined), label: Text('止 ${_date(end)}'))),
                ],
              ),
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: error != null
              ? EmptyState(label: error!, icon: Icons.error_outline)
              : TabBarView(controller: tabs, children: [_usage(), _stats()]),
        ),
      ],
    );
  }

  Widget _usage() {
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          Row(
            children: [
              Expanded(child: _SummaryCard(label: '上传', value: formatBytes(upload), color: Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _SummaryCard(label: '下载', value: formatBytes(download), color: Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _SummaryCard(label: '合计', value: formatBytes(upload + download), color: Colors.blue)),
            ],
          ),
          Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4), child: Text('$usageTotal 位用户')),
          if (usageItems.isEmpty)
            const EmptyState(label: '当前筛选范围没有用量数据')
          else
            for (final raw in usageItems) _usageCard(Map<String, dynamic>.from(raw as Map)),
        ],
      ),
    );
  }

  Widget _usageCard(Map<String, dynamic> item) {
    final total = _int(item['total']);
    final quota = _int(item['quota']);
    final progress = quota > 0 ? (total / quota).clamp(0.0, 1.0).toDouble() : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(item['online'] == true ? Icons.circle : Icons.circle_outlined, size: 12, color: item['online'] == true ? Colors.green : null), const SizedBox(width: 8), Expanded(child: Text(item['user']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700))), if (item['group']?.toString().isNotEmpty == true) Chip(label: Text(item['group'].toString()))]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: Text('↑ ${formatBytes(item['upload'])}', style: const TextStyle(color: Colors.orange))), Expanded(child: Text('↓ ${formatBytes(item['download'])}', style: const TextStyle(color: Colors.green))), Text(formatBytes(total), style: const TextStyle(fontWeight: FontWeight.w700))]),
            if (quota > 0) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 4),
              Text('所选日期用量 / 配额 ${formatBytes(quota)}', style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_int(item['expiry']) > 0) Padding(padding: const EdgeInsets.only(top: 5), child: Text('到期 ${formatTimestamp(item['expiry'])}', style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }

  Widget _stats() {
    if (statItems.isEmpty) return const EmptyState(label: '当前筛选范围没有统计数据');
    final points = statItems.map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final uploadPoints = points.where((item) => item['direction'] == true).toList();
    final downloadPoints = points.where((item) => item['direction'] != true).toList();
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$resource · ${user.text.trim().isEmpty ? '全部 Tag' : user.text.trim()}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SizedBox(height: 220, child: CustomPaint(painter: _TrafficPainter(uploadPoints, downloadPoints), child: const SizedBox.expand())),
                  const SizedBox(height: 8),
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.circle, size: 10, color: Colors.orange), SizedBox(width: 5), Text('上传'), SizedBox(width: 16), Icon(Icons.circle, size: 10, color: Colors.green), SizedBox(width: 5), Text('下载')]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in points.reversed.take(100))
            ListTile(
              dense: true,
              leading: Icon(item['direction'] == true ? Icons.upload : Icons.download, color: item['direction'] == true ? Colors.orange : Colors.green),
              title: Text('${item['resource']} · ${item['tag']}'),
              subtitle: Text(formatTimestamp(item['dateTime'])),
              trailing: Text(formatBytes(item['traffic'])),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [Text(label, style: TextStyle(color: color)), const SizedBox(height: 5), FittedBox(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)))]),
        ),
      );
}

class _TrafficPainter extends CustomPainter {
  _TrafficPainter(this.upload, this.download);
  final List<Map<String, dynamic>> upload;
  final List<Map<String, dynamic>> download;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = Colors.grey.withValues(alpha: .2)..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final all = [...upload, ...download];
    if (all.isEmpty) return;
    final minTime = all.map((item) => _int(item['dateTime'])).reduce((a, b) => a < b ? a : b);
    final maxTime = all.map((item) => _int(item['dateTime'])).reduce((a, b) => a > b ? a : b);
    final maxTraffic = math.max(1, all.map((item) => _int(item['traffic'])).reduce((a, b) => a > b ? a : b)).toInt();
    drawSeries(canvas, size, upload, Colors.orange, minTime, maxTime, maxTraffic);
    drawSeries(canvas, size, download, Colors.green, minTime, maxTime, maxTraffic);
  }

  void drawSeries(Canvas canvas, Size size, List<Map<String, dynamic>> values, Color color, int minTime, int maxTime, int maxTraffic) {
    if (values.isEmpty) return;
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2;
    final pointPaint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path();
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final time = _int(values[index]['dateTime']);
      final traffic = _int(values[index]['traffic']);
      final x = maxTime == minTime ? size.width / 2 : (time - minTime) / (maxTime - minTime) * size.width;
      final y = size.height - (traffic / maxTraffic * size.height);
      points.add(Offset(x, y));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
    for (final point in points) {
      canvas.drawCircle(point, 3.25, pointPaint);
      canvas.drawCircle(point, 1.25, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _TrafficPainter oldDelegate) => oldDelegate.upload != upload || oldDelegate.download != download;
}

int _int(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
String _date(DateTime value) => '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
