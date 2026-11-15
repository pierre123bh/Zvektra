import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const ZvektraApp()); }

const host = 'zvektra.net';
const manufacturers = ['Dahua', 'Hikvision', 'Uniview', 'MEye'];
const navy = Color(0xFF0D1725);
const cyan = Color(0xFF62E2E6);

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
  Future<void> save(Nvr device,String? newPassword) async {
    final idx=devices.indexWhere((x)=>x.id==device.id);
    if(idx<0 && devices.length>=5) throw StateError('Maximum 5 devices');
    if(idx<0) {devices.add(device);} else {devices[idx]=device;}
    if(newPassword!=null && newPassword.isNotEmpty) await _secure.write(key:'nvr_password_${device.id}',value:newPassword);
    await _persist();
  }
  Future<void> remove(String id) async {
    devices.removeWhere((x)=>x.id==id);
    await _secure.delete(key:'nvr_password_$id');
    await _persist();
  }
  Future<void> _persist() async {final p=await SharedPreferences.getInstance();await p.setString('devices',jsonEncode(devices.map((x)=>x.toJson()).toList()));notifyListeners();}
}

// Only Dahua's recording RTSP path has been verified with the user's NVR.
// Other vendor URLs are candidates requiring hardware-specific verification.
class StreamBuilderService {
  static String? url(Nvr n,int channel,{DateTime? start,DateTime? end,required String password}) {
    final user=Uri.encodeComponent(n.username);
    final pass=Uri.encodeComponent(password);
    final base='rtsp://$user:$pass@$host:${n.port}';
    if(n.manufacturer=='Dahua') {
      if(start==null) return '$base/cam/realmonitor?channel=$channel&subtype=1';
      final f=DateFormat('yyyy_MM_dd_HH_mm_ss');
      return '$base/cam/playback?channel=$channel&starttime=${f.format(start)}&endtime=${f.format(end??start.add(const Duration(minutes:10)))}';
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
  @override Widget build(BuildContext context)=>MaterialApp(title:'Zvektra',debugShowCheckedModeBanner:false,theme:ThemeData(brightness:Brightness.dark,scaffoldBackgroundColor:navy,colorScheme:ColorScheme.fromSeed(seedColor:cyan,brightness:Brightness.dark),useMaterial3:true),home:Home(store:store));
}

class Home extends StatefulWidget {final DeviceStore store;const Home({super.key,required this.store});@override State<Home> createState()=>_HomeState();}
class _HomeState extends State<Home> {
  int tab=0;
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:widget.store,builder:(context,_)=>Scaffold(appBar:AppBar(title:const Text('ZVEKTRA',style:TextStyle(fontWeight:FontWeight.w800,letterSpacing:3)),backgroundColor:navy,actions:[const Padding(padding:EdgeInsets.only(right:14),child:Icon(Icons.shield_outlined,color:cyan))]),body:tab==0?AssistantScreen(store:widget.store):DevicesScreen(store:widget.store),bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(x)=>setState(()=>tab=x),destinations:const [NavigationDestination(icon:Icon(Icons.graphic_eq),label:'Assistant'),NavigationDestination(icon:Icon(Icons.dns_outlined),label:'Devices')])));
}

class DevicesScreen extends StatelessWidget {
  final DeviceStore store;const DevicesScreen({super.key,required this.store});
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[Row(children:[Expanded(child:Text('My Devices (${store.devices.length}/5)',style:Theme.of(context).textTheme.titleLarge)),FilledButton.icon(onPressed:store.devices.length>=5?null:()=>showDeviceForm(context,store,null),icon:const Icon(Icons.add),label:const Text('Add NVR'))]),const SizedBox(height:12),const Text('Fixed hostname: zvektra.net',style:TextStyle(color:cyan)),const SizedBox(height:12),...store.devices.map((n)=>Card(child:ListTile(leading:const Icon(Icons.dns_outlined),title:Text(n.name),subtitle:Text('${n.manufacturer}  •  Zvektra Port ${n.port}  •  ${n.maxChannels} channels'),trailing:Wrap(spacing:0,children:[IconButton(tooltip:'Edit',onPressed:()=>showDeviceForm(context,store,n),icon:const Icon(Icons.edit_outlined)),IconButton(tooltip:'Delete',onPressed:() async {final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Delete device?'),content:Text('Remove ${n.name} and its stored credentials?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete'))]));if(ok==true) await store.remove(n.id);},icon:const Icon(Icons.delete_outline))])))),if(store.devices.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('Add an NVR to begin. The hostname is fixed; each NVR uses its own Zvektra Port.'))]);
}

Future<void> showDeviceForm(BuildContext context,DeviceStore store,Nvr? existing) async {
  final name=TextEditingController(text:existing?.name??'');final port=TextEditingController(text:existing?.port??'');final channels=TextEditingController(text:existing?.maxChannels.toString()??'');final user=TextEditingController(text:existing?.username??'');final pass=TextEditingController();var maker=existing?.manufacturer??'Dahua';final key=GlobalKey<FormState>();
  await showDialog<void>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(context,setDialog)=>AlertDialog(title:Text(existing==null?'Add NVR':'Edit NVR'),content:SizedBox(width:430,child:Form(key:key,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[const ListTile(dense:true,title:Text('Hostname'),subtitle:Text(host),trailing:Icon(Icons.lock_outline)),TextFormField(controller:name,decoration:const InputDecoration(labelText:'Device name'),validator:(v)=>v==null||v.trim().isEmpty?'Required':null),DropdownButtonFormField<String>(value:maker,decoration:const InputDecoration(labelText:'Manufacturer'),items:manufacturers.map((m)=>DropdownMenuItem(value:m,child:Text(m))).toList(),onChanged:(v)=>setDialog(()=>maker=v??maker)),TextFormField(controller:port,keyboardType:TextInputType.number,inputFormatters:[FilteringTextInputFormatter.digitsOnly,LengthLimitingTextInputFormatter(5)],decoration:const InputDecoration(labelText:'Zvektra Port',hintText:'Enter 1–65535'),validator:(v){final p=int.tryParse(v??'');return p==null||p<1||p>65535?'Enter a valid port (1–65535)':null;}),TextFormField(controller:channels,keyboardType:TextInputType.number,inputFormatters:[FilteringTextInputFormatter.digitsOnly,LengthLimitingTextInputFormatter(3)],decoration:const InputDecoration(labelText:'Maximum channels'),validator:(v){final n=int.tryParse(v??'');return n==null||n<1||n>999?'Enter 1–999':null;}),TextFormField(controller:user,decoration:const InputDecoration(labelText:'Username'),validator:(v)=>v==null||v.trim().isEmpty?'Required':null),TextFormField(controller:pass,obscureText:true,decoration:InputDecoration(labelText:existing==null?'Password':'New password (leave blank to keep)'),validator:(v)=>existing==null&&(v==null||v.isEmpty)?'Required':null)])))),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Cancel')),FilledButton(onPressed:() async {if(!key.currentState!.validate())return;final n=Nvr(id:existing?.id??DateTime.now().microsecondsSinceEpoch.toString(),name:name.text.trim(),manufacturer:maker,port:port.text,username:user.text.trim(),maxChannels:int.parse(channels.text));await store.save(n,pass.text.isEmpty?null:pass.text);if(dialogContext.mounted)Navigator.pop(dialogContext);},child:const Text('Save'))])));
  name.dispose();port.dispose();channels.dispose();user.dispose();pass.dispose();
}

class AssistantScreen extends StatefulWidget {final DeviceStore store;const AssistantScreen({super.key,required this.store});@override State<AssistantScreen> createState()=>_AssistantScreenState();}
class _AssistantScreenState extends State<AssistantScreen> {
  final command=TextEditingController();final speech=stt.SpeechToText();
  String output='Ready. Select an NVR and tell Zvektra what to play.';
  bool awaitingVoiceReview=false;
  bool detectionRequested=false;
  final List<String> detectionEvents=[];
  String? selectedId;int channel=1;bool recording=false;DateTime? from;
  VlcPlayerController? player;
  @override void dispose(){command.dispose();speech.stop();player?.dispose();super.dispose();}
  Nvr? get selected {for(final n in widget.store.devices){if(n.id==selectedId)return n;}return widget.store.devices.isNotEmpty?widget.store.devices.first:null;}
  Future<void> play({DateTime? start}) async {
    final n=selected;if(n==null){setState(()=>output='Add an NVR in Devices first.');return;}
    final pw=await widget.store.password(n.id);
    if(pw==null||pw.isEmpty){setState(()=>output='Missing credentials. Edit the device and enter its password.');return;}
    final begin=start;final link=StreamBuilderService.url(n,channel,start:begin,end:begin?.add(const Duration(minutes:10)),password:pw);
    if(link==null){setState(()=>output='${n.manufacturer} ${begin==null?'live':'recorded'} RTSP URL not verified yet. Vendor-specific integration is required.');return;}
    final old=player;
    final next=VlcPlayerController.network(link,hwAcc:HwAcc.auto,autoPlay:true,options:VlcPlayerOptions());
    setState((){player=next;from=begin;output='${begin==null?'Live':'Recorded'} playback: ${n.name}, camera $channel';});
    if(old!=null)await old.dispose();
  }
  Future<void> execute(String raw) async {
    final text=raw.trim().toLowerCase();if(text.isEmpty)return;
    final match=RegExp(r'(?:camera|channel|cam)\s*(\d+)').firstMatch(text);
    if(match!=null){final c=int.parse(match.group(1)!);if(selected!=null&&c<=selected!.maxChannels&&c>0)channel=c;else{setState(()=>output='Camera $c is outside the configured channel range.');return;}}
    for(final n in widget.store.devices){if(text.contains(n.name.toLowerCase()))selectedId=n.id;}
    if(text.contains('stop counting')||text.contains('stop detection')){setState((){detectionRequested=false;output='Detection request stopped. The native AI engine is not yet connected.';});return;}
    if(text.contains('count')||text.contains('detect')||text.contains('snapshot')){setState((){detectionRequested=true;output='Person detection requested. Native frame extraction and inference are not yet connected; no count or snapshots have been generated.';});return;}
    if(text.contains('pause')){await player?.pause();setState(()=>output='Paused');return;}
    if(text.contains('resume')){await player?.play();setState(()=>output='Resumed');return;}
    if(text.contains('forward')||text.contains('back')){final seconds=int.tryParse(RegExp(r'\d+').firstMatch(text)?.group(0)??'30')??30;if(from==null){setState(()=>output='Choose recorded playback first.');return;}await play(start:from!.add(Duration(seconds:text.contains('back')?-seconds:seconds)));return;}
    if(text.contains('yesterday')){final now=DateTime.now();final yesterday=DateTime(now.year,now.month,now.day-1,now.hour,now.minute);await play(start:yesterday);return;}
    if(text.contains('record')||text.contains('playback')){await play(start:DateTime.now().subtract(const Duration(minutes:10)));return;}
    if(text.contains('live')||text.contains('show')||text.contains('play')){await play();return;}
    setState(()=>output='Try: "show camera 2", "playback camera 1", "pause", or "forward 30 seconds".');
  }
  Future<void> toggleMic() async {
    if(recording){await speech.stop();setState(()=>recording=false);return;}
    final ready=await speech.initialize(onStatus:(s){if(s=='done'&&mounted)setState(()=>recording=false);},onError:(e){if(mounted)setState(()=>output='Microphone: ${e.errorMsg}');});
    if(!ready){setState(()=>output='Speech recognition unavailable on this phone.');return;}
    setState(()=>recording=true);
    await speech.listen(onResult:(r){command.value=TextEditingValue(text:r.recognizedWords,selection:TextSelection.collapsed(offset:r.recognizedWords.length));if(r.finalResult){setState((){recording=false;awaitingVoiceReview=true;output='Review the recognized command below. Correct it if necessary, then press Execute.';});}});
  }
  @override Widget build(BuildContext context){final n=selected;return ListView(padding:const EdgeInsets.all(16),children:[const Center(child:Icon(Icons.blur_circular,size:82,color:cyan)),const SizedBox(height:6),Center(child:Text('ZVEKTRA ASSISTANT',style:Theme.of(context).textTheme.titleLarge)),const Center(child:Text('Local-first remote video intelligence',style:TextStyle(color:Colors.white60))),const SizedBox(height:18),if(widget.store.devices.isNotEmpty)DropdownButtonFormField<String>(value:n?.id,decoration:const InputDecoration(labelText:'Active NVR',border:OutlineInputBorder()),items:widget.store.devices.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.name))).toList(),onChanged:(x)=>setState(()=>selectedId=x)),if(n!=null)...[const SizedBox(height:12),DropdownButtonFormField<int>(value:channel<=n.maxChannels?channel:1,decoration:const InputDecoration(labelText:'Camera',border:OutlineInputBorder()),items:List.generate(n.maxChannels,(i)=>DropdownMenuItem(value:i+1,child:Text('Camera ${i+1}'))),onChanged:(v)=>setState(()=>channel=v??1))],const SizedBox(height:14),Container(height:230,color:Colors.black,child:player==null?const Center(child:Text('No video selected')):VlcPlayer(key:ObjectKey(player),controller:player!,aspectRatio:16/9,placeholder:const Center(child:CircularProgressIndicator()))),const SizedBox(height:12),Wrap(alignment:WrapAlignment.center,spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:()=>play(),icon:const Icon(Icons.live_tv),label:const Text('Live')),OutlinedButton.icon(onPressed:()=>play(start:DateTime.now().subtract(const Duration(minutes:10))),icon:const Icon(Icons.history),label:const Text('Playback')),OutlinedButton.icon(onPressed:()=>player?.pause(),icon:const Icon(Icons.pause),label:const Text('Pause')),OutlinedButton.icon(onPressed:()=>player?.play(),icon:const Icon(Icons.play_arrow),label:const Text('Resume'))]),const SizedBox(height:10),OutlinedButton.icon(onPressed:() async {final now=DateTime.now();final date=await showDatePicker(context:context,initialDate:now,firstDate:DateTime(2020),lastDate:now);if(date==null||!context.mounted)return;final time=await showTimePicker(context:context,initialTime:TimeOfDay.now());if(time==null)return;await play(start:DateTime(date.year,date.month,date.day,time.hour,time.minute));},icon:const Icon(Icons.calendar_month),label:const Text('Select recording date & time')),if(from!=null)Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[TextButton(onPressed:()=>play(start:from!.subtract(const Duration(seconds:30))),child:const Text('−30 sec')),Text(DateFormat('MM/dd HH:mm:ss').format(from!)),TextButton(onPressed:()=>play(start:from!.add(const Duration(seconds:30))),child:const Text('+30 sec'))]),const SizedBox(height:12),Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(output))),const SizedBox(height:12),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[if(awaitingVoiceReview)const Padding(padding:EdgeInsets.only(bottom:8),child:Text('Voice transcription — edit before executing',style:TextStyle(color:cyan))),Row(children:[Expanded(child:TextField(controller:command,minLines:1,maxLines:3,onChanged:(_){if(awaitingVoiceReview)setState((){});},onSubmitted:(v){setState(()=>awaitingVoiceReview=false);execute(v);},decoration:const InputDecoration(hintText:'Speak or type a command...',border:OutlineInputBorder()))),IconButton(onPressed:toggleMic,tooltip:recording?'Stop listening':'Speak command',icon:Icon(recording?Icons.mic:Icons.mic_none,color:cyan)),IconButton(onPressed:(){setState(()=>awaitingVoiceReview=false);execute(command.text);},tooltip:'Execute edited command',icon:const Icon(Icons.send,color:cyan))]),if(awaitingVoiceReview)TextButton.icon(onPressed:(){command.clear();setState(()=>awaitingVoiceReview=false);},icon:const Icon(Icons.close),label:const Text('Discard transcription'))]),const SizedBox(height:10),Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('People detection',style:TextStyle(fontWeight:FontWeight.bold)),Text(detectionRequested?'Requested — waiting for native AI integration':'Inactive'),const SizedBox(height:4),Text('Detected appearances: ${detectionEvents.length} (no AI frames processed)',style:const TextStyle(color:Colors.white70)),const Text('Snapshots: not yet available',style:TextStyle(color:Colors.white70))]))),const SizedBox(height:10),const Text('Voice input currently uses Android speech recognition, not Whisper. Transcriptions are editable and require confirmation. Offline Whisper and native AI frame detection/snapshots are not yet operational.',style:TextStyle(color:Colors.white54,fontSize:12))]);}
}
