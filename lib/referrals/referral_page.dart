import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_service.dart';
import '../design/velixeo_design.dart';
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
  String percent(double value)=>value.toStringAsFixed(value%1==0?0:2);

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
  Widget build(BuildContext context) => fa
      ? _buildPersianReferral(context)
      : _buildEnglishReferral(context);

  Widget _buildPersianReferral(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: _buildPersianReferralPage(
          context,
          appBarTitle: 'دعوت از دوستان',
          heading: 'تجربهٔ خوب را شریک شو',
          subtitle: 'دوستانت را دعوت کن و کمیسیون بگیر.',
          heroTitle: 'با هم، یک قدم جلوتر',
          heroBody: 'یک دعوت ساده، یک فرصت تازه.',
          inviteMetric: 'دوست دعوت‌شده',
          rateMetric: 'نرخ کمیسیون',
          earnedMetric: 'درآمد دعوت',
          commissionNotice:
              'کمیسیون فقط برای افزایش موجودی HesabPay که سرور تأیید کرده باشد محاسبه می‌شود.',
          codeLabel: 'کد دعوت تو',
          linkLabel: 'پیوند دعوت',
          friendsTitle: 'دوستان دعوت‌شده',
          emptyTitle: 'هنوز دوستی دعوت نکرده‌ای',
          emptyBody: 'پیوندت را با دوستانت شریک کن.',
          faView: true,
        ),
      );

  Widget _buildEnglishReferral(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _buildEnglishReferralPage(
          context,
          appBarTitle: 'Invite friends',
          heading: 'Share a better experience',
          subtitle: 'Invite friends and earn commission.',
          heroTitle: 'A little further, together',
          heroBody: 'One simple invite, a new opportunity.',
          inviteMetric: 'Friends invited',
          rateMetric: 'Commission rate',
          earnedMetric: 'Earned',
          commissionNotice:
              'Commission is earned only on HesabPay top-ups verified by the server.',
          codeLabel: 'Your referral code',
          linkLabel: 'Referral link',
          friendsTitle: 'Invited friends',
          emptyTitle: 'No friends invited yet',
          emptyBody: 'Share your link with friends.',
          faView: false,
        ),
      );

  Widget _buildPersianReferralPage(
    BuildContext context, {
    required String appBarTitle,
    required String heading,
    required String subtitle,
    required String heroTitle,
    required String heroBody,
    required String inviteMetric,
    required String rateMetric,
    required String earnedMetric,
    required String commissionNotice,
    required String codeLabel,
    required String linkLabel,
    required String friendsTitle,
    required String emptyTitle,
    required String emptyBody,
    required bool faView,
  }) {
    final s = summary;
    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Text(
                    heading,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: VelixeoBrand.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: VelixeoBrand.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (error != null)
                    _Notice(
                      text: faView
                          ? 'اطلاعات دعوت دریافت نشد. دوباره تلاش کنید.'
                          : 'Could not load referral information. Try again.',
                    ),
                  if (s != null) ...[
                    Container(
                      padding: const EdgeInsets.all(21),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEFFAFF), Color(0xFFDEF4FD)],
                        ),
                        border: Border.all(color: const Color(0xFFDCEEF8)),
                        borderRadius: BorderRadius.circular(23),
                      ),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 68),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  heroTitle,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2C5366),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  heroBody,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    height: 1.6,
                                    color: Color(0xFF7293A5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PositionedDirectional(
                            end: 4,
                            bottom: -11,
                            child: Text(
                              '✧',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 72,
                                height: 1,
                                color: Color(0xFF7ACEF0),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 17,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: const Color(0xFFE4EDF3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ReferralTopMetric(
                              value: s.inviteCount.toString(),
                              label: inviteMetric,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 42,
                            color: const Color(0xFFEDF2F6),
                          ),
                          Expanded(
                            child: _ReferralTopMetric(
                              value: percent(s.rewardPercent) + '%',
                              label: rateMetric,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 42,
                            color: const Color(0xFFEDF2F6),
                          ),
                          Expanded(
                            child: _ReferralTopMetric(
                              value: widget.host.money(
                                s.totalRewardsAfn,
                                showBase: true,
                              ),
                              label: earnedMetric,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ReferralNotice(text: commissionNotice),
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CopyRow(
                            label: codeLabel,
                            value: s.code,
                            onCopy: () => copy(
                              s.code,
                              faView
                                  ? 'کد دعوت کپی شد.'
                                  : 'Referral code copied.',
                            ),
                          ),
                          const SizedBox(height: 10),
                          _CopyRow(
                            label: linkLabel,
                            value: s.inviteLink,
                            onCopy: () => copy(
                              s.inviteLink,
                              faView
                                  ? 'لینک دعوت کپی شد.'
                                  : 'Referral link copied.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: shareWhatsApp,
                                  icon: const Icon(
                                    Icons.chat_rounded,
                                    color: Color(0xFF20A76F),
                                    size: 17,
                                  ),
                                  label: const Text('WhatsApp'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: shareTelegram,
                                  icon: const Icon(
                                    Icons.send_rounded,
                                    color: VelixeoBrand.sky,
                                    size: 17,
                                  ),
                                  label: const Text('Telegram'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      friendsTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: VelixeoBrand.ink,
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (s.invites.isEmpty)
                      _ReferralEmpty(
                        title: emptyTitle,
                        body: emptyBody,
                      )
                    else
                      ...s.invites.map(
                        (invite) => _Card(
                          child: _InviteTile(
                            invite: invite,
                            fa: faView,
                            money: widget.host.money,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

Widget _buildEnglishReferralPage(
    BuildContext context, {
    required String appBarTitle,
    required String heading,
    required String subtitle,
    required String heroTitle,
    required String heroBody,
    required String inviteMetric,
    required String rateMetric,
    required String earnedMetric,
    required String commissionNotice,
    required String codeLabel,
    required String linkLabel,
    required String friendsTitle,
    required String emptyTitle,
    required String emptyBody,
    required bool faView,
  }) {
    final s = summary;
    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Text(
                    heading,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: VelixeoBrand.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: VelixeoBrand.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (error != null)
                    _Notice(
                      text: faView
                          ? 'اطلاعات دعوت دریافت نشد. دوباره تلاش کنید.'
                          : 'Could not load referral information. Try again.',
                    ),
                  if (s != null) ...[
                    Container(
                      padding: const EdgeInsets.all(21),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEFFAFF), Color(0xFFDEF4FD)],
                        ),
                        border: Border.all(color: const Color(0xFFDCEEF8)),
                        borderRadius: BorderRadius.circular(23),
                      ),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 68),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  heroTitle,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2C5366),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  heroBody,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    height: 1.6,
                                    color: Color(0xFF7293A5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PositionedDirectional(
                            end: 4,
                            bottom: -11,
                            child: Text(
                              '✧',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 72,
                                height: 1,
                                color: Color(0xFF7ACEF0),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 17,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: const Color(0xFFE4EDF3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ReferralTopMetric(
                              value: s.inviteCount.toString(),
                              label: inviteMetric,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 42,
                            color: const Color(0xFFEDF2F6),
                          ),
                          Expanded(
                            child: _ReferralTopMetric(
                              value: percent(s.rewardPercent) + '%',
                              label: rateMetric,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 42,
                            color: const Color(0xFFEDF2F6),
                          ),
                          Expanded(
                            child: _ReferralTopMetric(
                              value: widget.host.money(
                                s.totalRewardsAfn,
                                showBase: true,
                              ),
                              label: earnedMetric,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ReferralNotice(text: commissionNotice),
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CopyRow(
                            label: codeLabel,
                            value: s.code,
                            onCopy: () => copy(
                              s.code,
                              faView
                                  ? 'کد دعوت کپی شد.'
                                  : 'Referral code copied.',
                            ),
                          ),
                          const SizedBox(height: 10),
                          _CopyRow(
                            label: linkLabel,
                            value: s.inviteLink,
                            onCopy: () => copy(
                              s.inviteLink,
                              faView
                                  ? 'لینک دعوت کپی شد.'
                                  : 'Referral link copied.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: shareWhatsApp,
                                  icon: const Icon(
                                    Icons.chat_rounded,
                                    color: Color(0xFF20A76F),
                                    size: 17,
                                  ),
                                  label: const Text('WhatsApp'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: shareTelegram,
                                  icon: const Icon(
                                    Icons.send_rounded,
                                    color: VelixeoBrand.sky,
                                    size: 17,
                                  ),
                                  label: const Text('Telegram'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      friendsTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: VelixeoBrand.ink,
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (s.invites.isEmpty)
                      _ReferralEmpty(
                        title: emptyTitle,
                        body: emptyBody,
                      )
                    else
                      ...s.invites.map(
                        (invite) => _Card(
                          child: _InviteTile(
                            invite: invite,
                            fa: faView,
                            money: widget.host.money,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

}

class _ReferralTopMetric extends StatelessWidget {
  const _ReferralTopMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF308DB5),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 9,
              height: 1.35,
              color: Color(0xFF8A9BA5),
            ),
          ),
        ],
      );
}

class _ReferralNotice extends StatelessWidget {
  const _ReferralNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8FC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFE4F0F6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: Color(0xFF65AACA),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.55,
                  color: Color(0xFF66808F),
                ),
              ),
            ),
          ],
        ),
      );
}

class _ReferralEmpty extends StatelessWidget {
  const _ReferralEmpty({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE4EDF3)),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.group_outlined,
              size: 34,
              color: Color(0xFF9AAABA),
            ),
            const SizedBox(height: 9),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                color: VelixeoBrand.muted,
              ),
            ),
          ],
        ),
      );
}

class _Card extends StatelessWidget{
 const _Card({required this.child});final Widget child;
 @override Widget build(BuildContext context)=>Container(
  width:double.infinity,padding:const EdgeInsets.all(16),
  decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFFDDE8F1))),
  child:child,
 );
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
    IconButton(onPressed:onCopy,icon:const Icon(Icons.copy_rounded,color:VelixeoBrand.sky)),
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
   const CircleAvatar(backgroundColor:Color(0xFFEAF5FF),child:Icon(Icons.person_outline_rounded,color:VelixeoBrand.sky)),
   const SizedBox(width:10),
   Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(invite.name,style:const TextStyle(fontWeight:FontWeight.w800)),
    Text(invite.createdAt.toLocal().toString().substring(0,10),style:const TextStyle(fontSize:10,color:Color(0xFF8A98A6))),
   ])),
   Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
    Text(invite.rewardCount>0?(fa?'${invite.rewardCount} شارژ موفق':'${invite.rewardCount} verified top-ups'):(fa?'هنوز شارژ نشده':'No top-up yet'),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:VelixeoBrand.green)),
    if(invite.qualifyingTopupAfn>0)Text(fa?'شارژ: ${money(invite.qualifyingTopupAfn,showBase:true)}':'Top-ups: ${money(invite.qualifyingTopupAfn,showBase:true)}',style:const TextStyle(fontSize:9.5,color:Color(0xFF718399))),
    if(invite.rewardAfn>0)Text(fa?'کمیسیون: ${money(invite.rewardAfn,showBase:true)}':'Commission: ${money(invite.rewardAfn,showBase:true)}',style:const TextStyle(fontSize:10,color:VelixeoBrand.sky,fontWeight:FontWeight.w800)),
   ]),
  ]),
 );
}
class _Notice extends StatelessWidget{
 const _Notice({required this.text});final String text;
 @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:const Color(0xFFFFF4E6),borderRadius:BorderRadius.circular(14)),child:Text(text,style:const TextStyle(color:Color(0xFF96600B))));
}
