# COSTruct — Supabase setup

Every page now talks to Supabase instead of `localStorage`. Follow these steps before opening anything in the browser.

## 1. Create a Supabase project

1. Go to https://supabase.com → **New project**
2. Once ready, open **Project Settings → API** and copy:
   - **Project URL** (looks like `https://xxxxxxxx.supabase.co`)
   - **anon public** key

## 2. Configure the client

Open `supabase-client.js` and paste the two values:

```js
export const SUPABASE_URL     = 'https://glficbqlwjxedlbovdtn.supabase.co';
export const SUPABASE_ANON_KEY = 'sb_publishable_J2Txi6Dt26H0JK_SIvIO2w_esti_hDr';
```

This is the **anon** key, not the service-role key. It's safe in the browser — RLS protects your data.

## 3. Run the schema

1. Supabase Dashboard → **SQL Editor** → **New query**
2. Paste the entire contents of `supabase_schema.sql`
3. Run

This creates: `profiles`, `suppliers`, `materials`, `estimates`, all RLS policies, realtime on `suppliers` and `materials`, and the `increment_profile_views` RPC.

## 4. Turn off email confirmation (dev only)

**Dashboard → Authentication → Providers → Email** → turn off **"Confirm email"**.

Why: with confirmation on, `supabase.auth.signUp()` returns no session. The follow-up `profiles` / `suppliers` inserts during registration then fail under RLS because `auth.uid()` is null. For production, re-enable confirmation and move the profile/supplier inserts into a `handle_new_user` trigger on `auth.users`.

## 5. Serve over HTTP

You **cannot open the HTML files directly** (`file://...`). ES module imports and the Supabase auth session won't work. Pick one:

```bash
# Any of these from the project folder:
python3 -m http.server 8000
npx serve .
php -S localhost:8000
```

Then open `http://localhost:8000/index.html`.

Or deploy the folder to Vercel / Netlify / Cloudflare Pages / GitHub Pages — any static host works.

## 6. Try it

1. Open `login.html` → **Register** → create a buyer and a supplier (use different emails).
2. Log in as the supplier → `admin.html` opens → add a material.
3. Log out → log in as the buyer → visit `suppliers.html` → click the supplier → see the material in `catalog.html`.
4. Run an estimation on `estimation.html`, pick the supplier card, save the estimate, then visit `estimation.html?view=saved` to see it persisted.

---

## File map

| File | Purpose |
|---|---|
| `supabase-client.js` | Shared client + `getCurrentUser`, `getSupplierByEmail`, `getSupplierByUserId`, `signOutAndGo`, `escapeHtml` |
| `supabase_schema.sql` | Tables, RLS, realtime, trigger, RPC |
| `login.html` | Email/password signup + login, role check |
| `index.html` | Home page; shows survey for guests, dashboard nav for users |
| `suppliers.html` | Public supplier directory with realtime updates |
| `catalog.html` | Single supplier page with materials list + view counter |
| `admin.html` | Supplier dashboard — materials CRUD, store profile |
| `estimation.html` | Estimation tool; loads suppliers + materials from DB; saves estimates per user |

## Data model

```
auth.users (Supabase-managed)
    │
    ├── profiles        (1:1)  id, name, role, contact, address
    │
    └── suppliers       (1:1 for role='supplier')
            │           user_id, email, name, owner_name, category,
            │           location, contact, address, description,
            │           since, delivery, rating, profile_views
            │
            └── materials (1:many)
                         supplier_id, name, price, unit,
                         description, category, qty, stock

auth.users
    │
    └── estimates       (1:many)
                        user_id, name, total, area, floors,
                        supplier, breakdown, saved_at
```

## RLS summary

| Table | Read | Write |
|---|---|---|
| `profiles` | self only | self only |
| `suppliers` | **public** | owner only |
| `materials` | **public** | owning supplier only |
| `estimates` | owner only | owner only |

Public-read on `suppliers` and `materials` is what makes the directory and catalog work for guests.

## Known gotchas

- **`auth.signUp` with confirmation on**: disable it for dev (Step 4) or the first-time profile/supplier insert won't happen.
- **Opening via `file://`**: the page loads but Supabase does nothing — modules can't be imported and `localStorage` for auth is scoped to the origin.
- **Role mismatch on login**: login.html rejects a buyer account that tries to sign in on the "Supplier" tab (or vice versa). This is intentional.
- **Guest estimates**: still live in `localStorage` under `costruct_estimates_guest` — they don't migrate to the DB on login. Add a one-time migration if you want that.
- **Profile-view counter**: uses the `increment_profile_views` RPC so any visitor can bump it without needing write access to `suppliers`.

## Going to production

When you're ready:

1. Re-enable **Confirm email** in Supabase.
2. Move profile/supplier inserts into a database trigger:
   ```sql
   create or replace function public.handle_new_user()
   returns trigger language plpgsql security definer as $$
   begin
     insert into public.profiles (id, name, role, contact, address)
     values (
       new.id,
       coalesce(new.raw_user_meta_data->>'name', new.email),
       coalesce(new.raw_user_meta_data->>'role', 'buyer'),
       new.raw_user_meta_data->>'contact',
       new.raw_user_meta_data->>'address'
     );
     return new;
   end $$;

   create trigger on_auth_user_created
   after insert on auth.users
   for each row execute procedure public.handle_new_user();
   ```
   Then drop the client-side `profiles.insert` from `login.html`. Keep the `suppliers.insert` client-side (it can run after the user confirms and signs in for the first time), or gate supplier registration behind a verified-email step.
3. Set up OAuth providers properly in **Authentication → Providers** if you want Google/Facebook login.
4. Consider adding **indexes** on columns you filter on (`materials.category`, `estimates.user_id` — already indexed).
