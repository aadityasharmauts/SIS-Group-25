import { useCallback, useEffect, useState } from 'react';
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
import Profile from './components/Profile';
import CalendarView from './components/CalendarView';
import UserProfileModal from './components/UserProfileModal';

import { supabase } from './lib/supabaseClient';
import { createExampleEvents, CURRENT_USER, SAMPLE_EVENT, SEED_FEED } from './constants/seed';
import { makeId, initials } from './utils/helpers';
import {
  createActivity,
  cancelActivity,
  joinActivity,
  loadActiveMapPoints,
  loadAreas,
  loadExampleHosts,
  mapPointToFeedItem,
  rsvpToEvent,
  subscribeToMapChanges,
  updateActivity,
} from './services/events';

export default function App() {
  const [page, setPage] = useState(() => {
    if (window.location.pathname === '/terms') return 'terms';
    if (window.location.pathname === '/privacy') return 'privacy';
    return 'landing';
  });
  const [authMode, setAuthMode] = useState('signin');
  const [legalReturnPage, setLegalReturnPage] = useState('landing');
  const [session, setSession] = useState(null);
  const [feed, setFeed] = useState(SEED_FEED);
  const [areas, setAreas] = useState([]);
  const [showEventForm, setShowEventForm] = useState(false);
  const [selectedEvent, setSelectedEvent] = useState(null);
  const [joined, setJoined] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const [loadingFeed, setLoadingFeed] = useState(false);
  const [eventError, setEventError] = useState(null);
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [selectedProfileUserId, setSelectedProfileUserId] = useState(null);
  const [editingEvent, setEditingEvent] = useState(null);

  const refreshRemoteFeed = useCallback(async () => {
    if (!session) return;
    setLoadingFeed(true);
    try {
      const [points, exampleHosts] = await Promise.all([
        loadActiveMapPoints(),
        loadExampleHosts(),
      ]);
      const hostFallback = session?.user?.user_metadata?.display_name || CURRENT_USER;
      const remoteEvents = points
        .filter((point) => point.point_type === 'activity' || point.point_type === 'official_event')
        .map((point) => mapPointToFeedItem(point, hostFallback));
      setFeed((previous) => [
        ...previous.filter((item) => item.type === 'status'),
        ...createExampleEvents(exampleHosts),
        ...remoteEvents,
      ]);
      setEventError(null);
    } catch (error) {
      setEventError(error?.message ?? 'Unable to load events from Supabase.');
    } finally {
      setLoadingFeed(false);
    }
  }, [session]);

  useEffect(() => {
    let mounted = true;
    supabase.auth.getSession().then(async ({ data: { session: currentSession } }) => {
      if (!mounted) return;
      if (currentSession) {
        const { error } = await supabase.auth.getUser();
        if (error) {
          await supabase.auth.signOut();
          if (mounted) setPage('landing');
          return;
        }
      }
      setSession(currentSession);
      if (currentSession) setPage('feed');
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      if (nextSession) setPage('feed');
      else setPage('landing');
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (!session) return undefined;
    let active = true;
    loadAreas().then((loadedAreas) => {
      if (active) setAreas(loadedAreas);
    }).catch((error) => {
      if (active) setEventError(error?.message ?? 'Unable to load approved areas.');
    });
    const refreshTimer = window.setTimeout(() => { void refreshRemoteFeed(); }, 0);
    const unsubscribe = subscribeToMapChanges(() => { void refreshRemoteFeed(); });
    return () => {
      active = false;
      window.clearTimeout(refreshTimer);
      unsubscribe();
    };
  }, [session, refreshRemoteFeed]);

  const currentUserName = session?.user?.user_metadata?.display_name || CURRENT_USER;

  const handlePostStatus = (text) => {
    setFeed((previous) => [{ id: makeId(), type: 'status', text, time: 'Just now', author: currentUserName }, ...previous]);
  };

  // tags are now part of the payload and must be written to Supabase.
  const handlePublishEvent = async ({ title, location, description, category, tags, participantLimit, areaId, startTime, endTime, latitude, longitude }) => {
    setPublishing(true);
    setEventError(null);
    try {
      const payload = {
        area_id: areaId,
        title,
        description,
        category,
        tags,
        participant_limit: participantLimit,
        start_time: startTime,
        end_time: endTime,
        location_label: location,
        latitude,
        longitude,
      };
      if (editingEvent?.remoteId) {
        await updateActivity(editingEvent.remoteId, payload);
      } else {
        await createActivity(payload);
      }
      await refreshRemoteFeed();
      setShowEventForm(false);
      setEditingEvent(null);
    } catch (error) {
      setEventError(error?.message ?? 'Unable to publish this event.');
    } finally {
      setPublishing(false);
    }
  };

  // category + tags must be copied onto selectedEvent, or EventDetails
  // renders the fallback colour and no tags.
  const handleOpenEvent = (item) => {
    setEventError(null);
    setSelectedEvent({
      remoteId: item.remoteId,
      source: item.source,
      isCreator: item.isCreator,
      title: item.title,
      description: item.description || 'Join this Recess meetup and connect with people nearby.',
      location: item.location,
      time: item.time,
      category: item.category ?? 'other',
      tags: item.tags ?? [],
      host: {
        name: item.author,
        initials: initials(item.author),
        detail: item.source === 'official_event' ? 'Approved organisation event' : 'Verified Recess user',
      },
    });
    setJoined(false);
    setPage('event');
  };

  const handleJoinEvent = async () => {
    if (!selectedEvent?.remoteId) {
      setJoined(true);
      return;
    }
    try {
      if (selectedEvent.source === 'official_event') await rsvpToEvent(selectedEvent.remoteId);
      else await joinActivity(selectedEvent.remoteId);
      setJoined(true);
    } catch (error) {
      const message = error?.message ?? '';
      setEventError(message.includes('[forbidden]')
        ? 'The event creator is already a participant in this meetup.'
        : message || 'Unable to join this event.');
    }
  };

  const handleDeleteEvent = async (remoteId) => {
    if (!window.confirm('Are you sure you want to delete this event?')) return;
    try {
      await cancelActivity(remoteId);
      await refreshRemoteFeed();
    } catch (err) {
      alert('Failed to cancel event: ' + err.message);
    }
  };

  const handleEditEvent = (item) => {
    setEditingEvent(item);
    setShowEventForm(true); 
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

  if (page === 'terms' || page === 'privacy') return <LegalPage type={page} onBack={closeLegal} />;

  if (page === 'landing') {
    return <Landing onGetStarted={(mode) => { setAuthMode(mode); setPage('auth'); }} />;
  }

  if (page === 'auth') {
    return <Auth mode={authMode} onBack={() => setPage('landing')} onSuccess={() => setPage('feed')} onOpenLegal={openLegal} />;
  }

  return (
    <div className="min-h-screen bg-orange-50 p-4 md:p-8 font-sans">
      <div className="mx-auto max-w-7xl">
        <Header
          page={page}
          onBack={() => setPage('feed')}
          showEventForm={showEventForm}
          onToggle={() => { setEventError(null); setShowEventForm((visible) => !visible); }}
          onNavigate={(nextPage) => setPage(nextPage)}
        />

        {page === 'calendar' ? (
          <CalendarView />
        ) : page === 'event' ? (
          <>
            {eventError && <p role="alert" className="mb-3 rounded-xl border border-red-100 bg-red-50 px-3 py-2 text-xs text-red-700">{eventError}</p>}
            <EventDetails event={currentEvent} joined={joined} onJoin={handleJoinEvent} />
          </>
        ) : page === 'profile' ? (
          <Profile />
        ) : (
          <div className="grid gap-6 lg:grid-cols-[420px_minmax(0,1fr)] lg:items-start">
            <div className="space-y-3">
              <PresenceStrip />
              {eventError && <p role="alert" className="rounded-xl border border-red-100 bg-red-50 px-3 py-2 text-xs text-red-700">{eventError}</p>}
              {showEventForm && (
                <EventForm
                  initialData={editingEvent}
                  areas={areas}
                  onSubmit={handlePublishEvent}
                  onCancel={() => {
                    setShowEventForm(false);
                    setEditingEvent(null);
                  }}
                  submitting={publishing}
                />
              )}
              

              <StatusInput onPost={handlePostStatus} />

              {/* Event Category Filter Bar */}
              <div className="flex items-center gap-1.5 overflow-x-auto py-1 scrollbar-none">
                {[
                  { label: 'All', value: 'all' },
                  { label: 'Study session', value: 'study_session' },
                  { label: 'Coffee break', value: 'coffee_break' },
                  { label: 'Lunch', value: 'lunch' },
                  { label: 'Walk', value: 'walk' },
                  { label: 'Casual game', value: 'casual_game' },
                  { label: 'Group discussion', value: 'group_discussion' },
                ].map((cat) => (
                  <button
                    key={cat.value}
                    onClick={() => setSelectedCategory(cat.value)}
                    className={`text-xs px-3 py-1.5 rounded-xl font-medium transition-colors whitespace-nowrap ${
                      selectedCategory === cat.value
                        ? 'bg-orange-600 text-white shadow-sm'
                        : 'bg-white hover:bg-neutral-100 text-neutral-600 border border-neutral-100'
                    }`}
                  >
                    {cat.label}
                  </button>
                ))}
              </div>

              <p className="px-1 pt-1 text-[10px] font-semibold uppercase tracking-widest text-neutral-400">Today's updates</p>

              {loadingFeed && <p className="py-4 text-center text-xs text-neutral-400">Loading events…</p>}
              {!loadingFeed && feed.length === 0 && <p className="py-16 text-center text-sm text-neutral-400">Nothing here yet. Post a status or host an event.</p>}

              {feed
                .filter((item) => {
                  if (selectedCategory === 'all') return true;
                  if (item.type === 'status') return true; // keeps status posts visible regardless of filter
                  return item.category === selectedCategory;
                })
                .map((item) => item.type === 'event'
                  ? <EventCard 
                      key={item.id} 
                      item={item} 
                      onOpen={() => handleOpenEvent(item)} 
                      onOpenProfile={(userId) => setSelectedProfileUserId(userId)} 
                      onEdit={(item) => handleEditEvent(item)}
                      onDelete={(remoteId) => handleDeleteEvent(remoteId)}
                    />
                  : <StatusCard key={item.id} item={item} />)}
            </div>

            <div className="lg:sticky lg:top-6">
              <CampusMap events={feed.filter((item) => item.type === 'event')} />
            </div>
          </div>
        )}

        <footer className="text-center text-[11px] text-neutral-400 mt-12 pt-6 border-t border-neutral-100">Recess v1.3 · Campus coordination for UTS</footer>
      </div>

      <UserProfileModal 
        userId={selectedProfileUserId} 
        onClose={() => setSelectedProfileUserId(null)} 
      />

    </div>
  );
}
