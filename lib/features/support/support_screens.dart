import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';
import '../../models/models.dart';

final ticketsProvider = FutureProvider.autoDispose<List<Ticket>>((ref) async => (await ref.watch(repositoryProvider).tickets()).items);

final ticketProvider = FutureProvider.autoDispose.family<Ticket, int>((ref, id) => ref.watch(repositoryProvider).ticket(id));

Color _statusColor(String s) => switch (s) {
      'closed' || 'resolved' => AppColors.success,
      'open' => AppColors.warning,
      _ => AppColors.primary,
    };

class TicketsScreen extends ConsumerWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ticketsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الدعم والشكاوى')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ticket = await showModalBottomSheet<Ticket>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const _NewTicketSheet(),
          );
          ref.invalidate(ticketsProvider);
          if (ticket != null && context.mounted) context.push('/support/${ticket.id}');
        },
        icon: const Icon(Icons.add),
        label: const Text('تذكرة جديدة'),
      ),
      body: switch (async) {
        AsyncValue(:final value?) when value.isEmpty => const EmptyView(
            icon: Icons.forum_outlined,
            title: 'لا توجد تذاكر',
            subtitle: 'لو عندك مشكلة أو استفسار افتح تذكرة وهنرد عليك.',
          ),
        AsyncValue(:final value?) => RefreshIndicator(
            onRefresh: () => ref.refresh(ticketsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: value.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final t = value[i];
                return Card(
                  child: ListTile(
                    title: Text(t.subject, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(dateTime(t.updatedAt)),
                    trailing: StatusChip(t.statusLabel, color: _statusColor(t.status)),
                    onTap: () => context.push('/support/${t.id}'),
                  ),
                );
              },
            ),
          ),
        AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(ticketsProvider)),
        _ => const LoadingView(),
      },
    );
  }
}

class _NewTicketSheet extends ConsumerStatefulWidget {
  const _NewTicketSheet();

  @override
  ConsumerState<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends ConsumerState<_NewTicketSheet> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_subject.text.trim().isEmpty || _message.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final t = await ref.read(repositoryProvider).createTicket(subject: _subject.text.trim(), message: _message.text.trim());
      if (mounted) Navigator.pop(context, t);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('تذكرة جديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(controller: _subject, decoration: const InputDecoration(hintText: 'الموضوع')),
          const SizedBox(height: 12),
          TextField(controller: _message, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: 'اكتب مشكلتك بالتفصيل')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _send, child: _busy ? const Spinner() : const Text('إرسال')),
        ],
      ),
    );
  }
}

class TicketScreen extends ConsumerStatefulWidget {
  const TicketScreen({super.key, required this.ticketId});

  final int ticketId;

  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).replyTicket(widget.ticketId, text);
      _reply.clear();
      ref.invalidate(ticketProvider(widget.ticketId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ticketProvider(widget.ticketId));

    return Scaffold(
      appBar: AppBar(title: Text(async.value?.subject ?? 'التذكرة')),
      body: Column(
        children: [
          Expanded(
            child: switch (async) {
              AsyncValue(:final value?) => RefreshIndicator(
                  onRefresh: () => ref.refresh(ticketProvider(widget.ticketId).future),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final m in value.messages)
                        Align(
                          alignment: m.isMine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                            decoration: BoxDecoration(
                              color: m.isMine ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!m.isMine) Text(m.sender, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                                Text(m.body),
                                const SizedBox(height: 4),
                                Text(dateTime(m.createdAt), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(ticketProvider(widget.ticketId))),
              _ => const LoadingView(),
            },
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'اكتب ردك…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    icon: _busy ? const Spinner() : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
