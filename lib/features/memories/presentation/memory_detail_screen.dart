import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_spacing.dart';
import '../data/memory_model.dart';
import '../data/memory_repository.dart';

class MemoryDetailScreen extends ConsumerStatefulWidget {
  final String memoryId;

  const MemoryDetailScreen({super.key, required this.memoryId});

  @override
  ConsumerState<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends ConsumerState<MemoryDetailScreen> {
  MemoryModel? _memory;
  bool _isLoading = true;
  bool _isEditing = false;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _loadMemory();
  }

  Future<void> _loadMemory() async {
    final repo = ref.read(memoryRepositoryProvider);
    final m = await repo.getMemoryById(widget.memoryId);
    if (mounted) {
      setState(() {
        _memory = m;
        _isLoading = false;
        if (m != null) {
          _titleController.text = m.title;
          _contentController.text = m.originalContent;
        }
      });
    }
  }

  Future<void> _saveEdits() async {
    if (_memory == null) return;
    final updated = _memory!.copyWith(
      title: _titleController.text.trim(),
      originalContent: _contentController.text.trim(),
      updatedAt: DateTime.now(),
    );

    await ref.read(memoryRepositoryProvider).updateMemory(updated);
    ref.invalidate(memoriesStreamProvider);

    setState(() {
      _memory = updated;
      _isEditing = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memory updated')),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_memory == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Memory Not Found')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('This memory does not exist or was deleted.'),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    final memory = _memory!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Memory' : 'Memory Detail'),
        actions: [
          if (!_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: () {
                Share.share('${memory.title}\n\n${memory.originalContent}');
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => setState(() => _isEditing = true),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              tooltip: 'Delete',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Memory'),
                    content: const Text('Are you sure you want to remove this memory?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await ref.read(memoryRepositoryProvider).deleteMemory(memory.id);
                  ref.invalidate(memoriesStreamProvider);
                  if (mounted) context.pop();
                }
              },
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.check_rounded),
              tooltip: 'Save',
              onPressed: _saveEdits,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Metadata chips
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                Chip(
                  label: Text(memory.category),
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  labelStyle: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Chip(
                  label: Text(memory.memoryType.replaceAll('_', ' ')),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Title
            if (_isEditing)
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              )
            else
              Text(
                memory.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: AppSpacing.lg),

            // Content
            Text(
              'Captured Content',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_isEditing)
              TextField(
                controller: _contentController,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Original Content'),
              )
            else
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Text(
                  memory.originalContent,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),

            // Details section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    if (memory.associatedPerson != null)
                      _buildDetailRow(Icons.person_rounded, 'Person', memory.associatedPerson!),
                    if (memory.associatedDate != null)
                      _buildDetailRow(Icons.event_rounded, 'Date', DateFormat('MMMM d, y • h:mm a').format(memory.associatedDate!)),
                    _buildDetailRow(Icons.access_time_rounded, 'Created', DateFormat('MMM d, y • h:mm a').format(memory.createdAt)),
                    if (memory.tags.isNotEmpty)
                      _buildDetailRow(Icons.tag_rounded, 'Tags', memory.tags.join(', ')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Text('$label:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
