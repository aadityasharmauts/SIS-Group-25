import { useState } from 'react';
import Landing from './components/Landing'; 
import Auth from './components/Auth';
import Header from './components/Header';
import PresenceStrip from './components/PresenceStrip';
import StatusInput from './components/StatusInput';
import StatusCard from './components/StatusCard';
import EventCard from './components/EventCard';
import EventForm from './components/EventForm';
import EventDetails from './components/EventDetails';
import CampusMap from './components/CampusMap';
import LegalPage from './components/LegalPage';

import { CURRENT_USER, SEED_FEED, SAMPLE_EVENT } from './constants/seed';
import { makeId, initials } from './utils/helpers';

// --- Main App ---

export default function App() {
  const [page, setPage] = useState(() => {
    if (window.location.pathname === '/terms') return 'terms';
    if (window.location.pathname === '/privacy') return 'privacy';
    return 'landing';
  });
  const [authMode, setAuthMode] = useState('signin');
  const [legalReturnPage, setLegalReturnPage] = useState('landing');
  const [feed, setFeed] = useState(SEED_FEED);
  const [showEventForm, setShowEventForm] = useState(false);
  const [selectedEvent, setSelectedEvent] = useState(null);
  const [joined, setJoined] = useState(false);


  const handlePostStatus = (text) => {
    setFeed(prev => [{ id: makeId(), type: 'status', text, time: 'Just now', author: CURRENT_USER }, ...prev]);
  };

  const handlePublishEvent = ({
    title,
    location,
    time,
    mapX,
    mapY,
  }) => {
    setFeed(prev => [
      {
        id: makeId(),
        type: 'event',
        title,
        location,
        time,
        author: CURRENT_USER,
        mapX,
        mapY,
      },
      ...prev,
    ]);
  
    setShowEventForm(false);
  };
  
  

  const handleOpenEvent = (item) => {
    setSelectedEvent({
      title: item.title,
      description: 'Join us for this campus event! RSVP below to confirm your attendance.',
      location: item.location,
      time: item.time,
      host: {
        name: item.author,
        initials: initials(item.author),
        detail: 'UTS Student',
      },
    });
    setJoined(false);
    setPage('event');
  };

  const currentEvent = selectedEvent ?? SAMPLE_EVENT;

  const navigate = (nextPage, path) => {
    window.history.pushState({}, '', path);
    setPage(nextPage);
  };

  const openLegal = (type, mode = authMode) => {
    setLegalReturnPage(page === 'terms' || page === 'privacy' ? 'landing' : page);
    setAuthMode(mode);
    navigate(type, `/${type}`);
  };

  const closeLegal = () => {
    const returnPage = legalReturnPage === 'auth' ? 'auth' : 'landing';
    navigate(returnPage, '/');
  };

  if (page === 'terms' || page === 'privacy') {
    return <LegalPage type={page} onBack={closeLegal} />;
  }


  // Render the Landing page view when page state is 'landing'
  if (page === 'landing') {
    return (
      <Landing 
        onGetStarted={(mode) => {
          setAuthMode(mode);
          setPage('auth');
        }} 
      />
    );
  }

  // Render the Auth page view when page state is 'auth'
  if (page === 'auth') {
    return (
      <Auth 
        mode={authMode} 
        onBack={() => setPage('landing')} 
        onSuccess={() => setPage('feed')} 
        onOpenLegal={openLegal}
      />
    );
  }



  return (
    <div className="min-h-screen bg-orange-50 p-4 md:p-8 font-sans">
      <div className="mx-auto max-w-7xl">

    <Header
        page={page}
        onBack={() => setPage('feed')}
        showEventForm={showEventForm}
        onToggle={() => setShowEventForm(f => !f)}
    />

{page === 'event' ? (
  <EventDetails
    event={currentEvent}
    joined={joined}
    onJoin={() => setJoined(true)}
  />
) : (
  <div className="grid gap-6 lg:grid-cols-[420px_minmax(0,1fr)] lg:items-start">
    {/* Feed on the left */}
    <div className="space-y-3">
      <PresenceStrip />

      {showEventForm && (
        <EventForm
          onSubmit={handlePublishEvent}
          onCancel={() => setShowEventForm(false)}
        />
      )}

      <StatusInput onPost={handlePostStatus} />

      <p className="px-1 pt-1 text-[10px] font-semibold uppercase tracking-widest text-neutral-400">
        Today's updates
      </p>

      {feed.length === 0 && (
        <p className="py-16 text-center text-sm text-neutral-400">
          Nothing here yet. Post a status or host an event.
        </p>
      )}

      {feed.map(item =>
        item.type === 'event' ? (
          <EventCard
            key={item.id}
            item={item}
            onOpen={() => handleOpenEvent(item)}
          />
        ) : (
          <StatusCard key={item.id} item={item} />
        )
      )}
    </div>

    {/* Map on the right */}
    <div className="lg:sticky lg:top-6">
      <CampusMap
        events={feed.filter(item => item.type === 'event')}
      />
    </div>
  </div>
)}



        <footer className="text-center text-[11px] text-neutral-400 mt-12 pt-6 border-t border-neutral-100">
          Recess v1.3 · Campus coordination for UTS
        </footer>

      </div>
    </div>
  );
}
