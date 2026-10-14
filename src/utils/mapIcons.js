import L from 'leaflet';

// Both maps use the same geometry: the bottom tip sits exactly on the coordinate.
const createPinIcon = (color) => L.divIcon({
  className: 'campus-pin',
  html: `<svg class="campus-pin__svg" width="28" height="40" viewBox="5 2 14 20" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z" fill="${color}" />
    <circle cx="12" cy="9" r="2.5" fill="white" />
  </svg>`,
  iconSize: [28, 40],
  iconAnchor: [14, 40],
  popupAnchor: [0, -40],
});

export const eventIcon = createPinIcon('#ea580c');
export const selectionIcon = createPinIcon('#2563eb');
