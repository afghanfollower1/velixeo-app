import 'package:flutter/material.dart';

import '../core/api_service.dart';
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
    final subject = TextEditingController();
    final message = TextEditingController();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(18, 4, 18, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('تیکت جدید', 'New support ticket'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(controller: subject, maxLength: 180, decoration: InputDecoration(labelText: t('موضوع', 'Subject'), prefixIcon: const Icon(Icons.subject_rounded))),
            const SizedBox(height: 10),
            TextField(controller: message, minLines: 4, maxLines: 7, maxLength: 5000, decoration: InputDecoration(labelText: t('پیام', 'Message'), alignLabelWithHint: true)),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () {
                if (subject.text.trim().length < 3 || message.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              child: Text(t('ارسال تیکت', 'Send ticket')),
            ),
          ],
        ),
      ),
    );
    if (result != true) {
      subject.dispose();
      message.dispose();
      return;
    }
    setState(() => busy = true);
    try {
      final ticket = await widget.host.api.createSupportTicket(subject: subject.text, message: message.text);
      if (mounted) setState(() => tickets = [ticket, ...tickets.where((item) => item.id != ticket.id)]);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorLabel(e.code))));
    } finally {
      subject.dispose();
      message.dispose();
      if (mounted) setState(() => busy = false);
    }
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
      case 'PENDING_USER': return const Color(0xFF158365);
      case 'CLOSED': return const Color(0xFF74818B);
      default: return const Color(0xFFEFAF38);
    }
  }

  @override
  Widget build(BuildContext context) {
    return fa
        ? Directionality(
            textDirection: TextDirection.rtl,
            child: _buildSupportScaffold(context),
          )
        : Directionality(
            textDirection: TextDirection.ltr,
            child: _buildSupportScaffold(context),
          );
  }

  Widget _buildSupportScaffold(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(t('پشتیبانی', 'Support')),
          actions: [IconButton(onPressed: loading ? null : load, icon: const Icon(Icons.refresh_rounded))],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: busy ? null : newTicket,
          icon: const Icon(Icons.add_comment_outlined),
          label: Text(t('تیکت جدید', 'New ticket')),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFFEAF6FF), borderRadius: BorderRadius.circular(18)),
                      child: Row(
                        children: [
                          const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.support_agent_rounded, color: Color(0xFF38BDF8))),
                          const SizedBox(width: 12),
                          Expanded(child: Text(t('پیام شما و پاسخ ادمین در همین تیکت ذخیره می‌شود.', 'Your messages and admin replies stay together in each ticket.'), style: const TextStyle(color: Color(0xFF315B78), height: 1.4))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
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
                                            Text('${statusLabel(ticket.status)} • ${ticket.messages.length} ${t('پیام', 'messages')}', style: const TextStyle(fontSize: 11, color: Color(0xFF74818B))),
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
  Widget build(BuildContext context) {
    return fa
        ? Directionality(
            textDirection: TextDirection.rtl,
            child: _buildTicketScaffold(context),
          )
        : Directionality(
            textDirection: TextDirection.ltr,
            child: _buildTicketScaffold(context),
          );
  }

  Widget _buildTicketScaffold(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(ticket.subject), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: ticket.messages.length,
                itemBuilder: (context, index) {
                  final message = ticket.messages[index];
                  return Align(
                    alignment: message.isAdmin ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: message.isAdmin ? const Color(0xFFF0F5F8) : const Color(0xFFE4F4FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message.isAdmin ? t('پشتیبانی VELIXEO', 'VELIXEO Support') : t('شما', 'You'), style: TextStyle(fontSize: 10, color: message.isAdmin ? const Color(0xFF74818B) : const Color(0xFF38BDF8), fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(message.content, style: const TextStyle(height: 1.45)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: ticket.status == 'CLOSED'
                    ? Text(t('این تیکت بسته شده است.', 'This ticket is closed.'), style: const TextStyle(color: Color(0xFF74818B)))
                    : Row(
                        children: [
                          Expanded(child: TextField(controller: reply, minLines: 1, maxLines: 4, decoration: InputDecoration(hintText: t('پاسخ شما...', 'Your reply...')))),
                          const SizedBox(width: 8),
                          IconButton.filled(onPressed: busy ? null : send, icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
