import { useState, useEffect } from 'react';
import DailyCalendar from './DailyCalendar';
import { format } from 'date-fns';
import loftImage from '../assets/loft.jpg';
import { getLoftReservations } from '../utils/loftApi';

const SignageDisplay = () => {
  const [currentDate, setCurrentDate] = useState(new Date());
  const [currentTime, setCurrentTime] = useState(new Date());
  const [reservations, setReservations] = useState([]);

  // Fetch Loft reservations
  const fetchReservations = async () => {
    try {
      const loftReservations = await getLoftReservations();
      
      if (loftReservations.length > 0) {
        setReservations(loftReservations);
      } else {
        // No Loft events found - show empty calendar
        console.log('No Loft events found, showing empty calendar');
        setReservations([]);
      }
    } catch (err) {
      console.error('Failed to fetch reservations:', err);
      // Show empty calendar on error
      setReservations([]);
    }
  };

  // Update the date and time every 5 seconds
  useEffect(() => {
    const interval = setInterval(() => {
      const now = new Date();
      setCurrentDate(now);
      setCurrentTime(now);
    }, 5000); // Update every 5 seconds

    // Initial update
    setCurrentTime(new Date());

    return () => clearInterval(interval);
  }, []);

  // Fetch reservations on component mount and refresh every 5 minutes
  useEffect(() => {
    fetchReservations();
    
    const refreshInterval = setInterval(fetchReservations, 5 * 60 * 1000); // Refresh every 5 minutes
    
    return () => clearInterval(refreshInterval);
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

      {/* Calendar Section - Always visible */}
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
