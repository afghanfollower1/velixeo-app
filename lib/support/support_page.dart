import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../design/velixeo_design.dart';
import 'support_models.dart';

abstract class SupportPanelHost {
  ApiService get api;
  bool get fa;
}

class SupportPage extends StatefulWidget {
  const SupportPage({super.key, required this.host});
  final SupportPanelHost host;

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  List<SupportTicket> tickets = const [];
  bool loading = true;
  bool busy = false;
  String? error;

  bool get fa => widget.host.fa;
  String t(String faText, String enText) => fa ? faText : enText;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      tickets = await widget.host.api.supportTickets();
    } on ApiException catch (e) {
      error = e.code;
    } catch (_) {
      error = 'network_error';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> newTicket() async {
    final ticket = await Navigator.push<SupportTicket>(
      context,
      MaterialPageRoute(
        builder: (_) => NewSupportTicketPage(host: widget.host),
      ),
    );
    if (ticket == null || !mounted) return;
    setState(() {
      tickets = [ticket, ...tickets.where((item) => item.id != ticket.id)];
    });
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupportTicketPage(
          host: widget.host,
          initialTicket: ticket,
        ),
      ),
    );
    await load();
  }

  String errorLabel(String code) {
    if (code == 'ticket_closed') return t('این تیکت بسته شده است.', 'This ticket is closed.');
    if (code == 'network_error') return t('ارتباط با سرور برقرار نشد.', 'Could not reach the server.');
    return t('عملیات پشتیبانی انجام نشد.', 'Support request could not be completed.');
  }

  String statusLabel(String status) {
    switch (status) {
      case 'PENDING_ADMIN': return t('در انتظار پاسخ پشتیبانی', 'Waiting for support');
      case 'PENDING_USER': return t('پاسخ جدید', 'Waiting for you');
      case 'CLOSED': return t('بسته شده', 'Closed');
      default: return t('باز', 'Open');
    }
  }

  Color statusColor(String status) {
    switch (status) {
      case 'PENDING_USER': return VelixeoBrand.green;
      case 'CLOSED': return VelixeoBrand.muted;
      default: return const Color(0xFFEFAF38);
    }
  }

  @override
  Widget build(BuildContext context) {
    return fa
        ? Directionality(
            textDirection: TextDirection.rtl,
            child: _buildPersianSupportScaffold(context),
          )
        : Directionality(
            textDirection: TextDirection.ltr,
            child: _buildEnglishSupportScaffold(context),
          );
  }

  Widget _buildPersianSupportScaffold(BuildContext context) => Scaffold(
        appBar: VelixeoFaAppBar(
          title: 'پشتیبانی و تیکت',
          subtitle: 'سؤال‌ها، گفتگوها و پاسخ‌های پشتیبانی.',
          actions: [IconButton(onPressed: loading ? null : load, icon: const Icon(Icons.refresh_rounded))],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
                  children: [
                    Text(
                      t('کنارت هستیم', 'We are here to help'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: VelixeoBrand.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('سؤال یا مشکلت را برای ما بنویس.', 'Tell us what you need help with.'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: VelixeoBrand.muted,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF8FC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDDEFF6)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t('گفتگو را شروع کن', 'Let us start a conversation'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2C5366),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  t('پیام‌ها و پاسخ‌ها، همیشه در دسترس.', 'Your messages and replies, always at hand.'),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF7293A5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.mail_outline_rounded,
                            color: Color(0xFF6AB4D2),
                            size: 34,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: busy ? null : newTicket,
                        icon: const Icon(Icons.add_comment_outlined, size: 18),
                        label: Text(t('تیکت جدید', 'New ticket')),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (error != null)
                      Text(errorLabel(error!), textAlign: TextAlign.center)
                    else if (tickets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 52),
                        child: Column(
                          children: [
                            const Icon(Icons.forum_outlined, size: 64, color: Color(0xFF9BB1C4)),
                            const SizedBox(height: 12),
                            Text(t('هنوز تیکتی ندارید', 'No support tickets yet'), style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      )
                    else
                      ...tickets.map((ticket) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(21),
                                onTap: () async {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => SupportTicketPage(host: widget.host, initialTicket: ticket)));
                                  await load();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: statusColor(ticket.status).withValues(alpha: .10),
                                        child: Icon(Icons.chat_bubble_outline_rounded, color: statusColor(ticket.status)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(ticket.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 4),
                                            Text('${statusLabel(ticket.status)} • ${ticket.messages.length} ${t('پیام', 'messages')}', style: const TextStyle(fontSize: 11, color: VelixeoBrand.muted)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right_rounded),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )),
                  ],
                ),
              ),
      );

Widget _buildEnglishSupportScaffold(BuildContext context) => Scaffold(
        appBar: VelixeoEnAppBar(
          title: 'Support & Tickets',
          subtitle: 'Questions, conversations and support replies.',
          actions: [IconButton(onPressed: loading ? null : load, icon: const Icon(Icons.refresh_rounded))],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
                  children: [
                    Text(
                      t('کنارت هستیم', 'We are here to help'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: VelixeoBrand.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('سؤال یا مشکلت را برای ما بنویس.', 'Tell us what you need help with.'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: VelixeoBrand.muted,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF8FC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDDEFF6)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t('گفتگو را شروع کن', 'Let us start a conversation'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2C5366),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  t('پیام‌ها و پاسخ‌ها، همیشه در دسترس.', 'Your messages and replies, always at hand.'),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF7293A5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.mail_outline_rounded,
                            color: Color(0xFF6AB4D2),
                            size: 34,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: busy ? null : newTicket,
                        icon: const Icon(Icons.add_comment_outlined, size: 18),
                        label: Text(t('تیکت جدید', 'New ticket')),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (error != null)
                      Text(errorLabel(error!), textAlign: TextAlign.center)
                    else if (tickets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 52),
                        child: Column(
                          children: [
                            const Icon(Icons.forum_outlined, size: 64, color: Color(0xFF9BB1C4)),
                            const SizedBox(height: 12),
                            Text(t('هنوز تیکتی ندارید', 'No support tickets yet'), style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      )
                    else
                      ...tickets.map((ticket) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(21),
                                onTap: () async {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => SupportTicketPage(host: widget.host, initialTicket: ticket)));
                                  await load();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: statusColor(ticket.status).withValues(alpha: .10),
                                        child: Icon(Icons.chat_bubble_outline_rounded, color: statusColor(ticket.status)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(ticket.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 4),
                                            Text('${statusLabel(ticket.status)} • ${ticket.messages.length} ${t('پیام', 'messages')}', style: const TextStyle(fontSize: 11, color: VelixeoBrand.muted)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right_rounded),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )),
                  ],
                ),
              ),
      );
}


class NewSupportTicketPage extends StatefulWidget {
  const NewSupportTicketPage({super.key, required this.host});
  final SupportPanelHost host;

  @override
  State<NewSupportTicketPage> createState() => _NewSupportTicketPageState();
}

class _NewSupportTicketPageState extends State<NewSupportTicketPage> {
  final subject = TextEditingController();
  final message = TextEditingController();
  bool busy = false;

  bool get fa => widget.host.fa;

  @override
  void dispose() {
    subject.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final title = subject.text.trim();
    final body = message.text.trim();
    if (title.length < 4 || body.length < 10 || busy) return;
    setState(() => busy = true);
    try {
      final ticket = await widget.host.api.createSupportTicket(
        subject: title,
        message: body,
      );
      if (!mounted) return;
      Navigator.pop(context, ticket);
    } on ApiException catch (error) {
      if (!mounted) return;
      final text = error.code == 'network_error'
          ? (fa ? 'ارتباط با سرور برقرار نشد.' : 'Could not reach the server.')
          : (fa ? 'ارسال تیکت انجام نشد.' : 'Ticket could not be submitted.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => fa
      ? _buildPersianPage(context)
      : _buildEnglishPage(context);

Widget _buildPersianPage(BuildContext context) => Directionality(
        textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            title: Text(fa ? 'تیکت جدید' : 'New ticket'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            children: [
              Text(
                fa ? 'چطور می‌توانیم کمک کنیم؟' : 'How can we help?',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fa ? 'جزئیات بیشتر، کمک دقیق‌تر.' : 'More details help us give you a better answer.',
                style: const TextStyle(
                  fontSize: 11,
                  color: VelixeoBrand.muted,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: subject,
                maxLength: 120,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: fa ? 'موضوع' : 'Subject',
                  hintText: fa
                      ? 'مثلاً: بررسی وضعیت سفارش #VX-20481'
                      : 'For example: Check order #VX-20481',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: message,
                minLines: 6,
                maxLines: 9,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: fa ? 'پیام شما' : 'Your message',
                  alignLabelWithHint: true,
                  hintText: fa
                      ? 'چه اتفاقی افتاده است؟ جزئیات و شمارهٔ سفارش را بنویس.'
                      : 'What happened? Include the details and order ID.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E8),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFF5E4C9)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: VelixeoBrand.orange,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fa
                            ? 'رمز عبور، کد تأیید و اطلاعات حساس را در پیام ننویس.'
                            : 'Do not include passwords, verification codes or sensitive details in your message.',
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.55,
                          color: Color(0xFF8A682B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: busy ||
                        subject.text.trim().length < 4 ||
                        message.text.trim().length < 10
                    ? null
                    : submit,
                child: busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(fa ? 'ارسال تیکت' : 'Submit ticket'),
              ),
            ],
          ),
        ),
      );

Widget _buildEnglishPage(BuildContext context) => Directionality(
        textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            title: Text(fa ? 'تیکت جدید' : 'New ticket'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            children: [
              Text(
                fa ? 'چطور می‌توانیم کمک کنیم؟' : 'How can we help?',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fa ? 'جزئیات بیشتر، کمک دقیق‌تر.' : 'More details help us give you a better answer.',
                style: const TextStyle(
                  fontSize: 11,
                  color: VelixeoBrand.muted,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: subject,
                maxLength: 120,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: fa ? 'موضوع' : 'Subject',
                  hintText: fa
                      ? 'مثلاً: بررسی وضعیت سفارش #VX-20481'
                      : 'For example: Check order #VX-20481',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: message,
                minLines: 6,
                maxLines: 9,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: fa ? 'پیام شما' : 'Your message',
                  alignLabelWithHint: true,
                  hintText: fa
                      ? 'چه اتفاقی افتاده است؟ جزئیات و شمارهٔ سفارش را بنویس.'
                      : 'What happened? Include the details and order ID.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E8),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFF5E4C9)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: VelixeoBrand.orange,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fa
                            ? 'رمز عبور، کد تأیید و اطلاعات حساس را در پیام ننویس.'
                            : 'Do not include passwords, verification codes or sensitive details in your message.',
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.55,
                          color: Color(0xFF8A682B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: busy ||
                        subject.text.trim().length < 4 ||
                        message.text.trim().length < 10
                    ? null
                    : submit,
                child: busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(fa ? 'ارسال تیکت' : 'Submit ticket'),
              ),
            ],
          ),
        ),
      );
}

class SupportTicketPage extends StatefulWidget {
  const SupportTicketPage({super.key, required this.host, required this.initialTicket});
  final SupportPanelHost host;
  final SupportTicket initialTicket;

  @override
  State<SupportTicketPage> createState() => _SupportTicketPageState();
}

class _SupportTicketPageState extends State<SupportTicketPage> {
  late SupportTicket ticket;
  final reply = TextEditingController();
  bool busy = false;

  bool get fa => widget.host.fa;
  String t(String faText, String enText) => fa ? faText : enText;

  @override
  void initState() {
    super.initState();
    ticket = widget.initialTicket;
  }

  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final rows = await widget.host.api.supportTickets();
      final latest = rows.where((item) => item.id == ticket.id).firstOrNull;
      if (latest != null && mounted) setState(() => ticket = latest);
    } catch (_) {}
  }

  Future<void> send() async {
    final text = reply.text.trim();
    if (text.isEmpty || busy || ticket.status == 'CLOSED') return;
    setState(() => busy = true);
    try {
      final message = await widget.host.api.replySupportTicket(ticket.id, text);
      reply.clear();
      setState(() => ticket = ticket.copyWith(messages: [...ticket.messages, message], status: 'PENDING_ADMIN'));
      await refresh();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.code == 'ticket_closed' ? t('این تیکت بسته شده است.', 'This ticket is closed.') : t('ارسال پیام انجام نشد.', 'Message could not be sent.'))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => fa
      ? _buildPersianConversation(context)
      : _buildEnglishConversation(context);

  Widget _buildPersianConversation(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: _buildPersianConversationPage(
          context,
          appBarTitle: 'گفتگوی پشتیبانی',
          supportLabel: 'پشتیبانی VELIXEO',
          waitingLabel: 'در انتظار پشتیبانی',
          closedLabel: 'بسته‌شده',
          todayLabel: 'امروز',
          youLabel: 'شما',
          replyLabel: 'پاسخ شما',
          sendLabel: 'ارسال پاسخ',
          closedNotice:
              'این تیکت بسته شده است. برای موضوع جدید، تیکت تازه‌ای بساز.',
          newTicketLabel: 'تیکت جدید',
          refreshLabel: 'به‌روزرسانی گفتگو',
          faView: true,
        ),
      );

  Widget _buildEnglishConversation(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _buildEnglishConversationPage(
          context,
          appBarTitle: 'Support conversation',
          supportLabel: 'VELIXEO support',
          waitingLabel: 'Waiting for support',
          closedLabel: 'Closed',
          todayLabel: 'Today',
          youLabel: 'You',
          replyLabel: 'Your reply',
          sendLabel: 'Send reply',
          closedNotice:
              'This ticket is closed. Create a new ticket for a new issue.',
          newTicketLabel: 'New ticket',
          refreshLabel: 'Refresh conversation',
          faView: false,
        ),
      );

  Widget _buildPersianConversationPage(
    BuildContext context, {
    required String appBarTitle,
    required String supportLabel,
    required String waitingLabel,
    required String closedLabel,
    required String todayLabel,
    required String youLabel,
    required String replyLabel,
    required String sendLabel,
    required String closedNotice,
    required String newTicketLabel,
    required String refreshLabel,
    required bool faView,
  }) {
    final closed = ticket.status == 'CLOSED';
    final shortId =
        ticket.id.length > 8 ? ticket.id.substring(0, 8).toUpperCase() : ticket.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: VelixeoFaDesign.pagePadding,
          children: [
            Text(
              ticket.subject,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              (faView ? 'تیکت شمارهٔ #' : 'Ticket #') + shortId,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 10.5,
                color: VelixeoBrand.muted,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    supportLabel,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF7C919E),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: closed
                        ? const Color(0xFFF0F3F5)
                        : const Color(0xFFFFF4DF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    closed ? closedLabel : waitingLabel,
                    style: TextStyle(
                      fontSize: 9,
                      color: closed
                          ? VelixeoBrand.muted
                          : VelixeoBrand.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                todayLabel,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: Color(0xFF9BADB8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...ticket.messages.map((message) {
              final customer = !message.isAdmin;
              final time = message.createdAt
                  .toLocal()
                  .toString()
                  .substring(11, 16);
              return Align(
                alignment: customer
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.centerEnd,
                child: FractionallySizedBox(
                  widthFactor: .89,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
                    decoration: BoxDecoration(
                      color: customer
                          ? const Color(0xFFEAF7FD)
                          : const Color(0xFFF1F5F8),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(
                          !faView && customer ? 5 : 18,
                        ),
                        topRight: Radius.circular(
                          faView && customer
                              ? 5
                              : (!faView && !customer ? 5 : 18),
                        ),
                        bottomLeft: const Radius.circular(18),
                        bottomRight: const Radius.circular(18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.isAdmin) ...[
                          Text(
                            supportLabel,
                            style: const TextStyle(
                              color: Color(0xFF4C7184),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          message.content,
                          style: TextStyle(
                            color: customer
                                ? const Color(0xFF4B7D96)
                                : const Color(0xFF68818E),
                            fontSize: 11.5,
                            height: 1.75,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          (customer ? youLabel + ' · ' : '') + time,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF91A5B1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (closed) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6F8),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  closedNotice,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.6,
                    color: Color(0xFF718793),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final created = await Navigator.push<SupportTicket>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NewSupportTicketPage(host: widget.host),
                    ),
                  );
                  if (created == null || !context.mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupportTicketPage(
                        host: widget.host,
                        initialTicket: created,
                      ),
                    ),
                  );
                },
                child: Text(newTicketLabel),
              ),
            ] else ...[
              TextField(
                controller: reply,
                minLines: 3,
                maxLines: 6,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: replyLabel,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: busy ? null : send,
                icon: busy
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 17),
                label: Text(sendLabel),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: Text(refreshLabel),
            ),
          ],
        ),
      ),
    );
  }

Widget _buildEnglishConversationPage(
    BuildContext context, {
    required String appBarTitle,
    required String supportLabel,
    required String waitingLabel,
    required String closedLabel,
    required String todayLabel,
    required String youLabel,
    required String replyLabel,
    required String sendLabel,
    required String closedNotice,
    required String newTicketLabel,
    required String refreshLabel,
    required bool faView,
  }) {
    final closed = ticket.status == 'CLOSED';
    final shortId =
        ticket.id.length > 8 ? ticket.id.substring(0, 8).toUpperCase() : ticket.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: VelixeoEnDesign.pagePadding,
          children: [
            Text(
              ticket.subject,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              (faView ? 'تیکت شمارهٔ #' : 'Ticket #') + shortId,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 10.5,
                color: VelixeoBrand.muted,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    supportLabel,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF7C919E),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: closed
                        ? const Color(0xFFF0F3F5)
                        : const Color(0xFFFFF4DF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    closed ? closedLabel : waitingLabel,
                    style: TextStyle(
                      fontSize: 9,
                      color: closed
                          ? VelixeoBrand.muted
                          : VelixeoBrand.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                todayLabel,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: Color(0xFF9BADB8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...ticket.messages.map((message) {
              final customer = !message.isAdmin;
              final time = message.createdAt
                  .toLocal()
                  .toString()
                  .substring(11, 16);
              return Align(
                alignment: customer
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.centerEnd,
                child: FractionallySizedBox(
                  widthFactor: .89,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
                    decoration: BoxDecoration(
                      color: customer
                          ? const Color(0xFFEAF7FD)
                          : const Color(0xFFF1F5F8),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(
                          !faView && customer ? 5 : 18,
                        ),
                        topRight: Radius.circular(
                          faView && customer
                              ? 5
                              : (!faView && !customer ? 5 : 18),
                        ),
                        bottomLeft: const Radius.circular(18),
                        bottomRight: const Radius.circular(18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.isAdmin) ...[
                          Text(
                            supportLabel,
                            style: const TextStyle(
                              color: Color(0xFF4C7184),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          message.content,
                          style: TextStyle(
                            color: customer
                                ? const Color(0xFF4B7D96)
                                : const Color(0xFF68818E),
                            fontSize: 11.5,
                            height: 1.75,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          (customer ? youLabel + ' · ' : '') + time,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF91A5B1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (closed) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6F8),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  closedNotice,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.6,
                    color: Color(0xFF718793),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final created = await Navigator.push<SupportTicket>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NewSupportTicketPage(host: widget.host),
                    ),
                  );
                  if (created == null || !context.mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupportTicketPage(
                        host: widget.host,
                        initialTicket: created,
                      ),
                    ),
                  );
                },
                child: Text(newTicketLabel),
              ),
            ] else ...[
              TextField(
                controller: reply,
                minLines: 3,
                maxLines: 6,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: replyLabel,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: busy ? null : send,
                icon: busy
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 17),
                label: Text(sendLabel),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: Text(refreshLabel),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
