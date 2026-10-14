import { supabase } from '../lib/supabaseClient';

const edgeFunctionUnavailable = (error) => {
  const message = String(error?.message ?? error ?? '').toLowerCase();
  return message.includes('failed to fetch')
    || message.includes('functionsfetcherror')
    || message.includes('not found')
    || message.includes('404')
    || error?.context?.status === 404;
};

async function invokeWithLocalFallback(functionName, body, fallback) {
  const { data, error } = await supabase.functions.invoke(functionName, { body });
  if (!error) return data?.data ?? data;
  // Local Supabase projects do not always run the Edge Function server. The
  // same RLS-protected operation is safe as a development fallback; hosted
  // deployments use the function path above.
  if (edgeFunctionUnavailable(error)) return fallback();
  if (error.context && typeof error.context.json === 'function') {
    try {
      const responseBody = await error.context.json();
      const message = responseBody?.error || responseBody?.message;
      if (message) throw new Error(message);
    } catch (responseError) {
      if (responseError instanceof Error && responseError.message) throw responseError;
    }
  }
  throw error;
}

export async function loadActiveMapPoints() {
  const { data, error } = await supabase.rpc('active_map_points', {
    p_area_ids: null,
    p_location_id: null,
    p_include_presence: true,
  });
  if (error) throw error;
  return data ?? [];
}

export async function loadAreas() {
  const { data, error } = await supabase
    .from('areas')
    .select('id, name, type, location_id, locations(id, name, type, latitude, longitude)')
    .order('name');
  if (error) throw error;
  return data ?? [];
}

export async function loadExampleHosts() {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, display_name')
    .eq('account_status', 'verified')
    .not('display_name', 'is', null)
    .order('created_at')
    .limit(4);
  if (error) throw error;
  return data ?? [];
}

export async function createActivity(payload) {
  return invokeWithLocalFallback('create-activity', payload, async () => {
    const { data, error } = await supabase
      .from('activities')
      .insert(payload)
      .select('id, title, description, category, tags, start_time, end_time, participant_limit, location_label, latitude, longitude, area_id')
      .single();
    if (error) throw error;
    return data;
  });
}

export async function createOfficialEvent(payload) {
  return invokeWithLocalFallback('create-official-event', payload, async () => {
    const { data, error } = await supabase.from('official_events').insert(payload).select().single();
    if (error) throw error;
    return data;
  });
}

export async function rsvpToEvent(eventId, status = 'going') {
  return invokeWithLocalFallback('rsvp-to-event', { event_id: eventId, status }, async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('Authentication required');
    const { data, error } = await supabase
      .from('event_rsvps')
      .upsert({ event_id: eventId, user_id: user.id, status }, { onConflict: 'event_id,user_id' })
      .select()
      .single();
    if (error) throw error;
    return data;
  });
}

export async function loadCalendarEvents() {
  const [{ data: rsvps, error: rsvpError }, { data: memberships, error: membershipError }] = await Promise.all([
    supabase
      .from('event_rsvps')
      .select('event_id, status, created_at')
      .in('status', ['going', 'interested']),
    supabase
      .from('activity_participants')
      .select('activity_id, status, created_at')
      .eq('status', 'accepted'),
  ]);

  if (rsvpError) throw rsvpError;
  if (membershipError) throw membershipError;

  const eventIds = (rsvps ?? []).map((rsvp) => rsvp.event_id);
  const activityIds = (memberships ?? []).map((membership) => membership.activity_id);

  const [{ data: officialEvents, error: officialError }, { data: activities, error: activityError }] = await Promise.all([
    eventIds.length
      ? supabase
        .from('official_events')
        .select('id, title, description, location_id, area_id, latitude, longitude, start_time, end_time, status, locations(name), areas(name), organisations(name)')
        .in('id', eventIds)
        .gte('end_time', new Date().toISOString())
      : Promise.resolve({ data: [], error: null }),
    activityIds.length
      ? supabase
        .from('activities')
        .select('id, title, description, category, location_label, latitude, longitude, start_time, end_time, status, areas(name, locations(name)), creator:profiles!creator_id(display_name)')
        .in('id', activityIds)
        .gte('end_time', new Date().toISOString())
      : Promise.resolve({ data: [], error: null }),
  ]);

  if (officialError) throw officialError;
  if (activityError) throw activityError;

  const rsvpByEventId = new Map((rsvps ?? []).map((rsvp) => [rsvp.event_id, rsvp]));
  const membershipByActivityId = new Map((memberships ?? []).map((membership) => [membership.activity_id, membership]));

  const officialCalendarEvents = (officialEvents ?? []).map((event) => {
    const rsvp = rsvpByEventId.get(event.id);
    return {
      id: `official:${event.id}`,
      remoteId: event.id,
      eventType: 'official_event',
      title: event.title,
      description: event.description,
      location: event.locations?.name ?? event.areas?.name ?? 'Campus venue',
      time: formatTimeWindow(event.start_time, event.end_time),
      startTime: event.start_time,
      endTime: event.end_time,
      host: event.organisations?.name?.trim() || 'Organisation event',
      rsvpStatus: rsvp?.status ?? 'going',
    };
  });

  const activityCalendarEvents = (activities ?? []).map((activity) => {
    const membership = membershipByActivityId.get(activity.id);
    const area = activity.areas;
    return {
      id: `activity:${activity.id}`,
      remoteId: activity.id,
      eventType: 'activity',
      title: activity.title,
      description: activity.description,
      location: activity.location_label ?? area?.name ?? area?.locations?.name ?? 'Campus meeting point',
      time: formatTimeWindow(activity.start_time, activity.end_time),
      startTime: activity.start_time,
      endTime: activity.end_time,
      host: activity.creator?.display_name?.trim() || 'Recess community',
      rsvpStatus: membership?.status ?? 'pending',
    };
  });

  return [...officialCalendarEvents, ...activityCalendarEvents]
    .sort((left, right) => new Date(left.startTime) - new Date(right.startTime));
}

export async function cancelCalendarEvent(event) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Authentication required');

  if (event.eventType === 'official_event') {
    const { error } = await supabase
      .from('event_rsvps')
      .delete()
      .eq('event_id', event.remoteId)
      .eq('user_id', user.id);
    if (error) throw error;
    return;
  }

  const { error } = await supabase
    .from('activity_participants')
    .update({ status: 'left' })
    .eq('activity_id', event.remoteId)
    .eq('user_id', user.id);
  if (error) throw error;
}

export function subscribeToCalendarChanges(onChange) {
  const channel = supabase
    .channel('recess-calendar-updates')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'event_rsvps' }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'official_events' }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'activity_participants' }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'activities' }, onChange)
    .subscribe();

  return () => {
    void supabase.removeChannel(channel);
  };
}

export async function joinActivity(activityId) {
  const { data, error } = await supabase
    .from('activity_participants')
    .insert({ activity_id: activityId, status: 'pending' })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export function subscribeToMapChanges(onChange) {
  const channel = supabase
    .channel('recess-map-updates')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'activities' }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'activity_participants' }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'official_events' }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'event_rsvps' }, onChange)
    .subscribe();

  return () => {
    void supabase.removeChannel(channel);
  };
}

export function mapPointToFeedItem(point, currentUserName) {
  const official = point.point_type === 'official_event';
  const hostName = typeof point.host_name === 'string' ? point.host_name.trim() : '';
  const author = official
    ? (hostName || 'Organisation event')
    : (hostName || (point.is_creator === true && currentUserName) || 'Recess community');

  return {
    id: point.point_id,
    remoteId: point.point_id,
    type: 'event',
    source: point.point_type,
    title: point.title,
    areaId: point.area_id,
    location: point.location_name ?? point.area_name ?? 'Campus meeting point',
    time: formatTimeWindow(point.starts_at, point.ends_at),
    author,
    category: point.category,
    description: point.category ? formatCategory(point.category) : null,
    latitude: point.latitude,
    longitude: point.longitude,
    participantCount: point.participant_count,
    participantLimit: point.participant_limit,
    isCreator: point.is_creator === true,
  };
}

function formatTimeWindow(start, end) {
  if (!start) return 'Time to be confirmed';
  const startDate = new Date(start);
  const endDate = end ? new Date(end) : null;
  const formatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' });
  return endDate ? `${formatter.format(startDate)} – ${formatter.format(endDate)}` : formatter.format(startDate);
}

export async function updateActivity(activityId, payload) {
  const { data, error } = await supabase
    .from('activities')
    .update(payload)
    .eq('id', activityId)
    .select('id, title, description, category, tags, start_time, end_time, participant_limit, location_label, latitude, longitude, area_id, status')
    .single();
  if (error) throw error;
  return data;
}

export async function cancelActivity(activityId) {
  const { error } = await supabase
    .from('activities')
    .update({ status: 'cancelled' })
    .eq('id', activityId)
    .eq('status', 'open')
    .select('id')
    .single();
  if (error) throw error;
}
