import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'widgets.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with SingleTickerProviderStateMixin {
  late final TabController tabs;
  List<dynamic> users = [];
  List<dynamic> tokens = [];
  List<dynamic> changes = [];
  Map<String, dynamic> security = {};
  final search = TextEditingController();
  final actor = TextEditingController();
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 4, vsync: this)..addListener(() {
        if (!tabs.indexIsChanging) load();
      });
    load();
  }

  @override
  void dispose() {
    tabs.dispose();
    search.dispose();
    actor.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<AppState>().api!;
      if (tabs.index == 0) {
        final value = await api.get('users');
        if (mounted) setState(() => users = List<dynamic>.from(value as List? ?? const []));
      } else if (tabs.index == 1) {
        final value = await api.get('tokens');
        if (mounted) setState(() => tokens = List<dynamic>.from(value as List? ?? const []));
      } else if (tabs.index == 2) {
        final value = Map<String, dynamic>.from(await api.get('changes', query: {'user': actor.text.trim(), 'search': search.text.trim(), 'limit': 500}) as Map);
        if (mounted) setState(() => changes = List<dynamic>.from(value['items'] as List? ?? const []));
	  } else {
		final value = await api.get('auth/security');
		if (mounted) setState(() => security = Map<String, dynamic>.from(value as Map? ?? const {}));
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> changeCredentials(Map<String, dynamic> item) async {
    final oldPassword = TextEditingController();
    final username = TextEditingController(text: item['username']?.toString() ?? '');
    final password = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改管理员凭据'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: oldPassword, obscureText: true, decoration: const InputDecoration(labelText: '当前密码')),
              const SizedBox(height: 10),
              TextField(controller: username, decoration: const InputDecoration(labelText: '新用户名')),
              const SizedBox(height: 10),
              TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: '新密码')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              try {
                await context.read<AppState>().api!.patch('users/${item['id']}', data: {'oldPassword': oldPassword.text, 'username': username.text.trim(), 'password': password.text});
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await load();
              } catch (exception) {
                if (dialogContext.mounted) showMessage(dialogContext, exception.toString(), error: true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    oldPassword.dispose();
    username.dispose();
    password.dispose();
  }

  Future<void> addToken() async {
    final description = TextEditingController(text: 'Mobile/API');
    final days = TextEditingController(text: '30');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('创建 API Token'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: description, decoration: const InputDecoration(labelText: '说明')), const SizedBox(height: 10), TextField(controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '有效天数（0 为永久）'))]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              try {
                final result = Map<String, dynamic>.from(await context.read<AppState>().api!.post('tokens', data: {'description': description.text, 'expiryDays': int.tryParse(days.text) ?? 30}) as Map);
                if (!mounted) return;
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  await showDialog<void>(context: context, builder: (resultContext) => AlertDialog(title: const Text('请立即保存 Token'), content: SelectableText(result['token']?.toString() ?? ''), actions: [FilledButton(onPressed: () => Navigator.pop(resultContext), child: const Text('完成'))]));
                }
                await load();
              } catch (exception) {
                if (dialogContext.mounted) showMessage(dialogContext, exception.toString(), error: true);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    description.dispose();
    days.dispose();
  }

  Future<void> deleteToken(Map<String, dynamic> token) async {
    if (!await confirm(context, title: '删除 Token', message: '使用此 Token 的客户端会立即失去访问权限。', action: '删除')) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api!.delete('tokens/${token['id']}');
      await load();
    } catch (exception) {
      if (mounted) showMessage(context, exception.toString(), error: true);
    }
  }

  Future<void> enableTotp() async {
	try {
	  final setup = Map<String, dynamic>.from(await context.read<AppState>().api!.post('auth/totp/begin') as Map);
	  if (!mounted) return;
	  final code = TextEditingController();
	  final confirmed = await showDialog<bool>(
		context: context,
		builder: (dialogContext) => AlertDialog(
		  title: const Text('启用两步验证'),
		  content: SizedBox(
			width: 520,
			child: Column(mainAxisSize: MainAxisSize.min, children: [
			  const Text('在验证器中导入下面的 URI 或密钥，然后输入当前验证码。'),
			  const SizedBox(height: 10),
			  SelectableText(setup['uri']?.toString() ?? setup['secret']?.toString() ?? '', style: const TextStyle(fontFamily: 'monospace')),
			  const SizedBox(height: 12),
			  TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6 位验证码')),
			]),
		  ),
		  actions: [
			TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
			FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('启用')),
		  ],
		),
	  );
	  if (confirmed != true || !mounted) {
		code.dispose();
		return;
	  }
	  final result = Map<String, dynamic>.from(await context.read<AppState>().api!.post('auth/totp/enable', data: {'code': code.text.trim()}) as Map);
	  code.dispose();
	  if (!mounted) return;
	  await showDialog<void>(context: context, builder: (resultContext) => AlertDialog(
		title: const Text('请保存恢复码'),
		content: SelectableText((result['recoveryCodes'] as List? ?? const []).join('\n'), style: const TextStyle(fontFamily: 'monospace')),
		actions: [FilledButton(onPressed: () => Navigator.pop(resultContext), child: const Text('我已保存'))],
	  ));
	  await load();
	} catch (exception) {
	  if (mounted) showMessage(context, exception.toString(), error: true);
	}
  }

  Future<void> disableTotp() async {
	final password = TextEditingController();
	final code = TextEditingController();
	final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
	  title: const Text('关闭两步验证'),
	  content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
		TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: '当前密码')),
		const SizedBox(height: 10),
		TextField(controller: code, decoration: const InputDecoration(labelText: '验证码或恢复码')),
	  ])),
	  actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('关闭'))],
	));
	if (confirmed == true && mounted) {
	  try {
		await context.read<AppState>().api!.post('auth/totp/disable', data: {'password': password.text, 'code': code.text.trim()});
		await load();
	  } catch (exception) {
		if (mounted) showMessage(context, exception.toString(), error: true);
	  }
	}
	password.dispose();
	code.dispose();
  }

  Future<void> deletePasskey(Map<String, dynamic> passkey) async {
	if (!await confirm(context, title: '删除通行密钥', message: '删除后该设备将不能再用于免密码登录。', action: '删除')) return;
	if (!mounted) return;
	try {
	  await context.read<AppState>().api!.delete('auth/passkeys/${passkey['id']}');
	  await load();
	} catch (exception) {
	  if (mounted) showMessage(context, exception.toString(), error: true);
	}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: '管理员',
          subtitle: '账号、API Token 与变更审计',
          actions: [if (tabs.index == 1) IconButton.filled(onPressed: addToken, icon: const Icon(Icons.add))],
        ),
        TabBar(controller: tabs, isScrollable: true, tabs: const [Tab(text: '管理员'), Tab(text: 'API Token'), Tab(text: '变更记录'), Tab(text: '登录安全')]),
        if (tabs.index == 2)
          FilterCard(
            child: Row(children: [Expanded(child: TextField(controller: actor, onSubmitted: (_) => load(), decoration: const InputDecoration(labelText: '执行者'))), const SizedBox(width: 8), Expanded(child: TextField(controller: search, onSubmitted: (_) => load(), decoration: const InputDecoration(labelText: '搜索', prefixIcon: Icon(Icons.search)))), const SizedBox(width: 8), IconButton.filledTonal(onPressed: load, icon: const Icon(Icons.refresh))]),
          ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: error != null
              ? EmptyState(label: error!, icon: Icons.error_outline)
              : TabBarView(controller: tabs, children: [_users(), _tokens(), _changes(), _security()]),
        ),
      ],
    );
  }

  Widget _users() => RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: users.isEmpty
              ? [const EmptyState(label: '没有管理员')]
              : [for (final raw in users) _userCard(Map<String, dynamic>.from(raw as Map))],
        ),
      );

  Widget _userCard(Map<String, dynamic> item) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.admin_panel_settings_outlined)),
          title: Text(item['username']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('上次登录 ${item['lastLogin']?.toString().isNotEmpty == true ? item['lastLogin'] : '—'}'),
          trailing: IconButton(onPressed: () => changeCredentials(item), icon: const Icon(Icons.edit_outlined)),
        ),
      );

  Widget _tokens() => RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: tokens.isEmpty
              ? [const EmptyState(label: '没有额外 API Token')]
              : [for (final raw in tokens) _tokenCard(Map<String, dynamic>.from(raw as Map))],
        ),
      );

  Widget _tokenCard(Map<String, dynamic> item) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.key_outlined)),
          title: Text(item['desc']?.toString().isNotEmpty == true ? item['desc'].toString() : '未命名 Token'),
          subtitle: Text(_expiry(item['expiry'])),
          trailing: IconButton(onPressed: () => deleteToken(item), icon: const Icon(Icons.delete_outline)),
        ),
      );

  Widget _changes() => RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: changes.isEmpty
              ? [const EmptyState(label: '没有匹配的变更记录')]
              : [for (final raw in changes) _changeCard(Map<String, dynamic>.from(raw as Map))],
        ),
      );

  Widget _changeCard(Map<String, dynamic> item) => Card(
        child: ExpansionTile(
          leading: const Icon(Icons.history),
          title: Text('${item['action']} · ${item['key']}'),
          subtitle: Text('${item['actor']} · ${formatTimestamp(item['dateTime'])}'),
          children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Align(alignment: Alignment.centerLeft, child: SelectableText(item['obj']?.toString() ?? '', style: const TextStyle(fontFamily: 'monospace'))))],
        ),
      );

  Widget _security() {
	final methods = Map<String, dynamic>.from(security['methods'] as Map? ?? const {});
	final passkeys = List<dynamic>.from(security['passkeys'] as List? ?? const []);
	final totpEnabled = security['totpEnabled'] == true;
	return RefreshIndicator(
	  onRefresh: load,
	  child: ListView(
		physics: const AlwaysScrollableScrollPhysics(),
		padding: const EdgeInsets.all(12),
		children: [
		  Card(child: SwitchListTile(
			secondary: const Icon(Icons.phonelink_lock_outlined),
			title: const Text('TOTP 两步验证'),
			subtitle: Text(totpEnabled ? '已启用；登录需要验证码或恢复码' : '未启用'),
			value: totpEnabled,
			onChanged: (_) => totpEnabled ? disableTotp() : enableTotp(),
		  )),
		  Card(child: Column(children: [
			ListTile(leading: const Icon(Icons.key_outlined), title: const Text('通行密钥'), subtitle: Text(methods['passkey'] == true ? '服务端已启用；请在 Web 页面注册新通行密钥' : '服务端尚未启用')),
			for (final raw in passkeys)
			  ListTile(
				leading: const Icon(Icons.key_outlined),
				title: Text((raw as Map)['name']?.toString() ?? 'Passkey'),
				subtitle: Text('创建 ${formatTimestamp(raw['createdAt'])}'),
				trailing: IconButton(onPressed: () => deletePasskey(Map<String, dynamic>.from(raw)), icon: const Icon(Icons.delete_outline)),
			  ),
		  ])),
		  Card(child: ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('OIDC 单点登录'), subtitle: Text(methods['oidc'] == true ? '已启用，可从 Web 登录页使用' : '未启用'))),
		],
	  ),
	);
  }

  String _expiry(dynamic value) {
    final timestamp = int.tryParse(value?.toString() ?? '') ?? 0;
    return timestamp == 0 ? '永久有效' : '到期 ${formatTimestamp(timestamp)}';
  }
}
