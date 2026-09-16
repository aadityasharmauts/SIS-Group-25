import { useState } from 'react';

const inputClass =
  'w-full px-3 py-2 text-sm border border-neutral-200 rounded-lg bg-neutral-50 text-neutral-900 placeholder-neutral-400 focus:outline-none focus:border-orange-400 focus:ring-2 focus:ring-orange-100 transition-all font-[inherit]';

export default function EventForm({ onSubmit, onCancel }) {
  const [title, setTitle] = useState('');
  const [location, setLocation] = useState('');
  const [time, setTime] = useState('');

  // Default location: UTS campus
  const [mapX, setMapX] = useState('512');
  const [mapY, setMapY] = useState('512');
  

  const handleSubmit = () => {
    if (!title.trim() || !location.trim()) return;

    const mapXNumber = Number(mapX);
    const mapYNumber = Number(mapY);

    // Prevent invalid coordinates outside the campus image.
    if (
      Number.isNaN(mapXNumber) ||
      Number.isNaN(mapYNumber) ||
      mapXNumber < 0 ||
      mapXNumber > 1824 ||
      mapYNumber < 0 ||
      mapYNumber > 1824
    ) {
      return;
    }

    onSubmit({
      title: title.trim(),
      location: location.trim(),
      time: time.trim() || 'TBD',
      mapX: mapXNumber,
      mapY: mapYNumber,
    });
    
  };

  const formIsInvalid =
    !title.trim() ||
    !location.trim() ||
    !mapX.trim() ||
    !mapY.trim();

  return (
    <div className="rounded-2xl border border-orange-200 bg-white p-5">
      <h2 className="mb-0.5 text-sm font-bold text-neutral-950">
        Host a campus event
      </h2>

      <p className="mb-4 text-xs text-neutral-400">
        Open it up — anyone nearby can see it and RSVP.
      </p>

      <div className="space-y-3">
        <div>
          <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-wider text-neutral-500">
            Event title
          </label>

          <input
            type="text"
            value={title}
            onChange={event => setTitle(event.target.value)}
            placeholder="React study session"
            maxLength={80}
            className={inputClass}
          />
        </div>

        <div>
          <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-wider text-neutral-500">
            Location
          </label>

          <input
            type="text"
            value={location}
            onChange={event => setLocation(event.target.value)}
            placeholder="UTS Building 11, Lab 302"
            maxLength={80}
            className={inputClass}
          />
        </div>

        <div>
          <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-wider text-neutral-500">
            Time
          </label>

          <input
            type="text"
            value={time}
            onChange={event => setTime(event.target.value)}
            placeholder="3:00 PM"
            maxLength={40}
            className={inputClass}
          />
        </div>

        <div className="grid grid-cols-2 gap-3">
  <div>
    <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-wider text-neutral-500">
      Map X
    </label>

    <input
      type="number"
      value={mapX}
      onChange={event => setMapX(event.target.value)}
      min="0"
      max="1824"
      className={inputClass}
    />
  </div>

  <div>
    <label className="mb-1.5 block text-[11px] font-semibold uppercase tracking-wider text-neutral-500">
      Map Y
    </label>

    <input
      type="number"
      value={mapY}
      onChange={event => setMapY(event.target.value)}
      min="0"
      max="1824"
      className={inputClass}
    />
  </div>
</div>


        <p className="text-[11px] leading-relaxed text-neutral-400">
          The coordinates determine where the event marker appears on the map.
        </p>
      </div>

      <div className="mt-5 flex gap-2">
        <button
          type="button"
          onClick={onCancel}
          className="flex-1 rounded-xl bg-neutral-100 py-2.5 text-sm font-semibold text-neutral-600 transition-colors hover:bg-neutral-200"
        >
          Cancel
        </button>

        <button
          type="button"
          onClick={handleSubmit}
          disabled={formIsInvalid}
          className="flex-[2] rounded-xl bg-orange-600 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-orange-700 disabled:cursor-not-allowed disabled:bg-orange-200"
        >
          Publish event
        </button>
      </div>
    </div>
  );
}
