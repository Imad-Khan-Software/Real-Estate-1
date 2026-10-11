

const WHATSAPP_NUMBER = '923185512803'; 

const SUPABASE_URL = 'https://fkcwaoomlwojpfufhzqe.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZrY3dhb29tbHdvanBmdWZoenFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE3Mjc5NzIsImV4cCI6MjEwNzMwMzk3Mn0.p4Xsh1q_LGI3iDJSy03MsyN7FoXemmlJvq6LqipBJ58';

/* ── Supabase client (using CDN build) ── */
const { createClient } = supabase;
const sb = createClient(SUPABASE_URL, SUPABASE_KEY);

/* =====================================================
   SHARED UTILITIES
   ===================================================== */

/** Show a brief toast notification */
function showToast(msg, duration = 3000) {
  let t = document.getElementById('toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'toast';
    t.className = 'toast';
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), duration);
}

/** Format PKR currency */
function formatPKR(amount) {
  if (!amount) return '—';
  return 'PKR ' + Number(amount).toLocaleString('en-PK');
}

/** Format a date string nicely */
function formatDate(str) {
  if (!str) return '—';
  return new Date(str).toLocaleDateString('en-PK', {
    day: 'numeric', month: 'short', year: 'numeric'
  });
}

/** Open / close modal */
function openModal(id) {
  document.getElementById(id).classList.add('open');
  document.body.style.overflow = 'hidden';
}

function closeModal(id) {
  document.getElementById(id).classList.remove('open');
  document.body.style.overflow = '';
}

/* Close modal on overlay click */
document.addEventListener('click', e => {
  if (e.target.classList.contains('modal-overlay')) {
    e.target.classList.remove('open');
    document.body.style.overflow = '';
  }
});

/* ── Auth helpers ── */
async function getSession() {
  const { data } = await sb.auth.getSession();
  return data.session;
}

async function requireAuth() {
  const session = await getSession();
  if (!session) {
    window.location.href = 'admin.html';
  }
  return session;
}

/* =====================================================
   ADMIN ROLE HELPERS  (v3 security upgrade)
   The frontend NEVER decides who is an admin — it only reflects
   whatever admin_profiles says server-side. RLS + RPC functions
   enforce the real permission checks in the database.
   ===================================================== */

/** Returns { id, email, role, is_active } for the signed-in user, or null. */
async function getAdminProfile() {
  const session = await getSession();
  if (!session) return null;
  const { data, error } = await sb
    .from('admin_profiles')
    .select('id, email, role, is_active')
    .eq('id', session.user.id)
    .maybeSingle();
  if (error || !data || !data.is_active) return null;
  return data;
}

/* =====================================================
   PAYMENT CONFIG  (edit here to change accepted methods)
   ===================================================== */
const PAYMENT_METHODS = [
  { id: 'Easypaisa',      title: 'Easypaisa',      account_title: 'Gem Group of Companies', account_number: '0318-5512803' },
  { id: 'JazzCash',       title: 'JazzCash',       account_title: 'Gem Group of Companies', account_number: '0318-5512803' },
  { id: 'Bank Transfer',  title: 'Bank Transfer',  account_title: 'Gem Group of Companies', account_number: 'PK00 XXXX 0000 1111 2222 3333', bank_name: 'Meezan Bank' }
];

/* =====================================================
   STATUS BADGES  (shared across customer + admin views)
   ===================================================== */
const BOOKING_STATUS_META = {
  pending_payment:   { icon: '🟡', label: 'Payment Pending',    css: 'pending'   },
  payment_submitted: { icon: '🔵', label: 'Verification Pending', css: 'new'     },
  confirmed:         { icon: '🟢', label: 'Confirmed',          css: 'confirmed' },
  rejected:          { icon: '🔴', label: 'Rejected',           css: 'rejected'  },
  expired:           { icon: '⚫', label: 'Expired',            css: 'closed'    },
  cancelled:         { icon: '⚫', label: 'Cancelled',          css: 'closed'    }
};

function bookingStatusBadge(status) {
  const meta = BOOKING_STATUS_META[status] || { icon: '⚪', label: status || 'Unknown', css: 'pending' };
  return `<span class="status-pill ${meta.css}">${meta.icon} ${meta.label}</span>`;
}
