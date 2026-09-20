import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_service.dart';
import 'referral_models.dart';

abstract class ReferralPanelHost {
  ApiService get api;
  bool get fa;
  String money(int amountAfn,{bool showBase});
}

class InviteFriendsPage extends StatefulWidget {
  const InviteFriendsPage({super.key,required this.host});
  final ReferralPanelHost host;

  @override
  State<InviteFriendsPage> createState()=>_InviteFriendsPageState();
}

class _InviteFriendsPageState extends State<InviteFriendsPage>{
  ReferralSummary? summary;
  bool loading=true;
  String? error;

  bool get fa=>widget.host.fa;
  String t(String f,String e)=>fa?f:e;

  @override
  void initState(){super.initState();load();}

  Future<void> load() async {
    if(mounted)setState((){loading=true;error=null;});
    try{
      final value=await widget.host.api.referralSummary();
      if(mounted)setState(()=>summary=value);
    }on ApiException catch(e){
      if(mounted)setState(()=>error=e.code);
    }catch(_){
      if(mounted)setState(()=>error='network_error');
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  Future<void> copy(String value,String label) async{
    await Clipboard.setData(ClipboardData(text:value));
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(label)));
  }

  Future<void> shareWhatsApp()async{
    final s=summary;if(s==null)return;
    final message=t(
      'با لینک دعوت من به VELIXEO بپیوند:\n${s.inviteLink}\nکد دعوت: ${s.code}',
      'Join VELIXEO with my invitation:\n${s.inviteLink}\nReferral code: ${s.code}',
    );
    await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'),mode:LaunchMode.externalApplication);
  }

  Future<void> shareTelegram()async{
    final s=summary;if(s==null)return;
    final text=t('با دعوت من به VELIXEO بپیوند','Join VELIXEO with my invitation');
    await launchUrl(Uri.parse('https://t.me/share/url?url=${Uri.encodeComponent(s.inviteLink)}&text=${Uri.encodeComponent(text)}'),mode:LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context){
    final s=summary;
    return Scaffold(
      appBar:AppBar(title:Text(t('دعوت از دوستان','Invite friends'))),
      body:loading
        ?const Center(child:CircularProgressIndicator())
        :RefreshIndicator(
          onRefresh:load,
          child:ListView(
            physics:const AlwaysScrollableScrollPhysics(),
            padding:const EdgeInsets.fromLTRB(16,8,16,28),
            children:[
              if(error!=null) _Notice(text:t('اطلاعات دعوت دریافت نشد. دوباره تلاش کنید.','Could not load referral information. Try again.')),
              if(s!=null)...[
                Container(
                  padding:const EdgeInsets.all(20),
                  decoration:BoxDecoration(
                    gradient:const LinearGradient(colors:[Color(0xFF28B6F6),Color(0xFF0878CB)]),
                    borderRadius:BorderRadius.circular(22),
                  ),
                  child:Row(children:[
                    Container(
                      width:86,height:86,
                      decoration:BoxDecoration(color:Colors.white.withValues(alpha:.14),borderRadius:BorderRadius.circular(25)),
                      child:const Icon(Icons.card_giftcard_rounded,size:48,color:Colors.white),
                    ),
                    const SizedBox(width:16),
                    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text(t('دوستانت را دعوت کن، جایزه بگیر','Invite friends, earn rewards'),style:const TextStyle(color:Colors.white,fontSize:19,fontWeight:FontWeight.w900)),
                      const SizedBox(height:6),
                      Text(
                        s.rewardAfn>0
                          ?t('برای هر دعوت موفق تا ${widget.host.money(s.rewardAfn,showBase:true)} پاداش بگیر.','Earn ${widget.host.money(s.rewardAfn,showBase:true)} for each successful referral.')
                          :t('لینک اختصاصی خودت را با دوستانت به اشتراک بگذار.','Share your personal invitation link with friends.'),
                        style:const TextStyle(color:Color(0xFFE6F7FF),fontSize:11.5,height:1.45),
                      ),
                    ])),
                  ]),
                ),
                const SizedBox(height:14),
                Row(children:[
                  Expanded(child:_Metric(icon:Icons.group_add_rounded,label:t('دعوت‌های موفق','Successful invites'),value:'${s.inviteCount}',accent:const Color(0xFF16A875))),
                  const SizedBox(width:10),
                  Expanded(child:_Metric(icon:Icons.toll_rounded,label:t('مجموع پاداش‌ها','Total rewards'),value:widget.host.money(s.totalRewardsAfn,showBase:true),accent:const Color(0xFF1686FF))),
                ]),
                const SizedBox(height:14),
                _Card(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(t('لینک اختصاصی دعوت','Your personal invitation'),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16)),
                  const SizedBox(height:4),
                  Text(t('دوستت می‌تواند لینک را باز کند یا هنگام ثبت‌نام کد دعوت را وارد کند.','Your friend can open the link or enter your referral code during registration.'),style:const TextStyle(fontSize:11,color:Color(0xFF718399))),
                  const SizedBox(height:14),
                  _CopyRow(
                    label:t('کد دعوت','Referral code'),
                    value:s.code,
                    onCopy:()=>copy(s.code,t('کد دعوت کپی شد.','Referral code copied.')),
                  ),
                  const SizedBox(height:10),
                  _CopyRow(
                    label:t('لینک دعوت','Invitation link'),
                    value:s.inviteLink,
                    onCopy:()=>copy(s.inviteLink,t('لینک دعوت کپی شد.','Invitation link copied.')),
                  ),
                  const SizedBox(height:12),
                  Row(children:[
                    Expanded(child:OutlinedButton.icon(onPressed:shareWhatsApp,icon:const Icon(Icons.chat_rounded,color:Color(0xFF20A76F)),label:const Text('WhatsApp'))),
                    const SizedBox(width:8),
                    Expanded(child:OutlinedButton.icon(onPressed:shareTelegram,icon:const Icon(Icons.send_rounded,color:Color(0xFF1686FF)),label:const Text('Telegram'))),
                  ]),
                ])),
                const SizedBox(height:14),
                _Card(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Row(children:[
                    Expanded(child:Text(t('دوستان دعوت‌شده','Invited friends'),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16))),
                    Text('${s.invites.length}',style:const TextStyle(color:Color(0xFF1686FF),fontWeight:FontWeight.w900)),
                  ]),
                  const SizedBox(height:10),
                  if(s.invites.isEmpty)
                    Padding(
                      padding:const EdgeInsets.symmetric(vertical:24),
                      child:Center(child:Column(children:[
                        const Icon(Icons.group_outlined,size:36,color:Color(0xFF9AAABA)),
                        const SizedBox(height:8),
                        Text(t('هنوز دوستی دعوت نشده است.','No friends invited yet.'),style:const TextStyle(color:Color(0xFF718399))),
                      ])),
                    )
                  else
                    ...s.invites.map((x)=>_InviteTile(invite:x,fa:fa,money:widget.host.money)),
                ])),
                const SizedBox(height:12),
                Text(
                  t('پاداش‌ها و شرایط دعوت توسط مدیریت VELIXEO تنظیم می‌شوند. ساخت حساب‌های غیرواقعی ممکن است باعث لغو پاداش شود.','Referral rewards and conditions are controlled by VELIXEO administration. Fake or duplicate accounts may have rewards revoked.'),
                  textAlign:TextAlign.center,
                  style:const TextStyle(fontSize:10,color:Color(0xFF8B99A7),height:1.4),
                ),
              ]
            ],
          ),
        ),
    );
  }
}

class _Card extends StatelessWidget{
 const _Card({required this.child});final Widget child;
 @override Widget build(BuildContext context)=>Container(
  width:double.infinity,padding:const EdgeInsets.all(16),
  decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFFDDE8F1))),
  child:child,
 );
}
class _Metric extends StatelessWidget{
 const _Metric({required this.icon,required this.label,required this.value,required this.accent});
 final IconData icon;final String label,value;final Color accent;
 @override Widget build(BuildContext context)=>_Card(child:Row(children:[
  Container(width:44,height:44,decoration:BoxDecoration(color:accent.withValues(alpha:.10),borderRadius:BorderRadius.circular(13)),child:Icon(icon,color:accent)),
  const SizedBox(width:10),
  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Text(label,style:const TextStyle(fontSize:10,color:Color(0xFF718399))),
   const SizedBox(height:3),
   Text(value,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:15),maxLines:1,overflow:TextOverflow.ellipsis),
  ])),
 ]));
}
class _CopyRow extends StatelessWidget{
 const _CopyRow({required this.label,required this.value,required this.onCopy});
 final String label,value;final VoidCallback onCopy;
 @override Widget build(BuildContext context)=>Container(
  padding:const EdgeInsets.all(11),
  decoration:BoxDecoration(color:const Color(0xFFF2F8FD),borderRadius:BorderRadius.circular(13),border:Border.all(color:const Color(0xFFCDE5F8))),
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Text(label,style:const TextStyle(fontSize:10,color:Color(0xFF718399),fontWeight:FontWeight.w800)),
   const SizedBox(height:5),
   Row(children:[
    Expanded(child:SelectableText(value,style:const TextStyle(fontSize:12.5,fontWeight:FontWeight.w900),maxLines:2)),
    IconButton(onPressed:onCopy,icon:const Icon(Icons.copy_rounded,color:Color(0xFF1686FF))),
   ]),
  ]),
 );
}
class _InviteTile extends StatelessWidget{
 const _InviteTile({required this.invite,required this.fa,required this.money});
 final ReferralInvite invite;final bool fa;final String Function(int,{bool showBase}) money;
 @override Widget build(BuildContext context)=>Container(
  padding:const EdgeInsets.symmetric(vertical:11),
  decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Color(0xFFEDF2F7)))),
  child:Row(children:[
   const CircleAvatar(backgroundColor:Color(0xFFEAF5FF),child:Icon(Icons.person_outline_rounded,color:Color(0xFF1686FF))),
   const SizedBox(width:10),
   Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(invite.name,style:const TextStyle(fontWeight:FontWeight.w800)),
    Text(invite.createdAt.toLocal().toString().substring(0,10),style:const TextStyle(fontSize:10,color:Color(0xFF8A98A6))),
   ])),
   Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
    Text(invite.status=='REWARDED'?(fa?'پاداش داده شد':'Rewarded'):(fa?'ثبت‌نام شده':'Registered'),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:Color(0xFF18A875))),
    if(invite.rewardAfn>0)Text(money(invite.rewardAfn,showBase:true),style:const TextStyle(fontSize:10,color:Color(0xFF1686FF))),
   ]),
  ]),
 );
}
class _Notice extends StatelessWidget{
 const _Notice({required this.text});final String text;
 @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:const Color(0xFFFFF4E6),borderRadius:BorderRadius.circular(14)),child:Text(text,style:const TextStyle(color:Color(0xFF96600B))));
}
