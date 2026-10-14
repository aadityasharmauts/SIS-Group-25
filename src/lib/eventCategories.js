// Category → styling lookup.
//
// The keys MUST match the category values written to Supabase (see the
// check constraint in the migration, and the picker in EventForm).
//
// IMPORTANT: every value below is a complete, literal Tailwind class string.
// Do NOT refactor these into `bg-${colour}-500` style interpolation — Tailwind
// scans source text for complete class names, so a built-up name is never
// generated and the colour disappears in production.

export const EVENT_CATEGORIES = {
  study_session: {
    id: 'study_session',
    label: 'Study session',
    emoji: '📚',
    hex: '#3b82f6', // map pin fill
    text: 'text-blue-600',
    textDeep: 'text-blue-700',
    soft: 'bg-blue-50',
    border: 'border-blue-200',
    left: 'border-l-blue-500',
    leftHover: 'hover:border-l-blue-500',
    solid: 'bg-blue-500',
    button: 'bg-blue-600 hover:bg-blue-700 disabled:bg-blue-200',
    joinButton: 'bg-blue-500 hover:bg-blue-600',
    focus: 'focus:border-blue-400 focus:ring-blue-100',
    chip: 'bg-blue-50 text-blue-700',
    chipActive: 'border-blue-500 bg-blue-500 text-white',
    badge: 'bg-blue-50 text-blue-700',
  },

  coffee_break: {
    id: 'coffee_break',
    label: 'Coffee break',
    emoji: '☕',
    hex: '#8b5cf6',
    text: 'text-violet-600',
    textDeep: 'text-violet-700',
    soft: 'bg-violet-50',
    border: 'border-violet-200',
    left: 'border-l-violet-500',
    leftHover: 'hover:border-l-violet-500',
    solid: 'bg-violet-500',
    button: 'bg-violet-600 hover:bg-violet-700 disabled:bg-violet-200',
    joinButton: 'bg-violet-500 hover:bg-violet-600',
    focus: 'focus:border-violet-400 focus:ring-violet-100',
    chip: 'bg-violet-50 text-violet-700',
    chipActive: 'border-violet-500 bg-violet-500 text-white',
    badge: 'bg-violet-50 text-violet-700',
  },

  lunch: {
    id: 'lunch',
    label: 'Lunch',
    emoji: '🍜',
    hex: '#f59e0b',
    text: 'text-amber-600',
    textDeep: 'text-amber-700',
    soft: 'bg-amber-50',
    border: 'border-amber-200',
    left: 'border-l-amber-500',
    leftHover: 'hover:border-l-amber-500',
    solid: 'bg-amber-500',
    button: 'bg-amber-600 hover:bg-amber-700 disabled:bg-amber-200',
    joinButton: 'bg-amber-500 hover:bg-amber-600',
    focus: 'focus:border-amber-400 focus:ring-amber-100',
    chip: 'bg-amber-50 text-amber-700',
    chipActive: 'border-amber-500 bg-amber-500 text-white',
    badge: 'bg-amber-50 text-amber-700',
  },

  walk: {
    id: 'walk',
    label: 'Walk',
    emoji: '🚶',
    hex: '#10b981',
    text: 'text-emerald-600',
    textDeep: 'text-emerald-700',
    soft: 'bg-emerald-50',
    border: 'border-emerald-200',
    left: 'border-l-emerald-500',
    leftHover: 'hover:border-l-emerald-500',
    solid: 'bg-emerald-500',
    button: 'bg-emerald-600 hover:bg-emerald-700 disabled:bg-emerald-200',
    joinButton: 'bg-emerald-500 hover:bg-emerald-600',
    focus: 'focus:border-emerald-400 focus:ring-emerald-100',
    chip: 'bg-emerald-50 text-emerald-700',
    chipActive: 'border-emerald-500 bg-emerald-500 text-white',
    badge: 'bg-emerald-50 text-emerald-700',
  },

  casual_game: {
    id: 'casual_game',
    label: 'Casual game',
    emoji: '🏀',
    hex: '#f43f5e',
    text: 'text-rose-600',
    textDeep: 'text-rose-700',
    soft: 'bg-rose-50',
    border: 'border-rose-200',
    left: 'border-l-rose-500',
    leftHover: 'hover:border-l-rose-500',
    solid: 'bg-rose-500',
    button: 'bg-rose-600 hover:bg-rose-700 disabled:bg-rose-200',
    joinButton: 'bg-rose-500 hover:bg-rose-600',
    focus: 'focus:border-rose-400 focus:ring-rose-100',
    chip: 'bg-rose-50 text-rose-700',
    chipActive: 'border-rose-500 bg-rose-500 text-white',
    badge: 'bg-rose-50 text-rose-700',
  },

  group_discussion: {
    id: 'group_discussion',
    label: 'Group discussion',
    emoji: '💬',
    hex: '#0ea5e9',
    text: 'text-sky-600',
    textDeep: 'text-sky-700',
    soft: 'bg-sky-50',
    border: 'border-sky-200',
    left: 'border-l-sky-500',
    leftHover: 'hover:border-l-sky-500',
    solid: 'bg-sky-500',
    button: 'bg-sky-600 hover:bg-sky-700 disabled:bg-sky-200',
    joinButton: 'bg-sky-500 hover:bg-sky-600',
    focus: 'focus:border-sky-400 focus:ring-sky-100',
    chip: 'bg-sky-50 text-sky-700',
    chipActive: 'border-sky-500 bg-sky-500 text-white',
    badge: 'bg-sky-50 text-sky-700',
  },

  // Fallback — keeps your original orange for anything uncategorised.
  other: {
    id: 'other',
    label: 'Other',
    emoji: '📌',
    hex: '#f97316',
    text: 'text-orange-500',
    textDeep: 'text-orange-700',
    soft: 'bg-orange-50',
    border: 'border-orange-200',
    left: 'border-l-orange-500',
    leftHover: 'hover:border-l-orange-500',
    solid: 'bg-orange-500',
    button: 'bg-orange-600 hover:bg-orange-700 disabled:bg-orange-200',
    joinButton: 'bg-orange-500 hover:bg-orange-600',
    focus: 'focus:border-orange-400 focus:ring-orange-100',
    chip: 'bg-orange-50 text-orange-700',
    chipActive: 'border-orange-500 bg-orange-500 text-white',
    badge: 'bg-orange-50 text-orange-700',
  },
};

export const DEFAULT_CATEGORY = 'other';

// Order determines the picker order in EventForm (study_session first).
export const CATEGORY_OPTIONS = Object.values(EVENT_CATEGORIES);

export const MAX_TAGS = 6;
export const MAX_TAG_LENGTH = 24;

// Shown as one-tap chips under the tag input.
export const TAG_SUGGESTIONS = [
  'study oriented',
  'physics student',
  'first years',
  'international students',
  'exam prep',
  'beginners welcome',
];

/** Always returns a usable category, so an unknown/absent value can't break a render. */
export function getCategory(id) {
  return EVENT_CATEGORIES[id] ?? EVENT_CATEGORIES[DEFAULT_CATEGORY];
}

/** Accepts an array (Supabase text[]) or a comma string, always returns a clean array. */
export function toTagList(value) {
  if (Array.isArray(value)) {
    return value.map(tag => String(tag).trim()).filter(Boolean);
  }

  if (typeof value === 'string') {
    return value
      .split(',')
      .map(tag => tag.trim())
      .filter(Boolean);
  }

  return [];
}

function normaliseTag(raw) {
  return String(raw).trim().replace(/\s+/g, ' ').slice(0, MAX_TAG_LENGTH);
}

/** Trims, length-caps, blocks case-insensitive duplicates, enforces the count cap. */
export function addTag(tags, raw) {
  const tag = normaliseTag(raw);

  if (!tag) return tags;
  if (tags.length >= MAX_TAGS) return tags;

  const isDuplicate = tags.some(
    existing => existing.toLowerCase() === tag.toLowerCase()
  );
  if (isDuplicate) return tags;

  return [...tags, tag];
}

/** Splits pasted/comma-typed input into individual tags. */
export function parseTagInput(tags, value) {
  return value.split(',').reduce((acc, part) => addTag(acc, part), tags);
}
