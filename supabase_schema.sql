-- =====================================================
-- GEM GROUP OF COMPANIES — Supabase Schema
-- Run this entire file in: Supabase → SQL Editor
-- =====================================================


-- ─────────────────────────────────────────────────────
-- 1. PROPERTIES TABLE (for property.html)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS properties (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at    TIMESTAMPTZ DEFAULT now(),

  title         TEXT NOT NULL,                      -- e.g. "5 Marla Residential Plot"
  category      TEXT NOT NULL DEFAULT 'Residential', -- "Residential" | "Commercial"
  location      TEXT NOT NULL,                      -- e.g. "Sector G-13, Islamabad"
  size          TEXT NOT NULL,                      -- e.g. "5 Marla"
  total_price   NUMERIC NOT NULL,                   -- e.g. 7500000
  installment   TEXT,                               -- e.g. "PKR 50,000 / month for 3 years"
  description   TEXT,                               -- free text description
  image_url     TEXT,                               -- direct image URL or Supabase Storage path
  whatsapp_no   TEXT DEFAULT '923185512803',        -- without + sign
  is_active     BOOLEAN DEFAULT TRUE               -- hide/show on site
);

-- ─────────────────────────────────────────────────────
-- 2. ROOMS TABLE (for lodges.html)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rooms (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at    TIMESTAMPTZ DEFAULT now(),

  name          TEXT NOT NULL,                      -- e.g. "Executive Suite"
  room_type     TEXT NOT NULL DEFAULT 'Double Bed', -- "Single" | "Double Bed" | "Executive" | "Family"
  description   TEXT,
  features      TEXT[],                             -- e.g. '{"WiFi","AC","Hot Water","TV"}'
  nightly_rate  NUMERIC NOT NULL,                   -- PKR per night
  image_url     TEXT,
  is_active     BOOLEAN DEFAULT TRUE,
  is_available  BOOLEAN DEFAULT TRUE               -- admin can toggle this manually
);

-- ─────────────────────────────────────────────────────
-- 3. BOOKINGS TABLE (for lodges.html + admin.html)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bookings (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at    TIMESTAMPTZ DEFAULT now(),

  room_id       UUID REFERENCES rooms(id) ON DELETE CASCADE,
  guest_name    TEXT NOT NULL,
  guest_phone   TEXT NOT NULL,
  check_in      DATE NOT NULL,
  check_out     DATE NOT NULL,
  nights        INT GENERATED ALWAYS AS (check_out - check_in) STORED,
  total_amount  NUMERIC,
  notes         TEXT,
  status        TEXT DEFAULT 'confirmed'            -- "confirmed" | "pending" | "cancelled"
);

-- ─────────────────────────────────────────────────────
-- 4. ROW LEVEL SECURITY (RLS)
-- ─────────────────────────────────────────────────────

-- Enable RLS on all tables
ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms      ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings   ENABLE ROW LEVEL SECURITY;

-- PUBLIC can READ active properties
CREATE POLICY "Public read properties"
  ON properties FOR SELECT
  USING (is_active = TRUE);

-- PUBLIC can READ active rooms
CREATE POLICY "Public read rooms"
  ON rooms FOR SELECT
  USING (is_active = TRUE);

-- PUBLIC can READ bookings (so calendar can check dates)
CREATE POLICY "Public read bookings"
  ON bookings FOR SELECT
  USING (TRUE);

-- PUBLIC can INSERT bookings (guest booking from website)
CREATE POLICY "Public insert bookings"
  ON bookings FOR INSERT
  WITH CHECK (TRUE);

-- AUTHENTICATED (admin) can do everything
CREATE POLICY "Admin all properties"
  ON properties FOR ALL
  USING (auth.role() = 'authenticated');

CREATE POLICY "Admin all rooms"
  ON rooms FOR ALL
  USING (auth.role() = 'authenticated');

CREATE POLICY "Admin all bookings"
  ON bookings FOR ALL
  USING (auth.role() = 'authenticated');


-- ─────────────────────────────────────────────────────
-- 5. SAMPLE DATA — delete after testing
-- ─────────────────────────────────────────────────────

-- Sample properties
INSERT INTO properties (title, category, location, size, total_price, installment, description, image_url)
VALUES
  ('Residential Plot – G-13',   'Residential', 'Sector G-13, Islamabad', '5 Marla',  7500000,  'PKR 45,000/month for 3 years', 'Prime residential plot in a developed sector with all utilities available.', ''),
  ('Residential Plot – B-17',   'Residential', 'Block B, B-17, Islamabad', '8 Marla', 12000000, 'PKR 70,000/month for 3 years', 'Corner plot in CDA-approved housing scheme with parks and mosque nearby.', ''),
  ('Commercial Shop – G-9',     'Commercial',  'G-9 Markaz, Islamabad',   '200 sqft', 8500000,  'PKR 55,000/month for 3 years', 'Ground-floor shop in a busy commercial plaza, ideal for retail or office use.', '');

-- Sample rooms
INSERT INTO rooms (name, room_type, description, features, nightly_rate, is_available)
VALUES
  ('Standard Double Room',  'Double Bed', 'Comfortable room with a queen-size bed, perfect for couples or solo travellers.', '{"WiFi","AC","Hot Water","Smart TV","Room Service"}', 8000,  TRUE),
  ('Executive Suite',       'Executive',  'Spacious suite with a king-size bed, lounge area, and city-facing windows.',          '{"WiFi","AC","Hot Water","Smart TV","Mini Fridge","Room Service","Workspace"}', 14000, TRUE),
  ('Family Room',           'Family',     'Two double beds in a large room, ideal for families up to 4 guests.',                 '{"WiFi","AC","Hot Water","Smart TV","Room Service"}', 12000, FALSE);

-- Sample booking (to test blocked dates)
INSERT INTO bookings (room_id, guest_name, guest_phone, check_in, check_out, total_amount, status)
SELECT id, 'Ahmed Khan', '03001234567', CURRENT_DATE + 3, CURRENT_DATE + 7, 56000, 'confirmed'
FROM rooms WHERE name = 'Standard Double Room' LIMIT 1;
