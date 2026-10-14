import { useCallback, useEffect, useState } from 'react';
import { CheckCircle2, Clock, MapPin } from 'lucide-react';
import {
  cancelCalendarEvent,
  loadCalendarEvents,
  subscribeToCalendarChanges,
} from '../services/events';

export default function CalendarView() {
  const [events, setEvents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [leavingId, setLeavingId] = useState(null);

  const refresh = useCallback(async () => {
    try {
      setError(null);
      setEvents(await loadCalendarEvents());
    } catch (loadError) {
      setError(loadError?.message ?? 'Unable to load your events.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const unsubscribe = subscribeToCalendarChanges(() => { void refresh(); });
    return unsubscribe;
  }, [refresh]);

  const handleLeave = async (event) => {
    setLeavingId(event.id);
    try {
      await cancelCalendarEvent(event);
      await refresh();
    } catch (leaveError) {
      setError(leaveError?.message ?? 'Unable to leave this event.');
    } finally {
      setLeavingId(null);
    }
  };

  return (
    <div className="mx-auto max-w-4xl space-y-5 p-3 sm:p-6">
      <header className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm sm:p-6">
        <h1 className="text-2xl font-bold text-slate-950">My events</h1>
        <p className="mt-1 text-sm text-slate-500">
          Events you have joined or RSVP’d to.
        </p>
      </header>

      {error && (
        <p role="alert" className="rounded-xl border border-red-100 bg-red-50 p-4 text-sm text-red-700">
          {error}
        </p>
      )}

      {loading ? (
        <div className="rounded-2xl border border-slate-100 bg-white p-12 text-center text-sm text-slate-400">
          Loading your events…
        </div>
      ) : events.length === 0 ? (
        <div className="rounded-2xl border border-slate-100 bg-white p-12 text-center shadow-sm">
          <CheckCircle2 size={42} className="mx-auto mb-3 text-slate-300" />
          <p className="font-medium text-slate-700">No accepted events yet.</p>
          <p className="mt-1 text-sm text-slate-400">
            Events will appear here after your request is accepted or your RSVP is confirmed.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {events.map((event) => (
            <article key={event.id} className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm transition-colors hover:border-orange-200">
              <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div className="min-w-0">
                  <div className="mb-2 flex flex-wrap items-center gap-2">
                    <span className="inline-flex items-center gap-1 rounded-lg bg-orange-50 px-2 py-1 text-[11px] font-semibold text-orange-700">
                      <CheckCircle2 size={12} />
                      {event.rsvpStatus === 'interested' ? 'Interested' : 'Accepted'}
                    </span>
                    <span className="text-xs text-slate-400">Hosted by {event.host}</span>
                  </div>

                  <h2 className="text-lg font-bold text-slate-900">{event.title}</h2>

                  <div className="mt-3 flex flex-col gap-2 text-sm text-slate-500 md:flex-row md:flex-wrap md:gap-5">
                    <span className="flex items-start gap-2">
                      <Clock size={16} className="mt-0.5 shrink-0 text-orange-500" />
                      {event.time}
                    </span>
                    <span className="flex items-start gap-2">
                      <MapPin size={16} className="mt-0.5 shrink-0 text-orange-500" />
                      {event.location}
                    </span>
                  </div>
                </div>

                <button
                  type="button"
                  onClick={() => handleLeave(event)}
                  disabled={leavingId === event.id}
                  className="shrink-0 rounded-xl border border-rose-100 bg-rose-50 px-4 py-2 text-sm font-semibold text-rose-600 hover:bg-rose-100 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {leavingId === event.id
                    ? 'Leaving…'
                    : event.eventType === 'official_event' ? 'Cancel RSVP' : 'Leave event'}
                </button>
              </div>
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
