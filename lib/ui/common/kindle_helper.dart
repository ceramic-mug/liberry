import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/kindle_settings_repository.dart';

class KindleHelper {
  final BuildContext context;
  final WidgetRef ref;

  KindleHelper({required this.context, required this.ref});

  Future<void> handleSendToKindle({
    required String filePath,
    required String bookTitle,
  }) async {
    // 1. Get devices locally to avoid async gaps initially
    final repo = ref.read(kindleSettingsRepositoryProvider);
    List<KindleDevice> devices = repo.getDevices();

    KindleDevice? targetDevice;

    if (devices.isEmpty) {
      // Case 0: No devices. Prompt to add one.
      await _showAddDeviceDialog();
      // Refresh
      devices = repo.getDevices();
      if (devices.isEmpty) return; // User cancelled
      targetDevice = devices.first;
    } else if (devices.length == 1) {
      // Case 1: Single device. Use it.
      targetDevice = devices.first;
    } else {
      // Case Many: Show selection dialog.
      targetDevice = await _showDeviceSelectionDialog(devices);
      if (targetDevice == null) return; // User cancelled
    }

    // Proceed to send
    if (context.mounted) {
      await _sendToDevice(targetDevice, filePath, bookTitle);
    }
  }

  Future<void> _sendToDevice(
    KindleDevice device,
    String filePath,
    String bookTitle,
  ) async {
    final Email sendEmail = Email(
      body: 'Here is your book: $bookTitle',
      subject: bookTitle,
      recipients: [device.email],
      attachmentPaths: [filePath],
      isHTML: false,
    );

    try {
      await FlutterEmailSender.send(sendEmail);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Emailing to ${device.name}...')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sending email: $e')));
      }
    }
  }

  Future<KindleDevice?> _showDeviceSelectionDialog(
    List<KindleDevice> devices,
  ) async {
    return await showDialog<KindleDevice>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Select Kindle'),
          children: [
            ...devices.map(
              (device) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, device),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tablet_mac,
                        color: Colors.black54,
                      ), // Default to black54 for general use
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              device.email,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context); // Close selection
                showManageDevicesDialog(); // Open management
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Manage Devices...',
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddDeviceDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Kindle Device'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Device Name (e.g. My Kindle)',
                  hintText: 'My Kindle',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Kindle Email',
                  hintText: 'name@kindle.com',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final email = emailController.text.trim();
                if (name.isNotEmpty && email.isNotEmpty) {
                  await ref
                      .read(kindleSettingsRepositoryProvider)
                      .addDevice(name, email);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> showManageDevicesDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            // Re-fetch to see updates
            final devices = ref
                .read(kindleSettingsRepositoryProvider)
                .getDevices();

            return AlertDialog(
              title: const Text('Manage Devices'),
              content: SizedBox(
                width: double.maxFinite,
                child: devices.isEmpty
                    ? const Text('No devices saved.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          return ListTile(
                            title: Text(device.name),
                            subtitle: Text(device.email),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.redAccent,
                              ),
                              onPressed: () async {
                                await ref
                                    .read(kindleSettingsRepositoryProvider)
                                    .removeDevice(device.id);
                                setStateDialog(() {});
                              },
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: () async {
                    await _showAddDeviceDialog();
                    // Refresh dialog
                    setStateDialog(() {});
                  },
                  child: const Text('Add New'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
