import 'package:flutter/material.dart';

// 💡 فكرة جديدة: عنوان + ملاحظات، بدون مجلد
class IdeaDialog extends StatefulWidget {
  const IdeaDialog({super.key});

  @override
  State<IdeaDialog> createState() => _IdeaDialogState();
}

class _IdeaDialogState extends State<IdeaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (
      title: _title.text.trim(),
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('فكرة جديدة 💡'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'الفكرة',
                  hintText: 'مثلاً: تطبيق يذكّرني أسقي النباتات',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'اكتب الفكرة'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: '📝 ملاحظات',
                  hintText: 'ليش الفكرة حلوة؟ وش تحتاج؟ أول خطوة؟',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _save, child: const Text('احفظ الفكرة')),
      ],
    );
  }
}
