import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'constants.dart';

class SpeechToTextExample extends StatefulWidget {
  const SpeechToTextExample({super.key});

  @override
  _SpeechToTextExampleState createState() => _SpeechToTextExampleState();
}

class _SpeechToTextExampleState extends State<SpeechToTextExample> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _transcription = '';
  final AudioRecorder audioRecorder = AudioRecorder();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  Future<bool> _checkPermission() async {
    var status = await Permission.microphone.status;
    if (status.isDenied) {
      status = await Permission.microphone.request();
    }
    return status.isGranted;
  }

  Future<void> _handleAudioUpload(File audioFile) async {
    try {
      var request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/transcribe'));
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          audioFile.path,
        ),
      );
      var response = await request.send();
      await audioFile.delete();
      Navigator.of(context).pop(); // Close loading dialog
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var jsonResponse = jsonDecode(responseData);
        setState(() {
          _transcription = jsonResponse['transcription'] ?? '';
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send recording')),
        );
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog on error
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error uploading recording')),
      );
    }
  }

  void _showRecordingModal() {
    bool localIsRecording = false;
    String? recordingPath;
    int remainingSeconds = 30;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Voice Recording',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!localIsRecording)
                    const Text(
                      'Press and hold the button to start recording',
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 32),
                  if (localIsRecording)
                    Text(
                      '$remainingSeconds seconds remaining',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  GestureDetector(
                    onTapDown: (_) async {
                      setDialogState(() {
                        localIsRecording = true;
                      });

                      final tempDir = await getTemporaryDirectory();
                      recordingPath = '${tempDir.path}/audio_note.m4a';

                      await audioRecorder.start(
                        const RecordConfig(encoder: AudioEncoder.aacLc),
                        path: recordingPath!,
                      );

                      Timer.periodic(const Duration(seconds: 1), (timer) {
                        if (remainingSeconds > 0 && localIsRecording) {
                          setDialogState(() {
                            remainingSeconds--;
                          });
                        } else {
                          timer.cancel();
                          if (localIsRecording) {
                            // Auto-stop after 30 seconds
                            audioRecorder.stop().then((path) {
                              if (path != null) {
                                _handleAudioUpload(File(path));
                              }
                            });
                            setDialogState(() {
                              localIsRecording = false;
                              remainingSeconds = 30;
                            });
                          }
                        }
                      });
                    },
                    onTapUp: (_) async {
                      if (localIsRecording) {
                        final path = await audioRecorder.stop();
                        if (path != null) {
                          _handleAudioUpload(File(path));
                        }
                        setDialogState(() {
                          localIsRecording = false;
                          remainingSeconds = 30;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: localIsRecording ? Colors.red : Colors.blue,
                      ),
                      child: Icon(
                        localIsRecording ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _listen() async {
    if (!await _checkPermission()) {
      print('Microphone permission denied');
      return;
    }

    if (!_isListening) {
      // Initialize speech recognition
      bool available = await _speech.initialize(
        onStatus: (status) {
          print('Status: $status');
          // Only set listening to false when truly done
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (errorNotification) {
          print('Error: ${errorNotification.errorMsg}');
          // Don't stop listening on temporary errors
          if (errorNotification.permanent) {
            setState(() => _isListening = false);
          }
        },
      );

      if (available) {
        setState(() => _isListening = true);
        await _speech.listen(
          onResult: (result) {
            setState(() {
              _transcription = result.recognizedWords;
            });
          },
          listenMode: stt.ListenMode
              .confirmation, // Changed from dictation to confirmation
          partialResults: true,
          listenFor:
              const Duration(seconds: 300), // Increased from 60 to 300 seconds
          pauseFor: const Duration(seconds: 5),
          localeId: 'hi-IN',
          cancelOnError: false,
          onSoundLevelChange:
              null, // Removed sound level monitoring to reduce overhead
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Speech recognition not available on this device')),
        );
      }
    } else {
      _speech.stop();
      setState(() => _isListening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Input')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Choose your preferred input method 👇'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _listen,
              child: Text(
                  _isListening ? 'Stop Listening' : 'Start Speech Recognition'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _showRecordingModal,
              child: const Text('Start Voice Recording'),
            ),
            const SizedBox(height: 20),
            Text('🗣️ Transcription:\n$_transcription'),
          ],
        ),
      ),
    );
  }
}
