// supabase-client.js
// Shared Supabase client + auth helpers used by every page.
// Import this with: <script type="module" src="supabase-client.js"></script>
// or: import { supabase, getCurrentUser } from './supabase-client.js'

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ====== CONFIGURE THESE ======
export const SUPABASE_URL = 'https://glficbqlwjxedlbovdtn.supabase.co';
export const SUPABASE_ANON_KEY = 'sb_publishable_J2Txi6Dt26H0JK_SIvIO2w_esti_hDr';
// =============================

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

/**
 * Returns the logged-in user combined with their profile row,
 * or null if not signed in.
 * Shape: { id, email, name, role, contact, address }
 */
export async function getCurrentUser() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return null;

  const user = session.user;
  const { data: profile } = await supabase
    .from('profiles')
    .select('name, role, contact, address')
    .eq('id', user.id)
    .maybeSingle();

  return {
    id: user.id,
    email: user.email,
    name: profile?.name || user.user_metadata?.name || user.email,
    role: profile?.role || user.user_metadata?.role || 'buyer',
    contact: profile?.contact || null,
    address: profile?.address || null
  };
}

/**
 * Returns the supplier row for a given user id, or null.
 */
export async function getSupplierByUserId(userId) {
  if (!userId) return null;
  const { data, error } = await supabase
    .from('suppliers')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) console.error('getSupplierByUserId:', error);
  return data;
}

/**
 * Returns a supplier row by email.
 */
export async function getSupplierByEmail(email) {
  if (!email) return null;
  const { data, error } = await supabase
    .from('suppliers')
    .select('*')
    .eq('email', email)
    .maybeSingle();
  if (error) console.error('getSupplierByEmail:', error);
  return data;
}

/**
 * Sign out and redirect.
 */
export async function signOutAndGo(url = 'index.html') {
  await supabase.auth.signOut();
  location.href = url;
}

/**
 * Tiny HTML-escape helper for rendering user-provided strings.
 */
export function escapeHtml(str) {
  return String(str ?? '').replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}
