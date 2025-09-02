import { useState, useEffect } from 'react';
import DailyCalendar from './DailyCalendar';
import { format } from 'date-fns';
import loftImage from '../assets/loft.jpg';

const SignageDisplay = () => {
  const [currentDate, setCurrentDate] = useState(new Date());
  const [currentTime, setCurrentTime] = useState(new Date());
  
  // Empty reservations array - no sample events
  const [reservations] = useState([]);

  // Update the date and time every minute
  useEffect(() => {
    const interval = setInterval(() => {
      const now = new Date();
      setCurrentDate(now);
      setCurrentTime(now);
    }, 60000); // Update every minute

    // Initial update
    setCurrentTime(new Date());

    return () => clearInterval(interval);
  }, []);

  return (
    <div className="signage-display">
      {/* Image Section - 16:9 aspect ratio */}
      <div className="image-section">
        <img 
          src={loftImage} 
          alt="Loft Space" 
          className="display-image"
        />
        
        {/* Clock Display - Bottom Left */}
        <div className="clock-display">
          <div className="time-display">
            {format(currentTime, 'h:mm a')}
          </div>
        </div>

        {/* Date Display - Bottom Right */}
        <div className="date-display">
          <div className="date-text">
            {format(currentTime, 'EEE, MMM d')}
          </div>
        </div>
      </div>

      {/* Calendar Section */}
      <div className="calendar-section">
        <DailyCalendar 
          reservations={reservations}
          currentDate={currentDate}
          currentTime={currentTime}
        />
      </div>
    </div>
  );
};

export default SignageDisplay;
