import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/connection_profile.dart';
import '../state/app_state.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final name = TextEditingController(text: '我的 S-UI');
  final url = TextEditingController();
  final token = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final secondFactor = TextEditingController();
  final headers = <_HeaderDraft>[
    _HeaderDraft(ConnectionProfile.cloudflareClientId, ''),
    _HeaderDraft(ConnectionProfile.cloudflareClientSecret, ''),
  ];
  bool useCredentials = true;
  bool showAdvanced = false;
  bool obscurePassword = true;
  bool requiresSecondFactor = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AppState>().profile;
    if (profile == null) return;
    name.text = profile.name;
    url.text = profile.normalizedBaseUrl;
    token.text = profile.token;
    useCredentials = false;
    showAdvanced = profile.headers.values.any((value) => value.isNotEmpty);
    for (final header in headers) {
      header.dispose();
    }
    headers
      ..clear()
      ..addAll(profile.headers.entries.map((entry) => _HeaderDraft(entry.key, entry.value)));
    if (headers.isEmpty) {
      headers.addAll([
        _HeaderDraft(ConnectionProfile.cloudflareClientId, ''),
        _HeaderDraft(ConnectionProfile.cloudflareClientSecret, ''),
      ]);
    }
  }

  @override
  void dispose() {
    name.dispose();
    url.dispose();
    token.dispose();
    username.dispose();
    password.dispose();
    secondFactor.dispose();
    for (final header in headers) {
      header.dispose();
    }
    super.dispose();
  }

  ConnectionProfile buildProfile() => ConnectionProfile(
        name: name.text.trim().isEmpty ? '我的 S-UI' : name.text.trim(),
        baseUrl: url.text.trim(),
        token: token.text.trim(),
        headers: {
          for (final header in headers)
            if (header.key.text.trim().isNotEmpty) header.key.text.trim(): header.value.text.trim(),
        },
      );

  Future<void> connect() async {
    final state = context.read<AppState>();
    try {
      if (useCredentials) {
		final required = await state.connectWithCredentials(
		  buildProfile(),
		  username.text.trim(),
		  password.text,
		  code: secondFactor.text,
		);
		if (required && mounted) {
		  setState(() => requiresSecondFactor = true);
		}
      } else {
        await state.connectWithToken(buildProfile());
      }
    } catch (_) {
      // AppState exposes the user-facing error below the form.
    }
  }

  void addHeader() => setState(() => headers.add(_HeaderDraft('', '')));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 20),
                CircleAvatar(
                  radius: 34,
                  backgroundColor: colors.primaryContainer,
                  child: Icon(Icons.shield_outlined, size: 36, color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 16),
                Text('连接 S-UI', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('连接信息与令牌仅保存在系统安全存储中', textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(controller: name, decoration: const InputDecoration(labelText: '连接名称', prefixIcon: Icon(Icons.bookmark_outline))),
                        const SizedBox(height: 12),
                        TextField(
                          controller: url,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: '面板地址（包含 Web Path）',
                            hintText: 'https://panel.example.com/app/',
                            prefixIcon: Icon(Icons.link),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: true, label: Text('账号登录'), icon: Icon(Icons.person_outline)),
                            ButtonSegment(value: false, label: Text('API Token'), icon: Icon(Icons.key_outlined)),
                          ],
                          selected: {useCredentials},
                          onSelectionChanged: (value) => setState(() => useCredentials = value.first),
                        ),
                        const SizedBox(height: 12),
                        if (useCredentials) ...[
                          TextField(controller: username, autocorrect: false, decoration: const InputDecoration(labelText: '管理员用户名', prefixIcon: Icon(Icons.person_outline))),
                          const SizedBox(height: 12),
                          TextField(
                            controller: password,
                            obscureText: obscurePassword,
                            decoration: InputDecoration(
                              labelText: '管理员密码',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => obscurePassword = !obscurePassword),
                              ),
                            ),
                          ),
						  if (requiresSecondFactor) ...[
							const SizedBox(height: 12),
							TextField(
							  controller: secondFactor,
							  autofocus: true,
							  keyboardType: TextInputType.number,
							  autocorrect: false,
							  decoration: const InputDecoration(
								labelText: '两步验证码或恢复码',
								prefixIcon: Icon(Icons.security_outlined),
							  ),
							),
						  ],
                        ] else
                          TextField(controller: token, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'API Token', prefixIcon: Icon(Icons.key_outlined))),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('自定义请求 Header'),
                          subtitle: const Text('已预置 Cloudflare Access Service Token 字段'),
                          value: showAdvanced,
                          onChanged: (value) => setState(() => showAdvanced = value),
                        ),
                        if (showAdvanced) ...[
                          for (var index = 0; index < headers.length; index++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Expanded(child: TextField(controller: headers[index].key, autocorrect: false, decoration: const InputDecoration(labelText: 'Header 名称'))),
                                  const SizedBox(width: 8),
                                  Expanded(child: TextField(controller: headers[index].value, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'Header 值'))),
                                  IconButton(
                                    tooltip: '删除',
                                    onPressed: headers.length <= 2
                                        ? null
                                        : () => setState(() {
                                              headers.removeAt(index).dispose();
                                            }),
                                    icon: const Icon(Icons.remove_circle_outline),
                                  ),
                                ],
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(onPressed: addHeader, icon: const Icon(Icons.add), label: const Text('添加 Header')),
                          ),
                        ],
                        if (state.error != null) ...[
                          const SizedBox(height: 8),
                          Text(state.error!, style: TextStyle(color: colors.error)),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: state.busy ? null : connect,
                            icon: state.busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.login),
                            label: Text(state.busy ? '正在验证…' : '连接面板'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('建议仅通过 HTTPS 连接。使用 Cloudflare Zero Trust 时，请填写 CF-Access-Client-Id 与 CF-Access-Client-Secret。', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderDraft {
  _HeaderDraft(String key, String value)
      : key = TextEditingController(text: key),
        value = TextEditingController(text: value);

  final TextEditingController key;
  final TextEditingController value;

  void dispose() {
    key.dispose();
    value.dispose();
  }
}
