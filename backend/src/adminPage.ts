export const adminHtml = String.raw`<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>VELIXEO Admin</title>
<style>
:root{--p:#0D78C8;--sky:#31A8FF;--bg:#F4FAFF;--card:#fff;--text:#102235;--muted:#607487;--line:#DCE8F1;--ok:#18A875;--bad:#E65454;--warn:#EFAF38}*{box-sizing:border-box}body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif;background:var(--bg);color:var(--text)}button,input{font:inherit}.hidden{display:none!important}.login{min-height:100vh;display:grid;place-items:center;padding:24px}.login-card{width:min(440px,100%);background:#fff;border:1px solid var(--line);border-radius:28px;padding:28px;box-shadow:0 22px 70px rgba(13,120,200,.10)}.brand{display:flex;gap:12px;align-items:center}.logo{width:46px;height:46px;border-radius:14px;background:linear-gradient(145deg,#4DB8FF,#0D78C8);display:grid;place-items:center;color:#fff;font-weight:900;font-size:22px}.brand b{font-size:20px;letter-spacing:1px}.sub{color:var(--muted);font-size:13px}.field{margin-top:14px}.field label{display:block;font-size:12px;color:var(--muted);margin-bottom:6px}.field input{width:100%;height:48px;border:1px solid var(--line);border-radius:14px;padding:0 14px;outline:none;background:#fff}.field input:focus{border-color:var(--p);box-shadow:0 0 0 3px rgba(13,120,200,.08)}.primary{border:0;background:linear-gradient(135deg,var(--sky),var(--p));color:#fff;min-height:48px;border-radius:14px;padding:0 18px;font-weight:800;cursor:pointer}.primary:disabled{opacity:.65;cursor:not-allowed}.wide{width:100%;margin-top:18px}.err{color:var(--bad);font-size:13px;margin-top:12px;min-height:20px}.app{display:grid;grid-template-columns:250px 1fr;min-height:100vh}.side{background:#0D2640;color:#fff;padding:18px;position:sticky;top:0;height:100vh}.side .brand{margin-bottom:28px}.nav button{width:100%;border:0;background:transparent;color:#cfe8fa;text-align:right;padding:13px 14px;border-radius:12px;margin:4px 0;cursor:pointer}.nav button.active,.nav button:hover{background:rgba(49,168,255,.16);color:#fff}.main{padding:24px;min-width:0}.top{display:flex;justify-content:space-between;gap:16px;align-items:center;margin-bottom:20px}.top h1{font-size:24px;margin:0}.chip{font-size:12px;padding:7px 10px;border-radius:999px;background:#eaf6ff;color:var(--p)}.stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}.stat,.card{background:#fff;border:1px solid var(--line);border-radius:20px;padding:18px}.stat span{color:var(--muted);font-size:12px}.stat strong{display:block;margin-top:8px;font-size:24px}.card{margin-top:16px}.toolbar{display:flex;gap:10px;flex-wrap:wrap;align-items:center}.toolbar input{height:44px;border:1px solid var(--line);border-radius:12px;padding:0 12px;min-width:260px}.ghost{height:42px;border:1px solid var(--line);background:#fff;border-radius:12px;padding:0 13px;cursor:pointer}.table-wrap{overflow:auto;margin-top:14px}table{width:100%;border-collapse:collapse;min-width:780px}th,td{padding:12px 10px;border-bottom:1px solid #edf3f7;text-align:right;font-size:13px}th{color:var(--muted);font-weight:700}.money{font-weight:900;color:var(--p)}.badge{display:inline-block;padding:5px 8px;border-radius:999px;font-size:11px;background:#eef3f7}.badge.admin{background:#e8f8f1;color:#0b8a5c}.drawer{position:fixed;inset:0;background:rgba(8,25,40,.38);display:flex;justify-content:flex-start;z-index:20}.drawer-panel{width:min(520px,92vw);height:100%;background:#fff;padding:22px;overflow:auto;box-shadow:8px 0 40px rgba(0,0,0,.14)}.row{display:grid;grid-template-columns:1fr 1fr;gap:10px}.info{background:#f7fbff;border:1px solid var(--line);border-radius:14px;padding:12px;margin:8px 0}.info small{display:block;color:var(--muted)}.info b{display:block;margin-top:4px}.amount-actions{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}.amount-actions button{border:1px solid var(--line);background:#fff;padding:8px 10px;border-radius:10px;cursor:pointer}.save{margin-top:10px}.section-title{font-weight:900;margin:18px 0 8px}.tx{display:flex;justify-content:space-between;gap:10px;padding:11px 0;border-bottom:1px solid #edf3f7}.tx small{color:var(--muted)}.pos{color:var(--ok);font-weight:800}.neg{color:var(--bad);font-weight:800}.rates{display:grid;grid-template-columns:1fr 1fr;gap:12px}.ratebox input{width:100%;height:44px;border:1px solid var(--line);border-radius:12px;padding:0 12px;margin-top:8px}.logout{margin-top:28px;color:#ffced0!important}.notice{padding:12px 14px;border-radius:14px;background:#eaf6ff;color:#0D6EFD;font-size:13px;margin-top:12px}@media(max-width:900px){.app{grid-template-columns:1fr}.side{height:auto;position:static}.nav{display:flex;overflow:auto;gap:4px}.nav button{white-space:nowrap;width:auto}.stats{grid-template-columns:1fr 1fr}.main{padding:16px}}@media(max-width:540px){.stats,.rates,.row{grid-template-columns:1fr}.toolbar input{min-width:100%;width:100%}}
</style>
</head>
<body>
<section id="loginView" class="login">
  <form id="loginForm" class="login-card" novalidate>
    <div class="brand"><div class="logo">V</div><div><b>VELIXEO</b><div class="sub">پنل مدیریت امن</div></div></div>
    <h2>ورود مدیر</h2>
    <div class="sub">با حسابی که نقش ADMIN دارد وارد شوید.</div>
    <div class="field"><label for="loginId">ایمیل یا شماره</label><input id="loginId" autocomplete="username" required></div>
    <div class="field"><label for="loginPass">رمز عبور</label><input id="loginPass" type="password" autocomplete="current-password" required></div>
    <button class="primary wide" id="loginBtn" type="submit">ورود به پنل</button>
    <div id="loginError" class="err" aria-live="polite"></div>
  </form>
</section>
<section id="appView" class="app hidden">
  <aside class="side">
    <div class="brand"><div class="logo">V</div><div><b>VELIXEO</b><div class="sub" style="color:#9fc2db">Admin Console</div></div></div>
    <div class="nav">
      <button data-view="dashboard" class="active">داشبورد</button>
      <button data-view="users">کاربران</button>
      <button data-view="rates">نرخ ارز</button>
      <button data-view="providers">API و Providerها</button>
      <button id="logoutBtn" class="logout">خروج</button>
    </div>
  </aside>
  <main class="main">
    <div class="top"><div><h1 id="pageTitle">داشبورد</h1><div class="sub">مدیریت واقعی کاربران، کیف پول و تنظیمات VELIXEO</div></div><span class="chip" id="adminIdentity">ADMIN</span></div>
    <div id="dashboardView"><div class="stats"><div class="stat"><span>کل کاربران</span><strong id="sUsers">—</strong></div><div class="stat"><span>ثبت‌نام امروز</span><strong id="sToday">—</strong></div><div class="stat"><span>موجودی کل کیف پول‌ها</span><strong id="sWallet">—</strong></div><div class="stat"><span>مدیران</span><strong id="sAdmins">—</strong></div></div><div class="card"><b>آخرین کاربران</b><div id="recentUsers" class="table-wrap"></div></div></div>
    <div id="usersView" class="hidden"><div class="card"><div class="toolbar"><input id="userSearch" placeholder="جستجو با نام، ایمیل یا شماره"><button class="ghost" id="searchBtn">جستجو</button><button class="ghost" id="refreshUsersBtn">بروزرسانی</button></div><div id="usersTable" class="table-wrap"></div></div></div>
    <div id="ratesView" class="hidden"><div class="card"><b>نرخ‌های نمایش</b><p class="sub">واحد پایه همیشه AFN است.</p><div class="rates"><div class="ratebox"><label>AFN به ازای 1 USD</label><input id="usdRate" inputmode="decimal"><button class="primary save" data-rate="USD">ذخیره USD</button></div><div class="ratebox"><label>AFN به ازای 1 TOMAN</label><input id="tomanRate" inputmode="decimal"><button class="primary save" data-rate="TOMAN">ذخیره TOMAN</button></div></div></div></div>
    <div id="providersView" class="hidden"><div class="card"><b>API و Providerها</b><p class="sub">مدیریت Providerهای Social، Virtual Number، Top-up، Premium و HesabPay در این بخش توسعه داده می‌شود.</p><div class="notice">API Keyها فقط روی Backend نگهداری می‌شوند و داخل APK قرار نمی‌گیرند.</div></div></div>
  </main>
</section>
<div id="drawer" class="drawer hidden"><div class="drawer-panel"><div class="toolbar" style="justify-content:space-between"><b>جزئیات کاربر</b><button class="ghost" id="closeDrawer">بستن</button></div><div id="userDetail"></div></div></div>
<script>
(function(){
  'use strict';
  var accessToken = '';
  var refreshToken = '';
  var me = null;
  var currentUser = null;
  function el(id){ return document.getElementById(id); }
  function esc(value){
    return String(value == null ? '' : value).replace(/[&<>"']/g, function(ch){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch];
    });
  }
  function fmt(value){ return Number(value || 0).toLocaleString('en-US') + ' AFN'; }
  async function request(path, options){
    options = options || {};
    var headers = {'content-type':'application/json'};
    if(options.auth !== false && accessToken){ headers.authorization = 'Bearer ' + accessToken; }
    var response = await fetch(path, {
      method: options.method || 'GET',
      headers: headers,
      body: options.body ? JSON.stringify(options.body) : undefined
    });
    if(response.status === 401 && refreshToken && path !== '/api/v1/auth/refresh'){
      var refreshResponse = await fetch('/api/v1/auth/refresh', {
        method: 'POST',
        headers: {'content-type':'application/json'},
        body: JSON.stringify({refreshToken: refreshToken})
      });
      if(refreshResponse.ok){
        var refreshed = await refreshResponse.json();
        accessToken = refreshed.accessToken;
        refreshToken = refreshed.refreshToken;
        sessionStorage.setItem('va', accessToken);
        sessionStorage.setItem('vr', refreshToken);
        return request(path, options);
      }
    }
    if(!response.ok){
      var data = {};
      try { data = await response.json(); } catch(_error) {}
      throw new Error(data.error || ('HTTP ' + response.status));
    }
    if(response.status === 204){ return null; }
    return response.json();
  }
  function humanError(code){
    var map = {
      invalid_credentials: 'ایمیل/شماره یا رمز عبور اشتباه است.',
      admin_required: 'این حساب دسترسی مدیر ندارد.',
      unauthorized: 'نشست شما معتبر نیست. دوباره وارد شوید.',
      internal_server_error: 'خطای سرور رخ داد. دوباره تلاش کنید.'
    };
    return map[code] || code || 'خطای ناشناخته';
  }
  async function login(event){
    if(event){ event.preventDefault(); }
    var errorBox = el('loginError');
    var button = el('loginBtn');
    errorBox.textContent = '';
    var identifier = el('loginId').value.trim();
    var password = el('loginPass').value;
    if(!identifier || !password){ errorBox.textContent = 'ایمیل/شماره و رمز عبور را وارد کنید.'; return; }
    button.disabled = true;
    button.textContent = 'در حال ورود...';
    try {
      var result = await request('/api/v1/auth/login', {method:'POST', auth:false, body:{identifier:identifier,password:password}});
      if(!result.user || result.user.role !== 'ADMIN'){ throw new Error('admin_required'); }
      accessToken = result.accessToken;
      refreshToken = result.refreshToken;
      me = result.user;
      sessionStorage.setItem('va', accessToken);
      sessionStorage.setItem('vr', refreshToken);
      showApp();
      await loadDashboard();
    } catch(error) {
      errorBox.textContent = humanError(error && error.message ? error.message : 'login_failed');
    } finally {
      button.disabled = false;
      button.textContent = 'ورود به پنل';
    }
  }
  function showApp(){
    el('loginView').classList.add('hidden');
    el('appView').classList.remove('hidden');
    el('adminIdentity').textContent = (me && (me.fullName || me.email || me.phone)) || 'ADMIN';
  }
  function logout(){
    accessToken=''; refreshToken=''; me=null; currentUser=null;
    sessionStorage.removeItem('va'); sessionStorage.removeItem('vr');
    el('appView').classList.add('hidden'); el('loginView').classList.remove('hidden');
  }
  async function restore(){
    accessToken = sessionStorage.getItem('va') || '';
    refreshToken = sessionStorage.getItem('vr') || '';
    if(!accessToken){ return; }
    try {
      var result = await request('/api/v1/me');
      if(!result.user || result.user.role !== 'ADMIN'){ throw new Error('admin_required'); }
      me = result.user;
      showApp();
      await loadDashboard();
    } catch(_error) { logout(); }
  }
  function userTable(users){
    var rows = users.map(function(user){
      var id = esc(user.id);
      var identity = esc(user.email || user.phone || '—');
      var name = esc(user.fullName || '—');
      var roleClass = user.role === 'ADMIN' ? 'badge admin' : 'badge';
      var date = new Date(user.createdAt).toLocaleDateString('fa-IR');
      return '<tr><td>'+name+'</td><td>'+identity+'</td><td class="money">'+fmt(user.balanceAfn)+'</td><td><span class="'+roleClass+'">'+esc(user.role)+'</span></td><td>'+date+'</td><td><button class="ghost view-user" data-user-id="'+id+'">مشاهده</button></td></tr>';
    }).join('');
    return '<table><thead><tr><th>نام</th><th>ایمیل/شماره</th><th>موجودی</th><th>نقش</th><th>تاریخ عضویت</th><th></th></tr></thead><tbody>'+rows+'</tbody></table>';
  }
  function bindUserButtons(container){
    container.querySelectorAll('.view-user').forEach(function(button){
      button.addEventListener('click', function(){ openUser(button.getAttribute('data-user-id')); });
    });
  }
  async function loadDashboard(){
    var data = await request('/api/v1/admin/stats');
    el('sUsers').textContent = data.totalUsers;
    el('sToday').textContent = data.usersToday;
    el('sWallet').textContent = fmt(data.totalWalletBalanceAfn);
    el('sAdmins').textContent = data.totalAdmins;
    el('recentUsers').innerHTML = userTable(data.recentUsers || []);
    bindUserButtons(el('recentUsers'));
  }
  async function loadUsers(){
    var q = el('userSearch').value.trim();
    var url = '/api/v1/admin/users?limit=100' + (q ? '&q=' + encodeURIComponent(q) : '');
    var data = await request(url);
    el('usersTable').innerHTML = userTable(data.users || []);
    bindUserButtons(el('usersTable'));
  }
  async function openUser(id){
    var data = await request('/api/v1/admin/users/' + encodeURIComponent(id));
    currentUser = data.user;
    var u = data.user;
    var entries = (u.walletEntries || []).map(function(entry){
      var cls = Number(entry.amountAfn) >= 0 ? 'pos' : 'neg';
      return '<div class="tx"><div><b>'+esc(entry.description)+'</b><br><small>'+new Date(entry.createdAt).toLocaleString('fa-IR')+'</small></div><span class="'+cls+'">'+esc(entry.amountAfn)+' AFN</span></div>';
    }).join('');
    el('userDetail').innerHTML = '<div class="row"><div class="info"><small>نام</small><b>'+esc(u.fullName || '—')+'</b></div><div class="info"><small>نقش</small><b>'+esc(u.role)+'</b></div></div><div class="info"><small>ایمیل / شماره</small><b>'+esc(u.email || u.phone || '—')+'</b></div><div class="info"><small>موجودی فعلی</small><b class="money">'+fmt(u.balanceAfn)+'</b></div><div class="section-title">افزایش / کسر دستی کیف پول</div><div class="amount-actions"><button data-amount="100">+100</button><button data-amount="500">+500</button><button data-amount="1000">+1,000</button><button data-amount="-100">-100</button></div><div class="field"><label>مبلغ AFN (برای کسر، عدد منفی)</label><input id="adjAmount" inputmode="numeric"></div><div class="field"><label>دلیل</label><input id="adjReason" maxlength="300"></div><button class="primary wide" id="applyAdjustment">ثبت تغییر کیف پول</button><div class="section-title">آخرین تراکنش‌ها</div>'+(entries || '<div class="sub">تراکنشی وجود ندارد.</div>');
    el('userDetail').querySelectorAll('[data-amount]').forEach(function(button){ button.addEventListener('click', function(){ el('adjAmount').value = button.getAttribute('data-amount'); }); });
    el('applyAdjustment').addEventListener('click', adjustWallet);
    el('drawer').classList.remove('hidden');
  }
  async function adjustWallet(){
    if(!currentUser){ return; }
    var amount = el('adjAmount').value.trim();
    var reason = el('adjReason').value.trim();
    if(!amount || !reason){ alert('مبلغ و دلیل را وارد کنید.'); return; }
    if(!confirm('تغییر ' + amount + ' AFN برای این کاربر ثبت شود؟')){ return; }
    try {
      await request('/api/v1/admin/wallet-adjustments', {method:'POST', body:{userId:currentUser.id,amountAfn:String(amount),reason:reason,idempotencyKey:'web-'+Date.now()+'-'+currentUser.id}});
      alert('تغییر کیف پول ثبت شد.');
      await openUser(currentUser.id);
      await loadDashboard();
      await loadUsers();
    } catch(error){ alert(humanError(error.message)); }
  }
  async function loadRates(){
    var data = await request('/api/v1/rates', {auth:false});
    (data.rates || []).forEach(function(rate){ if(rate.code === 'USD'){ el('usdRate').value = rate.afnPerUnit; } if(rate.code === 'TOMAN'){ el('tomanRate').value = rate.afnPerUnit; } });
  }
  async function saveRate(code){
    var value = code === 'USD' ? el('usdRate').value.trim() : el('tomanRate').value.trim();
    if(!value){ return; }
    try { await request('/api/v1/admin/rates', {method:'PUT',body:{code:code,afnPerUnit:value}}); alert('نرخ ذخیره شد.'); }
    catch(error){ alert(humanError(error.message)); }
  }
  function switchView(name){
    ['dashboard','users','rates','providers'].forEach(function(view){ el(view+'View').classList.toggle('hidden', view !== name); });
    document.querySelectorAll('.nav button[data-view]').forEach(function(button){ button.classList.toggle('active', button.getAttribute('data-view') === name); });
    var titles = {dashboard:'داشبورد',users:'کاربران',rates:'نرخ ارز',providers:'API و Providerها'};
    el('pageTitle').textContent = titles[name] || 'VELIXEO';
    if(name === 'dashboard'){ loadDashboard(); }
    if(name === 'users'){ loadUsers(); }
    if(name === 'rates'){ loadRates(); }
  }
  el('loginForm').addEventListener('submit', login);
  el('logoutBtn').addEventListener('click', logout);
  el('searchBtn').addEventListener('click', loadUsers);
  el('refreshUsersBtn').addEventListener('click', loadUsers);
  el('closeDrawer').addEventListener('click', function(){ el('drawer').classList.add('hidden'); });
  el('drawer').addEventListener('click', function(event){ if(event.target === el('drawer')){ el('drawer').classList.add('hidden'); } });
  document.querySelectorAll('.nav button[data-view]').forEach(function(button){ button.addEventListener('click', function(){ switchView(button.getAttribute('data-view')); }); });
  document.querySelectorAll('[data-rate]').forEach(function(button){ button.addEventListener('click', function(){ saveRate(button.getAttribute('data-rate')); }); });
  restore();
})();
</script>
</body>
</html>`;
