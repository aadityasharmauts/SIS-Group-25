export const CURRENT_USER = 'Salha';

export const PRESENCE_USERS = ['Salha', 'Ahmed', 'Saba', 'Jay'];


const EXAMPLE_EVENT_TEMPLATES = [
  {
    id: 'example-study-group',
    title: 'Library study sprint',
    description: 'A focused study block with a short break halfway through.',
    location: 'UTS Library, Level 4',
    category: 'study_session',
    tags: ['study focused', 'all courses'],
    startsInHours: 1,
    latitude: -33.8832,
    longitude: 151.2006,
  },
  {
    id: 'example-coffee-break',
    title: 'Coffee between classes',
    description: 'Grab a coffee and meet someone new before the next class.',
    location: 'Central Park Cafe',
    category: 'coffee_break',
    tags: ['new students', 'casual chat'],
    startsInHours: 2.5,
    latitude: -33.8830,
    longitude: 151.1996,
  },
  {
    id: 'example-lunch',
    title: 'Lunch at Central Food Court',
    description: 'A relaxed group lunch for anyone who wants some company.',
    location: 'Central Food Court',
    category: 'lunch',
    tags: ['everyone welcome', 'quick lunch'],
    startsInHours: 4,
    latitude: -33.8836,
    longitude: 151.2008,
  },
];

const formatExampleTime = (start, end) => {
  const formatter = new Intl.DateTimeFormat(undefined, {
    weekday: 'short',
    hour: 'numeric',
    minute: '2-digit',
  });
  return `${formatter.format(start)} – ${formatter.format(end)}`;
};

export function createExampleEvents(profiles = []) {
  const now = new Date();

  return EXAMPLE_EVENT_TEMPLATES.map((template, index) => {
    const profile = profiles[index % profiles.length];
    const start = new Date(now.getTime() + template.startsInHours * 60 * 60 * 1000);
    const end = new Date(start.getTime() + 60 * 60 * 1000);

    return {
      ...template,
      type: 'event',
      source: 'example',
      time: formatExampleTime(start, end),
      author: profile?.display_name?.trim() || PRESENCE_USERS[index % PRESENCE_USERS.length],
      userId: profile?.id,
    };
  });
}

export const SEED_FEED = createExampleEvents();


export const SAMPLE_EVENT = {
  title: 'Capstone study session',
  description: 'Working through architecture diagrams and sprint planning before Friday demo.',
  location: 'Building 11, Level 4',
  time: 'Friday 28th August, 3:00 PM – 5:00 PM',
  latitude: -33.8832,
  longitude: 151.2006,
  host: {
    name: 'Alex Chen',
    initials: 'AC',
    detail: 'Software Engineering · 4th year',
  },
};
