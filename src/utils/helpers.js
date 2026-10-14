let nextId = 1;
export const makeId = () => nextId++;
export const now = () => new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
export const initials = (name) => String(name ?? '')
  .split(' ')
  .filter(Boolean)
  .map((word) => word[0])
  .join('')
  .toUpperCase()
  .slice(0, 2) || '?';