// API utility functions for fetching Loft events from Grace Church

const GRACE_CHURCH_API_URL = 'https://api2.grace.church/v2/events/today';

// Fetch events from the Grace Church API
export const fetchGraceChurchEvents = async () => {
  try {
    const response = await fetch(GRACE_CHURCH_API_URL, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      mode: 'cors', // Try to handle CORS
    });
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    const data = await response.json();
    return data;
  } catch (error) {
    console.error('Error fetching Grace Church events:', error);
    return [];
  }
};

// Filter events for Loft reservations that are approved
export const filterLoftEvents = (events) => {
  if (!Array.isArray(events)) return [];
  
  return events.filter(event => {
    // Check if the event has resources
    if (!event.Resources) return false;
    
    // Handle both single resource and array of resources
    let resources = [];
    if (Array.isArray(event.Resources)) {
      resources = event.Resources;
    } else if (typeof event.Resources === 'object' && event.Resources !== null) {
      resources = [event.Resources];
    } else {
      return false;
    }
    
    // Check if any resource is "The Loft" and has approved status
    return resources.some(resource => {
      return resource.name === "The Loft" && 
             resource.status && 
             resource.status.value === "Approved";
    });
  });
};

// Transform Grace Church event data to match our reservation format
export const transformEventToReservation = (event) => {
  return {
    id: event.ID,
    title: event.Name,
    startTime: event.SetupStart || event.StartTime, // Use setup time if available, fallback to event time
    endTime: event.SetupEnd || event.EndTime, // Use teardown time if available, fallback to event time
    organizer: event.Organizer,
    room: "The Loft",
    description: event.Description,
    location: event.Location?.Name || "The Loft",
    recurrence: event.Recurrence
  };
};

// Main function to get Loft reservations for today
export const getLoftReservations = async () => {
  try {
    const events = await fetchGraceChurchEvents();
    const loftEvents = filterLoftEvents(events);
    const reservations = loftEvents.map(transformEventToReservation);
    return reservations;
  } catch (error) {
    console.error('Error getting Loft reservations:', error);
    return [];
  }
};
