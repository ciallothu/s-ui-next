import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_locale_context.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final status = _map(state.bootstrap['status']);
    final panel = _map(state.bootstrap['panel']);
    final online = _map(panel['onlines']);
    final database = _map(status['db']);
    final system = _map(status['sys']);
    final core = _map(status['sbd']);
    final memory = _map(status['mem']);
    final disk = _map(status['dsk']);

    return RefreshIndicator(
      onRefresh: state.refreshBootstrap,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          PageHeader(
            title: context.t('dashboard.title'),
            subtitle: '${system['hostName'] ?? 'S-UI Next'} · v${system['appVersion'] ?? '—'}',
            actions: [
              IconButton.filledTonal(
                tooltip: context.t('dashboard.restartCore'),
                onPressed: () => _restartCore(context),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricCard(label: 'sing-box', value: core['running'] == true ? context.t('dashboard.running') : context.t('dashboard.stopped'), icon: Icons.power_settings_new, good: core['running'] == true),
                _MetricCard(label: 'CPU', value: '${(_number(status['cpu'])).toStringAsFixed(1)}%', icon: Icons.memory),
                _MetricCard(label: context.t('dashboard.memory'), value: '${formatBytes(memory['current'])} / ${formatBytes(memory['total'])}', icon: Icons.data_usage),
                _MetricCard(label: context.t('dashboard.disk'), value: '${formatBytes(disk['current'])} / ${formatBytes(disk['total'])}', icon: Icons.storage_outlined),
                _MetricCard(label: context.t('dashboard.totalUpload'), value: formatBytes(database['clientUp']), icon: Icons.upload, color: Colors.orange),
                _MetricCard(label: context.t('dashboard.totalDownload'), value: formatBytes(database['clientDown']), icon: Icons.download, color: Colors.green),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('dashboard.resources'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CountChip(label: context.t('dashboard.users'), value: database['clients']),
                        _CountChip(label: context.t('dashboard.inbounds'), value: database['inbounds']),
                        _CountChip(label: context.t('dashboard.outbounds'), value: database['outbounds']),
                        _CountChip(label: context.t('dashboard.nodes'), value: database['endpoints']),
                        _CountChip(label: context.t('dashboard.services'), value: database['services']),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('dashboard.onlineStatus'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _OnlineSection(label: context.t('dashboard.users'), values: _strings(online['user']), color: Colors.blue),
                    _OnlineSection(label: context.t('dashboard.inbounds'), values: _strings(online['inbound']), color: Colors.green),
                    _OnlineSection(label: context.t('dashboard.outbounds'), values: _strings(online['outbound']), color: Colors.teal),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restartCore(BuildContext context) async {
    if (!await confirm(context, title: context.tr('dashboard.restartCore'), message: context.tr('dashboard.restartConfirm'), action: context.tr('dashboard.restartCore'))) return;
    if (!context.mounted) return;
    try {
      await context.read<AppState>().api!.post('actions/restart-core');
      if (context.mounted) showMessage(context, context.tr('dashboard.restartSubmitted'));
    } catch (exception) {
      if (context.mounted) showMessage(context, exception.toString(), error: true);
    }
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon, this.good, this.color});
  final String label;
  final String value;
  final IconData icon;
  final bool? good;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 44) / (MediaQuery.sizeOf(context).width > 650 ? 3 : 2);
    final resolved = color ?? (good == false ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary);
    return SizedBox(
      width: width.clamp(150, 360).toDouble(),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: resolved),
              const SizedBox(height: 12),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label  ${value ?? 0}'));
}

class _OnlineSection extends StatelessWidget {
  const _OnlineSection({required this.label, required this.values, required this.color});
  final String label;
  final List<String> values;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 48, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(label))),
            Expanded(
              child: values.isEmpty
                  ? Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.t('dashboard.noOnline')))
                  : Wrap(spacing: 6, runSpacing: 6, children: [for (final value in values) Chip(label: Text(value), backgroundColor: color.withValues(alpha: .12))]),
            ),
          ],
        ),
      );
}

Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : {};
List<String> _strings(dynamic value) => value is List ? value.map((item) => item.toString()).toList() : [];
double _number(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;
