-- =====================================================
-- GEM GROUP — Migration v2: Property Advisor Upgrade
-- Run ONCE in Supabase → SQL Editor, AFTER supabase_schema.sql
-- Safe / additive only — does not drop or rename anything,
-- does not touch rooms/bookings, existing data is untouched.
-- =====================================================

-- ─────────────────────────────────────────────────────
-- 1. NEW COLUMNS ON properties
--    (all nullable / defaulted so existing rows stay valid)
-- ─────────────────────────────────────────────────────
ALTER TABLE properties
  ADD COLUMN IF NOT EXISTS property_type   TEXT DEFAULT 'Plot',        -- 'House' | 'Apartment' | 'Villa' | 'Plot' | 'Office' | 'Shop'
  ADD COLUMN IF NOT EXISTS purpose         TEXT DEFAULT 'Sale',        -- 'Sale' | 'Rent'
  ADD COLUMN IF NOT EXISTS status          TEXT DEFAULT 'Available',   -- 'Available' | 'Reserved' | 'Sold' | 'Rented'
  ADD COLUMN IF NOT EXISTS bedrooms        INT,                        -- null for plots/shops
  ADD COLUMN IF NOT EXISTS bathrooms       INT,
  ADD COLUMN IF NOT EXISTS is_featured     BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS features        TEXT[] DEFAULT '{}',        -- e.g. '{"Parking","Security","Electricity"}'
  ADD COLUMN IF NOT EXISTS images          TEXT[] DEFAULT '{}',        -- gallery, in addition to image_url (primary)
  ADD COLUMN IF NOT EXISTS agent_name      TEXT DEFAULT 'Gem Group Advisory Team',
  ADD COLUMN IF NOT EXISTS agent_phone     TEXT,
  ADD COLUMN IF NOT EXISTS agent_email     TEXT;

-- Backfill purpose/status/type defaults for any pre-existing rows (no-op if already set)
UPDATE properties SET property_type = 'Plot'      WHERE property_type IS NULL;
UPDATE properties SET purpose       = 'Sale'       WHERE purpose IS NULL;
UPDATE properties SET status        = 'Available'  WHERE status IS NULL;

-- ─────────────────────────────────────────────────────
-- 2. INQUIRIES TABLE (property contact-form leads)
-- ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inquiries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at    TIMESTAMPTZ DEFAULT now(),

  property_id   UUID REFERENCES properties(id) ON DELETE SET NULL,
  name          TEXT NOT NULL,
  email         TEXT,
  phone         TEXT NOT NULL,
  message       TEXT,
  status        TEXT DEFAULT 'New'                 -- 'New' | 'Contacted' | 'Closed'
);

ALTER TABLE inquiries ENABLE ROW LEVEL SECURITY;

-- PUBLIC can submit an inquiry (the property contact form)
DROP POLICY IF EXISTS "Public insert inquiries" ON inquiries;
CREATE POLICY "Public insert inquiries"
  ON inquiries FOR INSERT
  WITH CHECK (TRUE);

-- Only logged-in ADMIN can read / update / delete inquiries
DROP POLICY IF EXISTS "Admin all inquiries" ON inquiries;
CREATE POLICY "Admin all inquiries"
  ON inquiries FOR ALL
  USING (auth.role() = 'authenticated');

-- ─────────────────────────────────────────────────────
-- 3. OPTIONAL DEMO DATA — safe to skip / delete
--    Enriches the 3 sample properties from the base schema
--    with the new fields so the upgraded listing/detail
--    pages have something realistic to display immediately.
-- ─────────────────────────────────────────────────────
UPDATE properties SET
  property_type = 'Plot', purpose = 'Sale', is_featured = TRUE,
  features = '{"Gated Community","Electricity","Water Supply","Boundary Wall"}',
  agent_name = 'Imad Khan', agent_phone = '923185512803'
WHERE title = 'Residential Plot – G-13';

UPDATE properties SET
  property_type = 'Plot', purpose = 'Sale',
  features = '{"Corner Plot","Park Facing","Mosque Nearby","Electricity"}',
  agent_name = 'Imad Khan', agent_phone = '923185512803'
WHERE title = 'Residential Plot – B-17';

UPDATE properties SET
  property_type = 'Shop', purpose = 'Sale', is_featured = TRUE,
  features = '{"Main Road Access","Electricity","Water Supply","Security"}',
  agent_name = 'Imad Khan', agent_phone = '923185512803'
WHERE title = 'Commercial Shop – G-9';
