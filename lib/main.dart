import 'arabic_playback_command.dart';
import 'multi_camera.dart';
import 'playback_detection_results.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const ZvektraApp()); }

const host = String.fromEnvironment('ZVEKTRA_RTSP_HOST', defaultValue: 'zvektra.net');
const manufacturers = ['Dahua', 'Hikvision', 'Uniview', 'MEye', 'Topcam'];
const navy = Color(0xFF0D1725);
const cyan = Color(0xFF62E2E6);
const surface = Color(0xFF142439);
const accent = Color(0xFF8B9CFF);

class Nvr {
  final String id, name, manufacturer, port, username;
  final int maxChannels;
  const Nvr({required this.id,required this.name,required this.manufacturer,required this.port,required this.username,required this.maxChannels});
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'manufacturer':manufacturer,'port':port,'username':username,'maxChannels':maxChannels};
  factory Nvr.fromJson(Map<String,dynamic> x)=>Nvr(id:x['id'],name:x['name'],manufacturer:x['manufacturer'],port:x['port'],username:x['username'],maxChannels:x['maxChannels']);
  Nvr copyWith({String? name,String? manufacturer,String? port,String? username,int? maxChannels})=>Nvr(id:id,name:name??this.name,manufacturer:manufacturer??this.manufacturer,port:port??this.port,username:username??this.username,maxChannels:maxChannels??this.maxChannels);
}

class DeviceStore extends ChangeNotifier {
  final _secure=const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  List<Nvr> devices=[];
  Future<void> load() async {
    final p=await SharedPreferences.getInstance();
    try { devices=(jsonDecode(p.getString('devices')??'[]') as List).map((x)=>Nvr.fromJson(Map<String,dynamic>.from(x))).toList(); } catch (_) { devices=[]; }
    notifyListeners();
  }
  Future<String?> password(String id)=>_secure.read(key:'nvr_password_$id');
  Future<void> save(Nvr device, String? newPassword) async {
    final updated = List<Nvr>.of(devices);
    final index = updated.indexWhere((entry) => entry.id == device.id);
    if (index < 0) {
      if (updated.length >= 5) throw StateError('Maximum 5 devices');
      updated.add(device);
    } else {
      updated[index] = device;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = 'nvr_password_${device.id}';
    final changingPassword = newPassword != null && newPassword.isNotEmpty;
    final previousPassword =
        changingPassword && index >= 0 ? await _secure.read(key: key) : null;
    if (changingPassword) await _secure.write(key: key, value: newPassword);
    try {
      await _persist(prefs, updated);
    } catch (_) {
      if (changingPassword) {
        if (previousPassword == null) {
          await _secure.delete(key: key);
        } else {
          await _secure.write(key: key, value: previousPassword);
        }
      }
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs, devices.where((entry) => entry.id != id).toList());
    await _secure.delete(key: 'nvr_password_$id');
  }

  Future<void> _persist(SharedPreferences prefs, List<Nvr> updated) async {
    final saved = await prefs.setString(
      'devices',
      jsonEncode(updated.map((device) => device.toJson()).toList()),
    );
    if (!saved) {
      await prefs.reload();
      throw StateError('Could not write device settings');
    }
    devices = updated;
    notifyListeners();
  }
}

// Only Dahua's recording RTSP path has been verified with the user's NVR.
// Other vendor URLs are candidates requiring hardware-specific verification.
class StreamBuilderService {
  static String? url(Nvr n,int channel,{DateTime? start,DateTime? end,bool mainStream=false,bool topcamFallback=false,required String password}) {
    final user=Uri.encodeComponent(n.username);
    final pass=Uri.encodeComponent(password);
    final base='rtsp://$user:$pass@$host:${n.port}';
    if(n.manufacturer=='Dahua') {
      if(start==null) return '$base/cam/realmonitor?channel=$channel&subtype=${mainStream ? 0 : 1}';
      final f=DateFormat('yyyy_MM_dd_HH_mm_ss');
      return '$base/cam/playback?channel=$channel&starttime=${f.format(start)}&endtime=${f.format(end??start.add(const Duration(minutes:10)))}';
    }
    if (n.manufacturer == 'Topcam') {
      if (start == null) {
        return topcamFallback
            ? '$base/Streaming/Channels/${channel}01'
            : 'rtsp://$host:${n.port}/user=${user}_password=${pass}_channel=${channel}_stream=0.sdp';
      }
      final finish = end ?? start.add(const Duration(minutes: 10));
      if (topcamFallback) {
        final utc = DateFormat("yyyyMMdd'T'HHmmss'Z'");
        return '$base/Streaming/tracks/${channel}01'
            '?starttime=${utc.format(start.toUtc())}&endtime=${utc.format(finish.toUtc())}';
      }
      final local = DateFormat('yyyy_MM_dd_HH_mm_ss');
      return '$base/playback/ch$channel'
          '?starttime=${local.format(start)}&endtime=${local.format(finish)}';
    }
    if(n.manufacturer=='Hikvision') {
      if(start==null) return '$base/Streaming/Channels/${channel}01';
      // Hikvision recorded playback requires device-specific ISAPI/RTSP validation.
      return null;
    }
    if(n.manufacturer=='Uniview' || n.manufacturer=='MEye') return null;
    return null;
  }
}

class ZvektraApp extends StatefulWidget { const ZvektraApp({super.key}); @override State<ZvektraApp> createState()=>_ZvektraAppState(); }
class _ZvektraAppState extends State<ZvektraApp> {
  final store=DeviceStore();
  @override void initState(){super.initState();store.load();}
  @override Widget build(BuildContext context)=>MaterialApp(title:'Zvektra',debugShowCheckedModeBanner:false,theme:ThemeData(brightness:Brightness.dark,scaffoldBackgroundColor:navy,colorScheme:ColorScheme.fromSeed(seedColor:cyan,brightness:Brightness.dark),useMaterial3:true,cardTheme:CardThemeData(color:surface,elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18))),inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:surface,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none)),navigationBarTheme:NavigationBarThemeData(backgroundColor:surface,indicatorColor:cyan.withValues(alpha:0.18)),appBarTheme:const AppBarTheme(backgroundColor:navy,centerTitle:false,elevation:0)),home:Home(store:store));
}

class Home extends StatefulWidget {final DeviceStore store;const Home({super.key,required this.store});@override State<Home> createState()=>_HomeState();}
class _HomeState extends State<Home> {
  int tab=0;
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:widget.store,builder:(context,_)=>Scaffold(appBar:AppBar(title:const Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.videocam_rounded,color:cyan,size:24),SizedBox(width:10),Text('ZVEKTRA',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:2.5,fontSize:21))]),backgroundColor:navy,actions:[const Padding(padding:EdgeInsets.only(right:14),child:Icon(Icons.shield_outlined,color:cyan))]),body:tab==0?AssistantScreen(store:widget.store):tab==1?MultiCameraScreen(store:widget.store):DevicesScreen(store:widget.store),bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(x)=>setState(()=>tab=x),destinations:const [NavigationDestination(icon:Icon(Icons.auto_awesome_outlined),selectedIcon:Icon(Icons.auto_awesome),label:'Assistant'),NavigationDestination(icon:Icon(Icons.grid_view_outlined),selectedIcon:Icon(Icons.grid_view_rounded),label:'8 Cameras'),NavigationDestination(icon:Icon(Icons.dns_outlined),label:'Devices')])));
}

class DevicesScreen extends StatelessWidget {
  final DeviceStore store;const DevicesScreen({super.key,required this.store});
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[Row(children:[Expanded(child:Text('My Devices (${store.devices.length}/5)',style:Theme.of(context).textTheme.titleLarge)),FilledButton.icon(onPressed:store.devices.length>=5?null:()=>showDeviceForm(context,store,null),icon:const Icon(Icons.add),label:const Text('Add NVR'))]),const SizedBox(height:12),...store.devices.map((n)=>Card(child:ListTile(leading:const Icon(Icons.dns_outlined),title:Text(n.name),subtitle:Text('${n.manufacturer}  •  Zvektra Port ${n.port}  •  ${n.maxChannels} channels'),trailing:Wrap(spacing:0,children:[IconButton(tooltip:'Edit',onPressed:()=>showDeviceForm(context,store,n),icon:const Icon(Icons.edit_outlined)),IconButton(tooltip:'Delete',onPressed:() async {final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Delete device?'),content:Text('Remove ${n.name} and its stored credentials?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete'))]));if(ok==true) await store.remove(n.id);},icon:const Icon(Icons.delete_outline))])))),if(store.devices.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('Add an NVR to begin.'))]);
}

Future<void> showDeviceForm(BuildContext context, DeviceStore store, Nvr? existing) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeviceForm(store: store, existing: existing),
  );
}

class _DeviceForm extends StatefulWidget {
  const _DeviceForm({required this.store, required this.existing});

  final DeviceStore store;
  final Nvr? existing;

  @override
  State<_DeviceForm> createState() => _DeviceFormState();
}

class _DeviceFormState extends State<_DeviceForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _port = TextEditingController(text: widget.existing?.port);
  late final _channels =
      TextEditingController(text: widget.existing?.maxChannels.toString());
  late final _user = TextEditingController(text: widget.existing?.username);
  final _password = TextEditingController();
  late String _manufacturer = widget.existing?.manufacturer ?? 'Dahua';
  late final String _id = widget.existing?.id ??
      DateTime.now().microsecondsSinceEpoch.toString();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _port.dispose();
    _channels.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final device = Nvr(
      id: _id,
      name: _name.text.trim(),
      manufacturer: _manufacturer,
      port: int.parse(_port.text).toString(),
      username: _user.text.trim(),
      maxChannels: int.parse(_channels.text),
    );
    try {
      await widget.store.save(
        device,
        _password.text.isEmpty ? null : _password.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on Exception {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the NVR. Try again.';
      });
    } on StateError {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the NVR. Try again.';
      });
    }
  }

  String? _requiredText(String? value) =>
      (value ?? '').trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(isNew ? 'Add NVR' : 'Edit NVR'),
        content: SizedBox(
          width: 430,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _name,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Device name'),
                    validator: _requiredText,
                  ),
                  DropdownButtonFormField<String>(
                    value: _manufacturer,
                    decoration: const InputDecoration(labelText: 'Manufacturer'),
                    items: manufacturers.map((name) =>
                        DropdownMenuItem(value: name, child: Text(name))).toList(),
                    onChanged: _saving ? null : (value) {
                      if (value != null) setState(() => _manufacturer = value);
                    },
                  ),
                  TextFormField(
                    controller: _port,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    decoration: const InputDecoration(labelText: 'Zvektra Port'),
                    validator: (value) {
                      final port = int.tryParse(value ?? '');
                      return port == null || port < 1 || port > 65535
                          ? 'Enter a port from 1 to 65535'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: _channels,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(labelText: 'Maximum channels'),
                    validator: (value) {
                      final channels = int.tryParse(value ?? '');
                      return channels == null || channels < 1 || channels > 999
                          ? 'Enter 1–999'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: _user,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: _requiredText,
                  ),
                  TextFormField(
                    controller: _password,
                    enabled: !_saving,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: isNew ? 'Password' : 'New password (leave blank to keep)',
                    ),
                    validator: (value) =>
                        isNew && (value ?? '').isEmpty ? 'Required' : null,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class AssistantScreen extends StatefulWidget {final DeviceStore store;const AssistantScreen({super.key,required this.store});@override State<AssistantScreen> createState()=>_AssistantScreenState();}
class _AssistantScreenState extends State<AssistantScreen> with WidgetsBindingObserver {
  final command = TextEditingController();
  static const _speech = MethodChannel('net.zvektra/speech');
  Timer? _recordingLimit;
  bool _voiceBusy = false;
  bool _awaitingSpeech = false;
  int _voiceRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech.setMethodCallHandler((call) async {
      if (!mounted || !(recording || _voiceBusy || _awaitingSpeech)) return;
      if (call.method != 'recognized' && call.method != 'speechError') return;
      final arg = call.arguments;
      final transcript = call.method == 'recognized' && arg is String ? arg.trim() : '';
      _cancelVoice();
      setState(() {
        recording = false;
        _voiceBusy = false;
        _awaitingSpeech = false;
        awaitingVoiceReview = transcript.isNotEmpty;
        if (transcript.isNotEmpty) {
          _showCommands = true;
          command.value = TextEditingValue(text: transcript,
            selection: TextSelection.collapsed(offset: transcript.length));
        }
      });
      if (transcript.isEmpty) _commandFeedback('No speech recognized. Please try again.');
    });
  }

  void _commandFeedback(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.paused || (!recording && !_voiceBusy && !_awaitingSpeech)) return;
    _cancelVoice();
    setState(() {
      recording = false;
      _voiceBusy = false;
      _awaitingSpeech = false;
      output = 'Voice recording cancelled.';
    });
  }

  void _cancelVoice() {
    ++_voiceRequest;
    _recordingLimit?.cancel();
    if (recording || _voiceBusy || _awaitingSpeech) unawaited(_cancelNativeVoice());
  }

  Future<void> _cancelNativeVoice() async {
    try {
      await _speech.invokeMethod<void>('cancel');
    } on PlatformException {
      // The activity may already be detached.
    } on MissingPluginException {
      // This screen is also used in Flutter-only tests.
    }
  }
  String output='Ready. Select an NVR and tell Zvektra what to play.';
  bool awaitingVoiceReview=false;
  static const _detection = MethodChannel('net.zvektra/playback_detection');
  static const _snapshotLimit = 200;
  final _detections = <PlaybackDetection>[];
  Timer? _detectionTimer;
  int _detectionSession = 0;
  int _peopleCount = 0;
  int _plateCount = 0;
  bool _detecting = false;
  bool _analyzing = false;
  Future<Uint8List>? _snapshotInFlight;
  Future<void>? _playerTeardown;
  bool _foreground = true;
  String? _detectionError;
  String? selectedId;int channel=1;bool recording=false;DateTime? from;DateTime? to;
  VlcPlayerController? player;
  Timer? _streamTimeout;
  ConnectionTask<Socket>? _portCheck;
  int _playRequest = 0;
  bool _connecting = false;
  bool _sharingSnapshot = false;
  bool _resumeAfterShare = false;
  bool _hasVideo = false;
  String? _videoStatus;
  ({String deviceId, int camera, DateTime? start, DateTime? end})? _lastStream;

  @override
  void dispose() {
    _streamTimeout?.cancel();
    _portCheck?.cancel();
    _stopDetection();
    WidgetsBinding.instance.removeObserver(this);
    _cancelVoice();
    _speech.setMethodCallHandler(null);
    command.dispose();
    final active = player;
    if (active != null) unawaited(_disposePlayer(active, _snapshotInFlight));
    super.dispose();
  }

  Nvr? get selected {
    for (final device in widget.store.devices) {
      if (device.id == selectedId) return device;
    }
    return widget.store.devices.isEmpty ? null : widget.store.devices.first;
  }

  Future<void> _waitForSnapshot(Future<Uint8List>? snapshot) async {
    if (snapshot == null) return;
    try {
      await snapshot;
    } catch (_) {
      // The frame sampler handles the capture error.
    }
  }

  Future<void> _disposePlayer(
    VlcPlayerController controller, [Future<Uint8List>? snapshot]
  ) async {
    await _waitForSnapshot(snapshot);
    try {
      await controller.dispose();
    } catch (_) {
      // The platform view can detach before the controller initializes.
    }
  }

  void _replacePlayer(VlcPlayerController? next) {
    final old = player;
    if (old != null) {
      _stopDetection();
      final snapshot = _snapshotInFlight;
      _playerTeardown = WidgetsBinding.instance.endOfFrame.then(
        (_) => _disposePlayer(old, snapshot),
      );
    }
    player = next;
  }

  bool _isCurrent(int request) => mounted && request == _playRequest;

  void _finishAttempt(int request, String message) {
    if (!_isCurrent(request)) return;
    _streamTimeout?.cancel();
    setState(() {
      _connecting = false;
      _hasVideo = false;
      _replacePlayer(null);
      output = message;
      _videoStatus = message;
    });
  }

  Future<void> play({DateTime? start, DateTime? end, Nvr? device, int? camera,
      bool keepDetections = false}) async {
    if (_sharingSnapshot) return;
    final target = device ?? selected;
    if (target == null) {
      setState(() => output = 'Add an NVR in Devices first.');
      return;
    }

    final request = ++_playRequest;
    final cameraNumber = (camera ?? channel).clamp(1, target.maxChannels).toInt();
    final source = '${target.name}, camera $cameraNumber';
    final port = int.tryParse(target.port);
    _streamTimeout?.cancel();
    _portCheck?.cancel();
    _stopDetection();
    final capture = _snapshotInFlight;
    if (capture != null) {
      setState(() => _connecting = true);
      await _waitForSnapshot(capture);
    }
    if (!_isCurrent(request)) return;
    setState(() {
      _replacePlayer(null);
      if (!keepDetections) {
        _detections.clear();
        _peopleCount = 0;
        _plateCount = 0;
      }
      _resumeAfterShare = false;
      _detectionError = null;
      _connecting = true;
      _hasVideo = false;
      _lastStream = (deviceId: target.id, camera: cameraNumber, start: start, end: end);
      selectedId = target.id;
      channel = cameraNumber;
      from = start;
      to = end;
      output = 'Connecting to $source…';
      _videoStatus = output;
    });

    await _playerTeardown;
    if (!_isCurrent(request)) return;
    if (port == null || port < 1 || port > 65535) {
      _finishAttempt(request, 'Edit the NVR and enter a valid RTSP port.');
      return;
    }

    String? password;
    try {
      password = await widget.store.password(target.id);
    } on Exception {
      _finishAttempt(request, 'Could not read the password. Edit the NVR and save it again.');
      return;
    }
    if (!_isCurrent(request)) return;
    if (password == null || password.isEmpty) {
      _finishAttempt(request, 'Edit the NVR and enter its password.');
      return;
    }
    final link = StreamBuilderService.url(
      target, cameraNumber, start: start, end: end, password: password,
    );
    final mode = start == null ? 'Live video' : 'Recorded playback';
    if (link == null) {
      _finishAttempt(request, '$mode is unavailable for ${target.manufacturer}.');
      return;
    }

    final alternateLink = switch (target.manufacturer) {
      'Topcam' => StreamBuilderService.url(target, cameraNumber,
          start: start, end: end, password: password, topcamFallback: true),
      'Dahua' when start == null => StreamBuilderService.url(
          target, cameraNumber, password: password, mainStream: true),
      _ => null,
    };
    _openStream(
      request, link, port, mode, source,
      softwareDecoding: false, alternateLink: alternateLink,
    );
  }

  void _openStream(
    int request,
    String link,
    int port,
    String mode,
    String source, {
    required bool softwareDecoding,
    String? alternateLink,
  }) {
    final next = VlcPlayerController.network(
      link,
      hwAcc: softwareDecoding ? HwAcc.disabled : HwAcc.auto,
      autoPlay: true,
      options: VlcPlayerOptions(
        rtp: VlcRtpOptions([VlcRtpOptions.rtpOverRtsp(true)]),
        advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(1000)]),
      ),
    );

    bool current() => _isCurrent(request) && identical(player, next);
    bool failed = false;
    bool started = false;

    Future<void> handleFailure() async {
      if (!current() || failed) return;
      failed = true;
      _streamTimeout?.cancel();
      _stopDetection();
      final capture = _snapshotInFlight;
      if (capture != null) await _waitForSnapshot(capture);
      if (!current()) return;
      setState(() {
        _connecting = true;
        _hasVideo = false;
        _replacePlayer(null);
        output = 'Checking RTSP port $port…';
        _videoStatus = output;
      });

      if (!await _checkPort(request, port)) {
        _finishAttempt(
          request,
          'Could not reach RTSP port $port. Check the NVR is online and this '
          'TCP port is forwarded to it.',
        );
        return;
      }
      await _playerTeardown;
      if (!_isCurrent(request)) return;
      if (!started && (!softwareDecoding || alternateLink != null)) {
        final tryMainStream = softwareDecoding && alternateLink != null;
        _openStream(
          request, tryMainStream ? alternateLink : link, port, mode, source,
          softwareDecoding: true,
          alternateLink: tryMainStream ? null : alternateLink,
        );
        return;
      }
      _finishAttempt(request, 'RTSP port $port is reachable, but '
          '${mode.toLowerCase()} failed for $source. Check the NVR login and '
          '${mode == 'Recorded playback' ? 'recording time.' : 'camera stream.'}');
    }

    next.addListener(() {
      if (!current() || failed) return;
      if (next.value.isEnded && _detecting) setState(_stopDetection);
      if (next.value.hasError) {
        unawaited(handleFailure());
      } else if (!started && (next.value.isPlaying || next.value.position > Duration.zero)) {
        started = true;
        _streamTimeout?.cancel();
        setState(() {
          _connecting = false;
          _hasVideo = true;
          output = '$mode: $source';
        });
      }
    });

    setState(() {
      _replacePlayer(next);
      if (softwareDecoding) output = 'Retrying video for $source…';
      _videoStatus = output;
    });
    _streamTimeout = Timer(const Duration(seconds: 15), () {
      if (!started) unawaited(handleFailure());
    });
  }

  Future<bool> _checkPort(int request, int port) async {
    ConnectionTask<Socket>? task;
    final deadline = Stopwatch()..start();
    const timeout = Duration(seconds: 5);
    // A DNS lookup may outlast the timeout. Close any socket it creates late.
    bool expired = false;
    try {
      task = await Socket.startConnect(host, port).then((connection) {
        if (expired || !_isCurrent(request)) {
          unawaited(connection.socket.then<void>(
            (socket) => socket.destroy(),
            onError: (Object _) {},
          ));
          connection.cancel();
          return null;
        }
        return connection;
      }).timeout(timeout);
      if (task == null) return false;
      _portCheck = task;
      final socket = await task.socket.timeout(timeout - deadline.elapsed);
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      expired = true;
      return false;
    } finally {
      task?.cancel();
      if (identical(_portCheck, task)) _portCheck = null;
    }
  }

  Future<void> pausePlayback() async {
    if (_connecting) {
      final request = ++_playRequest;
      _streamTimeout?.cancel();
      _portCheck?.cancel();
      _stopDetection();
      final capture = _snapshotInFlight;
      if (capture != null) await _waitForSnapshot(capture);
      if (!_isCurrent(request)) return;
      setState(() {
        _connecting = false;
        _replacePlayer(null);
        output = 'Connection cancelled.';
        _videoStatus = output;
      });
      return;
    }
    final active = player;
    if (!_hasVideo || active == null) return;
    try {
      await active.pause();
      if (mounted && identical(player, active)) {
        setState(() => output = 'Paused.');
      }
    } on PlatformException {
      if (mounted && identical(player, active)) {
        setState(() => output = 'Could not pause this stream.');
      }
    }
  }

  Future<void> resumePlayback() async {
    if (_connecting || _sharingSnapshot) return;
    final active = player;
    if (_hasVideo && active != null) {
      try {
        await active.play();
        if (mounted && identical(player, active)) {
          setState(() => output = 'Resumed.');
        }
      } on PlatformException {
        if (mounted && identical(player, active)) {
          setState(() => output = 'Could not resume this stream.');
        }
      }
      return;
    }
    final last = _lastStream;
    if (last == null) return;
    for (final device in widget.store.devices) {
      if (device.id == last.deviceId) {
        await play(start: last.start, end: _resumeAfterShare ? last.end : null,
            device: device, camera: last.camera, keepDetections: _resumeAfterShare);
        return;
      }
    }
  }
  Future<void> _sharePlaybackSnapshot(Uint8List snapshot) async {
    if (_sharingSnapshot) return;
    _sharingSnapshot = true;
    const share = MethodChannel('net.zvektra/snapshot_share');
    try {
      final available = await share.invokeMethod<bool>('available');
      if (!mounted) return;
      if (available != true) {
        _commandFeedback('Install WhatsApp or WhatsApp Business to share this snapshot.');
        return;
      }
      final request = ++_playRequest;
      _streamTimeout?.cancel();
      _portCheck?.cancel();
      setState(_stopDetection);
      await _waitForSnapshot(_snapshotInFlight);
      if (!_isCurrent(request)) return;
      final active = player;
      final last = _lastStream;
      if (active != null && last != null) {
        final elapsed = active.value.position;
        final nextStart = last.start?.add(elapsed);
        final canResumeAtPosition =
            nextStart != null && (last.end == null || nextStart.isBefore(last.end!));
        _lastStream = (
          deviceId: last.deviceId, camera: last.camera,
          start: canResumeAtPosition ? nextStart : last.start, end: last.end,
        );
        _resumeAfterShare = true;
      }
      setState(() {
        _replacePlayer(null);
        _hasVideo = false;
        _connecting = false;
        _videoStatus = 'Playback paused for sharing. Tap Resume to continue.';
      });
      await _playerTeardown;
      if (!_isCurrent(request)) return;
      await share.invokeMethod<void>('whatsapp', snapshot);
    } on Exception {
      _commandFeedback('Could not open WhatsApp to share this snapshot.');
    } finally {
      _sharingSnapshot = false;
    }
  }

  void _stopDetection() {
    ++_detectionSession;
    _detectionTimer?.cancel();
    _detectionTimer = null;
    _detecting = false;
  }

  void _startDetection() {
    final active = player;
    final start = from;
    if (_connecting || !_hasVideo || active == null || start == null || active.value.isEnded) {
      setState(() => _detectionError = 'Start recorded playback to detect people and vehicles.');
      return;
    }
    if (_detecting) return;
    final session = ++_detectionSession;
    final camera = _lastStream!.camera;
    setState(() {
      _detecting = true;
      _detectionError = null;
    });
    void sample() => unawaited(_analyzePlaybackFrame(active, start, camera, session));
    _detectionTimer = Timer.periodic(const Duration(seconds: 1), (_) => sample());
    sample();
  }

  Future<void> _analyzePlaybackFrame(
    VlcPlayerController active, DateTime start, int camera, int session,
  ) async {
    bool current() => mounted && session == _detectionSession && identical(active, player);
    bool playing() => _foreground && active.value.isInitialized &&
        active.value.isPlaying;
    if (!current() || !playing() || _analyzing) return;
    _analyzing = true;
    try {
      final timestamp = start.add(active.value.position);
      final snapshot = active.takeSnapshot();
      _snapshotInFlight = snapshot;
      late final Uint8List jpeg;
      try {
        jpeg = await snapshot;
      } finally {
        _snapshotInFlight = null;
      }
      if (!current() || !playing() || jpeg.isEmpty) return;
      final detected = await _detection.invokeListMethod<Map<Object?, Object?>>('analyze', jpeg);
      if (!current() || !playing() || detected == null || detected.isEmpty) return;
      final results = detected.map((entry) => PlaybackDetection(
        kind: PlaybackDetectionKind.values.byName(entry['kind'] as String),
        timestamp: timestamp,
        camera: camera,
        snapshot: entry['snapshot'] as Uint8List,
      ));
      setState(() {
        for (final result in results) {
          if (result.kind == PlaybackDetectionKind.person) {
            _peopleCount++;
          } else {
            _plateCount++;
          }
          _detections.add(result);
        }
        final excess = _detections.length - _snapshotLimit;
        if (excess > 0) _detections.removeRange(0, excess);
      });
    } catch (_) {
      if (!current() || !playing()) return;
      setState(() {
        _stopDetection();
        _detectionError = 'Could not analyze the playback frame. Try starting detection again.';
      });
    } finally {
      _analyzing = false;
    }
  }

  Future<void> execute(String raw) async {
    final input = raw.trim();
    if (input.isEmpty) return;
    final normalized = RegExp(r'[\u0600-\u06FF]').hasMatch(input)
        ? arabicPlaybackCommand(input) : input;
    if (normalized == null) {
      _commandFeedback('الأمر مش واضح. جرّب: فرجيني كاميرا واحد مبارح من ١٢ للـ ١٢ وخمسة');
      return;
    }
    final text = normalized.toLowerCase().replaceAll(RegExp(r':(?=\s*(?:am|pm)\b)'), '');
    for(final n in widget.store.devices){if(text.contains(n.name.toLowerCase()))selectedId=n.id;}
    final match=RegExp(r'(?:camera|channel|cam)\s*(\d+)').firstMatch(text);
    if(match!=null){final c=int.tryParse(match.group(1)!);if(c!=null&&selected!=null&&c<=selected!.maxChannels&&c>0)channel=c;else{_commandFeedback('Camera number is outside the configured channel range.');return;}}
    if (RegExp(r'\bstop (counting|detection|detecting)\b').hasMatch(text)) {
      setState(_stopDetection);
      return;
    }
    if (RegExp(r'\b(count|detect|snapshot)\b').hasMatch(text)) {
      _startDetection();
      return;
    }
    if(text.contains('pause')){await pausePlayback();return;}
    if(text.contains('resume')){await resumePlayback();return;}
    if(RegExp(r'^(?:skip\s+)?(?:forward|back|rewind)\b').hasMatch(text)){final seconds=int.tryParse(RegExp(r'\d+').firstMatch(text)?.group(0)??'30')??30;if(from==null){setState(()=>output='Choose recorded playback first.');return;}await play(start:from!.add(Duration(seconds:RegExp(r'\bback\b|\brewind\b').hasMatch(text)?-seconds:seconds)));return;}
    if (text.contains('record') || text.contains('playback') || text.contains('play back')) {
      final now = DateTime.now();
      DateTime date = _playbackDate;
      if (RegExp(r'\btoday\b').hasMatch(text)) {
        date = DateTime(now.year, now.month, now.day);
      } else if (RegExp(r'\byesterday\b').hasMatch(text)) {
        date = DateTime(now.year, now.month, now.day - 1);
      }
      final range = RegExp(
        r'\bfrom\s+(\d{1,2})(?::(\d{1,2}))?\s*(am|pm|a\.m\.|p\.m\.)?\s+to\s+(\d{1,2})(?::(\d{1,2}))?\s*(am|pm|a\.m\.|p\.m\.)?',
      ).firstMatch(text);
      if (range == null) {
        _commandFeedback('Use: playback cam3 today from 6:00 am to 6:06 am');
        return;
      }
      TimeOfDay? parseClock(String? h, String? m, String? suffix) {
        var hour = int.tryParse(h ?? '');
        final minute = int.tryParse(m ?? '0');
        if (hour == null || minute == null || minute > 59) return null;
        final meridiem = suffix?.replaceAll('.', '');
        if (meridiem != null) {
          if (hour < 1 || hour > 12) return null;
          hour = (hour % 12) + (meridiem == 'pm' ? 12 : 0);
        } else if (hour > 23) {
          return null;
        }
        return TimeOfDay(hour: hour, minute: minute);
      }
      final firstSuffix = range.group(3) ?? range.group(6);
      final fromTime = parseClock(range.group(1), range.group(2), firstSuffix);
      final toTime = parseClock(range.group(4), range.group(5), range.group(6));
      if (fromTime == null || toTime == null) {
        _commandFeedback('Invalid playback time.');
        return;
      }
      final start = DateTime(date.year, date.month, date.day, fromTime.hour, fromTime.minute);
      final end = DateTime(date.year, date.month, date.day, toTime.hour, toTime.minute);
      setState(() {
        _playbackDate = date;
        _playbackFrom = fromTime;
        _playbackTo = toTime;
      });
      if (!end.isAfter(start) || end.isAfter(now)) {
        _commandFeedback('Choose an end time after the start and before now.');
        return;
      }
      await play(start: start, end: end);
      return;
    }
    if(text.contains('live')||text.contains('show')||text.contains('play')){await play();return;}
    _commandFeedback('Command not understood. Try “playback cam 1 yesterday from 12:00 to 12:05”.');
  }
  bool _showCommands = false;
  DateTime _playbackDate = DateTime.now().subtract(const Duration(days: 1));
  TimeOfDay _playbackFrom = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _playbackTo = const TimeOfDay(hour: 13, minute: 0);

  DateTime _atTime(TimeOfDay time) => DateTime(
    _playbackDate.year, _playbackDate.month, _playbackDate.day,
    time.hour, time.minute,
  );

  Future<void> _selectPlaybackDate() async {
    final date = await showDatePicker(
      context: context, initialDate: _playbackDate,
      firstDate: DateTime(2020), lastDate: DateTime.now(),
    );
    if (date != null && mounted) setState(() => _playbackDate = date);
  }

  Future<void> _selectPlaybackTime(bool isFrom) async {
    final time = await showTimePicker(
      context: context, initialTime: isFrom ? _playbackFrom : _playbackTo,
    );
    if (time != null && mounted) {
      setState(() {
        if (isFrom) { _playbackFrom = time; } else { _playbackTo = time; }
      });
    }
  }

  Future<void> _playSelectedRange() async {
    final start = _atTime(_playbackFrom);
    final end = _atTime(_playbackTo);
    if (!end.isAfter(start) || end.isAfter(DateTime.now())) {
      setState(() => output = 'Select a valid time range on the chosen date.');
      return;
    }
    await play(start: start, end: end);
  }

  Future<void> toggleMic() async {
    if (_voiceBusy || _awaitingSpeech) return;
    final request = ++_voiceRequest;
    final ending = recording;
    _recordingLimit?.cancel();
    setState(() {
      _voiceBusy = true;
      if (ending) {
        recording = false;
        _awaitingSpeech = true;
        output = 'Transcribing on this phone…';
      }
    });
    bool current() => mounted && request == _voiceRequest;

    try {
      if (ending) {
        _recordingLimit = Timer(const Duration(seconds: 8), () {
          if (!current() || !_awaitingSpeech) return;
          _cancelVoice();
          setState(() { _awaitingSpeech = false; _voiceBusy = false; });
          _commandFeedback('Speech recognition timed out. Please try again.');
        });
        await _speech.invokeMethod<void>('stop');
      } else {
        final permission = await Permission.microphone.request();
        if (!current()) return;
        if (!permission.isGranted) {
          setState(() => output = 'Allow microphone access to record a command.');
          return;
        }
        await _speech.invokeMethod<void>('start');
        if (!current()) return;
        setState(() {
          recording = true;
          output = 'Listening… tap the microphone to finish.';
        });
        _recordingLimit = Timer(const Duration(seconds: 10), () {
          if (mounted && recording) unawaited(toggleMic());
        });
      }
    } on Exception {
      if (current()) {
        _cancelVoice();
        setState(() {
          recording = false;
          _awaitingSpeech = false;
          _voiceBusy = false;
        });
        _commandFeedback(ending ? 'Speech recognition failed. Please try again.'
            : 'Could not start voice recognition.');
      }
    } finally {
      if (current()) setState(() => _voiceBusy = false);
    }
  }

  Widget _videoPanel() {
    final active = player;
    final status = _videoStatus;
    if (active == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(status ?? 'No video selected', textAlign: TextAlign.center),
        ),
      );
    }
    return LayoutBuilder(builder: (context, space) => Stack(
      fit: StackFit.expand,
      children: [
        VlcPlayer(
          key: ObjectKey(active),
          controller: active,
          aspectRatio: space.maxWidth / space.maxHeight.clamp(1.0, double.infinity),
          virtualDisplay: false,
        ),
        if (_connecting && status != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: ColoredBox(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(status, textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final n = selected;
    return LayoutBuilder(builder: (context, bounds) => Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 2), child: Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          value: n?.id, isExpanded: true,
          decoration: const InputDecoration(labelText: 'NVR', isDense: true, border: OutlineInputBorder()),
          items: widget.store.devices.map((x) => DropdownMenuItem(
            value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (x) => setState(() {
            if (x != n?.id) _stopDetection();
            selectedId = x;
          }),
        )),
        const SizedBox(width: 8),
        SizedBox(width: 138, child: DropdownButtonFormField<int>(
          key: ValueKey((n?.id, n?.maxChannels, channel)),
          value: n == null ? 1 : channel <= n.maxChannels ? channel : 1,
          decoration: const InputDecoration(labelText: 'Camera', isDense: true, border: OutlineInputBorder()),
          items: List.generate(n?.maxChannels ?? 1,
            (i) => DropdownMenuItem(value: i + 1, child: Text('Cam ${i + 1}'))),
          onChanged: n == null ? null : (v) {
            if (v == null || v == channel) return;
            setState(() {
              _stopDetection();
              channel = v;
            });
          },
        )),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          OutlinedButton(
            onPressed: _selectPlaybackDate,
            child: Text(DateFormat('dd MMM yyyy').format(_playbackDate)),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: () => _selectPlaybackTime(true),
            child: Text('From ${_playbackFrom.format(context)}'),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: () => _selectPlaybackTime(false),
            child: Text('To ${_playbackTo.format(context)}'),
          ),
        ]))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
        FilledButton.icon(
          onPressed: _playSelectedRange,
          icon: const Icon(Icons.play_arrow), label: const Text('Playback'),
        ),
        IconButton(onPressed: pausePlayback, icon: const Icon(Icons.pause), tooltip: 'Pause'),
        IconButton(onPressed: resumePlayback, icon: const Icon(Icons.play_arrow), tooltip: 'Resume'),
        IconButton(
          onPressed: _detecting ? () => setState(_stopDetection) : _startDetection,
          icon: Icon(_detecting ? Icons.stop_circle_outlined : Icons.center_focus_strong),
          tooltip: _detecting ? 'Stop detection' : 'Detect people and vehicles',
        ),
        IconButton(onPressed: _voiceBusy || _awaitingSpeech ? null : toggleMic,
          icon: Icon(recording ? Icons.mic : Icons.mic_none), tooltip: 'Voice'),
        IconButton(onPressed: () => setState(() => _showCommands = !_showCommands),
          icon: const Icon(Icons.keyboard), tooltip: 'Commands'),
        if (bounds.maxHeight < 345 && _detections.isNotEmpty)
          IconButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => SafeArea(child: PlaybackDetectionResults(
                detections: List.of(_detections),
                peopleCount: _peopleCount,
                plateCount: _plateCount,
                running: false,
                onShare: (snapshot) {
                  Navigator.pop(context);
                  unawaited(_sharePlaybackSnapshot(snapshot));
                },
              )),
            ),
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Detection results',
          ),
      ])),
      Expanded(child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12),border: Border.all(color:cyan.withValues(alpha:0.2))),
        child: _videoPanel(),
      )),
      if (_detectionError case final message?)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
      if (bounds.maxHeight >= 345 && (_detecting || _detections.isNotEmpty))
        PlaybackDetectionResults(
          detections: _detections,
          peopleCount: _peopleCount,
          plateCount: _plateCount,
          running: _detecting,
          onShare: _sharePlaybackSnapshot,
        ),
      if (_showCommands) Padding(
        padding: const EdgeInsets.all(6),
        child: Row(children: [
          Expanded(child: TextField(controller: command, minLines: 1, maxLines: 2,
            decoration: const InputDecoration(hintText: 'Command', isDense: true,
              border: OutlineInputBorder()))),
          IconButton(tooltip: 'Send command', onPressed: () async {
            final typed = command.text.trim();
            if (typed.isEmpty) return;
            FocusScope.of(context).unfocus();
            setState(() { awaitingVoiceReview = false; output = 'Processing command…'; });
            try { await execute(typed); }
            catch (_) { _commandFeedback('Command failed. Please try again.'); }
          }, icon: const Icon(Icons.send_rounded, color: cyan)),
        ]),
      ),
    ]));
  }
}
