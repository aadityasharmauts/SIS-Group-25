import { useEffect, useRef } from 'react';
import { MapContainer, Marker, Popup, TileLayer, useMap } from 'react-leaflet';
import L from 'leaflet';
import {
  UTS_CENTER,
  OSM_TILE_URL,
  OSM_ATTRIBUTION,
  isValidCoordinates,
} from '../constants/map';
import { CATEGORY_OPTIONS, getCategory } from '../lib/eventCategories';

function FitToEvents({ events }) {
  const map = useMap();
  const previousPoints = useRef(null);

  useEffect(() => {
    const points = events.map(event => [event.latitude, event.longitude]);
    const pointsKey = JSON.stringify(points);

    // Opening the form or posting a status must not reset the user's map view.
    if (pointsKey === previousPoints.current) return;

    previousPoints.current = pointsKey;

    if (points.length > 1) {
      map.fitBounds(points, { padding: [32, 32], maxZoom: 17 });
    } else if (points.length === 1) {
      map.setView(points[0], 17);
    } else {
      map.setView(UTS_CENTER, 16);
    }
  }, [events, map]);

  return null;
}

/**
 * Teardrop pin filled with the category colour.
 * Bottom tip sits exactly on the coordinate, so the point stays accurate.
 */
function createCategoryPin(color, width = 28) {
  const height = Math.round(width / 0.7);

  return L.divIcon({
    // A custom className avoids Leaflet's default 'leaflet-div-icon',
    // which paints a white box behind every marker.
    className: 'recess-category-pin',
    html: `
      <div style="width:${width}px;height:${height}px;background:transparent;border:0;">
        <svg width="${width}" height="${height}" viewBox="5 2 14 20"
             xmlns="http://www.w3.org/2000/svg"
             style="display:block;filter:drop-shadow(0 2px 3px rgba(0,0,0,0.25));"
             aria-hidden="true">
          <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z"
                fill="${color}" />
        </svg>
      </div>
    `,
    iconSize: [width, height],
    iconAnchor: [width / 2, height],
    popupAnchor: [0, -height],
  });
}

const pinByCategory = Object.fromEntries(
  CATEGORY_OPTIONS.map(category => [
    category.id,
    createCategoryPin(category.hex),
  ])
);

export default function CampusMap({ events = [] }) {
  const visibleEvents = events.filter(event =>
    isValidCoordinates(event.latitude, event.longitude)
  );

  // Counts per category, so the legend only lists what is actually on the map.
  const countsByCategory = visibleEvents.reduce((counts, event) => {
    const id = getCategory(event.category).id;
    counts[id] = (counts[id] ?? 0) + 1;
    return counts;
  }, {});

  const legend = CATEGORY_OPTIONS.filter(
    category => countsByCategory[category.id]
  );

  return (
    <div className="overflow-hidden rounded-2xl border border-neutral-100 bg-white shadow-sm">
      <div className="flex items-center justify-between border-b border-neutral-100 px-4 py-3">
        <div>
          <p className="text-sm font-bold text-neutral-900">Campus event map</p>
          <p className="text-[11px] text-neutral-400">
            Pan and zoom to explore meeting points
          </p>
        </div>

        <span className="rounded-full bg-orange-50 px-2 py-1 text-[11px] font-semibold text-orange-600">
          {visibleEvents.length} event{visibleEvents.length === 1 ? '' : 's'}
        </span>
      </div>

      {legend.length > 0 && (
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5 border-b border-neutral-100 px-4 py-2.5">
          {legend.map(category => (
            <span
              key={category.id}
              className="inline-flex items-center gap-1.5 text-[11px] text-neutral-500"
            >
              <span
                className={`inline-block h-2.5 w-2.5 rounded-full ${category.solid}`}
                aria-hidden="true"
              />
              {category.label}
              <span className="text-neutral-300">·</span>
              <span className="font-semibold text-neutral-600">
                {countsByCategory[category.id]}
              </span>
            </span>
          ))}
        </div>
      )}

      <MapContainer
        center={UTS_CENTER}
        zoom={16}
        minZoom={2}
        maxZoom={19}
        worldCopyJump
        scrollWheelZoom
        className="isolate z-0 h-[520px] w-full"
        aria-label="Campus event map"
      >
        <TileLayer
          attribution={OSM_ATTRIBUTION}
          url={OSM_TILE_URL}
          maxZoom={19}
        />

        <FitToEvents events={visibleEvents} />

        {visibleEvents.map(event => {
          const category = getCategory(event.category);

          return (
            <Marker
              key={event.id}
              position={[event.latitude, event.longitude]}
              icon={pinByCategory[category.id]}
              title={event.title}
              alt={`${event.title} — ${category.label}`}
            >
              <Popup>
                <div className="min-w-[170px]">
                  <p className={`text-[10px] font-bold uppercase tracking-wider ${category.text}`}>
                    {category.emoji} {category.label}
                  </p>

                  <p className="mt-1 font-bold text-neutral-900">
                    {event.title}
                  </p>

                  <p className="mt-1 text-xs text-neutral-500">
                    {event.location}
                  </p>

                  <p className="mt-1 text-xs text-neutral-400">{event.time}</p>

                  <p className="mt-2 text-xs text-neutral-400">
                    Posted by {event.author}
                  </p>
                </div>
              </Popup>
            </Marker>
          );
        })}
      </MapContainer>
    </div>
  );
}
