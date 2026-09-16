import { useEffect } from 'react';
import {
  ImageOverlay,
  MapContainer,
  Marker,
  Popup,
  useMap,
} from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

const CAMPUS_MAP_URL =
  "/uts-campus-map.avif";

const IMAGE_WIDTH = 1824;
const IMAGE_HEIGHT = 1824;

// Leaflet's simple coordinate system uses [y, x]
const IMAGE_BOUNDS = [
  [0, 0],
  [IMAGE_HEIGHT, IMAGE_WIDTH],
];

const orangeEventIcon = L.divIcon({
  className: 'custom-event-marker',
  html: `
    <div style="
      width: 22px;
      height: 22px;
      border-radius: 9999px;
      background: #f97316;
      border: 3px solid white;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35);
    "></div>
  `,
  iconSize: [22, 22],
  iconAnchor: [11, 11],
  popupAnchor: [0, -12],
});

function RecenterMap({ events }) { 
  const map = useMap();

  useEffect(() => {
    if (events.length === 0) {
      map.setView([IMAGE_HEIGHT / 2, IMAGE_WIDTH / 2], -1);
      return;
    }

    const eventPoints = events.map(event => [
      event.mapY ?? IMAGE_HEIGHT / 2,
      event.mapX ?? IMAGE_WIDTH / 2,
    ]);

    map.fitBounds(eventPoints, {
      padding: [80, 80],
      maxZoom: 0,
    });
  }, [events, map]);

  return null;
}

export default function CampusMap({ events = [] }) {
  const campusEvents = events.filter(
    event =>
      event.type === 'event' &&
      typeof event.mapX === 'number' &&
      typeof event.mapY === 'number'
  );

  return (
    <section className="overflow-hidden rounded-2xl border border-orange-100 bg-white shadow-sm">
      <div className="border-b border-orange-100 bg-white px-5 py-4">
        <p className="text-xs font-semibold uppercase tracking-widest text-orange-500">
          Live campus map
        </p>

        <div className="mt-1 flex items-center justify-between gap-3">
          <h2 className="text-lg font-bold text-neutral-900">
            UTS events
          </h2>

          <span className="rounded-full bg-orange-50 px-2.5 py-1 text-xs font-medium text-orange-600">
            {campusEvents.length}{' '}
            {campusEvents.length === 1 ? 'event' : 'events'}
          </span>
        </div>
      </div>

      <div className="h-[520px] bg-neutral-100">
        <MapContainer
          crs={L.CRS.Simple}
          center={[IMAGE_HEIGHT / 2, IMAGE_WIDTH / 2]}
          zoom={-1}
          minZoom={-2}
          maxZoom={1}
          zoomControl
          scrollWheelZoom
          className="h-full w-full"
        >
          <ImageOverlay
            url={CAMPUS_MAP_URL}
            bounds={IMAGE_BOUNDS}
          />

          <RecenterMap events={campusEvents} />

          {campusEvents.map(event => (
            <Marker
              key={event.id}
              position={[event.mapY, event.mapX]}
              icon={orangeEventIcon}
            >
              <Popup>
                <div className="min-w-[180px]">
                  <h3 className="font-semibold text-neutral-900">
                    {event.title}
                  </h3>

                  <p className="mt-1 text-sm text-neutral-600">
                    {event.location}
                  </p>

                  <p className="mt-1 text-xs text-neutral-500">
                    {event.time}
                  </p>

                  <p className="mt-2 text-xs text-neutral-400">
                    Posted by {event.author}
                  </p>
                </div>
              </Popup>
            </Marker>
          ))}
        </MapContainer>
      </div>

      {campusEvents.length === 0 && (
        <p className="border-t border-orange-100 px-5 py-3 text-center text-xs text-neutral-400">
          No events have been placed on the map yet.
        </p>
      )}
    </section>
  );
}
