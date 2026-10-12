import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabaseClient';
import Avatar from './Avatar';
import { getCategory } from '../lib/eventCategories';

export default function UserProfileModal({ userId, onClose }) {
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    async function loadUserProfile() {
      if (!userId) return;
      try {
        setLoading(true);
        setError(null);

        // Fetch profile details
        const { data: profileData, error: profileError } = await supabase
          .from('profiles')
          .select('id, display_name, avatar_url, bio, created_at')
          .eq('id', userId)
          .single();

        if (profileError) throw profileError;

        // Fetch activities hosted by this user
        const { data: activitiesData, error: activityError } = await supabase
          .from('activities')
          .select('id, title, category, start_time, location_label')
          .eq('creator_id', userId)
          .order('start_time', { ascending: false })
          .limit(5);

        if (activityError) throw activityError;

        setProfile({
          ...profileData,
          activities: activitiesData ?? [],
        });
      } catch (err) {
        setError(err.message ?? 'Failed to load profile');
      } finally {
        setLoading(false);
      }
    }

    loadUserProfile();
  }, [userId]);

  if (!userId) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-sm animate-fade-in">
      <div className="w-full max-w-md rounded-3xl bg-white p-6 shadow-2xl border border-neutral-100">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-base font-bold text-neutral-950">User Profile</h2>
          <button
            onClick={onClose}
            className="rounded-full p-1.5 text-neutral-400 hover:bg-neutral-100 hover:text-neutral-700 transition-colors"
          >
            ✕
          </button>
        </div>

        {loading && (
          <div className="py-12 text-center text-sm text-neutral-400">Loading profile...</div>
        )}

        {error && (
          <div className="py-8 text-center text-sm text-rose-600">{error}</div>
        )}

        {!loading && !error && profile && (
          <div>
            {/* User Header Info */}
            <div className="flex flex-col items-center text-center pb-6 border-b border-neutral-100">
              <div className="mb-3">
                <Avatar name={profile.display_name} variant="pro" />
              </div>
              <h3 className="text-lg font-bold text-neutral-950">{profile.display_name}</h3>
              <p className="text-xs text-neutral-500 mt-1 max-w-xs">
                {profile.bio || 'Active member of the Recess community.'}
              </p>
            </div>

            {/* Hosted Activities Section */}
            <div className="pt-5">
              <h4 className="text-xs font-semibold uppercase tracking-wider text-neutral-400 mb-3">
                Recent Hosted Activities
              </h4>

              {profile.activities.length === 0 ? (
                <p className="text-xs text-neutral-400 italic">No public activities hosted yet.</p>
              ) : (
                <div className="space-y-2 max-h-48 overflow-y-auto pr-1">
                  {profile.activities.map((act) => {
                    const cat = getCategory(act.category);
                    return (
                      <div
                        key={act.id}
                        className="flex items-center justify-between rounded-xl border border-neutral-100 p-3 bg-neutral-50/50"
                      >
                        <div className="flex items-center gap-2.5">
                          <span className="text-base">{cat.emoji}</span>
                          <div>
                            <p className="text-xs font-bold text-neutral-900">{act.title}</p>
                            <p className="text-[10px] text-neutral-500">{act.location_label || 'Campus venue'}</p>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            <div className="mt-6 pt-4 border-t border-neutral-100 flex justify-end">
              <button
                onClick={onClose}
                className="w-full rounded-xl bg-neutral-900 py-2.5 text-xs font-semibold text-white hover:bg-neutral-800 transition-colors"
              >
                Close
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
