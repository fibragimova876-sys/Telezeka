import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:record/record.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main(){WidgetsFlutterBinding.ensureInitialized();MediaKit.ensureInitialized();runApp(const FamilyApp());}
class Api {
  Api(this.base); final String base; String token=''; final client=HttpClient()..connectionTimeout=const Duration(seconds:10);
  Future<dynamic> req(String path,[Map<String,dynamic>? body]) async {
    final uri=Uri.parse('$base$path');
    final r=await client.openUrl(body==null?'GET':'POST',uri);r.headers.set('Authorization','Bearer $token');r.headers.contentType=ContentType.json;
    if(body!=null)r.write(jsonEncode(body));final res=await r.close().timeout(const Duration(seconds:30));final data=jsonDecode(await utf8.decoder.bind(res).join().timeout(const Duration(seconds:30)));if(res.statusCode>=400)throw Exception(data['error']??'Ошибка сети');return data;
  }
}
enum TelezekaTheme {system,light,dark}
final themeMode=ValueNotifier<ThemeMode>(ThemeMode.system);
class FamilyApp extends StatelessWidget {
 const FamilyApp({super.key});
 static ThemeData design(Brightness brightness){
  final dark=brightness==Brightness.dark;
  final scheme=ColorScheme.fromSeed(seedColor:const Color(0xff376b60),brightness:brightness).copyWith(
    primary:dark?const Color(0xffa0d7c5):const Color(0xff376b60),
    onPrimary:dark?const Color(0xff14332c):Colors.white,
    surface:dark?const Color(0xff1c2524):const Color(0xfffbfaf7),
    surfaceContainerLowest:dark?const Color(0xff131c1b):const Color(0xffefeee8),
    surfaceContainerHigh:dark?const Color(0xff2c3936):const Color(0xffe6eae3),
    surfaceContainerHighest:dark?const Color(0xff384842):const Color(0xffdce5de),
    primaryContainer:dark?const Color(0xff2c5146):const Color(0xffdcece1),
    onPrimaryContainer:dark?const Color(0xffe4f4eb):const Color(0xff244b3e),
    outlineVariant:dark?const Color(0xff35433d):const Color(0xffdce0d8));
  final base=ThemeData(useMaterial3:true,colorScheme:scheme,scaffoldBackgroundColor:scheme.surface);
  return base.copyWith(
    textTheme:base.textTheme,
    appBarTheme:AppBarTheme(backgroundColor:scheme.surface,foregroundColor:scheme.onSurface,elevation:0,scrolledUnderElevation:0,titleTextStyle:TextStyle(color:scheme.onSurface,fontWeight:FontWeight.w600,fontSize:18)),
    dividerTheme:DividerThemeData(color:scheme.outlineVariant,thickness:1,space:1),
    inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:scheme.surfaceContainerLowest,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none),enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none),focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide(color:scheme.primary,width:1.5)),contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:14)),
    filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(minimumSize:const Size(64,46),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),textStyle:const TextStyle(fontSize:14,fontWeight:FontWeight.w600))),
    snackBarTheme:SnackBarThemeData(behavior:SnackBarBehavior.floating,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
    popupMenuTheme:PopupMenuThemeData(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),color:scheme.surface,elevation:4),
    dialogTheme:DialogThemeData(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),backgroundColor:scheme.surface),
    navigationBarTheme:NavigationBarThemeData(backgroundColor:scheme.surface,indicatorColor:scheme.primaryContainer,height:66),
    listTileTheme:ListTileThemeData(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),selectedTileColor:scheme.primaryContainer,contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:3)),
  );
 }
 @override Widget build(BuildContext context)=>ValueListenableBuilder<ThemeMode>(valueListenable:themeMode,builder:(_,mode,child)=>MaterialApp(title:'Telezeka',debugShowCheckedModeBanner:false,theme:design(Brightness.light),darkTheme:design(Brightness.dark),themeMode:mode,home:const Login()));
}
class TelezekaAvatar extends StatelessWidget{
 const TelezekaAvatar({super.key,required this.name,this.kind='direct',this.size=44});
 final String name,kind;final double size;
 @override Widget build(BuildContext context){
  const colors=[Color(0xff3e7993),Color(0xff607b78),Color(0xff776e9e),Color(0xff9b7359),Color(0xff597898)];
  final color=colors[name.codeUnits.fold(0,(a,b)=>a+b)%colors.length];
  final initials=name.trim().split(RegExp(r'\s+')).where((w)=>w.isNotEmpty).take(2).map((w)=>String.fromCharCode(w.runes.first).toUpperCase()).join();
  return Container(width:size,height:size,decoration:BoxDecoration(color:color,shape:BoxShape.circle),alignment:Alignment.center,child:kind=='group'?Icon(Icons.groups_outlined,color:Colors.white,size:size*.47):kind=='channel'?Icon(Icons.campaign_outlined,color:Colors.white,size:size*.47):Text(initials.isEmpty?'?':initials,style:TextStyle(color:Colors.white,fontSize:size*.34,fontWeight:FontWeight.w600)));
 }
}
class Login extends StatefulWidget {const Login({super.key});@override State<Login> createState()=>_Login();}
class _Login extends State<Login>{
 static const server=String.fromEnvironment('CHAT_URL',defaultValue:'https://telezeka-api-production.up.railway.app');
 final countryController=TextEditingController(text:'+7'),contact=TextEditingController(),pass=TextEditingController(),name=TextEditingController(),user=TextEditingController(),invite=TextEditingController(),code=TextEditingController(),second=TextEditingController(),secondCode=TextEditingController();
 bool reg=false,busy=false,phone=true,passwordMode=false,both=false;int step=0;String error='',country='+7';DateTime? resendAt,secondResendAt;Timer? clock;
 @override void initState(){super.initState();clock=Timer.periodic(const Duration(seconds:1),(_){if(mounted&&(resendAt!=null||secondResendAt!=null))setState((){});});}
 @override void dispose(){clock?.cancel();for(final c in [countryController,contact,pass,name,user,invite,code,second,secondCode]){c.dispose();}super.dispose();}
 int get remaining{final n=resendAt?.difference(DateTime.now()).inSeconds??0;return n>0?n:0;}
 int get secondRemaining{final n=secondResendAt?.difference(DateTime.now()).inSeconds??0;return n>0?n:0;}
 String get address{final raw=contact.text.trim();if(!phone||passwordMode)return raw;if(raw.startsWith('+'))return raw;final digits=raw.replaceAll(RegExp(r'[^0-9]'),'');if(country=='+7'&&digits.length==11&&(digits.startsWith('7')||digits.startsWith('8')))return '+7${digits.substring(1)}';return '$country$digits';}
 String message(Object e){if(e is SocketException||e is TimeoutException||e is HandshakeException||e is FormatException)return 'Сервер Telezeka временно недоступен. Попробуйте позже.';return e.toString().replaceFirst('Exception: ','');}
 Future<void> work(Future<void> Function() job)async{if(busy)return;setState((){busy=true;error='';});try{await job();}catch(e){if(mounted)setState(()=>error=message(e));}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> sendCode()async{if(remaining>0&&step==1)return;await work(()async{if(contact.text.trim().isEmpty)throw Exception('Введите номер телефона или почту');if(reg&&invite.text.trim().isEmpty)throw Exception('Введите код приглашения');final api=Api(server);try{await api.req(reg?'/auth/send-code':'/auth/login-code',{'contact':address,if(reg)'invite':invite.text.trim()});}finally{api.client.close();}if(mounted)setState((){step=1;resendAt=DateTime.now().add(const Duration(seconds:60));});});}
 Future<void> sendSecond()async{if(secondRemaining>0)return;await work(()async{if(second.text.trim().isEmpty)throw Exception('Введите второй контакт');final api=Api(server);try{await api.req('/auth/send-code',{'contact':second.text.trim(),'invite':invite.text.trim()});}finally{api.client.close();}if(mounted)setState(()=>secondResendAt=DateTime.now().add(const Duration(seconds:60)));});}
 Future<void> finish()async{await work(()async{if(reg&&both&&(second.text.trim().isEmpty||secondCode.text.trim().length!=6))throw Exception('Подтвердите второй контакт');final api=Api(server);try{final result=await api.req(passwordMode?'/login':reg?'/register':'/auth/verify-login',{'contact':address,if(passwordMode||reg)'password':pass.text,if(!passwordMode)'code':code.text.trim(),if(reg)...{'name':name.text.trim(),'username':user.text.trim(),'invite':invite.text.trim(),if(both)...{'second_contact':second.text.trim(),'second_code':secondCode.text.trim()}}});api.token=result['token'];if(mounted)Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>Home(api:api,me:Map<String,dynamic>.from(result['user']))));else api.client.close();}catch(e){api.client.close();rethrow;}});}
 void reset({bool? register,bool? password,bool? usePhone}){setState((){reg=register??reg;passwordMode=password??passwordMode;phone=usePhone??phone;step=0;code.clear();pass.clear();resendAt=null;secondResendAt=null;both=false;second.clear();secondCode.clear();error='';if(usePhone!=null)contact.clear();});}
 Widget field(TextEditingController c,String label,{bool secret=false,TextInputType? keyboard,String? hint,int? maxLength,ValueChanged<String>? onSubmitted})=>Padding(padding:const EdgeInsets.only(bottom:14),child:TextField(controller:c,enabled:!busy,obscureText:secret,keyboardType:keyboard,maxLength:maxLength,onSubmitted:onSubmitted,decoration:InputDecoration(labelText:label,hintText:hint,counterText:'',border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)))));
 @override Widget build(BuildContext context){
 final theme=Theme.of(context);final color=theme.colorScheme;
 final heading=passwordMode?'Вход по паролю':step==1?'Подтверждение':step==2?'Ваш профиль':reg?'Создать аккаунт':phone?'Ваш номер телефона':'Ваша электронная почта';
 final subtitle=passwordMode?'Для владельца и пользователей с паролем.':step==1?'Введите шестизначный код. Если аккаунт существует, код для входа отправлен на указанный контакт.':step==2?'Укажите имя, которое увидят ваши собеседники.':reg?'Подтвердите контакт и введите семейный код приглашения.':phone?'Выберите код страны и введите номер телефона.':'Введите подтверждённый email для получения кода.';
 return Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:28,vertical:32),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:380),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
 Center(child:Container(width:78,height:78,decoration:BoxDecoration(color:color.primary,borderRadius:BorderRadius.circular(24)),child:Icon(Icons.send_rounded,size:42,color:color.onPrimary))),
 const SizedBox(height:18),Text('Telezeka',textAlign:TextAlign.center,style:theme.textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w700,letterSpacing:-.5)),
 const SizedBox(height:34),Text(heading,textAlign:TextAlign.center,style:theme.textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w600)),const SizedBox(height:10),Text(subtitle,textAlign:TextAlign.center,style:theme.textTheme.bodyMedium?.copyWith(color:color.onSurfaceVariant)),const SizedBox(height:28),
 if(step==0)...[
 if(!passwordMode&&phone)Row(children:[SizedBox(width:98,child:TextField(controller:countryController,enabled:!busy,keyboardType:TextInputType.phone,onChanged:(v)=>country=v.trim(),decoration:InputDecoration(labelText:'Код страны',border:OutlineInputBorder(borderRadius:BorderRadius.circular(12))))),const SizedBox(width:10),Expanded(child:TextField(controller:contact,enabled:!busy,keyboardType:TextInputType.phone,decoration:InputDecoration(labelText:'Номер',hintText:'978 000 00 00',border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)))) )])else field(contact,passwordMode?'Email, телефон или @zakaria':'Email',keyboard:TextInputType.emailAddress,hint:'name@example.com'),
 if(!passwordMode&&phone)const SizedBox(height:14),
 if(reg)field(invite,'Код приглашения',secret:true),
 if(passwordMode)field(pass,'Пароль',secret:true,onSubmitted:(_)=>finish()),
 if(!passwordMode)TextButton(onPressed:busy?null:()=>reset(usePhone:!phone),child:Text(phone?'Использовать электронную почту':'Использовать номер телефона')),
 ]else if(step==1)...[
 Text(address,textAlign:TextAlign.center,style:theme.textTheme.titleMedium),TextButton(onPressed:busy?null:()=>reset(),child:const Text('Изменить контакт')),
 field(code,'Код подтверждения',keyboard:TextInputType.number,maxLength:6,onSubmitted:(_){if(reg){if(code.text.trim().length==6)setState(()=>step=2);}else{finish();}}),
 TextButton(onPressed:busy||remaining>0?null:sendCode,child:Text(remaining>0?'Отправить повторно через $remaining с':'Отправить код повторно')),
 ]else ...[field(name,'Имя'),field(user,'Username (необязательно)'),SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(phone?'Также подтвердить email':'Также подтвердить телефон'),value:both,onChanged:busy?null:(v)=>setState(()=>both=v)),if(both)...[field(second,phone?'Email':'Телефон в международном формате',keyboard:phone?TextInputType.emailAddress:TextInputType.phone,hint:phone?'name@example.com':'+7 (978) 000 00 00'),OutlinedButton(onPressed:busy||secondRemaining>0?null:sendSecond,child:Text(secondRemaining>0?'Повторить через $secondRemaining с':'Получить второй код')),field(secondCode,'Второй код',keyboard:TextInputType.number,maxLength:6)],field(pass,'Пароль для альтернативного входа (необязательно)',secret:true),TextButton(onPressed:busy?null:()=>setState(()=>step=1),child:const Text('Назад к коду'))],
 if(error.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:12),child:Text(error,textAlign:TextAlign.center,style:TextStyle(color:color.error))),
 SizedBox(height:50,child:FilledButton(onPressed:busy?null:passwordMode||step==2||(!reg&&step==1)?finish:step==1?(){if(code.text.trim().length!=6){setState(()=>error='Введите 6 цифр');return;}setState((){step=2;error='';});}:sendCode,child:busy?const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2)):Text(passwordMode?'Войти':step==2?'Создать аккаунт':'Далее'))),
 const SizedBox(height:10),if(step==0)...[TextButton(onPressed:busy?null:()=>reset(register:!reg,password:false),child:Text(reg?'Уже есть аккаунт? Войти':'Нет аккаунта? Зарегистрироваться')),TextButton(onPressed:busy?null:()=>reset(register:false,password:!passwordMode),child:Text(passwordMode?'Вход по коду':'Войти по паролю'))]else TextButton(onPressed:busy?null:()=>reset(),child:const Text('Начать заново')),
 ]))))));
 }
}
class Home extends StatefulWidget {const Home({super.key,required this.api,required this.me});final Api api;final Map<String,dynamic> me;@override State<Home> createState()=>_Home();}
class _Home extends State<Home>{
  Api get api=>widget.api; Map<String,dynamic> get me=>widget.me;List chats=[],messages=[];Map<String,dynamic>? selected; final text=TextEditingController(),search=TextEditingController(),rec=AudioRecorder();Timer? timer;bool loading=false,recording=false,calling=false;String error='';int lastIncoming=0;bool showArchived=false;String announcement='';Map<String,dynamic>? reply;
  @override void initState(){super.initState();refresh();timer=Timer.periodic(const Duration(seconds:3),(_){if(!loading&&WidgetsBinding.instance.lifecycleState==AppLifecycleState.resumed)refresh();});search.addListener(()=>setState((){}));}
  @override void dispose(){timer?.cancel();rec.dispose();text.dispose();search.dispose();super.dispose();}
  void notice(Object e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  DateTime lastAnnouncement=DateTime.fromMillisecondsSinceEpoch(0);
  final readThrough=<int,int>{};
  bool refreshPending=false;
  Future<void> refresh() async{
    if(!mounted)return;
    if(loading){refreshPending=true;return;}
    loading=true;
    try{
      final id=selected?['id'];
      final requests=<Future<dynamic>>[api.req('/chats'),if(id!=null)api.req('/chats/$id/messages?recent=1'),if(!calling)api.req('/incoming')];
      final getIncoming=!calling;
      final getAnnouncement=DateTime.now().difference(lastAnnouncement).inSeconds>=30;
      if(getAnnouncement)requests.add(api.req('/announcement'));
      final results=await Future.wait(requests);
      if(!mounted)return;
      int pos=0;
      final list=results[pos++] as List;
      list.sort((a,b)=>(b['favorite']??0).compareTo(a['favorite']??0));
      final more=id==null?null:results[pos++] as List;
      final inc=getIncoming?results[pos++] as List:null;
      final ann=getAnnouncement?results[pos++]:null;
      if(getAnnouncement)lastAnnouncement=DateTime.now();
      final sameRoom=id!=null&&selected?['id']==id;
      Map<String,dynamic>? room;
      if(sameRoom){for(final item in list){if(item['id']==id){room=Map<String,dynamic>.from(item);break;}}}
      final nextAnnouncement=ann==null?announcement:(ann['text']??'').toString();
      final changed=jsonEncode(chats)!=jsonEncode(list)||nextAnnouncement!=announcement||error.isNotEmpty||
        (sameRoom&&(jsonEncode(messages)!=jsonEncode(more)||jsonEncode(selected)!=jsonEncode(room)));
      if(changed)setState((){chats=list;announcement=nextAnnouncement;error='';if(sameRoom){selected=room;messages=room==null?[]:more!;}});
      if(sameRoom&&room!=null&&more!=null&&more.isNotEmpty&&id is int){
        final last=(more.last['id'] as num).toInt();
        if(last>(readThrough[id]??0)){await api.req('/chats/$id/read',{'id':last});readThrough[id]=last;}
      }
      if(inc!=null&&inc.isNotEmpty&&!calling&&mounted&&inc.first['id']!=lastIncoming){lastIncoming=inc.first['id'];incoming(inc.first);}
    }catch(e){if(mounted&&error!=e.toString())setState(()=>error=e.toString());}
    finally{loading=false;if(refreshPending&&mounted){refreshPending=false;Future<void>.microtask(refresh);}}
  }
  Future<void> choose(dynamic c) async{if(recording){notice('Сначала завершите запись');return;}setState((){final old=selected?['id'];if(old is int)drafts[old]=text.text;selected=Map<String,dynamic>.from(c);text.text=drafts[c['id']]??'';messages=[];reply=null;});await refresh();}
  Future<String?> ask(String title,String label,{String initial=''})async{final ctrl=TextEditingController(text:initial);final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),content:TextField(controller:ctrl,autofocus:true,decoration:InputDecoration(labelText:label)),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(ctx,ctrl.text.trim()),child:const Text('OK'))]));ctrl.dispose();return result;}
  Future<void> create(String kind)async{final direct=kind=='direct';final v=await ask(direct?'Новый чат':kind=='group'?'Новая группа':'Новый канал',direct?'@username':'Название');if(v==null||v.isEmpty)return;try{final r=await api.req('/chats',{'kind':kind,(direct?'username':'title'):v});await refresh();for(final c in chats){if(c['id']==r['id']){await choose(c);break;}}}catch(e){notice(e);}}
  Future<void> profile()async{final n=TextEditingController(text:me['name']),u=TextEditingController(text:me['username']??''),bio=TextEditingController(text:me['bio']??'');final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Мой профиль'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Имя')),TextField(controller:u,decoration:const InputDecoration(labelText:'Username',helperText:'Оставьте пустым, чтобы удалить')),TextField(controller:bio,maxLength:200,decoration:const InputDecoration(labelText:'О себе'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Сохранить'))]));if(ok==true){try{final r=await api.req('/me',{'name':n.text,'username':u.text,'bio':bio.text});setState(()=>me.addAll(Map<String,dynamic>.from(r)));}catch(e){notice(e);}}n.dispose();u.dispose();bio.dispose();}
  Future<void> admin()async{if(me['role']!='owner')return;await Navigator.push(context,MaterialPageRoute(builder:(_)=>AdminPage(api:api)));await refresh();}
  Future<void> saved()async{try{final rows=await api.req('/saved') as List;if(!mounted)return;await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Избранные сообщения'),content:SizedBox(width:420,child:ListView(shrinkWrap:true,children:[for(final m in rows)ListTile(title:Text(m['kind']=='text'?m['body']:m['filename']??'Вложение'),trailing:IconButton(icon:const Icon(Icons.bookmark_remove),onPressed:()async{await api.req('/messages/${m['id']}/save',{'saved':false});if(ctx.mounted)Navigator.pop(ctx);}))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Закрыть'))]));}catch(e){notice(e);}}
  Future<void> chatOption(String key)async{final c=selected;if(c==null)return;try{if(key=='block'){final other=(c['members'] as List).firstWhere((x)=>x['id']!=me['id']);await api.req('/blocks',{'uid':other['id'],'blocked':true});notice('Пользователь заблокирован');}else if(key=='leave'){await api.req('/chats/${c['id']}/leave',{});setState(()=>selected=null);}else if(key=='rename'){final n=await ask('Название группы или канала','Название',initial:c['title']);if(n!=null&&n.isNotEmpty)await api.req('/chats/${c['id']}/rename',{'title':n});}else{await api.req('/chats/${c['id']}/prefs',{key:(c[key]??0)==0});}await refresh();}catch(e){notice(e);}}
  Future<void> security()async{final old=TextEditingController(),next=TextEditingController();final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Смена пароля'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:old,obscureText:true,decoration:const InputDecoration(labelText:'Старый пароль')),TextField(controller:next,obscureText:true,decoration:const InputDecoration(labelText:'Новый пароль (12+ символов)'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Сменить'))]));if(yes==true){try{await api.req('/me/password',{'old':old.text,'new':next.text});notice('Пароль изменён, другие сеансы завершены');}catch(e){notice(e);}}old.dispose();next.dispose();}
  Future<void> blockedUsers()async{try{final rows=await api.req('/blocks') as List;if(!mounted)return;await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Заблокированные пользователи'),content:SizedBox(width:360,child:ListView(shrinkWrap:true,children:[for(final u in rows)ListTile(title:Text(u['name']),trailing:TextButton(onPressed:()async{await api.req('/blocks',{'uid':u['id'],'blocked':false});if(ctx.mounted)Navigator.pop(ctx);},child:const Text('Разблокировать')))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Закрыть'))]));}catch(e){notice(e);}}
  Future<void> addMember()async{final id=selected?['id'];final u=await ask('Добавить участника','@username');if(u!=null&&u.isNotEmpty){try{await api.req('/chats/$id/invite',{'username':u});await refresh();notice('Участник добавлен');}catch(e){notice(e);}}}
  Future<void> send(String kind,String body,{int? chat})async{final id=chat??selected?['id'];if(id==null||body.isEmpty)return;await api.req('/chats/$id/messages',{'kind':kind,'body':body,if(reply!=null&&id==selected?['id'])'reply_to':reply!['id']});if(mounted)setState(()=>reply=null);await refresh();}
  Future<void> sendText()async{final s=text.text.trim();if(s.isEmpty)return;try{await send('text',s);if(text.text.trim()==s)text.clear();}catch(e){notice(e);}}
  Future<void> sendFile(String kind,String path,{int? chat})async{final f=File(path);if(await f.length()>16*1024*1024)throw Exception('Файл больше 16 МБ');await send(kind,base64Encode(await f.readAsBytes()),chat:chat);}
  Future<void> voice()async{final id=selected?['id'] as int?;try{if(recording){final p=await rec.stop();setState(()=>recording=false);if(p!=null){try{await sendFile('voice',p,chat:id);}finally{await File(p).delete();}}}else{if(!await rec.hasPermission())throw Exception('Разрешите доступ к микрофону');final p='${Directory.systemTemp.path}/circle_voice_${DateTime.now().millisecondsSinceEpoch}.wav';await rec.start(const RecordConfig(encoder:AudioEncoder.wav,sampleRate:16000,numChannels:1),path:p);setState(()=>recording=true);}}catch(e){notice(e);}}
  Future<void> circle()async{final id=selected?['id'] as int?;try{String? p;if(Platform.isAndroid||Platform.isIOS){final choice=await showModalBottomSheet<String>(context:context,builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[ListTile(leading:const Icon(Icons.videocam),title:const Text('Снять видео'),onTap:()=>Navigator.pop(ctx,'camera')),ListTile(leading:const Icon(Icons.video_library),title:const Text('Выбрать видео'),onTap:()=>Navigator.pop(ctx,'gallery'))])));if(choice==null)return;p=(await ImagePicker().pickVideo(source:choice=='camera'?ImageSource.camera:ImageSource.gallery,maxDuration:const Duration(seconds:30)))?.path;}else{p=(await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['mp4']))?.files.single.path;}if(p!=null)await sendFile('circle',p,chat:id);}catch(e){notice(e);}}
  Future<void> startCall(bool video)async{if(calling)return;setState(()=>calling=true);try{final r=await api.req('/chats/${selected!['id']}/call',{'video':video});if(mounted)await Navigator.push(context,MaterialPageRoute(builder:(_)=>CallPage(api:api,id:r['id'],video:video,outgoing:true,title:selected!['title'])));}catch(e){notice(e);}finally{if(mounted)setState(()=>calling=false);}}
  Future<void> incoming(dynamic r)async{if(calling)return;setState(()=>calling=true);try{final accept=await showDialog<bool>(context:context,barrierDismissible:false,builder:(ctx)=>AlertDialog(title:Text(r['video']==1?'Видеозвонок':'Входящий звонок'),content:Text(r['name']),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Отклонить')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Принять'))]));await api.req('/calls/${r['id']}/status',{'status':accept==true?'active':'ended'});if(accept==true&&mounted)await Navigator.push(context,MaterialPageRoute(builder:(_)=>CallPage(api:api,id:r['id'],video:r['video']==1,outgoing:false,title:r['name'])));}catch(e){notice(e);}finally{if(mounted)setState(()=>calling=false);}}
  Future<void> messageAction(dynamic m, String action)async{try{final id=m['id'];final ch=selected!['id'];if(action=='forward'){await forwardMessage(m);return;}if(action=='save'){await api.req('/messages/$id/save',{'saved':true});notice('Сообщение сохранено');return;}if(action=='report'){final why=await ask('Жалоба','Причина');if(why!=null&&why.isNotEmpty){await api.req('/messages/$id/report',{'reason':why});notice('Жалоба отправлена');}return;}if(action=='reply'){setState(()=>reply=Map<String,dynamic>.from(m));return;}if(action=='edit'){final v=await ask('Редактировать','Сообщение',initial:m['body']);if(v==null||v.isEmpty)return;await api.req('/messages/$id/edit',{'body':v});}else if(action=='delete'){final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Удалить сообщение для всех?'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Удалить'))]));if(ok!=true)return;await api.req('/messages/$id/delete',{});}else if(action=='pin'){await api.req('/chats/$ch/pin',{'id':id});}else{await api.req('/messages/$id/react',{'emoji':action});}await refresh();}catch(e){notice(e);}}
  Future<void> messageMenu(dynamic m)async{if(m['deleted']==1)return;final c=selected!;final own=m['sender']==me['id'];final owner=c['owner']==me['id'];final action=await showModalBottomSheet<String>(context:context,builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[Wrap(children:[for(final e in ['👍','❤️','😂','😮','😢','🔥'])TextButton(onPressed:()=>Navigator.pop(ctx,e),child:Text(e,style:const TextStyle(fontSize:24)))]),ListTile(leading:const Icon(Icons.forward_outlined),title:const Text('Переслать'),onTap:()=>Navigator.pop(ctx,'forward')),ListTile(leading:const Icon(Icons.bookmark_add),title:const Text('В избранное'),onTap:()=>Navigator.pop(ctx,'save')),if(!own)ListTile(leading:const Icon(Icons.flag_outlined),title:const Text('Пожаловаться'),onTap:()=>Navigator.pop(ctx,'report')),if(c['kind']!='channel'||owner)ListTile(leading:const Icon(Icons.reply),title:const Text('Ответить'),onTap:()=>Navigator.pop(ctx,'reply')),if(own&&m['kind']=='text')ListTile(leading:const Icon(Icons.edit),title:const Text('Редактировать'),onTap:()=>Navigator.pop(ctx,'edit')),if(owner||c['kind']=='direct')ListTile(leading:const Icon(Icons.push_pin),title:const Text('Закрепить'),onTap:()=>Navigator.pop(ctx,'pin')),if(own||(owner&&c['kind']!='direct'))ListTile(leading:const Icon(Icons.delete_outline),title:const Text('Удалить'),onTap:()=>Navigator.pop(ctx,'delete'))])));if(action!=null&&mounted)await messageAction(m,action);}
  Future<void> forwardMessage(dynamic m)async{
    final destinations=chats.where((x)=>x['kind']!='channel'||x['owner']==me['id']).toList();
    final id=await showDialog<int>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Переслать сообщение'),content:SizedBox(width:380,child:destinations.isEmpty?const Text('Нет доступных чатов'):ListView(shrinkWrap:true,children:[for(final x in destinations)ListTile(leading:TelezekaAvatar(name:x['title'].toString(),kind:x['kind'].toString()),title:Text(x['title'].toString()),onTap:()=>Navigator.pop(ctx,x['id'] as int))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Отмена'))]));
    if(id==null||!mounted)return;try{await api.req('/messages/${m['id']}/forward',{'chat':id});notice('Сообщение переслано');await refresh();}catch(e){notice(e);}
  }
  Future<void> chatInfo()async{
    final room=selected;if(room==null)return;final owner=room['owner']==me['id']&&room['kind']!='direct';
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:Text(room['title'].toString()),content:SizedBox(width:400,child:ListView(shrinkWrap:true,children:[
      Center(child:TelezekaAvatar(name:room['title'].toString(),kind:room['kind'].toString(),size:68)),const SizedBox(height:14),
      Text('Участники: ${room['members'].length}',style:Theme.of(ctx).textTheme.titleMedium),
      for(final p in room['members'])ListTile(leading:TelezekaAvatar(name:p['name'].toString(),size:36),title:Text(p['name'].toString()),subtitle:Text(p['username']==null?'':'@${p['username']}'),trailing:owner&&p['id']!=me['id']?IconButton(icon:const Icon(Icons.person_remove_outlined),tooltip:'Удалить участника',onPressed:()async{
        final yes=await showDialog<bool>(context:ctx,builder:(cc)=>AlertDialog(title:const Text('Удалить участника?'),actions:[TextButton(onPressed:()=>Navigator.pop(cc,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(cc,true),child:const Text('Удалить'))]));
        if(yes==true){try{await api.req('/chats/${room['id']}/remove_member',{'uid':p['id']});if(ctx.mounted)Navigator.pop(ctx);await refresh();}catch(e){notice(e);}}
      }):null),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Закрыть'))]));
  }
  Future<void> sharedFiles()async{
    final room=selected;if(room==null)return;try{
      final rows=await api.req('/chats/${room['id']}/files') as List;if(!mounted)return;
      await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Медиа и файлы'),content:SizedBox(width:420,child:rows.isEmpty?const Text('В этом чате пока нет вложений.'):ListView(shrinkWrap:true,children:[for(final m in rows)ListTile(leading:Icon(m['kind']=='circle'?Icons.play_circle_outline:m['kind']=='voice'?Icons.mic_none:Icons.description_outlined),title:Text((m['filename']??(m['kind']=='circle'?'Видеокружок':m['kind']=='voice'?'Голосовое сообщение':'Файл')).toString()),onTap:(){if(m['kind']=='circle'||m['kind']=='voice'){showDialog(context:ctx,builder:(_)=>MediaDialog(api:api,id:m['id'],circle:m['kind']=='circle'));}else{downloadFile(m);}})])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Закрыть'))]));
    }catch(e){notice(e);}
  }
  Future<void> findMessages()async{final id=selected?['id'];final q=await ask('Поиск по переписке','Текст');if(q==null||q.isEmpty||!mounted)return;try{final rows=await api.req('/chats/$id/search?q=${Uri.encodeQueryComponent(q)}') as List;if(!mounted)return;await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Результаты поиска'),content:SizedBox(width:400,child:rows.isEmpty?const Text('Ничего не найдено'):ListView(shrinkWrap:true,children:[for(final m in rows)ListTile(title:Text(m['body']),subtitle:Text(m['name']))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Закрыть'))]));}catch(e){notice(e);}}
  Future<void> attach()async{final id=selected?['id'];if(id==null)return;try{final pick=await FilePicker.platform.pickFiles();final f=pick?.files.single;if(f==null||f.path==null)return;if(f.size>16*1024*1024)throw Exception('Файл больше 16 МБ');await api.req('/chats/$id/messages',{'kind':'file','filename':f.name,'body':base64Encode(await File(f.path!).readAsBytes())});await refresh();}catch(e){notice(e);}}
  Future<void> downloadFile(dynamic m)async{try{final r=await api.req('/media/${m['id']}');final bytes=base64Decode(r['body']);final path=await FilePicker.platform.saveFile(fileName:r['filename']??'attachment',bytes:bytes);if(path!=null){if(Platform.isWindows)await File(path).writeAsBytes(bytes);notice('Файл сохранён');}}catch(e){notice(e);}}
  final drafts=<int,String>{};
  int chatFilter=0;
  bool mobileSettings=false;
  Future<void> menuAction(String v)async{
    if(v=='logout'){
      try{await api.req('/logout',{});}catch(_){}
      if(mounted)Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const Login()));
    }else if(v=='admin'){await admin();}
    else if(v=='saved'){await saved();}
    else if(v=='security'){await security();}
    else if(v=='blocks'){await blockedUsers();}
    else if(v=='sessions'){try{await api.req('/me/sessions',{});notice('Другие сеансы завершены');}catch(e){notice(e);}}
    else{await create(v);}
  }
  void changeFilter(int value){setState((){chatFilter=value;showArchived=value==4;mobileSettings=false;});}
  Future<void> newChat()async{
    final chosen=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(12,0,12,16),child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:const Icon(Icons.chat_bubble_outline),title:const Text('Новый чат'),subtitle:const Text('Начать переписку по username'),onTap:()=>Navigator.pop(ctx,'direct')),
      ListTile(leading:const Icon(Icons.group_add_outlined),title:const Text('Создать группу'),subtitle:const Text('Общайтесь вместе'),onTap:()=>Navigator.pop(ctx,'group')),
      ListTile(leading:const Icon(Icons.campaign_outlined),title:const Text('Создать канал'),subtitle:const Text('Публикуйте объявления'),onTap:()=>Navigator.pop(ctx,'channel')),
    ]))));
    if(chosen!=null&&mounted)await create(chosen);
  }
  Widget sectionTitle(String title)=>Padding(padding:const EdgeInsets.fromLTRB(20,18,20,8),child:Text(title,style:Theme.of(context).textTheme.labelLarge?.copyWith(color:Theme.of(context).colorScheme.onSurfaceVariant,fontWeight:FontWeight.w600)));
  Widget settings(){
    final c=Theme.of(context).colorScheme;
    return ListView(padding:const EdgeInsets.fromLTRB(8,12,8,24),children:[
      Padding(padding:const EdgeInsets.all(14),child:Column(children:[TelezekaAvatar(name:me['name'].toString(),size:76),const SizedBox(height:12),Text(me['name'].toString(),style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w600)),Text(me['username']==null?'Username не указан':'@${me['username']}',style:TextStyle(color:c.onSurfaceVariant)),const SizedBox(height:12),OutlinedButton.icon(onPressed:profile,icon:const Icon(Icons.edit_outlined,size:18),label:const Text('Редактировать профиль'))])),
      sectionTitle('АККАУНТ'),ListTile(leading:const Icon(Icons.bookmark_border),title:const Text('Избранные сообщения'),onTap:saved),ListTile(leading:const Icon(Icons.lock_outline),title:const Text('Пароль'),onTap:security),ListTile(leading:const Icon(Icons.devices_outlined),title:const Text('Завершить другие сеансы'),onTap:()=>menuAction('sessions')),ListTile(leading:const Icon(Icons.block_outlined),title:const Text('Заблокированные'),onTap:blockedUsers),
      sectionTitle('ОФОРМЛЕНИЕ'),Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:ValueListenableBuilder<ThemeMode>(valueListenable:themeMode,builder:(_,mode,child)=>SegmentedButton<ThemeMode>(segments:const [ButtonSegment(value:ThemeMode.system,icon:Icon(Icons.settings_brightness),label:Text('Авто')),ButtonSegment(value:ThemeMode.light,icon:Icon(Icons.light_mode_outlined),label:Text('Свет')),ButtonSegment(value:ThemeMode.dark,icon:Icon(Icons.dark_mode_outlined),label:Text('Тьма'))],selected:{mode},onSelectionChanged:(m)=>themeMode.value=m.first))),
      if(me['role']=='owner')...[sectionTitle('УПРАВЛЕНИЕ'),ListTile(leading:const Icon(Icons.admin_panel_settings_outlined),title:const Text('Панель владельца'),onTap:admin)],
      sectionTitle('TELEZEKA'),ListTile(leading:const Icon(Icons.info_outline),title:const Text('Версия ${const String.fromEnvironment("TELEZEKA_VERSION",defaultValue:"0.4.1")} · Studio'),subtitle:const Text('Предварительная сборка')),ListTile(leading:Icon(Icons.logout,color:c.error),title:Text('Выйти',style:TextStyle(color:c.error)),onTap:()=>menuAction('logout')),
    ]);
  }
  Widget sidebar(){
    final t=Theme.of(context),c=t.colorScheme;
    final filtered=chats.where((x){
      if(((x['archived']??0)==1)!=showArchived)return false;
      if(chatFilter==1&&(x['unread']??0)==0)return false;
      if(chatFilter==2&&x['kind']!='group')return false;
      if(chatFilter==3&&x['kind']!='channel')return false;
      return x['title'].toString().toLowerCase().contains(search.text.toLowerCase());
    }).toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(18,14,10,8),child:Row(children:[
        Text(mobileSettings?'Настройки':'Telezeka.',style:t.textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w700,letterSpacing:-.6)),
        const Spacer(),if(!mobileSettings)IconButton(onPressed:newChat,icon:const Icon(Icons.edit_square),tooltip:'Новый чат'),
        InkWell(borderRadius:BorderRadius.circular(28),onTap:()=>setState(()=>mobileSettings=!mobileSettings),child:TelezekaAvatar(name:me['name'].toString(),size:36)),
      ])),
      if(mobileSettings)Expanded(child:settings())else ...[
        Padding(padding:const EdgeInsets.fromLTRB(14,6,14,10),child:TextField(controller:search,decoration:InputDecoration(prefixIcon:const Icon(Icons.search,size:20),hintText:'Поиск',suffixIcon:search.text.isEmpty?null:IconButton(onPressed:search.clear,icon:const Icon(Icons.close,size:18))))),
        SizedBox(height:40,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),children:[
          for(final item in const [(0,'Все'),(1,'Новые'),(2,'Группы'),(3,'Каналы'),(4,'Архив')])Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(item.$2),selected:chatFilter==item.$1,onSelected:(_)=>changeFilter(item.$1),showCheckmark:false,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(9)),side:BorderSide.none,backgroundColor:c.surface,selectedColor:c.primaryContainer,labelStyle:TextStyle(fontSize:12,fontWeight:chatFilter==item.$1?FontWeight.w600:FontWeight.w400))),
        ])),
        if(announcement.isNotEmpty)Padding(padding:const EdgeInsets.fromLTRB(14,8,14,4),child:Container(decoration:BoxDecoration(color:c.primaryContainer,borderRadius:BorderRadius.circular(10)),padding:const EdgeInsets.all(12),child:Row(children:[Icon(Icons.campaign_outlined,size:20,color:c.primary),const SizedBox(width:10),Expanded(child:Text(announcement,maxLines:3,overflow:TextOverflow.ellipsis))]))),
        if(error.isNotEmpty)Padding(padding:const EdgeInsets.all(12),child:Text(error,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(color:c.error,fontSize:12))),
        Expanded(child:filtered.isEmpty?Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.forum_outlined,size:42,color:c.onSurfaceVariant),const SizedBox(height:12),Text('Нет чатов',style:t.textTheme.titleMedium),const SizedBox(height:6),Text('Начните новую переписку или измените фильтр.',textAlign:TextAlign.center,style:t.textTheme.bodySmall?.copyWith(color:c.onSurfaceVariant)),const SizedBox(height:14),TextButton(onPressed:newChat,child:const Text('Новый чат'))]))):ListView.builder(padding:const EdgeInsets.fromLTRB(8,6,8,12),itemCount:filtered.length,itemBuilder:(ctx,i){
          final x=filtered[i],unread=x['unread']??0,chosen=selected?['id']==x['id'];
          return Padding(padding:const EdgeInsets.only(bottom:3),child:ListTile(selected:chosen,onTap:()=>choose(x),leading:TelezekaAvatar(name:x['title'].toString(),kind:x['kind'].toString(),size:46),title:Text(x['title'].toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600,fontSize:15)),subtitle:Text(x['kind']=='group'?'Группа · ${x['members'].length} участников':x['kind']=='channel'?'Канал':'Личная переписка',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:c.onSurfaceVariant,fontSize:12)),trailing:Row(mainAxisSize:MainAxisSize.min,children:[if((x['muted']??0)==1)Icon(Icons.notifications_off_outlined,size:16,color:c.onSurfaceVariant),if((x['favorite']??0)==1)Icon(Icons.star_rounded,size:17,color:c.primary),if(unread>0)Container(margin:const EdgeInsets.only(left:4),padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),decoration:BoxDecoration(color:c.primary,borderRadius:BorderRadius.circular(12)),child:Text(unread>99?'99+':'$unread',style:TextStyle(color:c.onPrimary,fontSize:11,fontWeight:FontWeight.w600)))])));
        })),
      ],
      const Divider(),NavigationBar(selectedIndex:mobileSettings?2:0,onDestinationSelected:(v){if(v==1){saved();return;}setState(()=>mobileSettings=v==2);},destinations:const [NavigationDestination(icon:Icon(Icons.chat_bubble_outline),selectedIcon:Icon(Icons.chat_bubble),label:'Чаты'),NavigationDestination(icon:Icon(Icons.bookmark_border),label:'Избранное'),NavigationDestination(icon:Icon(Icons.settings_outlined),selectedIcon:Icon(Icons.settings),label:'Настройки')]),
    ]);
  }
  Widget chat(bool wide){
    final room=selected,t=Theme.of(context),c=t.colorScheme;
    if(room==null)return Container(color:c.surfaceContainerLowest,child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Container(width:84,height:84,decoration:BoxDecoration(color:c.primaryContainer,borderRadius:BorderRadius.circular(24)),child:Icon(Icons.send_rounded,size:40,color:c.primary)),const SizedBox(height:20),Text('Ваши разговоры',style:t.textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w600)),const SizedBox(height:8),Text('Выберите чат, чтобы начать общение.',style:TextStyle(color:c.onSurfaceVariant)),const SizedBox(height:20),FilledButton.icon(onPressed:newChat,icon:const Icon(Icons.edit_outlined),label:const Text('Новый чат'))])));
    final canWrite=room['kind']!='channel'||room['owner']==me['id'];
    return Column(children:[
      Container(color:c.surface,padding:const EdgeInsets.symmetric(horizontal:8,vertical:8),child:Row(children:[
        if(!wide)IconButton(onPressed:recording?null:()=>setState((){final id=selected?['id'];if(id is int)drafts[id]=text.text;selected=null;text.clear();}),icon:const Icon(Icons.arrow_back),tooltip:'Назад'),
        if(wide)const SizedBox(width:6),
        TelezekaAvatar(name:room['title'].toString(),kind:room['kind'].toString(),size:40),const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(room['title'].toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w600)),Text(room['kind']=='direct'?'Личная переписка':'${room['members'].length} участников',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:c.onSurfaceVariant,fontSize:12))])),
        if(room['kind']=='direct')...[IconButton(onPressed:()=>startCall(false),icon:const Icon(Icons.call_outlined),tooltip:'Аудиозвонок'),if(wide)IconButton(onPressed:()=>startCall(true),icon:const Icon(Icons.videocam_outlined),tooltip:'Видеозвонок')],
        if(wide)IconButton(onPressed:findMessages,icon:const Icon(Icons.search),tooltip:'Поиск сообщений'),
        PopupMenuButton<String>(onSelected:(v){if(v=='info'){chatInfo();}else if(v=='files'){sharedFiles();}else if(v=='search'){findMessages();}else if(v=='video'){startCall(true);}else if(v=='invite'){addMember();}else{chatOption(v);}},itemBuilder:(_)=>[
          const PopupMenuItem(value:'info',child:Text('Информация о чате')),const PopupMenuItem(value:'files',child:Text('Медиа и файлы')),const PopupMenuItem(value:'search',child:Text('Поиск сообщений')),
          if(room['kind']=='direct')const PopupMenuItem(value:'video',child:Text('Видеозвонок')),
          if(room['kind']!='direct'&&room['owner']==me['id'])const PopupMenuItem(value:'invite',child:Text('Добавить участника')),
          PopupMenuItem(value:'favorite',child:Text((room['favorite']??0)==1?'Убрать из избранного':'В избранное')),
          PopupMenuItem(value:'archived',child:Text((room['archived']??0)==1?'Разархивировать':'Архивировать')),
          PopupMenuItem(value:'muted',child:Text((room['muted']??0)==1?'Включить уведомления':'Без уведомлений')),
          if(room['kind']=='direct')const PopupMenuItem(value:'block',child:Text('Заблокировать')),
          if(room['kind']!='direct'&&room['owner']==me['id'])const PopupMenuItem(value:'rename',child:Text('Переименовать')),
          if(room['kind']!='direct'&&room['owner']!=me['id'])const PopupMenuItem(value:'leave',child:Text('Покинуть')),
        ]),
      ])),const Divider(),
      if(room['pin']!=null)Container(color:c.surfaceContainerHigh,child:ListTile(dense:true,leading:Icon(Icons.push_pin_outlined,color:c.primary),title:Text(room['pin']['preview'].toString(),maxLines:1,overflow:TextOverflow.ellipsis),subtitle:const Text('Закреплено'),trailing:room['kind']=='direct'||room['owner']==me['id']?IconButton(icon:const Icon(Icons.close),onPressed:()async{try{await api.req('/chats/${room['id']}/pin',{'id':null});await refresh();}catch(e){notice(e);}}):null)),
      Expanded(child:Container(color:c.surfaceContainerLowest,child:messages.isEmpty?Center(child:Text('Напишите первое сообщение',style:TextStyle(color:c.onSurfaceVariant))):LayoutBuilder(builder:(ctx,limits)=>ListView.builder(reverse:true,padding:EdgeInsets.symmetric(horizontal:wide?24:10,vertical:16),itemCount:messages.length,itemBuilder:(_,i){
        final index=messages.length-1-i,m=messages[index],own=m['sender']==me['id'];
        final date=DateTime.fromMillisecondsSinceEpoch((m['created'] as num).toInt()*1000);
        final older=index>0?DateTime.fromMillisecondsSinceEpoch((messages[index-1]['created'] as num).toInt()*1000):null;
        final newDay=older==null||date.year!=older.year||date.month!=older.month||date.day!=older.day;
        return Column(children:[
          if(newDay)Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:5),decoration:BoxDecoration(color:c.surfaceContainerHigh,borderRadius:BorderRadius.circular(12)),child:Text('${date.day.toString().padLeft(2,'0')}.${date.month.toString().padLeft(2,'0')}.${date.year}',style:TextStyle(fontSize:11,color:c.onSurfaceVariant)))),
          Align(alignment:own?Alignment.centerRight:Alignment.centerLeft,child:GestureDetector(onLongPress:()=>messageMenu(m),onSecondaryTap:()=>messageMenu(m),child:Container(constraints:BoxConstraints(maxWidth:(limits.maxWidth*(wide ? 0.68 : 0.83)).clamp(160,540).toDouble()),margin:const EdgeInsets.symmetric(vertical:3),padding:const EdgeInsets.fromLTRB(12,9,12,7),decoration:BoxDecoration(color:own?c.primaryContainer:c.surface,border:own?null:Border.all(color:c.outlineVariant.withValues(alpha:.55)),borderRadius:BorderRadius.only(topLeft:const Radius.circular(15),topRight:const Radius.circular(15),bottomLeft:Radius.circular(own?15:4),bottomRight:Radius.circular(own?4:15))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
            if(!own&&room['kind']!='direct')Padding(padding:const EdgeInsets.only(bottom:4),child:Text(m['name'].toString(),style:TextStyle(fontWeight:FontWeight.w600,color:c.primary,fontSize:12))),
            if(m['reply_preview']!=null)Container(margin:const EdgeInsets.only(bottom:6),padding:const EdgeInsets.fromLTRB(8,5,8,5),decoration:BoxDecoration(border:Border(left:BorderSide(color:c.primary,width:3)),color:c.surface.withValues(alpha:.35)),child:Text(m['reply_preview'].toString(),maxLines:2,overflow:TextOverflow.ellipsis,style:t.textTheme.labelMedium)),
            if(m['deleted']==1)Text('Сообщение удалено',style:TextStyle(fontStyle:FontStyle.italic,color:c.onSurfaceVariant))else if(m['kind']=='text')Text(m['body'].toString(),style:TextStyle(fontSize:15,height:1.35,color:own?c.onPrimaryContainer:c.onSurface))else if(m['kind']=='file'||m['kind']=='photo')TextButton.icon(onPressed:()=>downloadFile(m),icon:const Icon(Icons.file_download_outlined),label:Text((m['filename']??'Файл').toString(),overflow:TextOverflow.ellipsis))else TextButton.icon(onPressed:()=>showDialog(context:context,builder:(_)=>MediaDialog(api:api,id:m['id'],circle:m['kind']=='circle')),icon:Icon(m['kind']=='circle'?Icons.play_circle:Icons.play_arrow),label:Text(m['kind']=='circle'?'Видеокружок':'Голосовое')),
            if((m['reactions'] as List? ?? []).isNotEmpty)Wrap(spacing:4,children:[for(final r in m['reactions'])ActionChip(visualDensity:VisualDensity.compact,onPressed:()=>messageAction(m,r['emoji']),label:Text('${r['emoji']} ${r['count']}'))]),
            const SizedBox(height:4),Row(mainAxisSize:MainAxisSize.min,children:[if(m['edited']!=null)Text('изменено · ',style:TextStyle(fontSize:10,color:c.onSurfaceVariant)),Text(TimeOfDay.fromDateTime(date).format(context),style:TextStyle(fontSize:10,color:c.onSurfaceVariant)),if(own)...[const SizedBox(width:4),Icon(Icons.check,size:13,color:c.primary)]])
          ])))),
        ]);
      })))),
      if(canWrite&&reply!=null)Container(color:c.surface,child:ListTile(dense:true,leading:Icon(Icons.reply,color:c.primary),title:Text(reply!['kind']=='text'?reply!['body']:'Вложение',maxLines:1),subtitle:const Text('Ответ на сообщение'),trailing:IconButton(onPressed:()=>setState(()=>reply=null),icon:const Icon(Icons.close)))),
      if(canWrite)Container(color:c.surface,padding:const EdgeInsets.fromLTRB(6,8,8,10),child:SafeArea(top:false,child:Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
        IconButton(onPressed:attach,icon:const Icon(Icons.attach_file),tooltip:'Файл'),if(wide)IconButton(onPressed:circle,icon:const Icon(Icons.video_camera_back_outlined),tooltip:'Видеокружок'),
        Expanded(child:TextField(controller:text,onSubmitted:(_)=>sendText(),decoration:InputDecoration(hintText:recording?'Запись…':'Написать сообщение',prefixIcon:null))),
        if(!wide)IconButton(onPressed:circle,icon:const Icon(Icons.video_camera_back_outlined),tooltip:'Видеокружок'),
        IconButton(onPressed:voice,icon:Icon(recording?Icons.stop_circle:Icons.mic_none_rounded,color:recording?c.error:null),tooltip:recording?'Остановить и отправить':'Голосовое сообщение'),
        IconButton.filled(onPressed:sendText,icon:const Icon(Icons.send_rounded,size:20),tooltip:'Отправить'),
      ])))else Padding(padding:const EdgeInsets.all(16),child:Text('Публикации доступны владельцу канала',style:TextStyle(color:c.onSurfaceVariant))),
    ]);
  }
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:LayoutBuilder(builder:(ctx,b){
    final wide=b.maxWidth>=780;return wide?Row(children:[Container(width:76,color:Theme.of(context).colorScheme.surfaceContainerLowest,child:Column(children:[const SizedBox(height:18),Icon(Icons.send_rounded,size:32,color:Theme.of(context).colorScheme.primary),const SizedBox(height:26),IconButton.filledTonal(onPressed:()=>setState(()=>mobileSettings=false),icon:const Icon(Icons.chat_bubble_outline),tooltip:'Чаты'),const SizedBox(height:12),IconButton(onPressed:saved,icon:const Icon(Icons.bookmark_border),tooltip:'Избранное'),const SizedBox(height:12),IconButton(onPressed:()=>changeFilter(4),icon:const Icon(Icons.archive_outlined),tooltip:'Архив'),const Spacer(),IconButton(onPressed:()=>setState(()=>mobileSettings=true),icon:const Icon(Icons.settings_outlined),tooltip:'Настройки'),const SizedBox(height:18)])),const VerticalDivider(width:1),SizedBox(width:b.maxWidth>1150?390:340,child:sidebar()),const VerticalDivider(width:1),Expanded(child:chat(true))]):selected==null||mobileSettings?sidebar():chat(false);
  })));
}
class MediaDialog extends StatefulWidget{const MediaDialog({super.key,required this.api,required this.id,required this.circle});final Api api;final int id;final bool circle;@override State<MediaDialog> createState()=>_MediaDialog();}
class _MediaDialog extends State<MediaDialog>{final player=Player();late final vc=VideoController(player);String status='Загрузка…';File? file;bool ready=false;@override void initState(){super.initState();load();}Future<void> load()async{try{final r=await widget.api.req('/media/${widget.id}');if(!mounted)return;file=File('${Directory.systemTemp.path}/circle_play_${DateTime.now().microsecondsSinceEpoch}.${widget.circle?'mp4':'wav'}');await file!.writeAsBytes(base64Decode(r['body']));if(!mounted){await file!.delete();return;}await player.open(Media(file!.path),play:true);if(mounted)setState(()=>ready=true);}catch(e){if(mounted)setState(()=>status='$e');}}@override void dispose(){final f=file;player.dispose().then((_)async{if(f!=null&&await f.exists())await f.delete();});super.dispose();}@override Widget build(BuildContext context)=>AlertDialog(title:Text(widget.circle?'Видеокружок':'Голосовое'),content:ready?(widget.circle?SizedBox(width:260,height:260,child:ClipOval(child:Video(controller:vc,fit:BoxFit.cover))):const Text('Воспроизведение голосового')):Text(status),actions:[if(ready)IconButton(onPressed:()=>player.playOrPause(),icon:const Icon(Icons.play_arrow)),TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Закрыть'))]);}
class CallPage extends StatefulWidget{const CallPage({super.key,required this.api,required this.id,required this.video,required this.outgoing,required this.title});final Api api;final int id;final bool video,outgoing;final String title;@override State<CallPage> createState()=>_CallPage();}
class _CallPage extends State<CallPage>{
  final local=RTCVideoRenderer(),remote=RTCVideoRenderer();RTCPeerConnection? pc;MediaStream? stream;Timer? timer;bool busy=false,closed=false,muted=false,hasRemote=false,remoteDescription=false;int after=0;String status='Подключение…';final pending=<RTCIceCandidate>[];
  String get root=>'/calls/${widget.id}';
  Future<void> signal(Map<String,dynamic> data)async{if(!closed)await widget.api.req('$root/signals',data);}
  @override void initState(){super.initState();init();}
  Future<void> init()async{try{await local.initialize();await remote.initialize();if(closed)return;final servers=<Map<String,dynamic>>[{'urls':'stun:stun.l.google.com:19302'}];const turn=String.fromEnvironment('TURN_URL');if(turn.isNotEmpty)servers.add({'urls':turn,'username':const String.fromEnvironment('TURN_USER'),'credential':const String.fromEnvironment('TURN_PASS')});pc=await createPeerConnection({'iceServers':servers,'sdpSemantics':'unified-plan'});if(closed){await pc?.close();return;}pc!.onIceCandidate=(candidate){if(candidate.candidate!=null)signal({'type':'ice','candidate':candidate.candidate,'sdpMid':candidate.sdpMid,'sdpMLineIndex':candidate.sdpMLineIndex}).catchError((Object _){});};pc!.onTrack=(event){if(event.streams.isNotEmpty&&!closed){remote.srcObject=event.streams.first;if(mounted)setState(()=>hasRemote=true);}};pc!.onConnectionState=(s){if(mounted&&!closed)setState(()=>status=s==RTCPeerConnectionState.RTCPeerConnectionStateConnected?'На связи':'Соединение: ${s.name}');};stream=await navigator.mediaDevices.getUserMedia({'audio':true,'video':widget.video?{'facingMode':'user'}:false});if(closed){for(final t in stream!.getTracks()){await t.stop();}await stream!.dispose();return;}local.srcObject=stream;for(final t in stream!.getTracks()){await pc!.addTrack(t,stream!);}if(widget.outgoing){final offer=await pc!.createOffer();await pc!.setLocalDescription(offer);await signal({'type':'offer','sdp':offer.sdp});}timer=Timer.periodic(const Duration(milliseconds:800),(_)=>poll());await poll();}catch(e){if(mounted&&!closed)setState(()=>status='Ошибка подключения: $e');}}
  Future<void> poll()async{if(busy||closed||pc==null)return;busy=true;try{final st=await widget.api.req('$root/status');if(st['status']=='ended'||(st['status']=='ringing'&&DateTime.now().millisecondsSinceEpoch~/1000-st['created']>60)){await end();return;}final list=await widget.api.req('$root/signals?after=$after') as List;for(final row in list){if(closed)return;final d=jsonDecode(row['payload']);switch(d['type']){case 'offer':case 'answer':await pc!.setRemoteDescription(RTCSessionDescription(d['sdp'],d['type']));remoteDescription=true;for(final c in pending){await pc!.addCandidate(c);}pending.clear();if(d['type']=='offer'){final ans=await pc!.createAnswer();await pc!.setLocalDescription(ans);await signal({'type':'answer','sdp':ans.sdp});}break;case 'ice':final c=RTCIceCandidate(d['candidate'],d['sdpMid'],d['sdpMLineIndex']);if(remoteDescription){await pc!.addCandidate(c);}else{pending.add(c);}break;}after=row['id'];}}catch(e){if(mounted&&!closed)setState(()=>status='Соединение: $e');}finally{busy=false;}}
  Future<void> end()async{if(closed)return;closed=true;timer?.cancel();try{await widget.api.req('$root/status',{'status':'ended'}).timeout(const Duration(seconds:3));}catch(_){}if(mounted)Navigator.pop(context);}
  @override void dispose(){timer?.cancel();if(!closed){closed=true;widget.api.req('$root/status',{'status':'ended'}).catchError((Object _)=>null);}for(final t in stream?.getTracks()??<MediaStreamTrack>[]){t.stop();}stream?.dispose();pc?.close();local.dispose();remote.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.title)),body:Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[if(widget.video)Expanded(child:Stack(children:[Positioned.fill(child:hasRemote?RTCVideoView(remote):const Center(child:Icon(Icons.person,size:100))),Positioned(right:12,top:12,width:110,height:155,child:RTCVideoView(local,mirror:true))]))else const CircleAvatar(radius:64,child:Icon(Icons.person,size:72)),const SizedBox(height:16),Text(status),const SizedBox(height:20),Row(mainAxisAlignment:MainAxisAlignment.center,children:[IconButton.filledTonal(onPressed:(){setState(()=>muted=!muted);for(final t in stream?.getAudioTracks()??<MediaStreamTrack>[]){t.enabled=!muted;}},icon:Icon(muted?Icons.mic_off:Icons.mic)),const SizedBox(width:24),IconButton.filled(onPressed:end,style:IconButton.styleFrom(backgroundColor:Colors.red),icon:const Icon(Icons.call_end,color:Colors.white))]),const SizedBox(height:32)])));
}

class AdminPage extends StatefulWidget{const AdminPage({super.key,required this.api});final Api api;@override State<AdminPage> createState()=>_AdminPage();}
class _AdminPage extends State<AdminPage>{
 Map<String,dynamic> stats={};List users=[],rooms=[],audit=[],reports=[];String error='';bool busy=true;final announcement=TextEditingController();
 @override void initState(){super.initState();load();}
 @override void dispose(){announcement.dispose();super.dispose();}
 Future<void> load()async{try{final api=widget.api;final a=await api.req('/admin/stats');final b=await api.req('/admin/users');final c=await api.req('/admin/rooms');final d=await api.req('/admin/audit');final e=await api.req('/admin/reports');if(mounted)setState((){stats=Map<String,dynamic>.from(a);users=b;rooms=c;audit=d;reports=e;announcement.text=stats['announcement']??'';busy=false;error='';});}catch(e){if(mounted)setState((){busy=false;error='$e';});}}
 Future<void> action(String path,Map<String,dynamic> data)async{try{await widget.api.req(path,data);await load();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
 Future<void> rename(dynamic room)async{final t=TextEditingController(text:room['title']);final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Переименовать'),content:TextField(controller:t),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Сохранить'))]));if(yes==true)await action('/admin/room_rename',{'chat':room['id'],'title':t.text});t.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Панель владельца Telezeka'),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),body:busy?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[if(error.isNotEmpty)Text(error),Text('Статистика',style:Theme.of(context).textTheme.titleLarge),Text('Пользователи: ${stats['users']} · Группы: ${stats['groups']} · Каналы: ${stats['channels']} · Сообщения: ${stats['messages']}'),SwitchListTile(title:const Text('Разрешить регистрацию'),value:stats['registration']=='open',onChanged:(v)=>action('/admin/settings',{'registration':v?'open':'closed'})),TextField(controller:announcement,maxLength:1000,decoration:const InputDecoration(labelText:'Объявление для всех')),FilledButton(onPressed:()=>action('/admin/settings',{'announcement':announcement.text}),child:const Text('Опубликовать объявление')),const Divider(),Text('Пользователи',style:Theme.of(context).textTheme.titleLarge),for(final u in users)ListTile(leading:Icon(u['role']=='owner'?Icons.verified_user:Icons.person),title:Text(u['name']),subtitle:Text('${u['username']??'—'} · ${u['role']}'),trailing:u['role']=='owner'?const Text('Владелец'):TextButton(onPressed:()=>action('/admin/ban',{'uid':u['id'],'banned':u['banned']!=1}),child:Text(u['banned']==1?'Разблокировать':'Заблокировать'))),const Divider(),Text('Группы и каналы',style:Theme.of(context).textTheme.titleLarge),for(final r in rooms)ListTile(title:Text(r['title']),subtitle:Text('${r['member_count']} участников'),trailing:IconButton(onPressed:()=>rename(r),icon:const Icon(Icons.edit))),const Divider(),Text('Жалобы',style:Theme.of(context).textTheme.titleLarge),for(final r in reports)ListTile(title:Text(r['reason']),subtitle:Text('№${r['id']} · ${r['status']}'),trailing:r['status']=='open'?TextButton(onPressed:()=>action('/admin/report_close',{'id':r['id']}),child:const Text('Закрыть')):null),const Divider(),Text('Журнал действий',style:Theme.of(context).textTheme.titleLarge),for(final a in audit)ListTile(title:Text(a['action']),subtitle:Text('ID: ${a['actor']} → ${a['target']??'—'}'))]));
}
