-- =====================================================
-- GEM GROUP — Migration v3: Admin Roles + Booking Payment Security
-- Run ONCE in Supabase → SQL Editor, AFTER migration_v2_property_upgrade.sql
--
-- This migration is additive: it does not drop or rename any existing
-- table/column. It adds new tables, new columns, new RLS policies and
-- new SECURITY DEFINER functions ("RPCs") that the frontend now calls
-- instead of writing sensitive columns directly.
--
-- READ THE "BOOTSTRAP FIRST ROOT ADMIN" SECTION AT THE BOTTOM — it is
-- a manual, one-time step you must run yourself with your own email.
-- =====================================================


-- ─────────────────────────────────────────────────────
-- 1. ADMIN ROLES  (admin_profiles)
-- ─────────────────────────────────────────────────────
-- One row per admin user. `id` is the same UUID as the Supabase Auth
-- user (auth.users.id) — the admin must already exist as an Auth user
-- (created the normal way: Supabase Dashboard → Authentication → Invite user).
-- This table is the ONLY source of truth for admin permissions — the
-- frontend never decides who is an admin, it just reflects this table.

CREATE TABLE IF NOT EXISTS admin_profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         TEXT NOT NULL,
  role          TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'root_admin')),
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE admin_profiles ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────
-- 2. ROLE-CHECK HELPER FUNCTIONS
--    SECURITY DEFINER so they can read admin_profiles even from inside
--    a policy on admin_profiles itself (avoids RLS recursion), but they
--    only ever return a boolean — they never expose row data.
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION is_admin(uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_profiles
    WHERE id = uid AND is_active = TRUE
  );
$$;

CREATE OR REPLACE FUNCTION is_root_admin(uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_profiles
    WHERE id = uid AND role = 'root_admin' AND is_active = TRUE
  );
$$;

REVOKE ALL ON FUNCTION is_admin(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION is_root_admin(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION is_admin(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION is_root_admin(UUID) TO authenticated, anon;

-- admin_profiles RLS: you can read your own row; a root admin can read all.
-- There is NO insert/update/delete policy here on purpose — all writes to
-- this table go through the SECURITY DEFINER functions in section 8,
-- which re-check permissions in plpgsql (not just RLS) before writing.
DROP POLICY IF EXISTS "Read own admin profile or all if root" ON admin_profiles;
CREATE POLICY "Read own admin profile or all if root"
  ON admin_profiles FOR SELECT
  USING (auth.uid() = id OR is_root_admin(auth.uid()));

REVOKE INSERT, UPDATE, DELETE ON admin_profiles FROM authenticated, anon;


-- ─────────────────────────────────────────────────────
-- 3. APP SETTINGS  (root-admin configurable)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app_settings (
  key           TEXT PRIMARY KEY,
  value         TEXT NOT NULL,
  updated_at    TIMESTAMPTZ DEFAULT now()
);

INSERT INTO app_settings (key, value)
VALUES ('payment_window_minutes', '30')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read settings" ON app_settings;
CREATE POLICY "Public read settings"
  ON app_settings FOR SELECT
  USING (TRUE);

-- No direct write policy — updated only via update_setting() below.
REVOKE INSERT, UPDATE, DELETE ON app_settings FROM authenticated, anon;


-- ─────────────────────────────────────────────────────
-- 4. BOOKINGS — new columns for the payment workflow
--    (existing columns from supabase_schema.sql are untouched)
-- ─────────────────────────────────────────────────────
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS guests            INT DEFAULT 1,
  ADD COLUMN IF NOT EXISTS price_per_night    NUMERIC,
  ADD COLUMN IF NOT EXISTS booking_status     TEXT DEFAULT 'pending_payment'
    CHECK (booking_status IN (
      'pending_payment', 'payment_submitted', 'confirmed',
      'rejected', 'expired', 'cancelled'
    )),
  ADD COLUMN IF NOT EXISTS expires_at         TIMESTAMPTZ;

-- Backfill booking_status for any bookings created before this migration
-- (the original schema only had `status` with values confirmed/pending/cancelled).
UPDATE bookings
SET booking_status = CASE status
  WHEN 'confirmed' THEN 'confirmed'
  WHEN 'cancelled' THEN 'cancelled'
  ELSE 'confirmed'   -- legacy manual/staff bookings: treat as trusted & confirmed
END
WHERE booking_status IS NULL OR booking_status = 'pending_payment' AND status = 'confirmed';

-- From now on booking_status is the source of truth for availability logic.
-- `status` is kept as-is for backward compatibility with any old reports.


-- ─────────────────────────────────────────────────────
-- 5. PAYMENT SUBMISSIONS
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payment_submissions (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id            UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,

  payment_method        TEXT NOT NULL,            -- 'Easypaisa' | 'JazzCash' | 'Bank Transfer'
  transaction_reference TEXT,
  amount                NUMERIC NOT NULL,
  screenshot_path       TEXT,                      -- path inside the private 'payment-proofs' bucket

  status                TEXT NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('submitted', 'verified', 'rejected')),
  rejection_reason      TEXT,

  submitted_at          TIMESTAMPTZ DEFAULT now(),
  verified_at           TIMESTAMPTZ,
  verified_by           UUID REFERENCES auth.users(id)
);

ALTER TABLE payment_submissions ENABLE ROW LEVEL SECURITY;

-- Only admins can read payment submissions (customers have no login/session
-- to scope a "my submissions" policy to, so read access is admin-only —
-- the customer sees their own submission's result inline in the same
-- browser session right after they submit it, not via a later query).
DROP POLICY IF EXISTS "Admins read payment submissions" ON payment_submissions;
CREATE POLICY "Admins read payment submissions"
  ON payment_submissions FOR SELECT
  USING (is_admin(auth.uid()));

-- No direct insert/update policy for anon/authenticated — writes only via
-- submit_payment() and verify_payment() below.
REVOKE INSERT, UPDATE, DELETE ON payment_submissions FROM authenticated, anon;


-- ─────────────────────────────────────────────────────
-- 6. PAYMENT AUDIT LOG
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payment_audit_log (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id        UUID REFERENCES bookings(id) ON DELETE SET NULL,
  admin_id          UUID REFERENCES auth.users(id),
  action            TEXT NOT NULL,
  previous_status   TEXT,
  new_status        TEXT,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE payment_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read audit log" ON payment_audit_log;
CREATE POLICY "Admins read audit log"
  ON payment_audit_log FOR SELECT
  USING (is_admin(auth.uid()));

-- Written only from inside verify_payment() (SECURITY DEFINER) — no direct writes.
REVOKE INSERT, UPDATE, DELETE ON payment_audit_log FROM authenticated, anon;


-- ─────────────────────────────────────────────────────
-- 7. BOOKINGS / ROOMS / PROPERTIES — tightened RLS
--    Public can still read everything they could before. Public can no
--    longer write bookings directly (must go through create_booking /
--    submit_payment). Admins keep full direct table access for the
--    existing admin.html management screens.
-- ─────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Public insert bookings" ON bookings;

DROP POLICY IF EXISTS "Admin all bookings v2" ON bookings;
CREATE POLICY "Admin all bookings v2"
  ON bookings FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- (existing "Public read bookings" and "Admin all bookings" policies from
--  the base schema are left in place; this one supersedes write access
--  using the new role table rather than a bare `auth.role() = 'authenticated'`
--  check, which used to let ANY logged-in user — not just real admins —
--  write to bookings.)
DROP POLICY IF EXISTS "Admin all bookings" ON bookings;
DROP POLICY IF EXISTS "Admin all rooms" ON rooms;
DROP POLICY IF EXISTS "Admin all properties" ON properties;

DROP POLICY IF EXISTS "Admin all rooms v2" ON rooms;
CREATE POLICY "Admin all rooms v2"
  ON rooms FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admin all properties v2" ON properties;
CREATE POLICY "Admin all properties v2"
  ON properties FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- Same tightening for the v2 inquiries table (was "any authenticated user").
DROP POLICY IF EXISTS "Admin all inquiries" ON inquiries;

DROP POLICY IF EXISTS "Admin all inquiries v2" ON inquiries;
CREATE POLICY "Admin all inquiries v2"
  ON inquiries FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));


-- ─────────────────────────────────────────────────────
-- 8. RPC FUNCTIONS
-- ─────────────────────────────────────────────────────

-- 8a. Release expired holds. Safe to call from anywhere (anon included) —
--     it only ever moves bookings from pending_payment -> expired once
--     their payment window has passed. Called at the start of every
--     booking-availability check on the public site.
CREATE OR REPLACE FUNCTION expire_stale_bookings()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE bookings
  SET booking_status = 'expired'
  WHERE booking_status = 'pending_payment'
    AND expires_at IS NOT NULL
    AND expires_at < now();
END;
$$;

REVOKE ALL ON FUNCTION expire_stale_bookings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION expire_stale_bookings() TO anon, authenticated;


-- 8b. Create a booking with a SERVER-COMPUTED price. The browser only
--     supplies room + dates + guest details — never a price. This closes
--     the "customer changes JS to send price = 1" hole described in the
--     brief. Also enforces double-booking protection and a per-room
--     advisory lock so two simultaneous requests for the same room
--     cannot both slip through the overlap check at the same time.
CREATE OR REPLACE FUNCTION create_booking(
  p_room_id     UUID,
  p_guest_name  TEXT,
  p_guest_phone TEXT,
  p_check_in    DATE,
  p_check_out   DATE,
  p_guests      INT DEFAULT 1,
  p_notes       TEXT DEFAULT NULL
)
RETURNS TABLE (booking_id UUID, total_amount NUMERIC, nights INT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rate          NUMERIC;
  v_is_active     BOOLEAN;
  v_nights        INT;
  v_total         NUMERIC;
  v_window_min    INT;
  v_expires       TIMESTAMPTZ;
  v_booking_id    UUID;
  v_overlap       INT;
BEGIN
  PERFORM expire_stale_bookings();

  IF p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'Check-out date must be after check-in date';
  END IF;

  IF p_guest_name IS NULL OR trim(p_guest_name) = '' THEN
    RAISE EXCEPTION 'Guest name is required';
  END IF;

  IF p_guest_phone IS NULL OR trim(p_guest_phone) = '' THEN
    RAISE EXCEPTION 'Guest phone is required';
  END IF;

  -- Serialize concurrent booking attempts for the SAME room so two
  -- requests arriving at the same instant can't both pass the overlap
  -- check below before either has committed.
  PERFORM pg_advisory_xact_lock(hashtext(p_room_id::text));

  SELECT nightly_rate, is_active INTO v_rate, v_is_active
  FROM rooms WHERE id = p_room_id;

  IF v_rate IS NULL THEN
    RAISE EXCEPTION 'Room not found';
  END IF;

  IF NOT v_is_active THEN
    RAISE EXCEPTION 'Room is not available for booking';
  END IF;

  -- Double-booking protection: any other booking on this room that is
  -- still "active" (confirmed, or a live payment hold) and overlaps the
  -- requested dates blocks this request.
  SELECT count(*) INTO v_overlap
  FROM bookings
  WHERE room_id = p_room_id
    AND booking_status IN ('pending_payment', 'payment_submitted', 'confirmed')
    AND check_in < p_check_out
    AND check_out > p_check_in;

  IF v_overlap > 0 THEN
    RAISE EXCEPTION 'Room is not available for the selected dates';
  END IF;

  v_nights := p_check_out - p_check_in;
  v_total  := v_nights * v_rate;

  SELECT COALESCE(value::INT, 30) INTO v_window_min
  FROM app_settings WHERE key = 'payment_window_minutes';

  v_expires := now() + (COALESCE(v_window_min, 30) || ' minutes')::INTERVAL;

  INSERT INTO bookings (
    room_id, guest_name, guest_phone, check_in, check_out,
    guests, price_per_night, total_amount, notes,
    status, booking_status, expires_at
  ) VALUES (
    p_room_id, trim(p_guest_name), trim(p_guest_phone), p_check_in, p_check_out,
    GREATEST(COALESCE(p_guests, 1), 1), v_rate, v_total, p_notes,
    'pending', 'pending_payment', v_expires
  )
  RETURNING id INTO v_booking_id;

  RETURN QUERY SELECT v_booking_id, v_total, v_nights, v_expires;
END;
$$;

REVOKE ALL ON FUNCTION create_booking(UUID, TEXT, TEXT, DATE, DATE, INT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_booking(UUID, TEXT, TEXT, DATE, DATE, INT, TEXT) TO anon, authenticated;


-- 8c. Submit payment proof for a pending (or previously rejected) booking.
--     IMPORTANT: this never sets booking_status to 'confirmed'. It only
--     ever moves pending_payment/rejected -> payment_submitted, so a
--     screenshot alone can never confirm a booking (see section 12 of
--     the brief). The booking's own UUID acts as the customer's access
--     token for this guest-checkout flow (no customer login exists).
CREATE OR REPLACE FUNCTION submit_payment(
  p_booking_id        UUID,
  p_method            TEXT,
  p_transaction_ref   TEXT,
  p_amount            NUMERIC,
  p_screenshot_path   TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_status  TEXT;
  v_expires TIMESTAMPTZ;
BEGIN
  PERFORM expire_stale_bookings();

  SELECT booking_status, expires_at INTO v_status, v_expires
  FROM bookings WHERE id = p_booking_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;

  IF v_status NOT IN ('pending_payment', 'rejected') THEN
    RAISE EXCEPTION 'This booking is not awaiting payment (current status: %)', v_status;
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'A valid payment amount is required';
  END IF;

  IF p_method IS NULL OR trim(p_method) = '' THEN
    RAISE EXCEPTION 'Payment method is required';
  END IF;

  INSERT INTO payment_submissions (
    booking_id, payment_method, transaction_reference, amount, screenshot_path, status
  ) VALUES (
    p_booking_id, p_method, p_transaction_ref, p_amount, p_screenshot_path, 'submitted'
  );

  -- Screenshot is stored as evidence ONLY — status becomes "payment_submitted",
  -- i.e. "🟡 Verification Pending", never "confirmed".
  UPDATE bookings SET booking_status = 'payment_submitted' WHERE id = p_booking_id;
END;
$$;

REVOKE ALL ON FUNCTION submit_payment(UUID, TEXT, TEXT, NUMERIC, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_payment(UUID, TEXT, TEXT, NUMERIC, TEXT) TO anon, authenticated;


-- 8d. Admin verifies or rejects a submitted payment. Only callable by an
--     active admin/root_admin — checked against admin_profiles, not any
--     value supplied by the browser.
CREATE OR REPLACE FUNCTION verify_payment(
  p_booking_id UUID,
  p_action     TEXT,   -- 'confirm' | 'reject'
  p_notes      TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller      UUID := auth.uid();
  v_status      TEXT;
  v_new_status  TEXT;
  v_overlap     INT;
  v_room_id     UUID;
  v_check_in    DATE;
  v_check_out   DATE;
BEGIN
  IF NOT is_admin(v_caller) THEN
    RAISE EXCEPTION 'ACCESS DENIED: admin privileges required';
  END IF;

  IF p_action NOT IN ('confirm', 'reject') THEN
    RAISE EXCEPTION 'Invalid action: must be confirm or reject';
  END IF;

  SELECT booking_status, room_id, check_in, check_out
  INTO v_status, v_room_id, v_check_in, v_check_out
  FROM bookings WHERE id = p_booking_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;

  IF v_status <> 'payment_submitted' THEN
    RAISE EXCEPTION 'Booking is not awaiting payment verification (current status: %)', v_status;
  END IF;

  IF p_action = 'confirm' THEN
    -- Defensive re-check: don't allow confirming into a room that a
    -- DIFFERENT confirmed booking already occupies for overlapping dates.
    SELECT count(*) INTO v_overlap
    FROM bookings
    WHERE room_id = v_room_id
      AND id <> p_booking_id
      AND booking_status = 'confirmed'
      AND check_in < v_check_out
      AND check_out > v_check_in;

    IF v_overlap > 0 THEN
      RAISE EXCEPTION 'Cannot confirm: another booking already confirmed for overlapping dates. Reject this one instead.';
    END IF;

    v_new_status := 'confirmed';
  ELSE
    v_new_status := 'rejected';
  END IF;

  UPDATE bookings SET booking_status = v_new_status WHERE id = p_booking_id;

  UPDATE payment_submissions
  SET status        = CASE WHEN p_action = 'confirm' THEN 'verified' ELSE 'rejected' END,
      verified_at   = now(),
      verified_by   = v_caller,
      rejection_reason = CASE WHEN p_action = 'reject' THEN p_notes ELSE NULL END
  WHERE booking_id = p_booking_id AND status = 'submitted';

  INSERT INTO payment_audit_log (booking_id, admin_id, action, previous_status, new_status, notes)
  VALUES (p_booking_id, v_caller, 'verify_payment:' || p_action, v_status, v_new_status, p_notes);
END;
$$;

REVOKE ALL ON FUNCTION verify_payment(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION verify_payment(UUID, TEXT, TEXT) TO authenticated;


-- 8e. Root-admin-only: invite an existing Supabase Auth user (created via
--     Dashboard → Authentication → Invite user) as a normal Admin.
--     This function deliberately can only ever create role='admin' rows —
--     it can never be used to mint a root_admin, closing the "become
--     Root Admin" loophole described in the brief.
CREATE OR REPLACE FUNCTION add_admin(p_email TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_target UUID;
BEGIN
  IF NOT is_root_admin(v_caller) THEN
    RAISE EXCEPTION 'ACCESS DENIED: root admin privileges required';
  END IF;

  SELECT id INTO v_target FROM auth.users WHERE lower(email) = lower(p_email);

  IF v_target IS NULL THEN
    RAISE EXCEPTION 'No Auth user found for that email. Invite them first via Supabase Dashboard → Authentication → Invite user, then try again.';
  END IF;

  INSERT INTO admin_profiles (id, email, role, is_active)
  VALUES (v_target, p_email, 'admin', TRUE)
  ON CONFLICT (id) DO UPDATE SET role = 'admin', is_active = TRUE, email = EXCLUDED.email;
END;
$$;

REVOKE ALL ON FUNCTION add_admin(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION add_admin(TEXT) TO authenticated;


-- 8f. Root-admin-only: promote/demote between 'admin' and 'root_admin'.
--     A normal admin can never call this successfully against anyone,
--     including themselves, because of the is_root_admin() check.
CREATE OR REPLACE FUNCTION change_admin_role(p_target_id UUID, p_new_role TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller UUID := auth.uid();
BEGIN
  IF NOT is_root_admin(v_caller) THEN
    RAISE EXCEPTION 'ACCESS DENIED: root admin privileges required';
  END IF;

  IF p_new_role NOT IN ('admin', 'root_admin') THEN
    RAISE EXCEPTION 'Invalid role';
  END IF;

  IF p_target_id = v_caller AND p_new_role = 'admin' THEN
    RAISE EXCEPTION 'ACCESS DENIED: a root admin cannot demote themselves (ask another root admin, or update the database directly)';
  END IF;

  UPDATE admin_profiles SET role = p_new_role WHERE id = p_target_id;
END;
$$;

REVOKE ALL ON FUNCTION change_admin_role(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION change_admin_role(UUID, TEXT) TO authenticated;


-- 8g. Root-admin-only: enable/disable an admin account. A root admin can
--     never be disabled if they are the only active root admin left —
--     this prevents the system from ever being left with zero root admins.
CREATE OR REPLACE FUNCTION set_admin_active(p_target_id UUID, p_active BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller     UUID := auth.uid();
  v_target_role TEXT;
  v_root_count  INT;
BEGIN
  IF NOT is_root_admin(v_caller) THEN
    RAISE EXCEPTION 'ACCESS DENIED: root admin privileges required';
  END IF;

  SELECT role INTO v_target_role FROM admin_profiles WHERE id = p_target_id;

  IF v_target_role = 'root_admin' AND p_active = FALSE THEN
    SELECT count(*) INTO v_root_count
    FROM admin_profiles WHERE role = 'root_admin' AND is_active = TRUE;

    IF v_root_count <= 1 THEN
      RAISE EXCEPTION 'ACCESS DENIED: cannot disable the only active Root Admin';
    END IF;
  END IF;

  UPDATE admin_profiles SET is_active = p_active WHERE id = p_target_id;
END;
$$;

REVOKE ALL ON FUNCTION set_admin_active(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION set_admin_active(UUID, BOOLEAN) TO authenticated;


-- 8h. Root-admin-only: remove an admin row entirely. Root Admins can never
--     be removed through this function (disable them instead, or manage
--     them directly in SQL if a root account truly must be retired).
CREATE OR REPLACE FUNCTION remove_admin(p_target_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller      UUID := auth.uid();
  v_target_role TEXT;
BEGIN
  IF NOT is_root_admin(v_caller) THEN
    RAISE EXCEPTION 'ACCESS DENIED: root admin privileges required';
  END IF;

  SELECT role INTO v_target_role FROM admin_profiles WHERE id = p_target_id;

  IF v_target_role = 'root_admin' THEN
    RAISE EXCEPTION 'ACCESS DENIED: Root Admin accounts cannot be removed. Disable instead.';
  END IF;

  DELETE FROM admin_profiles WHERE id = p_target_id;
END;
$$;

REVOKE ALL ON FUNCTION remove_admin(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION remove_admin(UUID) TO authenticated;


-- 8i. Root-admin-only: update a setting (e.g. payment_window_minutes).
CREATE OR REPLACE FUNCTION update_setting(p_key TEXT, p_value TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT is_root_admin(auth.uid()) THEN
    RAISE EXCEPTION 'ACCESS DENIED: root admin privileges required';
  END IF;

  INSERT INTO app_settings (key, value, updated_at)
  VALUES (p_key, p_value, now())
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION update_setting(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_setting(TEXT, TEXT) TO authenticated;


-- ─────────────────────────────────────────────────────
-- 9. PRIVATE STORAGE BUCKET FOR PAYMENT SCREENSHOTS
-- ─────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('payment-proofs', 'payment-proofs', FALSE)
ON CONFLICT (id) DO NOTHING;

-- Anyone (including guest customers with no login) can UPLOAD a proof —
-- but never LIST or READ one back. Only admins can read.
DROP POLICY IF EXISTS "Anyone can upload payment proofs" ON storage.objects;
CREATE POLICY "Anyone can upload payment proofs"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'payment-proofs');

DROP POLICY IF EXISTS "Admins can view payment proofs" ON storage.objects;
CREATE POLICY "Admins can view payment proofs"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'payment-proofs' AND is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can delete payment proofs" ON storage.objects;
CREATE POLICY "Admins can delete payment proofs"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'payment-proofs' AND is_admin(auth.uid()));


-- =====================================================
-- 10. BOOTSTRAP THE FIRST ROOT ADMIN  (manual, one-time)
-- =====================================================
-- There is deliberately NO public "become root admin" form or API.
-- To create your first Root Admin:
--
--   1. Supabase Dashboard → Authentication → Users → Invite user
--      (use your own email). Set a password via the emailed link.
--
--   2. Come back to the SQL Editor and run the two lines below,
--      replacing the email with the one you just invited:
--
--   INSERT INTO admin_profiles (id, email, role, is_active)
--   SELECT id, email, 'root_admin', TRUE
--   FROM auth.users
--   WHERE email = 'YOUR-EMAIL@example.com'
--   ON CONFLICT (id) DO UPDATE SET role = 'root_admin', is_active = TRUE;
--
-- That is the ONLY way a root_admin row is ever created. From then on,
-- that Root Admin can add further admins from the "Admin Management"
-- tab in /admin, and can promote a normal admin to Root Admin there too.
-- =====================================================
