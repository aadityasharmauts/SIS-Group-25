export const UTS_CENTER = [-33.8835, 151.2005];

export const OSM_TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
export const OSM_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';
export const EVENT_MARKER_RADIUS_METERS = 250;

export const isValidCoordinates = (latitude, longitude) =>
  Number.isFinite(latitude) && latitude >= -90 && latitude <= 90 &&
  Number.isFinite(longitude) && longitude >= -180 && longitude <= 180;

// Leaflet allows panning through repeated worlds; store one canonical longitude.
export const wrapLongitude = (longitude) => ((longitude + 180) % 360 + 360) % 360 - 180;

export const formatCoordinates = (latitude, longitude) =>
  `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;

export const distanceInMeters = (firstLatitude, firstLongitude, secondLatitude, secondLongitude) => {
  const earthRadius = 6371000;
  const latitudeDelta = (secondLatitude - firstLatitude) * Math.PI / 180;
  const longitudeDelta = (secondLongitude - firstLongitude) * Math.PI / 180;
  const firstLatitudeRadians = firstLatitude * Math.PI / 180;
  const secondLatitudeRadians = secondLatitude * Math.PI / 180;
  const haversine = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(firstLatitudeRadians) * Math.cos(secondLatitudeRadians) * Math.sin(longitudeDelta / 2) ** 2;
  return 2 * earthRadius * Math.asin(Math.sqrt(haversine));
};

export const isWithinLocationRadius = (latitude, longitude, locationLatitude, locationLongitude) => {
  if (!isValidCoordinates(latitude, longitude) || !isValidCoordinates(locationLatitude, locationLongitude)) return true;
  return distanceInMeters(latitude, longitude, locationLatitude, locationLongitude) <= EVENT_MARKER_RADIUS_METERS;
};
