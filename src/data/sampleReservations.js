// Sample reservation data for testing
export const sampleReservations = [
  {
    id: 1,
    title: "Team Standup",
    startTime: "2024-01-15T09:00:00",
    endTime: "2024-01-15T09:30:00",
    organizer: "John Smith",
    room: "Conference Room A"
  },
  {
    id: 2,
    title: "Client Presentation",
    startTime: "2024-01-15T10:00:00",
    endTime: "2024-01-15T11:30:00",
    organizer: "Sarah Johnson",
    room: "Conference Room A"
  },
  {
    id: 3,
    title: "Lunch Meeting",
    startTime: "2024-01-15T12:00:00",
    endTime: "2024-01-15T13:00:00",
    organizer: "Mike Davis",
    room: "Conference Room A"
  },
  {
    id: 4,
    title: "Product Review",
    startTime: "2024-01-15T14:00:00",
    endTime: "2024-01-15T15:30:00",
    organizer: "Lisa Chen",
    room: "Conference Room A"
  },
  {
    id: 5,
    title: "Training Session",
    startTime: "2024-01-15T16:00:00",
    endTime: "2024-01-15T18:00:00",
    organizer: "David Wilson",
    room: "Conference Room A"
  },
  {
    id: 6,
    title: "Evening Workshop",
    startTime: "2024-01-15T19:00:00",
    endTime: "2024-01-15T21:00:00",
    organizer: "Emily Brown",
    room: "Conference Room A"
  }
];

// Helper function to get reservations for a specific date
export const getReservationsForDate = (date) => {
  const targetDate = new Date(date);
  return sampleReservations.filter(reservation => {
    const reservationDate = new Date(reservation.startTime);
    return reservationDate.toDateString() === targetDate.toDateString();
  });
};

// Helper function to generate random reservations for testing
export const generateRandomReservations = (date, count = 3) => {
  const reservations = [];
  const startHour = 9;
  const endHour = 18;
  
  for (let i = 0; i < count; i++) {
    const startHourRandom = Math.floor(Math.random() * (endHour - startHour)) + startHour;
    const duration = Math.floor(Math.random() * 3) + 1; // 1-3 hours
    const endHourRandom = Math.min(startHourRandom + duration, 21);
    
    const startTime = new Date(date);
    startTime.setHours(startHourRandom, 0, 0, 0);
    
    const endTime = new Date(date);
    endTime.setHours(endHourRandom, 0, 0, 0);
    
    const titles = [
      "Team Meeting",
      "Client Call",
      "Product Demo",
      "Strategy Session",
      "Training",
      "Review Meeting",
      "Planning Session",
      "Workshop"
    ];
    
    const organizers = [
      "John Smith",
      "Sarah Johnson",
      "Mike Davis",
      "Lisa Chen",
      "David Wilson",
      "Emily Brown",
      "Alex Thompson",
      "Maria Garcia"
    ];
    
    reservations.push({
      id: i + 1,
      title: titles[Math.floor(Math.random() * titles.length)],
      startTime: startTime.toISOString(),
      endTime: endTime.toISOString(),
      organizer: organizers[Math.floor(Math.random() * organizers.length)],
      room: "Conference Room A"
    });
  }
  
  return reservations.sort((a, b) => new Date(a.startTime) - new Date(b.startTime));
};
