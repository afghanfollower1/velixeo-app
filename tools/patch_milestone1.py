from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'[{label}] expected source fragment not found:\n{old[:260]}')
    return text.replace(old, new, 1)


# ---------------- Backend auth/profile hardening ----------------
p = Path('backend/src/index.ts')
s = p.read_text(encoding='utf-8')

s = replace_once(
    s,
    "    fullName: z.string().trim().min(2).max(120).optional(),\n",
    "    fullName: z.string().trim().min(2).max(120),\n",
    'backend-required-full-name',
)

preference_block = """const preferenceSchema = z
  .object({
    locale: z.enum(['FA', 'EN']).optional(),
    displayCurrency: z.enum(['AFN', 'USD', 'TOMAN']).optional(),
  })
  .refine((data) => data.locale !== undefined || data.displayCurrency !== undefined, {
    message: 'no_changes_requested',
  });
"""
profile_schemas = preference_block + """

const profileSchema = z.object({
  fullName: z.string().trim().min(2).max(120),
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1).max(128),
  newPassword: z.string().min(8).max(128),
});
"""
s = replace_once(s, preference_block, profile_schemas, 'backend-profile-schemas')

s = replace_once(
    s,
    "      fullName: parsed.data.fullName?.trim() || null,\n",
    "      fullName: parsed.data.fullName.trim(),\n",
    'backend-register-name',
)

preferences_endpoint = """app.patch(
  '/api/v1/me/preferences',
  { preHandler: authenticate },
  async (request, reply) => {
    const parsed = preferenceSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    const claims = request.user as JwtClaims;
    const user = await prisma.user.update({
      where: { id: claims.sub },
      data: {
        locale: parsed.data.locale as AppLocale | undefined,
        displayCurrency: parsed.data.displayCurrency as DisplayCurrency | undefined,
      },
    });
    return { user: publicUser(user) };
  },
);
"""
profile_endpoints = preferences_endpoint + """

app.patch(
  '/api/v1/me/profile',
  { preHandler: authenticate },
  async (request, reply) => {
    const parsed = profileSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    const claims = request.user as JwtClaims;
    const user = await prisma.user.update({
      where: { id: claims.sub },
      data: { fullName: parsed.data.fullName },
    });
    return { user: publicUser(user) };
  },
);

app.post(
  '/api/v1/me/change-password',
  { preHandler: authenticate },
  async (request, reply) => {
    const parsed = changePasswordSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    const claims = request.user as JwtClaims;
    const user = await prisma.user.findUnique({ where: { id: claims.sub } });
    if (!user) return reply.code(404).send({ error: 'user_not_found' });

    const matches = await bcrypt.compare(parsed.data.currentPassword, user.passwordHash);
    if (!matches) return reply.code(400).send({ error: 'incorrect_current_password' });
    if (parsed.data.currentPassword == parsed.data.newPassword) {
      return reply.code(400).send({ error: 'new_password_must_differ' });
    }

    const passwordHash = await bcrypt.hash(parsed.data.newPassword, 12);
    await prisma.user.update({
      where: { id: claims.sub },
      data: { passwordHash },
    });
    return { ok: true };
  },
);
"""
s = replace_once(s, preferences_endpoint, profile_endpoints, 'backend-profile-endpoints')
p.write_text(s, encoding='utf-8')


# ---------------- Flutter API methods ----------------
p = Path('lib/core/api_service.dart')
s = p.read_text(encoding='utf-8')

api_tail = """  Future<AppUser> updatePreferences({AppLang? language, DisplayCurrency? currency}) async {
    final body = <String, dynamic>{
      if (language != null) 'locale': language == AppLang.fa ? 'FA' : 'EN',
      if (currency != null) 'displayCurrency': currency.name.toUpperCase(),
    };
    final response = await _send('PATCH', '/api/v1/me/preferences', body: body, auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return AppUser.fromJson(Map<String, dynamic>.from(_decodeObject(response)['user'] as Map));
  }
}
"""
api_new_tail = """  Future<AppUser> updatePreferences({AppLang? language, DisplayCurrency? currency}) async {
    final body = <String, dynamic>{
      if (language != null) 'locale': language == AppLang.fa ? 'FA' : 'EN',
      if (currency != null) 'displayCurrency': currency.name.toUpperCase(),
    };
    final response = await _send('PATCH', '/api/v1/me/preferences', body: body, auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return AppUser.fromJson(Map<String, dynamic>.from(_decodeObject(response)['user'] as Map));
  }

  Future<AppUser> updateProfile({required String fullName}) async {
    final response = await _send(
      'PATCH',
      '/api/v1/me/profile',
      body: {'fullName': fullName.trim()},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return AppUser.fromJson(Map<String, dynamic>.from(_decodeObject(response)['user'] as Map));
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final response = await _send(
      'POST',
      '/api/v1/me/change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
  }
}
"""
s = replace_once(s, api_tail, api_new_tail, 'flutter-api-profile')
p.write_text(s, encoding='utf-8')


# ---------------- Flutter controller + profile + wallet UX ----------------
p = Path('lib/app.dart')
s = p.read_text(encoding='utf-8')

old_refresh = """    try {
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
      await _loadSecondaryData();
    } finally {
      refreshing = false;
      notifyListeners();
    }
"""
new_refresh = """    try {
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
      await _loadSecondaryData();
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await api.clearSession();
        authenticated = false;
        user = null;
        balanceAfn = 0;
        walletEntries = const [];
      }
    } finally {
      refreshing = false;
      notifyListeners();
    }
"""
s = replace_once(s, old_refresh, new_refresh, 'controller-session-expiry')

set_currency_block = """  Future<void> setCurrency(DisplayCurrency value) async {
    currency = value;
    await api.saveCurrency(value);
    if (authenticated) {
      try {
        user = await api.updatePreferences(currency: value);
      } catch (_) {}
    }
    notifyListeners();
  }
"""
controller_profile_methods = set_currency_block + """

  Future<String?> updateFullName(String fullName) async {
    final value = fullName.trim();
    if (value.length < 2) return 'invalid_name';
    try {
      user = await api.updateProfile(fullName: value);
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await api.clearSession();
        authenticated = false;
        notifyListeners();
      }
      return error.code;
    } catch (_) {
      return 'network_error';
    }
  }

  Future<String?> changePassword(String currentPassword, String newPassword) async {
    if (newPassword.length < 8) return 'weak_password';
    try {
      await api.changePassword(currentPassword: currentPassword, newPassword: newPassword);
      return null;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await api.clearSession();
        authenticated = false;
        notifyListeners();
      }
      return error.code;
    } catch (_) {
      return 'network_error';
    }
  }
"""
s = replace_once(s, set_currency_block, controller_profile_methods, 'controller-profile-methods')

s = replace_once(
    s,
    "                      Text(tr(c.fa, 'کاربر VELIXEO', 'VELIXEO User'), style: const TextStyle(fontWeight: FontWeight.w900)),\n",
    "                      Text(c.user?.fullName?.trim().isNotEmpty == true ? c.user!.fullName! : tr(c.fa, 'کاربر VELIXEO', 'VELIXEO User'), style: const TextStyle(fontWeight: FontWeight.w900)),\n",
    'profile-real-name',
)

profile_insert_anchor = """          const SizedBox(height: 16),
          SettingsTile(
            icon: Icons.language,
"""
profile_insert = """          const SizedBox(height: 16),
          SettingsTile(
            icon: Icons.manage_accounts_outlined,
            title: tr(c.fa, 'ویرایش پروفایل', 'Edit profile'),
            value: c.user?.fullName ?? '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditProfilePage(controller: c)),
            ),
          ),
          SettingsTile(
            icon: Icons.password_rounded,
            title: tr(c.fa, 'تغییر رمز عبور', 'Change password'),
            value: '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChangePasswordPage(controller: c)),
            ),
          ),
          SettingsTile(
            icon: Icons.language,
"""
s = replace_once(s, profile_insert_anchor, profile_insert, 'profile-settings-links')

s = replace_once(
    s,
    "          Center(child: Text('VELIXEO v0.2.0', style: const TextStyle(color: Color(0xFF8AA0B4), fontSize: 12))),\n",
    "          Center(child: Text('VELIXEO • Milestone 1', style: const TextStyle(color: Color(0xFF8AA0B4), fontSize: 12))),\n",
    'profile-version-label',
)

settings_anchor = """class SettingsTile extends StatelessWidget {
"""
profile_pages = r'''class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController fullName;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    fullName = TextEditingController(text: widget.controller.user?.fullName ?? '');
  }

  @override
  void dispose() {
    fullName.dispose();
    super.dispose();
  }

  Future<void> save() async {
    FocusScope.of(context).unfocus();
    if (fullName.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'نام معتبر وارد کنید.', 'Enter a valid full name.'))),
      );
      return;
    }
    setState(() => busy = true);
    final error = await widget.controller.updateFullName(fullName.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'پروفایل ذخیره شد.', 'Profile updated.'))),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'ذخیره پروفایل انجام نشد.', 'Could not update profile.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final identity = c.user?.email ?? c.user?.phone ?? '—';
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'ویرایش پروفایل', 'Edit profile'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: fullName,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.badge_outlined),
              labelText: tr(c.fa, 'نام و نام خانوادگی', 'Full name'),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            readOnly: true,
            controller: TextEditingController(text: identity),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.alternate_email),
              labelText: tr(c.fa, 'ایمیل / شماره', 'Email / phone'),
              helperText: tr(c.fa, 'تغییر ایمیل یا شماره بعد از فعال‌شدن تأیید هویت اضافه می‌شود.', 'Email/phone changes will be enabled with identity verification.'),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: busy ? tr(c.fa, 'درحال ذخیره...', 'Saving...') : tr(c.fa, 'ذخیره تغییرات', 'Save changes'),
            onPressed: busy ? null : save,
          ),
        ],
      ),
    );
  }
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  bool hidden = true;
  bool busy = false;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  String errorText(String code) {
    final fa = widget.controller.fa;
    switch (code) {
      case 'incorrect_current_password':
        return tr(fa, 'رمز فعلی نادرست است.', 'Current password is incorrect.');
      case 'new_password_must_differ':
        return tr(fa, 'رمز جدید باید با رمز فعلی متفاوت باشد.', 'New password must be different.');
      case 'weak_password':
      case 'invalid_request':
        return tr(fa, 'رمز جدید باید حداقل ۸ کاراکتر باشد.', 'New password must be at least 8 characters.');
      case 'network_error':
        return tr(fa, 'اتصال به سرور برقرار نشد.', 'Could not reach the server.');
      default:
        return tr(fa, 'تغییر رمز انجام نشد.', 'Password could not be changed.');
    }
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    if (next.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText('weak_password'))));
      return;
    }
    if (next.text != confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'رمز جدید و تکرار آن یکسان نیست.', 'New passwords do not match.'))),
      );
      return;
    }
    setState(() => busy = true);
    final error = await widget.controller.changePassword(current.text, next.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'رمز عبور با موفقیت تغییر کرد.', 'Password changed successfully.'))),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'تغییر رمز عبور', 'Change password'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: current,
            obscureText: hidden,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.lock_outline), labelText: tr(c.fa, 'رمز فعلی', 'Current password')),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: next,
            obscureText: hidden,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.password), labelText: tr(c.fa, 'رمز جدید', 'New password')),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: confirm,
            obscureText: hidden,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_reset_outlined),
              labelText: tr(c.fa, 'تکرار رمز جدید', 'Confirm new password'),
              suffixIcon: IconButton(
                onPressed: () => setState(() => hidden = !hidden),
                icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: busy ? tr(c.fa, 'لطفاً صبر کنید...', 'Please wait...') : tr(c.fa, 'تغییر رمز', 'Change password'),
            onPressed: busy ? null : submit,
          ),
        ],
      ),
    );
  }
}

'''
s = replace_once(s, settings_anchor, profile_pages + settings_anchor, 'profile-pages')

wallet_map_old = """                  child: TransactionTile(
                    title: entryTitle(c.fa, entry),
                    amount: '${entry.amountAfn >= 0 ? '+' : ''}${entry.amountAfn} AFN',
                    positive: entry.amountAfn >= 0,
                  ),
"""
wallet_map_new = """                  child: TransactionTile(
                    title: entryTitle(c.fa, entry),
                    subtitle: '${entry.status} • ${entry.createdAt.toLocal().toString().substring(0, 16)} • ${tr(c.fa, 'موجودی بعد', 'Balance after')}: ${entry.balanceAfterAfn} AFN',
                    amount: '${entry.amountAfn >= 0 ? '+' : ''}${c.money(entry.amountAfn)}',
                    positive: entry.amountAfn >= 0,
                  ),
"""
s = replace_once(s, wallet_map_old, wallet_map_new, 'wallet-entry-details')

transaction_old = """class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.title, required this.amount, required this.positive});
  final String title;
  final String amount;
  final bool positive;

  @override
  Widget build(BuildContext context) => SoftCard(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: (positive ? const Color(0xFF18A875) : const Color(0xFFE65454)).withValues(alpha: .1),
              child: Icon(
                positive ? Icons.add_rounded : Icons.remove_rounded,
                color: positive ? const Color(0xFF18A875) : const Color(0xFFE65454),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(
              amount,
              style: TextStyle(
                color: positive ? const Color(0xFF18A875) : const Color(0xFFE65454),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}
"""
transaction_new = """class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.title, required this.subtitle, required this.amount, required this.positive});
  final String title;
  final String subtitle;
  final String amount;
  final bool positive;

  @override
  Widget build(BuildContext context) => SoftCard(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: (positive ? const Color(0xFF18A875) : const Color(0xFFE65454)).withValues(alpha: .1),
              child: Icon(
                positive ? Icons.add_rounded : Icons.remove_rounded,
                color: positive ? const Color(0xFF18A875) : const Color(0xFFE65454),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF607487))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount,
              style: TextStyle(
                color: positive ? const Color(0xFF18A875) : const Color(0xFFE65454),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}
"""
s = replace_once(s, transaction_old, transaction_new, 'wallet-transaction-tile')
p.write_text(s, encoding='utf-8')


# ---------------- Backend CI coverage ----------------
p = Path('.github/workflows/backend-ci.yml')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "            -d '{\"email\":\"ci-user@velixeo.app\",\"password\":\"StrongPass123!\",\"locale\":\"FA\"}')\n",
    "            -d '{\"fullName\":\"CI VELIXEO User\",\"email\":\"ci-user@velixeo.app\",\"password\":\"StrongPass123!\",\"locale\":\"FA\"}')\n",
    'ci-register-full-name',
)
s = replace_once(
    s,
    "          assert data['user']['email']=='ci-user@velixeo.app'\n          assert data['user']['locale']=='FA'\n",
    "          assert data['user']['email']=='ci-user@velixeo.app'\n          assert data['user']['fullName']=='CI VELIXEO User'\n          assert data['user']['locale']=='FA'\n",
    'ci-assert-full-name',
)
wallet_test_anchor = """          print('login + wallet: ok')
          PY

      - name: Test no-JavaScript admin login form
"""
profile_test = """          print('login + wallet: ok')
          PY

      - name: Test profile update and password change
        run: |
          TOKEN=$(python3 -c \"import json; print(json.load(open('/tmp/login.json'))['accessToken'])\")
          curl -fsS -X PATCH http://127.0.0.1:8080/api/v1/me/profile \\
            -H 'content-type: application/json' \\
            -H \"authorization: Bearer $TOKEN\" \\
            -d '{\"fullName\":\"CI Updated User\"}' > /tmp/profile.json
          python3 - <<'PY'
          import json
          data=json.load(open('/tmp/profile.json'))
          assert data['user']['fullName']=='CI Updated User'
          print('profile update: ok')
          PY

          curl -fsS -X POST http://127.0.0.1:8080/api/v1/me/change-password \\
            -H 'content-type: application/json' \\
            -H \"authorization: Bearer $TOKEN\" \\
            -d '{\"currentPassword\":\"StrongPass123!\",\"newPassword\":\"StrongerPass456!\"}' > /tmp/password.json
          grep -q '\"ok\":true' /tmp/password.json
          curl -fsS -X POST http://127.0.0.1:8080/api/v1/auth/login \\
            -H 'content-type: application/json' \\
            -d '{\"identifier\":\"ci-user@velixeo.app\",\"password\":\"StrongerPass456!\"}' > /tmp/relogin.json
          echo 'password change: ok'

      - name: Test no-JavaScript admin login form
"""
s = replace_once(s, wallet_test_anchor, profile_test, 'ci-profile-password-tests')
# Admin test now uses the new password.
s = s.replace("--data-urlencode 'password=StrongPass123!'", "--data-urlencode 'password=StrongerPass456!'", 1)
p.write_text(s, encoding='utf-8')

print('VELIXEO Milestone 1 patch applied: auth/session/profile/wallet foundation')
