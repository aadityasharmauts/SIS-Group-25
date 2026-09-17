 import React, { useState } from 'react';
import { User, BookOpen, Briefcase, Mail, MapPin, Edit3, Save, X } from 'lucide-react';

export default function Profile() {
  const [isEditing, setIsEditing] = useState(false);

  // Mock initial state - you can replace this with fetched user data later
  const [profile, setProfile] = useState({
    fullName: 'Salha Alghoraibi',
    email: 'name@student.uts.edu.au',
    occupation: 'Software Engineering Student',
    degree: 'Bachelor of Engineering (Honours)',
    campusLocation: 'Sydney, Australia',
    bio: 'description of yourself',
  });

  const [formData, setFormData] = useState(profile);

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
  };

  const handleSave = (e) => {
    e.preventDefault();
    setProfile(formData);
    setIsEditing(false);
    // TODO: Add Supabase update call here later
  };

  const handleCancel = () => {
    setFormData(profile);
    setIsEditing(false);
  };

  return (
    <div className="max-w-4xl mx-auto p-6 space-y-6">
      {/* Header Banner & Profile Card */}
      <div className="bg-white rounded-2xl shadow-sm border border-slate-100 overflow-hidden">
        <div className="px-8 pb-8 relative">
          {/* Avatar & Action Buttons */}
          <div className="flex justify-between items-end pt-6 mb-6">            <div className="w-32 h-32 rounded-2xl bg-white p-2 shadow-md border border-slate-100 flex items-center justify-center">
              <div className="w-full h-full bg-orange-600 text-white rounded-xl flex items-center justify-center text-3xl font-bold">
                {profile.fullName.charAt(0)}
              </div>
            </div>

            {!isEditing ? (
              <button
              onClick={() => setIsEditing(true)}
              className="flex items-center gap-2 px-4 py-2 bg-orange-600 hover:bg-orange-700 text-white text-sm font-medium rounded-xl transition-colors shadow-sm"
            >
                <Edit3 size={16} />
                Edit Profile
              </button>
            ) : (
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={handleCancel}
                  className="flex items-center gap-1 px-4 py-2 bg-white border border-slate-200 hover:bg-slate-50 text-slate-700 text-sm font-medium rounded-xl transition-colors"
                >
                  <X size={16} />
                  Cancel
                </button>
                <button
                  type="submit"
                  form="profile-form"
                  className="flex items-center gap-1 px-4 py-2 bg-orange-600 hover:bg-orange-700 text-white text-sm font-medium rounded-xl transition-colors shadow-sm"
                >
                  <Save size={16} />
                  Save Changes
                </button>
              </div>
            )}
          </div>

          {/* View vs Edit Form */}
          {!isEditing ? (
            <div className="space-y-6">
              <div>
                <h1 className="text-2xl font-bold text-slate-900">{profile.fullName}</h1>
                <p className="text-slate-500 text-sm flex items-center gap-1.5 mt-1">
                  <Mail size={14} className="text-slate-400" />
                  {profile.email}
                </p>
              </div>

              {/* Bio Section */}
              <div className="space-y-2">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400">Bio</h3>
                <p className="text-slate-700 leading-relaxed bg-slate-50 p-4 rounded-xl border border-slate-100">
                  {profile.bio || 'No bio provided yet.'}
                </p>
              </div>

              {/* Details Grid */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 pt-2">
                <div className="flex items-center gap-3 p-4 rounded-xl bg-slate-50 border border-slate-100">
                  <div className="p-2.5 rounded-lg bg-orange-50 text-orange-600">
                    <Briefcase size={20} />
                  </div>
                  <div>
                    <span className="block text-xs font-medium text-slate-400">Occupation</span>
                    <span className="text-sm font-semibold text-slate-800">{profile.occupation || 'Not specified'}</span>
                  </div>
                </div>

                <div className="flex items-center gap-3 p-4 rounded-xl bg-slate-50 border border-slate-100">
                  <div className="p-2.5 rounded-lg bg-amber-50 text-amber-600">
                    <BookOpen size={20} />
                  </div>
                  <div>
                    <span className="block text-xs font-medium text-slate-400">Degree / Program</span>
                    <span className="text-sm font-semibold text-slate-800">{profile.degree || 'Not specified'}</span>
                  </div>
                </div>

                <div className="flex items-center gap-3 p-4 rounded-xl bg-slate-50 border border-slate-100">
                  <div className="p-2.5 rounded-lg bg-orange-50 text-orange-600">
                    <MapPin size={20} />
                  </div>
                  <div>
                    <span className="block text-xs font-medium text-slate-400">Campus Location</span>
                    <span className="text-sm font-semibold text-slate-800">{profile.campusLocation || 'Not specified'}</span>
                  </div>
                </div>
              </div>
            </div>
          ) : (
            <form id="profile-form" onSubmit={handleSave} className="space-y-5">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-600 uppercase tracking-wider mb-1.5">
                    Full Name
                  </label>
                  <input
                    type="text"
                    name="fullName"
                    value={formData.fullName}
                    onChange={handleChange}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500/20 focus:border-orange-600 transition-all"
                    required
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-600 uppercase tracking-wider mb-1.5">
                    Email Address
                  </label>
                  <input
                    type="email"
                    name="email"
                    value={formData.email}
                    onChange={handleChange}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500/20 focus:border-orange-600 transition-all"
                    required
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-600 uppercase tracking-wider mb-1.5">
                    Occupation
                  </label>
                  <input
                    type="text"
                    name="occupation"
                    value={formData.occupation}
                    onChange={handleChange}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500/20 focus:border-orange-600 transition-all"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-600 uppercase tracking-wider mb-1.5">
                    Degree / Program
                  </label>
                  <input
                    type="text"
                    name="degree"
                    value={formData.degree}
                    onChange={handleChange}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500/20 focus:border-orange-600 transition-all"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-600 uppercase tracking-wider mb-1.5">
                    Campus Location
                  </label>
                  <input
                    type="text"
                    name="campusLocation"
                    value={formData.campusLocation}
                    onChange={handleChange}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500/20 focus:border-orange-600 transition-all"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 uppercase tracking-wider mb-1.5">
                  Bio
                </label>
                <textarea
                  name="bio"
                  rows={4}
                  value={formData.bio}
                  onChange={handleChange}
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500/20 focus:border-orange-600 transition-all resize-none"
                />
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}