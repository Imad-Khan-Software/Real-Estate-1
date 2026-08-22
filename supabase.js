/* =====================================================
   GEM GROUP — Supabase Config & Shared Utilities
   supabase.js
   =====================================================

   HOW TO SET UP SUPABASE:
   1. Go to https://supabase.com → New Project
   2. Copy your Project URL and Anon Key from
      Settings → API
   3. Paste them below
   4. Run the SQL in supabase_schema.sql to create tables
   ===================================================== */

const WHATSAPP_NUMBER = '923185512803'; // Gem Group WhatsApp — no + sign, no spaces

const SUPABASE_URL = 'https://cmphacwtgdnkifqxafch.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNtcGhhY3d0Z2Rua2lmcXhhZmNoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3OTI2ODgsImV4cCI6MjA5OTM2ODY4OH0.6SpbM_QanNb4W8OSySxBHKkYWZSLDjfi_4Vc8gw4o9g';

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
