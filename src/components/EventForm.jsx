import { useState } from 'react';
import { MapContainer, Marker, TileLayer, useMapEvents } from 'react-leaflet';
import {
  OSM_ATTRIBUTION,
  OSM_TILE_URL,
  EVENT_MARKER_RADIUS_METERS,
  UTS_CENTER,
  formatCoordinates,
  isWithinLocationRadius,
  isValidCoordinates,
  wrapLongitude,
} from '../constants/map';
import { selectionIcon } from '../utils/mapIcons';
import {
  CATEGORY_OPTIONS,
  MAX_TAGS,
  MAX_TAG_LENGTH,
  TAG_SUGGESTIONS,
  addTag,
  getCategory,
  parseTagInput,
} from '../lib/eventCategories';

// Ring width lives here; the selected category supplies the ring colour.
const inputBase =
  'w-full rounded-xl border border-neutral-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 transition-colors';

const labelClass = 'block text-xs font-semibold text-neutral-700';
const labelTextClass = 'mb-1 block';
const MAX_ACTIVITY_DURATION_MS = 4 * 60 * 60 * 1000;

function toLocalDateTime(date) {
  const offset = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

function LocationPicker({ position, onChange }) {
  useMapEvents({
    click: event =>
      onChange([event.latlng.lat, wrapLongitude(event.latlng.lng)]),
  });

  return (
    <Marker
      position={position}
      icon={selectionIcon}
      draggable
      title="Drag to choose the event location"
      alt="Selected event location"
      eventHandlers={{
        dragend: event => {
          const { lat, lng } = event.target.getLatLng();
          onChange([lat, wrapLongitude(lng)]);
        },
      }}
    />
  );
}

export default function EventForm({
  initialData = null,
  areas = [],
  onSubmit,
  onCancel,
  submitting = false,
}) {
  const [title, setTitle] = useState(initialData?.title || '');
  const [location, setLocation] = useState(initialData?.location || '');
  const [description, setDescription] = useState(initialData?.description || '');
  const [category, setCategory] = useState(initialData?.category || CATEGORY_OPTIONS[0].id);
  const [tags, setTags] = useState(initialData?.tags || []);
  const [tagDraft, setTagDraft] = useState('');
  const participantLimit = String(initialData?.participantLimit || '3');
  const areaId = initialData?.areaId || '';
  const [startTime, setStartTime] = useState(() =>
    initialData?.startTime ? toLocalDateTime(new Date(initialData.startTime)) : toLocalDateTime(new Date(Date.now() + 30 * 60 * 1000))
  );
  const [endTime, setEndTime] = useState(() =>
    initialData?.endTime ? toLocalDateTime(new Date(initialData.endTime)) : toLocalDateTime(new Date(Date.now() + 90 * 60 * 1000))
  );
  const [position, setPosition] = useState(
    initialData?.latitude && initialData?.longitude 
      ? [initialData.latitude, initialData.longitude] 
      : UTS_CENTER
  );
  const c = getCategory(category);
  const field = `${inputBase} ${c.focus}`;
  const effectiveAreaId = areaId || areas[0]?.id || '';
  const selectedArea = areas.find(area => area.id === effectiveAreaId);
  const selectedLocation = selectedArea?.locations;
  const markerWithinArea = isWithinLocationRadius(
    position[0],
    position[1],
    selectedLocation?.latitude,
    selectedLocation?.longitude
  );
  const startTimestamp = Date.parse(startTime);
  const endTimestamp = Date.parse(endTime);
  const durationMs = endTimestamp - startTimestamp;
  const timeWindowValid = Number.isFinite(startTimestamp)
    && Number.isFinite(endTimestamp)
    && durationMs > 0
    && durationMs <= MAX_ACTIVITY_DURATION_MS;
  const timeWindowError = !startTime || !endTime || timeWindowValid
    ? null
    : durationMs <= 0
      ? 'The event end time must be after its start time.'
      : 'Events can last up to 4 hours. Shorten the end time.';
  const tagLimitReached = tags.length >= MAX_TAGS;

  const commitTag = () => {
    setTags(previous => addTag(previous, tagDraft));
    setTagDraft('');
  };

  const handleTagChange = value => {
    // Pasting or typing a comma commits everything before it.
    if (value.includes(',')) {
      setTags(previous => parseTagInput(previous, value));
      setTagDraft('');
      return;
    }

    setTagDraft(value);
  };

  const handleTagKeyDown = event => {
    if (event.key === 'Enter' || event.key === ',') {
      event.preventDefault();
      commitTag();
      return;
    }

    // Backspace on an empty field removes the most recent tag.
    if (event.key === 'Backspace' && !tagDraft) {
      setTags(previous => previous.slice(0, -1));
    }
  };

  const formIsInvalid = !title.trim()
    || title.trim().length < 3
    || !location.trim()
    || !effectiveAreaId
    || !startTime
    || !endTime
    || !timeWindowValid
    || !isValidCoordinates(position[0], position[1])
    || !markerWithinArea;

  const handleSubmit = event => {
    event.preventDefault();
    if (formIsInvalid) return;

    onSubmit({
      title: title.trim(),
      location: location.trim(),
      description: description.trim() || null,
      category,
      // Commits anything still sitting in the tag input.
      tags: addTag(tags, tagDraft),
      participantLimit: Number(participantLimit),
      areaId: effectiveAreaId,
      startTime: new Date(startTime).toISOString(),
      endTime: new Date(endTime).toISOString(),
      latitude: position[0],
      longitude: position[1],
    });
  };

  return (
    <form
      onSubmit={handleSubmit}
      className={`space-y-3 rounded-2xl border bg-white p-4 shadow-sm ${c.border}`}
    >
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-sm font-bold text-neutral-900">
            {initialData ? 'Edit event' : 'Host an event'}
          </h2>

          <p className="text-[11px] text-neutral-400">
            Create a public meetup for verified Recess users.
          </p>
        </div>

        <button
          type="button"
          onClick={onCancel}
          className="text-xs text-neutral-400 hover:text-neutral-700"
        >
          Cancel
        </button>
      </div>

      <label className={labelClass}>
        <span className={labelTextClass}>Event title</span>

        <input
          value={title}
          onChange={event => setTitle(event.target.value)}
          required
          minLength={3}
          maxLength={80}
          placeholder="React study session"
          className={field}
        />
      </label>

      <label className={labelClass}>
        <span className={labelTextClass}>Venue or meeting point</span>

        <input
          value={location}
          onChange={event => setLocation(event.target.value)}
          required
          maxLength={120}
          placeholder="UTS Building 11, Lab 302"
          className={field}
        />
      </label>

      <label className={labelClass}>
        <span className={labelTextClass}>Category</span>

        <select
          value={category}
          onChange={event => setCategory(event.target.value)}
          className={field}
        >
          {CATEGORY_OPTIONS.map(option => (
            <option key={option.id} value={option.id}>
              {option.emoji} {option.label}
            </option>
          ))}
        </select>
      </label>

      <p className={`text-[11px] ${c.text}`}>
        {c.emoji} {c.label} sets this event's colour on the feed, the details
        page and the map pin.
      </p>

      <div>
        <div className="mb-1 flex items-center justify-between">
          <span className="text-xs font-semibold text-neutral-700">
            Tags — who is this for?
          </span>

          <span className="text-[10px] text-neutral-400">
            {tags.length}/{MAX_TAGS}
          </span>
        </div>

        {tags.length > 0 && (
          <div className="mb-2 flex flex-wrap gap-1.5">
            {tags.map(tag => (
              <span
                key={tag}
                className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium ${c.chip}`}
              >
                {tag}

                <button
                  type="button"
                  onClick={() =>
                    setTags(previous => previous.filter(item => item !== tag))
                  }
                  aria-label={`Remove tag ${tag}`}
                  className="text-xs leading-none opacity-60 transition-opacity hover:opacity-100"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
        )}

        <input
          value={tagDraft}
          onChange={event => handleTagChange(event.target.value)}
          onKeyDown={handleTagKeyDown}
          onBlur={commitTag}
          placeholder="physics student, study oriented"
          maxLength={MAX_TAG_LENGTH}
          disabled={tagLimitReached}
          className={`${field} disabled:cursor-not-allowed disabled:bg-neutral-100 disabled:text-neutral-400`}
        />

        {!tagLimitReached && tags.length < TAG_SUGGESTIONS.length && (
          <div className="mt-1.5 flex flex-wrap gap-1.5">
            {TAG_SUGGESTIONS.filter(
              suggestion =>
                !tags.some(
                  tag => tag.toLowerCase() === suggestion.toLowerCase()
                )
            )
              .slice(0, 4)
              .map(suggestion => (
                <button
                  key={suggestion}
                  type="button"
                  onClick={() => setTags(previous => addTag(previous, suggestion))}
                  className="rounded-full border border-neutral-200 bg-white px-2 py-0.5 text-[10px] font-medium text-neutral-500 transition-colors hover:border-neutral-300 hover:text-neutral-700"
                >
                  + {suggestion}
                </button>
              ))}
          </div>
        )}

        <p className="mt-1 text-[11px] text-neutral-400">
          {tagLimitReached
            ? `Tag limit reached (${MAX_TAGS}). Remove one to add another.`
            : `Type a tag and press Enter or comma. Up to ${MAX_TAGS} tags, ${MAX_TAG_LENGTH} characters each.`}
        </p>
      </div>

      <label className={labelClass}>
        <span className={labelTextClass}>Description (optional)</span>

        <textarea
          value={description}
          onChange={event => setDescription(event.target.value)}
          maxLength={500}
          rows={2}
          placeholder="What should people know before joining?"
          className={`${field} resize-none`}
        />
      </label>

      <div className="grid grid-cols-2 gap-2">
        <label className={labelClass}>
          <span className={labelTextClass}>Starts</span>

          <input
            type="datetime-local"
            value={startTime}
            onChange={event => setStartTime(event.target.value)}
            required
            className={field}
          />
        </label>

        <label className={labelClass}>
          <span className={labelTextClass}>Ends</span>

          <input
            type="datetime-local"
            value={endTime}
            onChange={event => setEndTime(event.target.value)}
            required
            className={field}
          />
        </label>
      </div>

      {timeWindowError && (
        <p role="alert" className="text-[11px] text-red-600">
          {timeWindowError}
        </p>
      )}

      <div>
        <p className="mb-1 text-xs font-semibold text-neutral-700">
          Choose the event location
        </p>

        <p className="mb-2 text-[11px] text-neutral-400">
          Click the map or drag the pin. The pin is a public meeting point, not
          your live location.
        </p>

        <MapContainer
          center={position}
          zoom={16}
          minZoom={2}
          maxZoom={19}
          worldCopyJump
          scrollWheelZoom={false}
          className="isolate z-0 h-64 w-full overflow-hidden rounded-xl"
          aria-label="Choose event location on map"
        >
          <TileLayer
            attribution={OSM_ATTRIBUTION}
            url={OSM_TILE_URL}
            maxZoom={19}
          />

          <LocationPicker position={position} onChange={setPosition} />
        </MapContainer>

        <p aria-live="polite" className="mt-1 text-[11px] text-neutral-500">
          Selected: {formatCoordinates(position[0], position[1])}
        </p>

        {!markerWithinArea && (
          <p role="alert" className="mt-1 text-[11px] text-red-600">
            Move the pin within {EVENT_MARKER_RADIUS_METERS} metres of the
            selected area before publishing.
          </p>
        )}
      </div>

      <button
        type="submit"
        disabled={formIsInvalid || submitting}
        className={`w-full rounded-xl py-2.5 text-xs font-semibold text-white transition-colors disabled:cursor-not-allowed ${c.button}`}
      >
        {submitting ? 'Saving…' : initialData ? 'Save changes' : 'Publish event'}
      </button>
    </form>
  );
}
