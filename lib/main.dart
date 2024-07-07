import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:vibration/vibration.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:io';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'URL Submission Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Color backgroundColor = Colors.white;
  final TextEditingController _urlController = TextEditingController();
  String responseMessage = "Enter a URL and press submit.";
  bool isSubmitting = false;
  PlatformFile? pickedFile;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;


  Future<void> pickAndUploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true
    );

    if (result != null) {
      pickedFile = result.files.first;
      setState(() {
        responseMessage = "File picked: ${pickedFile!.name}";
      });
    } else {
      // User canceled the picker
      setState(() {
        responseMessage = "No file selected";
      });
    }
  }
  Future<void> submitURL() async {
    if (_urlController.text.isEmpty) {
      setState(() {
        responseMessage = "No URL entered. Cancelling submission.";
      });
      return; // Exit the function early
    }
    setState(() {
      isSubmitting = true;
    });
    var response = await http.post(
        // Uri.parse('http://10.0.2.2:5000/api/v1/predict'),
        Uri.parse('http://192.168.1.3:5000/api/v1/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"url": _urlController.text})
    );
    processResponse(response);
  }

  Future<void> submitFile() async {
    if (pickedFile == null) {
      setState(() {
        responseMessage = "Please pick a file first";
        isSubmitting = false;
      });
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    var request = http.MultipartRequest(
        'POST',
        // Uri.parse('http://10.0.2.2:5000/api/v1/bulk_predict')
        Uri.parse('http://192.168.1.3:5000/api/v1/bulk_predict')
    );

    final fileBytes = pickedFile?.bytes;
    final fileName = pickedFile?.name;

    if (fileBytes != null && fileName != null) {
      request.files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName
      ));

      try {
        var response = await request.send();
        if (response.statusCode == 200) {
          Directory? directory = await getExternalStorageDirectory();
          String newPath = "";
          List<String>? paths = directory?.path.split("/");
          for (int x = 1; x < paths!.length; x++) {
            String folder = paths[x];
            if (folder != "Android") {
              newPath += "/$folder";
            } else {
              break;
            }
          }
          newPath = "$newPath/Download";
          directory = Directory(newPath);

          if (!(await directory.exists())) {
            await directory.create(recursive: true);
          }

          File file = File('${directory.path}/updated_$fileName');

          // Write the byte stream to the file
          List<int> bytes = await response.stream.toBytes();
          await file.writeAsBytes(bytes);

          setState(() {
            responseMessage = 'File downloaded successfully';
            isSubmitting = false;
          });
        } else {
          throw Exception('Failed to upload file with status code: ${response.statusCode}');
        }
      } catch (e) {
        setState(() {
          responseMessage = 'Error: $e';
          isSubmitting = false;
        });
      }
    } else {
      setState(() {
        responseMessage = "File is empty or corrupted";
        isSubmitting = false;
      });
    }
  }

  Future<void> launchURL(url) async {
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  Future<void> promptUserToVisitURL(String url) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Open URL'),
          content: const Text('The URL is benign. Do you want to visit this URL?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await launchURL(url);
              },
              child: const Text('Open'),
            ),
          ],
        );
      },
    );
  }

  void processResponse(http.Response response) {
    if (response.statusCode == 200) {
      var responseData = jsonDecode(response.body);
      setState(() {
        responseMessage = responseData['prediction'];
      });
      if (responseData['prediction'] == "Malicious URL: Detected") {
        maliciousURLDetected();
      } else {
        promptUserToVisitURL(_urlController.text);
      }
    } else {
      setState(() {
        responseMessage = 'Failed to submit. Status code: ${response.statusCode}';
      });
    }
    setState(() {
      isSubmitting = false;
    });
  }

  @override
  void initState() {
    super.initState();
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    var android = const AndroidInitializationSettings('app_icon'); // Make sure to add your icon
    var initSettings = InitializationSettings(android: android);
    flutterLocalNotificationsPlugin.initialize(initSettings);
  }

  void maliciousURLDetected() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 3000);  // Vibrate for 3 seconds
    }

    Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (timer.tick >= 6) {
        timer.cancel();
        setState(() {
          backgroundColor = Colors.white;
        });
      } else {
        setState(() {
          backgroundColor = timer.tick % 2 == 0 ? Colors.red : Colors.white;
        });
      }
    });

    // Sending a notification
    var androidDetails = const AndroidNotificationDetails(
        'channelId', 'channelName');
    var generalNotificationDetails =
    NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Security Alert',
      'Malicious URL detected!',
      generalNotificationDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        color: backgroundColor,
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(responseMessage),
            const SizedBox(height: 20),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Enter URL',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 20),
            isSubmitting
                ? const Text('Processing...')
                : ElevatedButton(
              onPressed: submitURL,
              child: const Text('Submit Single URL'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: pickAndUploadFile,
              child: const Text('Pick CSV File'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: submitFile,
              child: const Text('Submit CSV File'),
            ),
            // const SizedBox(height: 20),
            // ElevatedButton(
            //   onPressed: () => changeBackgroundColor(Colors.blue),
            //   child: const Text('Change Background to Blue'),
            // ),
          ],
        ),
      ),
    );
  }
}