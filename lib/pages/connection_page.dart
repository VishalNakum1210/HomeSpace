import 'package:flutter/material.dart';

import '../application/home_scope.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../design/state_artwork.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../domain/server_address.dart';
import 'library_widgets.dart';
import 'uploads_page.dart';

String connectionLabel(ConnectionPhase phase) => switch (phase) {
  ConnectionPhase.disconnected => 'Ready to explore',
  ConnectionPhase.connecting => 'Trying the preview',
  ConnectionPhase.connected => 'Demo connected',
  ConnectionPhase.offline => 'Offline preview',
  ConnectionPhase.failed => 'Let\'s try again',
};

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});
  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final form = GlobalKey<FormState>();
  TextEditingController? address;
  String? error;

  @override
  void dispose() {
    address?.dispose();
    super.dispose();
  }

  Future<void> connect(ConnectionRepository connection) async {
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => error = null);
    try {
      await connection.connect(parseServerAddress(address!.text));
    } on LocalActionException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not open this preview. Please retry.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: spaceTheme(Theme.of(context).brightness, SpacePage.profile),
    child: Builder(
      builder: (context) {
        final connection = HomeScope.of(context).connection;
        address ??= TextEditingController(
          text: connection.status.address?.toString() ?? '',
        );
        return ListenableBuilder(
          listenable: connection,
          builder: (context, _) {
            final status = connection.status;
            final busy = status.phase == ConnectionPhase.connecting;
            final connected = status.phase == ConnectionPhase.connected;
            final text = Theme.of(context).textTheme;
            return Scaffold(
              appBar: AppBar(
                title: const Text('Home server'),
                centerTitle: true,
              ),
              body: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  key: const ValueKey('connection-scroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: HouseStateArt(icon: Icons.dns_outlined),
                        ),
                        Text(
                          'A home for every memory',
                          style: text.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your family library, with room to grow.',
                          style: text.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 22),
                        const MemoryStatusBanner(
                          message: 'Frontend preview only. Addresses are not contacted, and no files or passwords are sent.',
                        ),
                        const SizedBox(height: 22),
                        TextFormField(
                          key: const ValueKey('server-address'),
                          controller: address,
                          enabled: !busy,
                          readOnly: connected,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'Server address',
                            hintText: 'http://192.168.1.20:8080',
                            helperText:
                                'HTTP or HTTPS, including a port if needed.',
                            helperMaxLines: 3,
                            errorMaxLines: 4,
                            helperStyle: text.bodyMedium!.copyWith(
                              color: SpaceStyle.of(context).muted,
                            ),
                          ),
                          validator: (value) {
                            try {
                              parseServerAddress(value ?? '');
                              return null;
                            } on LocalActionException catch (failure) {
                              return failure.message;
                            }
                          },
                          onFieldSubmitted: busy || connected
                              ? null
                              : (_) => connect(connection),
                        ),
                        const SizedBox(height: 20),
                        SpaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(switch (status.phase) {
                                    ConnectionPhase.connected =>
                                      Icons.check_circle_outline_rounded,
                                    ConnectionPhase.failed ||
                                    ConnectionPhase.offline =>
                                      Icons.wifi_off_rounded,
                                    _ => Icons.home_outlined,
                                  }, color: SpaceStyle.of(context).accentInk),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      connectionLabel(status.phase),
                                      key: const ValueKey('connection-status'),
                                      style: text.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  status.message,
                                  style: text.bodyMedium,
                                ),
                              ),
                              if (busy) ...[
                                const SizedBox(height: 14),
                                if (MediaQuery.disableAnimationsOf(context))
                                  const Text('Connection preview in progress…')
                                else
                                  const LinearProgressIndicator(
                                    semanticsLabel: 'Trying demo connection',
                                  ),
                              ],
                              if (connected) ...[
                                const SizedBox(height: 14),
                                OutlinedButton.icon(
                                  key: const ValueKey('connection-uploads'),
                                  onPressed: () => openSpacePage<void>(
                                    context,
                                    const UploadsPage(),
                                  ),
                                  icon: const Icon(Icons.cloud_upload_outlined),
                                  label: const Text('View sample queue'),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 14),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              error!,
                              style: text.bodyLarge!.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        SpaceButton(
                          key: const ValueKey('connect-server'),
                          label: busy
                              ? 'Cancel preview'
                              : connected
                              ? 'Disconnect demo'
                              : status.phase == ConnectionPhase.failed ||
                                    status.phase == ConnectionPhase.offline
                              ? 'Try preview again'
                              : 'Try connection preview',
                          icon: busy || connected
                              ? Icons.close_rounded
                              : Icons.link_rounded,
                          onPressed: busy || connected
                              ? connection.disconnect
                              : () => connect(connection),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'The preview connection lasts for this app session. Your saved library is always available.',
                          textAlign: TextAlign.center,
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
