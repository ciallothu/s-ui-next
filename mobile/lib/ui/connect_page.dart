import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_localizations.dart';
import '../core/app_locale_context.dart';
import '../core/connection_profile.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final name = TextEditingController();
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
        name: name.text.trim().isEmpty ? context.tr('connect.defaultName') : name.text.trim(),
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

  Future<void> switchToSaved(ConnectionProfile saved) async {
    final state = context.read<AppState>();
    try {
      await state.switchProfile(saved);
    } catch (exception) {
      if (mounted) showMessage(context, exception.toString(), error: true);
    }
  }

  Future<void> removeSaved(ConnectionProfile saved) async {
    final confirmed = await confirm(
      context,
      title: context.tr('panelSwitcher.forgetTitle'),
      message: context.tr('panelSwitcher.forgetMessage', args: {'name': saved.name}),
      action: context.tr('common.delete'),
    );
    if (!confirmed || !mounted) return;
    await context.read<AppState>().removeProfile(saved);
  }

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
                Text(context.t('connect.title'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(context.t('connect.subtitle'), textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
                const SizedBox(height: 24),
                if (state.profiles.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Text(context.t('panelSwitcher.saved'), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          for (final saved in state.profiles)
                            ListTile(
                              leading: Icon(saved.id == state.profile?.id ? Icons.check_circle : Icons.dns_outlined),
                              title: Text(saved.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(saved.normalizedBaseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                              enabled: !state.busy,
                              onTap: state.busy ? null : () => switchToSaved(saved),
                              trailing: IconButton(
                                tooltip: context.t('common.delete'),
                                onPressed: state.busy ? null : () => removeSaved(saved),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        AnchoredSelect<String>(
                          value: state.localeCode,
                          label: context.t('common.language'),
                          prefixIcon: const Icon(Icons.translate),
                          options: [for (final language in AppLocalizations.languages) SelectOption(language.code, language.label)],
                          onChanged: state.setLocale,
                        ),
                        const SizedBox(height: 12),
                        TextField(controller: name, decoration: InputDecoration(labelText: context.t('connect.name'), prefixIcon: const Icon(Icons.bookmark_outline))),
                        const SizedBox(height: 12),
                        TextField(
                          controller: url,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: context.t('connect.panelUrl'),
                            hintText: 'https://panel.example.com/app/',
                            prefixIcon: const Icon(Icons.link),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(value: true, label: Text(context.t('connect.passwordLogin')), icon: const Icon(Icons.person_outline)),
                            const ButtonSegment(value: false, label: Text('API Token'), icon: Icon(Icons.key_outlined)),
                          ],
                          selected: {useCredentials},
                          onSelectionChanged: (value) => setState(() => useCredentials = value.first),
                        ),
                        const SizedBox(height: 12),
                        if (useCredentials) ...[
                          TextField(controller: username, autocorrect: false, decoration: InputDecoration(labelText: context.t('connect.adminUsername'), prefixIcon: const Icon(Icons.person_outline))),
                          const SizedBox(height: 12),
                          TextField(
                            controller: password,
                            obscureText: obscurePassword,
                            decoration: InputDecoration(
                              labelText: context.t('connect.adminPassword'),
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
							  decoration: InputDecoration(
								labelText: context.t('connect.secondFactor'),
								prefixIcon: const Icon(Icons.security_outlined),
							  ),
							),
						  ],
                        ] else
                          TextField(controller: token, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'API Token', prefixIcon: Icon(Icons.key_outlined))),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(context.t('connect.customHeaders')),
                          subtitle: Text(context.t('connect.cfPreset')),
                          value: showAdvanced,
                          onChanged: (value) => setState(() => showAdvanced = value),
                        ),
                        if (showAdvanced) ...[
                          for (var index = 0; index < headers.length; index++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Expanded(child: TextField(controller: headers[index].key, autocorrect: false, decoration: InputDecoration(labelText: context.t('connect.headerName')))),
                                  const SizedBox(width: 8),
                                  Expanded(child: TextField(controller: headers[index].value, obscureText: true, autocorrect: false, decoration: InputDecoration(labelText: context.t('connect.headerValue')))),
                                  IconButton(
                                    tooltip: context.t('common.delete'),
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
                            child: TextButton.icon(onPressed: addHeader, icon: const Icon(Icons.add), label: Text(context.t('connect.addHeader'))),
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
                            label: Text(state.busy ? context.t('connect.verifying') : context.t('connect.connect')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(context.t('connect.httpsHint'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
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
