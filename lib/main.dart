import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'history_page.dart';

void main() {
  runApp(const QRScannerApp());
}

class QRScannerApp extends StatelessWidget {
  const QRScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'QR Barcode Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const QRScannerHomePage(),
    );
  }
}

class QRScannerHomePage extends StatefulWidget {
  const QRScannerHomePage({super.key});

  @override
  State<QRScannerHomePage> createState() => _QRScannerHomePageState();
}

class _QRScannerHomePageState extends State<QRScannerHomePage> {
  MobileScannerController controller = MobileScannerController();
  bool isFlashOn = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR & Barcode Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryPage()),
              );
            },
            tooltip: 'History Scan',
          ),
          IconButton(
            icon: Icon(isFlashOn ? Icons.flash_off : Icons.flash_on),
            onPressed: () async {
              await controller.toggleTorch();
              setState(() {
                isFlashOn = !isFlashOn;
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: <Widget>[
            Expanded(
              flex: 4,
              child: MobileScanner(
                controller: controller,
                onDetect: _onDetect,
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      size: 48,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Arahkan kamera ke QR code atau barcode',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDetect(BarcodeCapture barcodeCapture) {
    if (barcodeCapture.barcodes.isNotEmpty) {
      final String scanData = barcodeCapture.barcodes.first.rawValue ?? '';
      if (scanData.isNotEmpty) {
        // Stop scanning immediately
        controller.stop();
        // Save to history
        _saveToHistory(scanData);
        // Show result dialog
        _showScanResultDialog(scanData);
      }
    }
  }

  Future<void> _saveToHistory(String scanData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList('scan_history') ?? [];
      
      // Create new history item
      final historyItem = ScanHistoryItem(
        data: scanData,
        dateTime: DateTime.now(),
      );
      
      // Add to beginning of list (newest first)
      historyJson.insert(0, jsonEncode(historyItem.toJson()));
      
      // Keep only last 100 items to avoid too much storage
      if (historyJson.length > 100) {
        historyJson.removeRange(100, historyJson.length);
      }
      
      // Save back to preferences
      await prefs.setStringList('scan_history', historyJson);
    } catch (e) {
      // If saving fails, just continue (don't block the scan)
      debugPrint('Error saving to history: $e');
    }
  }

  void _showScanResultDialog(String scanData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Hasil Scan'),
          content: SingleChildScrollView(
            child: Text(
              scanData,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _restartScan();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _copyToClipboard(scanData);
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _handleVisit(scanData);
              },
              child: const Text('Visit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleVisit(String scanData) async {
    if (scanData.isEmpty) {
      _restartScan();
      return;
    }

    String urlToOpen = scanData;

    // Format URL based on content type
    if (scanData.startsWith('http://') || scanData.startsWith('https://')) {
      // Already a complete URL
      urlToOpen = scanData;
    }
    else if (scanData.startsWith('wa.me/') || scanData.contains('whatsapp.com')) {
      // WhatsApp link - ensure it has https
      urlToOpen = scanData.startsWith('http') ? scanData : 'https://$scanData';
    }
    else if (RegExp(r'^\+?[0-9\s\-\(\)]{8,}$').hasMatch(scanData)) {
      // Phone number - create WhatsApp URL
      final phoneNumber = scanData.replaceAll(RegExp(r'[^\d+]'), '');
      urlToOpen = 'https://wa.me/$phoneNumber';
    }
    else {
      // Treat everything else as a website URL
      urlToOpen = 'https://$scanData';
    }

    // Always open in external browser
    await _launchInExternalBrowser(urlToOpen);
    
    // Restart scanning after action
    _restartScan();
  }

  Future<void> _launchInExternalBrowser(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      
      // Try to launch with external application first
      bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      
      if (!launched) {
        // If external application fails, try platform default
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      
      if (!launched) {
        // If still fails, show error
        _showErrorDialog('Tidak dapat membuka link: $url\n\nPastikan Anda memiliki aplikasi yang dapat membuka link ini.');
      }
    } catch (e) {
      // If parsing or launching fails, try with different approach
      try {
        // Try adding https if not present
        String fallbackUrl = url;
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          fallbackUrl = 'https://$url';
        }
        
        final Uri fallbackUri = Uri.parse(fallbackUrl);
        bool launched = await launchUrl(fallbackUri, mode: LaunchMode.platformDefault);
        
        if (!launched) {
          _showErrorDialog('Tidak dapat membuka link: $url\n\nError: ${e.toString()}');
        }
      } catch (fallbackError) {
        _showErrorDialog('Tidak dapat membuka link: $url\n\nError: ${fallbackError.toString()}');
      }
    }
  }

  void _restartScan() {
    controller.start();
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Teks berhasil disalin ke clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: SingleChildScrollView(
            child: Text(message),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _restartScan();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }



  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
