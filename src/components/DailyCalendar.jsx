import { format, parseISO, setHours, setMinutes } from 'date-fns';

const DailyCalendar = ({ reservations = [], currentDate = new Date(), currentTime = new Date() }) => {
  // Generate time slots from 7am to 9pm with 30-minute intervals
  const timeSlots = [];
  for (let hour = 7; hour <= 21; hour++) {
    timeSlots.push({ hour, minute: 0, isHour: true });
    if (hour < 21) { // Don't add 30-minute mark for 9pm
      timeSlots.push({ hour, minute: 30, isHour: false });
    }
  }

  // Helper function to get time position (0-1 scale)
  const getTimePosition = (hour, minute = 0) => {
    const totalMinutes = (hour - 7) * 60 + minute;
    const totalTimeRange = (21 - 7) * 60; // 14 hours = 840 minutes
    let position = totalMinutes / totalTimeRange;
    
    // Ensure 9pm line is visible by positioning it slightly above 100%
    if (hour === 21) {
      position = 1; // Position at 98% instead of 100%
    }
    
    return position;
  };

  // Helper function to get current time position
  const getCurrentTimePosition = () => {
    const currentHour = currentTime.getHours();
    const currentMinute = currentTime.getMinutes();
    
    // Only show indicator if current time is within the timeline range (7am-9pm)
    if (currentHour < 7 || currentHour > 21) {
      return null;
    }
    
    return getTimePosition(currentHour, currentMinute);
  };

  // Helper function to get event position and height
  const getEventPosition = (startTime, endTime) => {
    const start = new Date(startTime);
    const end = new Date(endTime);
    
    const startPosition = getTimePosition(start.getHours(), start.getMinutes());
    const endPosition = getTimePosition(end.getHours(), end.getMinutes());
    
    return {
      top: `${startPosition * 100}%`,
      height: `${(endPosition - startPosition) * 100}%`
    };
  };

  // Helper function to check if a time slot is within an event
  const isTimeInEvent = (hour, minute, reservation) => {
    const slotTime = new Date(currentDate);
    slotTime.setHours(hour, minute, 0, 0);
    
    const startTime = new Date(reservation.startTime);
    const endTime = new Date(reservation.endTime);
    
    return slotTime >= startTime && slotTime < endTime;
  };

  // Get events that overlap with current time slot
  const getEventsForTimeSlot = (hour, minute) => {
    return reservations.filter(reservation => 
      isTimeInEvent(hour, minute, reservation)
    );
  };

  const currentTimePosition = getCurrentTimePosition();

  return (
    <div className="daily-calendar">
      <div className="timeline-container">
        {/* Time labels on the left */}
        <div className="time-labels">
          {timeSlots.filter(slot => slot.isHour).map(({ hour }) => (
            <div 
              key={hour} 
              className="time-label"
              style={{ top: `${getTimePosition(hour) * 100}%` }}
            >
              {format(setHours(new Date(), hour), 'h a')}
            </div>
          ))}
        </div>

        {/* Timeline grid */}
        <div className="timeline-grid">
          {/* Hour lines */}
          {timeSlots.filter(slot => slot.isHour).map(({ hour }) => (
            <div 
              key={`hour-${hour}`} 
              className="timeline-line hour-line"
              style={{ top: `${getTimePosition(hour) * 100}%` }}
            />
          ))}
          
          {/* 30-minute lines */}
          {timeSlots.filter(slot => !slot.isHour).map(({ hour, minute }) => (
            <div 
              key={`half-${hour}-${minute}`} 
              className="timeline-line half-hour-line"
              style={{ top: `${getTimePosition(hour, minute) * 100}%` }}
            />
          ))}

          {/* Current Time Indicator */}
          {currentTimePosition !== null && (
            <>
              <div 
                className="current-time-indicator"
                style={{ top: `${currentTimePosition * 100}%` }}
              />
              <div 
                className="current-time-label"
                style={{ top: `${currentTimePosition * 100}%` }}
              >
                {format(currentTime, 'h:mm a')}
              </div>
            </>
          )}

          {/* Events */}
          {reservations.map((reservation) => {
            const position = getEventPosition(reservation.startTime, reservation.endTime);
            return (
              <div
                key={reservation.id}
                className="timeline-event"
                style={{
                  top: position.top,
                  height: position.height
                }}
              >
                <div className="event-content">
                  <div className="event-title">Reserved</div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};

export default DailyCalendar;
