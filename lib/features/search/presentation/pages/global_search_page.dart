import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/repositories/global_search_repository.dart';
import '../../../../data/repositories/appointment_repository.dart';
import '../../../../data/repositories/customer_repository.dart';
import '../../../../data/repositories/employee_repository.dart';
import '../../../../data/repositories/service_repository.dart';
import '../../../../data/repositories/supabase_repository.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late GlobalSearchRepository _repository;
  AppDatabase? _database;
  String? _accountId;
  Timer? _debounce;
  List<GlobalSearchResult> _results = const [];
  List<String> _recent = const [];
  GlobalSearchType? _filter;
  bool _loading = false;
  bool _initialized = false;
  bool _searchUnavailable = false;
  int _requestId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _database = context.read<AppDatabase?>();
    final database = _database;
    if (database == null) {
      // Production currently has no normalized global-search repository.
      // Keep the route usable without inventing local/demo results.
      _searchUnavailable = true;
      return;
    }
    _accountId = database.currentAccessAccount.id;
    database.addListener(_handleDatabaseChanged);
    _repository = GlobalSearchRepository(
      database,
      customerRepository: context.read<CustomerRepository>(),
      employeeRepository: context.read<EmployeeRepository>(),
      serviceRepository: context.read<ServiceRepository>(),
      appointmentRepository: context.read<AppointmentRepository>(),
      remote: context.read<SupabaseRepository?>(),
    );
    _loadRecent();
  }

  void _handleDatabaseChanged() {
    final database = _database;
    if (database == null) return;
    final nextAccountId = database.currentAccessAccount.id;
    if (nextAccountId != _accountId) {
      _accountId = nextAccountId;
      _debounce?.cancel();
      _requestId++;
      _controller.clear();
      if (mounted) {
        setState(() {
          _results = const [];
          _filter = null;
          _loading = false;
        });
        _loadRecent();
      }
      return;
    }
    if (_controller.text.trim().isNotEmpty && mounted) {
      _onQueryChanged(_controller.text);
    }
  }

  @override
  void dispose() {
    _database?.removeListener(_handleDatabaseChanged);
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final values = await _repository.recentSearches();
      if (mounted) setState(() => _recent = values);
    } catch (_) {}
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final request = ++_requestId;
    setState(() {
      _loading = value.trim().isNotEmpty;
      if (value.trim().isEmpty) _results = const [];
    });
    if (value.trim().isEmpty) return;

    _debounce = Timer(const Duration(milliseconds: 260), () async {
      try {
        final values = await _repository.search(value);
        if (!mounted || request != _requestId) return;
        setState(() {
          _results = values;
          _loading = false;
        });
      } catch (error) {
        if (!mounted || request != _requestId) return;
        setState(() {
          _results = const [];
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('جست‌وجو انجام نشد: $error')),
        );
      }
    });
  }

  void _useQuery(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _focusNode.requestFocus();
    _onQueryChanged(value);
  }

  Future<void> _submit() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    await _repository.rememberSearch(query);
    await _loadRecent();
    _onQueryChanged(query);
  }

  Future<void> _clearHistory() async {
    await _repository.clearHistory();
    if (mounted) setState(() => _recent = const []);
  }

  Future<void> _openResult(GlobalSearchResult result) async {
    await _repository.rememberSearch(_controller.text);
    await _loadRecent();
    if (!mounted) return;
    final database = _database;
    if (database == null || !canOpenGlobalSearchResult(database, result)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دسترسی شما به این نتیجه مجاز نیست.')),
      );
      return;
    }
    if (result.isRemote || result.showDetailsPage) {
      context.push('/search/result', extra: result);
    } else {
      context.push(result.route);
    }
  }

  List<GlobalSearchResult> get _visibleResults =>
      _filter == null ? _results : _results.where((item) => item.type == _filter).toList();

  Map<GlobalSearchType, List<GlobalSearchResult>> get _resultGroups {
    final groups = <GlobalSearchType, List<GlobalSearchResult>>{};
    for (final result in _visibleResults) {
      groups.putIfAbsent(result.type, () => []).add(result);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final hasQuery = _controller.text.trim().isNotEmpty;

    return PageScaffold(
      title: 'جست‌وجوی سراسری',
      subtitle: 'جست‌وجو در اطلاعات و سوابق DateTime',
      icon: Icons.search_rounded,
      showGlobalSearch: false,
      scrollable: false,
      child: _searchUnavailable
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'جست‌وجوی سراسری در این نسخه به مخزن داده آنلاین متصل نشده است. برای جلوگیری از نمایش اطلاعات ساختگی، نتیجه آزمایشی نمایش داده نمی‌شود.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: pal.primaryBright, size: 23),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      hintText: 'نام، شماره، کد نوبت، خدمت یا مبلغ را جست‌وجو کنید...',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (hasQuery)
                  IconButton(
                    tooltip: 'پاک‌کردن عبارت',
                    onPressed: () {
                      _controller.clear();
                      _onQueryChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: const Text('همه'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final type in GlobalSearchType.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      label: Text(type.pluralLabel),
                      selected: _filter == type,
                      onSelected: (_) => setState(() => _filter = type),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : !hasQuery
                    ? _buildSuggestions(pal)
                    : _visibleResults.isEmpty
                        ? _buildEmptyState(pal)
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 28),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  '${_visibleResults.length} نتیجه پیدا شد',
                                  style: TextStyle(fontSize: 12, color: pal.textMuted, fontWeight: FontWeight.w600),
                                ),
                              ),
                              for (final entry in _resultGroups.entries) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                                  child: Row(
                                    children: [
                                      Icon(_iconFor(entry.key), size: 17, color: pal.primaryBright),
                                      const SizedBox(width: 7),
                                      Text(
                                        entry.key.pluralLabel,
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: pal.textPrimary),
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        '${entry.value.length}',
                                        style: TextStyle(fontSize: 11, color: pal.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                for (final result in entry.value)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _ResultTile(
                                      result: result,
                                      icon: _iconFor(result.type),
                                      onTap: () => _openResult(result),
                                    ),
                                  ),
                              ],
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(AppPalette pal) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        if (_recent.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: pal.textMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text('جست‌وجوهای اخیر', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: pal.textPrimary)),
              ),
              TextButton.icon(
                onPressed: _clearHistory,
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('پاک‌کردن تاریخچه'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in _recent)
                ActionChip(
                  avatar: const Icon(Icons.history_rounded, size: 15),
                  label: Text(item),
                  onPressed: () => _useQuery(item),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        Text('پیشنهادهای جست‌وجو', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: pal.textPrimary)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in const ['سارا', 'ژلیش', 'OT-', '0912', 'اجاره'])
              ActionChip(
                avatar: const Icon(Icons.trending_up_rounded, size: 15),
                label: Text(item),
                onPressed: () => _useQuery(item),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Center(
          child: Column(
            children: [
              Icon(Icons.manage_search_rounded, size: 54, color: pal.textMuted.withValues(alpha: 0.65)),
              const SizedBox(height: 8),
              Text(
                'برای شروع، نام یا شماره‌ای وارد کنید',
                style: TextStyle(fontSize: 12, color: pal.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppPalette pal) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 58, color: pal.textMuted),
            const SizedBox(height: 12),
            Text('نتیجه‌ای پیدا نشد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: pal.textPrimary)),
            const SizedBox(height: 6),
            Text(
              'عبارت را کوتاه‌تر کنید یا فیلتر نوع اطلاعات را تغییر دهید.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: pal.textMuted),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => setState(() => _filter = null),
              child: const Text('حذف فیلتر نوع اطلاعات'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(GlobalSearchType type) => switch (type) {
        GlobalSearchType.customer => Icons.people_alt_outlined,
        GlobalSearchType.employee => Icons.badge_outlined,
        GlobalSearchType.service => Icons.content_cut_rounded,
        GlobalSearchType.category => Icons.category_outlined,
        GlobalSearchType.appointment => Icons.event_note_rounded,
        GlobalSearchType.transaction => Icons.account_balance_wallet_outlined,
        GlobalSearchType.document => Icons.description_outlined,
        GlobalSearchType.activity => Icons.history_rounded,
      };
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.icon, required this.onTap});

  final GlobalSearchResult result;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: pal.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: pal.primaryBright, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: pal.textPrimary)),
                  if (result.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(result.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: pal.textSecondary)),
                  ],
                  if (result.details.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(result.details, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: pal.textMuted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_left_rounded, color: pal.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}


class GlobalSearchResultDetailsPage extends StatelessWidget {
  const GlobalSearchResultDetailsPage({super.key, required this.result});

  final GlobalSearchResult result;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final database = context.watch<AppDatabase>();
    if (!canOpenGlobalSearchResult(database, result)) {
      return PageScaffold(
        title: 'دسترسی محدود',
        subtitle: 'مجوز مشاهده این نتیجه تغییر کرده است',
        icon: Icons.lock_outline_rounded,
        showGlobalSearch: false,
        child: const Center(child: Text('این نتیجه دیگر برای حساب فعال قابل مشاهده نیست.')),
      );
    }
    return PageScaffold(
      title: result.type.label,
      subtitle: 'جزئیات نتیجه جست‌وجو',
      icon: Icons.description_outlined,
      showGlobalSearch: false,
      child: AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(result.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: pal.textPrimary)),
            if (result.subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(result.subtitle, style: TextStyle(fontSize: 12, color: pal.textSecondary)),
            ],
            if (result.details.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(result.details, style: TextStyle(fontSize: 12, height: 1.8, color: pal.textPrimary)),
            ],
            const SizedBox(height: 16),
            Text('شناسه: ${result.id}', textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 10, color: pal.textMuted)),
            if (result.date != null) ...[
              const SizedBox(height: 6),
              Text('تاریخ: ${result.date}', style: TextStyle(fontSize: 10, color: pal.textMuted)),
            ],
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('بازگشت به نتایج'),
            ),
          ],
        ),
      ),
    );
  }
}
