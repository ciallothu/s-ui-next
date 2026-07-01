import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_locale_context.dart';
import '../state/app_state.dart';
import 'admin_page.dart';
import 'analytics_page.dart';
import 'config_page.dart';
import 'dashboard_page.dart';
import 'resource_page.dart';
import 'tools_page.dart';
import 'widgets.dart';

class _Destination {
  const _Destination(this.labelKey, this.icon, this.builder);
  final String labelKey;
  final IconData icon;
  final Widget Function(BuildContext context) builder;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selected = 0;

  late final destinations = <_Destination>[
    _Destination('nav.home', Icons.home_outlined, (_) => const DashboardPage()),
    _Destination('nav.clients', Icons.people_outline, (context) => ResourcePage(resource: 'clients', title: context.t('nav.clients'), icon: Icons.people_outline)),
    _Destination('nav.inbounds', Icons.cloud_download_outlined, (context) => ResourcePage(resource: 'inbounds', title: context.t('nav.inbounds'), icon: Icons.cloud_download_outlined)),
    _Destination('nav.outbounds', Icons.cloud_upload_outlined, (context) => ResourcePage(resource: 'outbounds', title: context.t('nav.outbounds'), icon: Icons.cloud_upload_outlined)),
    _Destination('nav.endpoints', Icons.cloud_queue_outlined, (context) => ResourcePage(resource: 'endpoints', title: context.t('nav.endpoints'), icon: Icons.cloud_queue_outlined)),
    _Destination('nav.services', Icons.dns_outlined, (context) => ResourcePage(resource: 'services', title: context.t('nav.services'), icon: Icons.dns_outlined)),
    _Destination('nav.tls', Icons.workspace_premium_outlined, (context) => ResourcePage(resource: 'tls', title: context.t('nav.tls'), icon: Icons.workspace_premium_outlined)),
    _Destination('nav.config', Icons.tune, (_) => const ConfigPage()),
    _Destination('nav.analytics', Icons.query_stats, (_) => const AnalyticsPage()),
    _Destination('nav.admin', Icons.admin_panel_settings_outlined, (_) => const AdminPage()),
    _Destination('nav.tools', Icons.settings_outlined, (_) => const ToolsPage()),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 920;
    final state = context.watch<AppState>();
    final body = KeyedSubtree(
      key: ValueKey(selected),
      child: destinations[selected].builder(context),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t(destinations[selected].labelKey)),
        centerTitle: !wide,
        actions: [
          IconButton(
            tooltip: context.t('common.refresh'),
            onPressed: state.busy
                ? null
                : () async {
                    try {
                      await state.refreshBootstrap();
                      if (context.mounted) showMessage(context, context.tr('common.refreshed'));
                    } catch (exception) {
                      if (context.mounted) showMessage(context, exception.toString(), error: true);
                    }
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: wide ? null : _drawer(context),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1180,
              selectedIndex: selected,
              onDestinationSelected: (index) => setState(() => selected = index),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircleAvatar(child: Icon(Icons.shield_outlined)),
              ),
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(icon: Icon(destination.icon), label: Text(context.t(destination.labelKey))),
              ],
            ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _drawer(BuildContext context) {
    final state = context.read<AppState>();
    return NavigationDrawer(
      selectedIndex: selected,
      onDestinationSelected: (index) {
        setState(() => selected = index);
        Navigator.pop(context);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Row(
            children: [
              const CircleAvatar(child: Icon(Icons.shield_outlined)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('S-UI Next', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text(state.profile?.name ?? '', overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        for (final destination in destinations)
          NavigationDrawerDestination(icon: Icon(destination.icon), label: Text(context.t(destination.labelKey))),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(context.t('nav.logout')),
          onTap: () async {
            Navigator.pop(context);
            final revoke = await confirm(context, title: context.tr('nav.logoutTitle'), message: context.tr('nav.logoutMessage'), action: context.tr('nav.logoutRevoke'));
            await state.disconnect(revoke: revoke);
          },
        ),
      ],
    );
  }
}
