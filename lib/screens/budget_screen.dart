import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../models/expense_model.dart';
import '../models/user_model.dart';
import '../widgets/common_widgets.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final group = auth.currentGroup;
    if (group == null) return const SizedBox.shrink();

    return Column(
      children: [
        // Tab bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle:
                  GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
              tabs: const [Tab(text: 'My Expenses'), Tab(text: 'Friends')],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _MyExpensesTab(),
              _FriendsExpensesTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── My Expenses Tab ──────────────────────────────────────────────────────────
class _MyExpensesTab extends StatefulWidget {
  const _MyExpensesTab();

  @override
  State<_MyExpensesTab> createState() => _MyExpensesTabState();
}

class _MyExpensesTabState extends State<_MyExpensesTab> {
  final BudgetService _budgetService = BudgetService();
  bool _showWeekly = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser!;
    final group = auth.currentGroup!;
    final month = DateTime.now();
    final weekStart = BudgetService.currentWeekStart;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Toggle
              Row(
                children: [
                  _PeriodToggle(
                    isWeekly: _showWeekly,
                    onChanged: (v) => setState(() => _showWeekly = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Expense stream
              StreamBuilder<List<ExpenseModel>>(
                stream: _showWeekly
                    ? _budgetService.getMyWeeklyExpenses(
                        groupId: group.groupId,
                        uid: user.uid,
                        weekStart: weekStart,
                      )
                    : _budgetService.getMyMonthlyExpenses(
                        groupId: group.groupId,
                        uid: user.uid,
                        month: month,
                      ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary, strokeWidth: 2));
                  }
                  final expenses = snapshot.data ?? [];
                  final total = BudgetService.totalFromList(expenses);
                  final typeSummary =
                      BudgetService.typeSummaryFromList(expenses);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Total card
                      GradientCard(
                        colors: [
                          AppTheme.accent.withOpacity(0.12),
                          AppTheme.surfaceElevated
                        ],
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _showWeekly
                                        ? 'This Week'
                                        : 'This Month',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '৳${total.toStringAsFixed(2)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${expenses.length} entries',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Type summary
                      if (typeSummary.isNotEmpty) ...[
                        SectionHeader(title: 'By Category Type'),
                        const SizedBox(height: 10),
                        ...typeSummary.entries.map((entry) {
                          final pct = total > 0
                              ? (entry.value / total).clamp(0.0, 1.0)
                              : 0.0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _TypeBar(
                              type: entry.key,
                              amount: entry.value,
                              percentage: pct,
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                      ],

                      // Expense list
                      SectionHeader(title: 'All Expenses'),
                      const SizedBox(height: 10),
                      if (expenses.isEmpty)
                        const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No expenses yet',
                          subtitle: 'Tap + to add your first expense',
                        )
                      else
                        ...expenses.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ExpenseTile(
                                expense: e,
                                onDelete: () async {
                                  await _budgetService.deleteExpense(
                                      group.groupId, e.id);
                                },
                              ),
                            )),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        // FAB
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add_expense',
            onPressed: () => _showAddExpenseSheet(context),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            elevation: 4,
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'Add Expense',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddExpenseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddExpenseSheet(),
    );
  }
}

// ─── Add Expense Bottom Sheet ─────────────────────────────────────────────────
class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet();

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final BudgetService _budgetService = BudgetService();
  final _amountCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _selectedType;
  DateTime _date = DateTime.now();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _categoryCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser!;
    final group = auth.currentGroup!;

    setState(() => _error = null);

    final amountText = _amountCtrl.text.trim();
    if (amountText.isEmpty) {
      setState(() => _error = 'Please enter an amount.');
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Please enter a valid amount.');
      return;
    }
    if (_selectedType == null) {
      setState(() => _error = 'Please select a category type.');
      return;
    }
    // Category name is optional — fall back to type name if empty
    final categoryName = _categoryCtrl.text.trim().isEmpty
        ? _selectedType!
        : _categoryCtrl.text.trim();

    setState(() => _isLoading = true);

    final expense = ExpenseModel(
      id: '',
      uid: user.uid,
      groupId: group.groupId,
      amount: amount,
      categoryName: categoryName,
      categoryType: _selectedType!,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      date: _date,
      createdAt: DateTime.now(),
    );

    final err = await _budgetService.addExpense(expense);
    if (mounted) {
      setState(() => _isLoading = false);
      if (err != null) {
        setState(() => _error = err);
      } else {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              surface: AppTheme.surfaceElevated,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final types = auth.currentGroup?.expenseTypes ?? [];
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: LoadingOverlay(
        isLoading: _isLoading,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Add Expense',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 20),

              // Date
              _Label('Date'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 18, color: AppTheme.textSecondary),
                      const SizedBox(width: 10),
                      Text(
                        '${_date.day}/${_date.month}/${_date.year}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Note
              _Label('Note (optional)'),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  hintText: 'Any notes...',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 14),

              // Category name
              _Label('Category Name (optional)'),
              const SizedBox(height: 8),
              TextField(
                controller: _categoryCtrl,
                decoration: const InputDecoration(
                  hintText: 'e.g. Lunch at Dhanmondi (or leave blank)',
                  prefixIcon: Icon(Icons.label_outline_rounded),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),

              // Category type
              _Label('Category Type'),
              const SizedBox(height: 8),
              if (types.isEmpty)
                Text(
                  'No types set. Ask your admin to add types.',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppTheme.textHint),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: types.map((type) {
                    final selected = _selectedType == type;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedType = type),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.divider,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          type,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: selected
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 14),

              // Amount
              _Label('Amount (৳)'),
              const SizedBox(height: 8),
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.currency_exchange_rounded),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorBox(_error!),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Save Expense'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Friends Expenses Tab ─────────────────────────────────────────────────────
class _FriendsExpensesTab extends StatefulWidget {
  const _FriendsExpensesTab();

  @override
  State<_FriendsExpensesTab> createState() => _FriendsExpensesTabState();
}

class _FriendsExpensesTabState extends State<_FriendsExpensesTab> {
  final BudgetService _budgetService = BudgetService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser!;
    final group = auth.currentGroup!;
    final otherUids =
        group.memberUids.where((uid) => uid != user.uid).toList();

    if (otherUids.isEmpty) {
      return const EmptyState(
        icon: Icons.group_outlined,
        title: 'No friends yet',
        subtitle: 'Share your invite code to add friends',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: otherUids.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final uid = otherUids[index];
        return FutureBuilder<DocumentSnapshot>(
          future: _db.collection('users').doc(uid).get(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 80,
                child: Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.primary, strokeWidth: 2),
                ),
              );
            }
            final friendUser =
                UserModel.fromMap(snap.data!.data() as Map<String, dynamic>);
            return _FriendBudgetCard(
              friend: friendUser,
              groupId: group.groupId,
            );
          },
        );
      },
    );
  }
}

class _FriendBudgetCard extends StatefulWidget {
  final UserModel friend;
  final String groupId;

  const _FriendBudgetCard(
      {required this.friend, required this.groupId});

  @override
  State<_FriendBudgetCard> createState() => _FriendBudgetCardState();
}

class _FriendBudgetCardState extends State<_FriendBudgetCard> {
  final BudgetService _budgetService = BudgetService();
  bool _expanded = false;
  Map<String, double>? _summary;
  double _total = 0;
  bool _loading = false;

  Future<void> _loadSummary() async {
    if (_summary != null) return;
    setState(() => _loading = true);
    final summary = await _budgetService.getFriendMonthlyTypeSummary(
      groupId: widget.groupId,
      uid: widget.friend.uid,
      month: DateTime.now(),
    );
    final total = summary.values.fold(0.0, (a, b) => a + b);
    if (mounted) {
      setState(() {
        _summary = summary;
        _total = total;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          // Header tap row
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              setState(() => _expanded = !_expanded);
              if (_expanded) await _loadSummary();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        widget.friend.username.isNotEmpty
                            ? widget.friend.username[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.friend.username,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (_summary != null)
                          Text(
                            'Total this month: ৳${_total.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textHint,
                  ),
                ],
              ),
            ),
          ),

          // Expanded summary
          if (_expanded)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                            color: AppTheme.primary, strokeWidth: 2),
                      ),
                    )
                  : _summary == null || _summary!.isEmpty
                      ? Text(
                          'No expenses this month.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppTheme.textHint,
                          ),
                        )
                      : Column(
                          children: _summary!.entries
                              .map((entry) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: _TypeBar(
                                      type: entry.key,
                                      amount: entry.value,
                                      percentage: _total > 0
                                          ? (entry.value / _total)
                                              .clamp(0.0, 1.0)
                                          : 0,
                                    ),
                                  ))
                              .toList(),
                        ),
            ),
        ],
      ),
    );
  }
}

// ─── Shared small widgets ─────────────────────────────────────────────────────
class _TypeBar extends StatelessWidget {
  final String type;
  final double amount;
  final double percentage;

  const _TypeBar(
      {required this.type,
      required this.amount,
      required this.percentage});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              type,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              '৳${amount.toStringAsFixed(0)}',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage,
            backgroundColor: AppTheme.surfaceHighlight,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            minHeight: 5,
          ),
        ),
      ],
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final ExpenseModel expense;
  final VoidCallback onDelete;

  const _ExpenseTile({required this.expense, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                expense.categoryType.isNotEmpty
                    ? expense.categoryType[0]
                    : '?',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.categoryName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceHighlight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        expense.categoryType,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: AppTheme.textHint,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${expense.date.day}/${expense.date.month}/${expense.date.year}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textHint,
                      ),
                    ),
                  ],
                ),
                if (expense.note != null && expense.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      expense.note!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textHint,
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '৳${expense.amount.toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _confirmDelete(context),
                child: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: AppTheme.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Delete Expense?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will permanently remove "${expense.categoryName}".',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  final bool isWeekly;
  final void Function(bool) onChanged;

  const _PeriodToggle({required this.isWeekly, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleBtn(
            label: 'Monthly',
            selected: !isWeekly,
            onTap: () => onChanged(false),
          ),
          _ToggleBtn(
            label: 'Weekly',
            selected: isWeekly,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: AppTheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
