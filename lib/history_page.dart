import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<ScanHistoryItem> scanHistory = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('scan_history') ?? [];
    
    setState(() {
      scanHistory = historyJson
          .map((json) => ScanHistoryItem.fromJson(jsonDecode(json)))
          .toList()
          .reversed
          .toList(); // Show newest first
      isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus History'),
        content: const Text('Yakin ingin menghapus semua history scan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('scan_history');
      setState(() {
        scanHistory.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('History berhasil dihapus')),
        );
      }
    }
  }

  Future<void> _deleteItem(int index) async {
    final prefs = await SharedPreferences.getInstance();
    scanHistory.removeAt(index);
    
    final historyJson = scanHistory
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    
    await prefs.setStringList('scan_history', historyJson);
    setState(() {});
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item dihapus dari history')),
      );
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teks berhasil disalin ke clipboard')),
      );
    }
  }

  Future<void> _launchUrl(String scanData) async {
    String urlToOpen = scanData;

    // Format URL based on content type
    if (scanData.startsWith('http://') || scanData.startsWith('https://')) {
      urlToOpen = scanData;
    }
    else if (scanData.startsWith('wa.me/') || scanData.contains('whatsapp.com')) {
      urlToOpen = scanData.startsWith('http') ? scanData : 'https://$scanData';
    }
    else if (RegExp(r'^\+?[0-9\s\-\(\)]{8,}$').hasMatch(scanData)) {
      final phoneNumber = scanData.replaceAll(RegExp(r'[^\d+]'), '');
      urlToOpen = 'https://wa.me/$phoneNumber';
    }
    else {
      urlToOpen = 'https://$scanData';
    }

    try {
      final Uri uri = Uri.parse(urlToOpen);
      bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      
      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tidak dapat membuka: $urlToOpen')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Scan'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (scanHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearHistory,
              tooltip: 'Hapus semua history',
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : scanHistory.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Belum ada history scan',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: scanHistory.length,
                  itemBuilder: (context, index) {
                    final item = scanHistory[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          child: Text(
                            (index + 1).toString(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          item.data,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          item.formattedDateTime,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'copy',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy),
                                  SizedBox(width: 8),
                                  Text('Copy'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'visit',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.open_in_browser),
                                  SizedBox(width: 8),
                                  Text('Visit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            switch (value) {
                              case 'copy':
                                _copyToClipboard(item.data);
                                break;
                              case 'visit':
                                _launchUrl(item.data);
                                break;
                              case 'delete':
                                _deleteItem(index);
                                break;
                            }
                          },
                        ),
                        onTap: () {
                          // Show full content in dialog
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Detail Scan'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Konten:',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    SelectableText(item.data),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Waktu Scan:',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(item.formattedDateTime),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Tutup'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _copyToClipboard(item.data);
                                  },
                                  child: const Text('Copy'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _launchUrl(item.data);
                                  },
                                  child: const Text('Visit'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

class ScanHistoryItem {
  final String data;
  final DateTime dateTime;

  ScanHistoryItem({
    required this.data,
    required this.dateTime,
  });

  String get formattedDateTime {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} hari yang lalu';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} jam yang lalu';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} menit yang lalu';
    } else {
      return 'Baru saja';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'dateTime': dateTime.millisecondsSinceEpoch,
    };
  }

  factory ScanHistoryItem.fromJson(Map<String, dynamic> json) {
    return ScanHistoryItem(
      data: json['data'],
      dateTime: DateTime.fromMillisecondsSinceEpoch(json['dateTime']),
    );
  }
}