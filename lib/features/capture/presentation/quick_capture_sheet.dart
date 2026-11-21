import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:kee/core/constants/app_spacing.dart';
import 'package:kee/core/intelligence/deterministic_classifier.dart';
import 'package:kee/features/memories/data/memory_model.dart';
import 'package:kee/features/memories/data/memory_repository.dart';
import 'package:kee/features/reminders/data/task_model.dart';
import 'package:kee/features/reminders/data/reminder_model.dart';
import 'package:kee/features/reminders/data/reminder_repository.dart';

class QuickCaptureSheet extends ConsumerStatefulWidget {
  final String? initialText;

  const QuickCaptureSheet({super.key, this.initialText});

  static Future<void> show(BuildContext context, {String? initialText}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QuickCaptureSheet(initialText: initialText),
    );
  }

  @override
  ConsumerState<QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends ConsumerState<QuickCaptureSheet> {
  late final TextEditingController _controller;
  ClassificationResult? _classification;
  DateTime? _overrideDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _analyzeInput(widget.initialText!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _analyzeInput(String text) {
    if (text.trim().isEmpty) {
      setState(() {
        _classification = null;
        _overrideDate = null;
      });
      return;
    }

    final result = DeterministicClassifier.classify(text);
    setState(() {
      _classification = result;
      _overrideDate = result.associatedDate;
    });
  }

  Future<void> _saveCapture() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final classification = _classification ?? DeterministicClassifier.classify(text);
      final uuid = const Uuid().v4();
      final now = DateTime.now();

      final effectiveDate = _overrideDate ?? classification.associatedDate;

      // 1. Save Primary Memory
      final memory = MemoryModel(
        id: uuid,
        title: classification.title,
        originalContent: text,
        memoryType: classification.memoryType,
        category: classification.category,
        tags: classification.tags,
        associatedPerson: classification.associatedPerson,
        associatedDate: effectiveDate,
        createdAt: now,
        updatedAt: now,
      );

      await ref.read(memoryRepositoryProvider).createMemory(memory);

      // 2. If it's a task or commitment, also create Task
      if (classification.shouldCreateTask) {
        final taskId = const Uuid().v4();
        final task = TaskModel(
          id: taskId,
          memoryId: memory.id,
          title: classification.title,
          description: text,
          dueDate: effectiveDate,
          createdAt: now,
          updatedAt: now,
        );
        await ref.read(reminderRepositoryProvider).createTask(task);

        // 3. If there is a scheduled date/time, also create Reminder
        if (effectiveDate != null && classification.shouldCreateReminder) {
          final reminderId = const Uuid().v4();
          final reminder = ReminderModel(
            id: reminderId,
            taskId: taskId,
            memoryId: memory.id,
            title: classification.title,
            scheduledAt: effectiveDate,
            recurrenceRule: classification.recurrenceRule,
            createdAt: now,
            updatedAt: now,
          );
          await ref.read(reminderRepositoryProvider).createReminder(reminder);
        }
      }

      // Refresh providers
      ref.invalidate(memoriesStreamProvider);
      ref.invalidate(tasksStreamProvider);
      ref.invalidate(remindersStreamProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${classification.category} (${classification.memoryType})'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.lg,
        bottom: bottomInset + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withOpacity(0.5),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Capture What Matters',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Your memory. Extended.',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.3,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Input field
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            onChanged: _analyzeInput,
            decoration: const InputDecoration(
              hintText: 'e.g. Call David tomorrow, I prefer black coffee, warranty expires in December...',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Live Classification & Date Preview
          if (_classification != null) ...[
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildTypeBadge(theme, _classification!.memoryType),
                _buildCategoryBadge(theme, _classification!.category),
                if (_classification!.associatedPerson != null)
                  _buildPersonBadge(theme, _classification!.associatedPerson!),
                if (_overrideDate != null)
                  _buildDateBadge(theme, _overrideDate!),
              ],
            ),
            if (_classification!.clarificationNeeded != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _classification!.clarificationNeeded!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
          ],

          // Action row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                label: Text(
                  _overrideDate != null
                      ? DateFormat('MMM d, h:mm a').format(_overrideDate!)
                      : 'Set Date',
                  style: const TextStyle(fontSize: 13),
                ),
                onPressed: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _overrideDate ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (pickedDate != null && mounted) {
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_overrideDate ?? DateTime.now()),
                    );
                    if (pickedTime != null) {
                      setState(() {
                        _overrideDate = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                      });
                    }
                  }
                },
              ),
              ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Remember'),
                onPressed: _isSaving ? null : _saveCapture,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(ThemeData theme, String type) {
    final label = type.replaceAll('_', ' ').toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(ThemeData theme, String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        category,
        style: TextStyle(
          fontSize: 11,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildPersonBadge(ThemeData theme, String person) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_rounded, size: 12, color: Colors.blue),
          const SizedBox(width: 4),
          Text(
            person,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateBadge(ThemeData theme, DateTime date) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time_rounded, size: 12, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            DateFormat('MMM d, h:mm a').format(date),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
