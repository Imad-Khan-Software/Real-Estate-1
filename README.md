# Gem Group of Companies — Website Setup Guide

## Files in this package

| File | Purpose |
|------|---------|
| `index.html` | Corporate hub / landing page |
| `property.html` | Real estate listings (public) |
| `lodges.html` | Lodge booking with live availability |
| `admin.html` | Secure admin dashboard |
| `styles.css` | Global stylesheet (shared by all pages) |
| `supabase.js` | Supabase client + shared utilities |
| `supabase_schema.sql` | Database tables — run once in Supabase |

---

## Step 1 — Create your Supabase project

1. Go to **https://supabase.com** → Sign up / Log in → **New Project**
2. Give it a name (e.g. `gem-group`) and set a strong database password
3. Wait ~2 minutes for it to provision

---

## Step 2 — Run the database schema

1. In your Supabase dashboard, click **SQL Editor** in the left sidebar
2. Click **New query**
3. Paste the entire contents of `supabase_schema.sql`
4. Click **Run**

This creates 3 tables: `properties`, `rooms`, `bookings` — with all the right security rules.

---

## Step 3 — Add your Supabase credentials to supabase.js

1. In Supabase: go to **Settings → API**
2. Copy:
   - **Project URL** (looks like `https://abcxyz.supabase.co`)
   - **Anon / public key** (long string starting with `eyJ…`)
3. Open `supabase.js` and replace:
   ```js
   const SUPABASE_URL = 'https://YOUR_PROJECT_ID.supabase.co';
   const SUPABASE_KEY = 'YOUR_ANON_PUBLIC_KEY';
   ```

---

## Step 4 — Create an admin user

1. In Supabase: go to **Authentication → Users → Invite user**
2. Enter your admin email and send the invite
3. Open the email link, set your password
4. You can now log in at `admin.html` with that email + password

---

## Step 5 — Add your logo

Place `GEMLAND_LOGO-01.png` in the **same folder** as the HTML files.  
It shows automatically in the header on all pages.

---

## Step 6 — Set your WhatsApp number

Your WhatsApp number is already set to **+92 318 5512803** in `supabase.js`
(`WHATSAPP_NUMBER` constant), and it's used site-wide: the homepage "Chat
with us on WhatsApp" button, every footer, and the "Inquire via WhatsApp"
button on each property card.

When you add a property in the admin panel, you can optionally give it its
own WhatsApp number — otherwise it falls back to this default one.

To change the number later, edit this one line in `supabase.js`:
```js
const WHATSAPP_NUMBER = '923185512803'; // no + sign, no spaces
```

## Step 7 — Private admin URL (`/admin`)

The admin dashboard is no longer linked anywhere on the public site — it's
only reachable at a private URL. Once deployed to Netlify, going to:

```
https://your-site-name.netlify.app/admin
```

opens the admin login directly. Every other URL (the homepage, property
listings, lodge booking) works exactly as before for the public.

This works automatically because of the included `_redirects` file — make
sure it's uploaded to Netlify along with your other files (it has no file
extension, so it's easy to miss in Finder/Explorer — don't skip it).

---

## How to add content (no coding needed)

### Add a property listing
1. Open `admin.html` → sign in
2. Click **Properties** tab
3. Fill in: Title, Category, Location, Size, Price, Installment plan, Image URL, Description
4. Click **Add Property** → it appears on `property.html` instantly

### Add a room
1. Open `admin.html` → **Rooms** tab
2. Fill in: Name, Type, Nightly rate, Image URL, Features, Description
3. Click **Add Room** → it appears on `lodges.html`
4. Use the toggle to mark a room **Available / Unavailable**

### Mark a room unavailable
- Toggle switch in the Rooms table → **instantly blocks bookings** for that room
- The room card on `lodges.html` shows an **"Unavailable" badge** and the booking button is disabled

### Add a manual booking (phone/walk-in)
1. Admin → **Reservations** tab
2. Fill in guest name, phone, room, dates → **Add Booking**
3. Those dates are now **blocked on the public calendar**

---

## How image URLs work

You can use any direct image link:

**Option A — Supabase Storage (recommended)**
1. Supabase dashboard → **Storage** → Create bucket called `images` (set to public)
2. Upload your image → click it → copy the **Public URL**
3. Paste into the Image URL field in admin

**Option B — Any public image URL**
Paste a direct link from Google Drive (shared), Cloudinary, Imgur, etc.

---

## Deployment (putting it live)

Easiest: **Netlify**
1. Create a free account at https://netlify.com
2. Drag and drop your entire project folder onto the Netlify dashboard
3. Your site is live in ~30 seconds with a free URL
4. Optional: connect a custom domain

All pages work as plain HTML — no server, no build step needed.

---

## File structure to upload

```
your-folder/
├── index.html
├── property.html
├── lodges.html
├── admin.html
├── styles.css
├── style.css
├── supabase.js
├── _redirects            ← makes /admin work (no file extension)
└── GEMLAND_LOGO-01.png   ← your logo file
```

Do NOT upload `supabase_schema.sql` or this README — they are only for setup.
