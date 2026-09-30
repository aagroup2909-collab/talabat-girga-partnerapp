import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../state/auth.dart';

/// قائمة المستندات المطلوبة مع رفع كل واحد (كاميرا أو معرض).
class DocumentsSection extends ConsumerStatefulWidget {
  const DocumentsSection({super.key});

  @override
  ConsumerState<DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends ConsumerState<DocumentsSection> {
  DocumentType? _uploading;

  Future<void> _pick(DocumentType type) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(type.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('تصوير بالكاميرا'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من المعرض'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    final file = await ImagePicker().pickImage(source: source, maxWidth: 1800, imageQuality: 80);
    if (file == null) return;

    setState(() => _uploading = type);
    try {
      await ref.read(repositoryProvider).uploadDocument(type, file.path);
      await ref.read(authProvider.notifier).refresh();
      if (mounted) showMessage(context, 'تم رفع ${type.label}.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(authProvider).user?.driver;

    return Card(
      child: Column(
        children: [
          for (final (i, type) in DocumentType.values.indexed) ...[
            if (i > 0) const Divider(),
            _row(type, driver?.document(type)),
          ],
        ],
      ),
    );
  }

  Widget _row(DocumentType type, DriverDocument? doc) {
    final (label, color) = switch (doc?.status) {
      null => ('مطلوب', AppColors.muted),
      'approved' => ('مقبول', AppColors.success),
      'rejected' => ('مرفوض', AppColors.danger),
      _ => ('تم الرفع', AppColors.warning),
    };

    return ListTile(
      leading: doc?.url != null
          ? NetImage(doc!.url, width: 48, height: 48, radius: 8, icon: Icons.description_outlined)
          : Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.upload_file, color: AppColors.primary),
            ),
      title: Text(type.label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: doc?.notes != null && doc!.notes!.isNotEmpty
          ? Text(doc.notes!, style: const TextStyle(color: AppColors.danger))
          : Align(alignment: AlignmentDirectional.centerStart, child: StatusChip(label, color: color)),
      trailing: _uploading == type
          ? const Spinner(color: AppColors.primary)
          : TextButton(
              onPressed: _uploading != null ? null : () => _pick(type),
              child: Text(doc == null ? 'رفع' : 'تغيير'),
            ),
    );
  }
}
