import { Clock } from 'lucide-react';
import Avatar from './Avatar';
import { getCategory, toTagList } from '../lib/eventCategories';

export default function EventCard({ item, onOpen, onOpenProfile, onEdit, onDelete }) {
  const c = getCategory(item.category);
  const tags = toTagList(item.tags);

  const visibleTags = tags.slice(0, 3);
  const extraCount = tags.length - visibleTags.length;

  const handleProfileClick = (e) => {
    e.stopPropagation();
    if (item.userId && onOpenProfile) {
      onOpenProfile(item.userId);
    }
  };

  return (
    <div
      className={`rounded-2xl border border-l-[3px] border-neutral-100 bg-white p-4 transition-colors hover:border-neutral-200 ${c.left} ${c.leftHover}`}
    >
      <div className="mb-2.5 flex items-start justify-between">
        <div className="flex items-start gap-2.5">
          <div onClick={handleProfileClick} className="cursor-pointer">
            <Avatar name={item.author} variant="pro" />
          </div>

          
          <div>
            <span
              className={`mb-1 inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider ${c.badge}`}
            >
              <span aria-hidden="true">{c.emoji}</span>
              {c.label}
            </span>

            <h3 className="text-sm font-bold leading-tight text-neutral-950">
              {item.title}
            </h3>
          </div>
        </div>

        <span className={`ml-2 inline-flex max-w-[46%] items-start justify-end gap-1.5 pt-0.5 text-xs text-neutral-500 ${c.text}`}>
          <Clock className="mt-0.5 h-4 w-4 shrink-0" strokeWidth={2.25} aria-hidden="true" />
          <span className="text-right leading-snug text-neutral-500">{item.time}</span>
        </span>
      </div>

      <p className="mb-2.5 ml-10 flex items-center gap-1.5 text-xs text-neutral-500">
        <span className={c.text}>📍</span>
        {item.location}
      </p>

      {visibleTags.length > 0 && (
        <div className="mb-2.5 ml-10 flex flex-wrap items-center gap-1.5">
          {visibleTags.map(tag => (
            <span
              key={tag}
              className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${c.chip}`}
            >
              {tag}
            </span>
          ))}

          {extraCount > 0 && (
            <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-[10px] font-semibold text-neutral-500">
              +{extraCount}
            </span>
          )}
        </div>
      )}

      <div className="ml-10 flex items-center justify-between border-t border-neutral-100 pt-2.5">
        <span className="text-[11px] text-neutral-400">
          Hosted by{' '}
          <button
            onClick={handleProfileClick}
            className="font-medium text-neutral-600 hover:underline cursor-pointer"
          >
            {item.author}
          </button>
          </span>

        <button
          onClick={onOpen}
          className={`text-[11px] font-semibold transition-colors hover:underline ${c.textDeep}`}
        >
          RSVP →
        </button>
      </div>
    </div>
  );
}
