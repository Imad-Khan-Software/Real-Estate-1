# Gem Group of Companies — Real Estate & Hospitality Hub 🏢🏨✨

A fully responsive corporate hub and booking management platform designed for the Gem Group of Companies. Features a secure administrative dashboard, real-time lodge booking, and direct property showcase integration.

🔗 **Live Demo:** https://alaflaila.netlify.app

---

## 📂 Project Architecture

* **`index.html`** — Corporate landing page and main organizational hub.
* **`property.html`** — Public real estate listings grid displaying available plots, homes, and investment properties.
* **`lodges.html`** — Interactive lodge reservation system featuring live room availability.
* **`admin.html`** — Secure, private administrative dashboard for managing inventory, rooms, and manual reservations.
* **`styles.css` / `style.css`** — Centralized global stylesheets ensuring consistent design system implementation.
* **`supabase.js`** — Unified Supabase client wrapper, shared utility scripts, and global configuration variables (including default WhatsApp integration).
* **`supabase_schema.sql`** — Database initialization script establishing tables (`properties`, `rooms`, `bookings`) and security rules.
* **`_redirects`** — Routing configuration file enabling clean access to the private admin portal (`/admin`) on Netlify.

---

## 🚀 Setup & Deployment Guide

1. Create a new project on [Supabase](https://supabase.com).
2. Open the **SQL Editor** in your Supabase dashboard, paste the contents of `supabase_schema.sql`, and execute it.
3. Retrieve your **Project URL** and **Anon public key** from Supabase under **Settings → API**, and update `supabase.js`.
4. Create your administrator credentials under Supabase **Authentication → Users**.
5. Ensure your asset files, including `GEMLAND_LOGO-01.png` and the extensionless `_redirects` file, are located in the root folder.
6. Drag and drop your project directory onto **Netlify** for instant global deployment.

---

## ⚙️ Administrative Workflows

* **Property Management:** Add or edit real estate listings directly via `admin.html` with instant reflection on `property.html`.
* **Lodge Bookings:** Manage room inventories, nightly rates, and toggle live availability states to automatically update booking buttons on `lodges.html`.
* **WhatsApp Integration:** Built-in direct communication routing defaults to configured customer service numbers (`+92 318 5512803`), with support for property-specific contact overrides.
