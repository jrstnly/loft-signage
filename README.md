# Loft Signage Display

A responsive digital signage display for conference rooms and meeting spaces. Features a 16:9 image area at the top and a daily calendar view below showing room reservations from 7am to 9pm.

## Features

- **16:9 Image Display**: Top section optimized for 4K displays (3840x2160px)
- **Daily Calendar View**: Shows time slots from 7am to 9pm
- **Reservation Blocks**: Visual indicators for booked time slots
- **Responsive Design**: Scales appropriately on different screen sizes
- **Real-time Updates**: Current time and date display
- **Portrait Orientation**: Optimized for TV displays in portrait mode

## Quick Start

1. **Install Dependencies**
   ```bash
   npm install
   ```

2. **Start Development Server**
   ```bash
   npm run dev
   ```

3. **Build for Production**
   ```bash
   npm run build
   ```

## Deployment

### Automated Deployment from GitHub

This project includes an automated deployment script that sets up a complete kiosk environment on a Linux system (Ubuntu/Debian recommended).

#### Prerequisites

- A Linux server or single-board computer (Raspberry Pi 4, NUC, etc.)
- Internet connection for package installation
- Root/sudo access
- At least 2GB RAM and 4GB storage

#### Quick Deployment

**Option 1: One-line deployment (recommended)**
```bash
curl -fsSL https://raw.githubusercontent.com/jrstnly/loft-signage/main/deploy.sh | sudo bash
```

**Option 2: Clone and run locally**
1. **Clone the repository on your target machine:**
   ```bash
   sudo git clone https://github.com/jrstnly/loft-signage.git /opt/kiosk/src
   cd /opt/kiosk/src
   ```

2. **Make the deploy script executable and run it:**
   ```bash
   sudo chmod +x deploy.sh
   sudo ./deploy.sh
   ```

3. **The script will automatically:**
   - Install all required packages (Node.js, Nginx, Chromium, Cage)
   - Create a kiosk user account
   - Build the React application
   - Configure Nginx to serve the app
   - Set up a systemd service for auto-start
   - Configure display for portrait orientation (1080x1920)
   - Enable the kiosk service to start on boot

#### What Gets Installed

- **System Packages**: git, curl, nginx-light, cage (Wayland compositor)
- **Browser**: Chromium with kiosk mode
- **Node.js**: Latest LTS version via NodeSource
- **Build Tools**: npm, pnpm, yarn (auto-detected)
- **Display Tools**: wlr-randr for display configuration

#### Configuration

The deploy script is highly configurable. Edit the variables at the top of `deploy.sh`:

```bash
# Kiosk configuration
KIOSK_USER="kiosk"                    # User account for the kiosk
APP_ROOT="/opt/kiosk/www"             # Web root directory
APP_PORT="9000"                       # Nginx port (127.0.0.1:9000)
AUTO_REBOOT="yes"                     # Auto-reboot after setup

# Repository settings
REPO_URL="https://github.com/jrstnly/loft-signage.git"
REPO_BRANCH="main"
BUILD_CMD="npm ci && npm run build"   # Build command
BUILD_OUTPUT_DIR="dist"               # Vite output directory
```

#### Post-Deployment

After successful deployment:

1. **Check the kiosk service:**
   ```bash
   sudo systemctl status kiosk.service
   ```

2. **View logs:**
   ```bash
   sudo journalctl -u kiosk.service -f
   ```

3. **Test the web app:**
   ```bash
   curl http://127.0.0.1:9000/health
   ```

4. **Restart if needed:**
   ```bash
   sudo systemctl restart kiosk.service
   ```

#### Troubleshooting Deployment

**Build fails:**
- Check Node.js version: `node --version`
- Verify package.json exists in the cloned directory
- Check available memory: `free -h`

**Kiosk won't start:**
- Check display configuration: `wlr-randr`
- Verify Chromium installation: `which chromium`
- Check systemd logs: `journalctl -u kiosk.service`

**Display issues:**
- Run display setup manually: `/usr/local/bin/kiosk-display-setup`
- Check if Wayland is available: `echo $XDG_SESSION_TYPE`

### Manual Deployment

If you prefer manual setup or need to customize the deployment:

1. **Install dependencies manually:**
   ```bash
   sudo apt update
   sudo apt install nginx nodejs npm
   ```

2. **Build the application:**
   ```bash
   npm ci
   npm run build
   ```

3. **Configure Nginx:**
   ```bash
   sudo cp -r dist/* /var/www/html/
   sudo systemctl restart nginx
   ```

4. **Set up auto-start:**
   ```bash
   # Configure your system to start the browser in kiosk mode
   # This varies by operating system and display manager
   ```

## Usage

### Adding Your Image

1. Replace the placeholder in the image section with your own 16:9 image
2. Recommended image size: 3840x2160px for 4K displays
3. Update the `SignageDisplay.jsx` component to use your image:

```jsx
// In src/components/SignageDisplay.jsx
<div className="image-section">
  <img 
    src="/path/to/your/image.jpg" 
    alt="Your image description"
    className="display-image"
  />
  {/* ... rest of the component */}
</div>
```

### Adding Real Reservation Data

1. Replace the sample data in `src/data/sampleReservations.js` with your actual reservation data
2. Each reservation should have the following structure:

```javascript
{
  id: 1,
  title: "Meeting Title",
  startTime: "2024-01-15T09:00:00", // ISO string
  endTime: "2024-01-15T10:30:00",   // ISO string
  organizer: "Organizer Name",
  room: "Room Name"
}
```

### Connecting to External APIs

To connect to external calendar APIs (Google Calendar, Outlook, etc.):

1. Create an API service in `src/services/calendarService.js`
2. Update the `SignageDisplay.jsx` component to fetch real-time data
3. Set up automatic refresh intervals

Example API integration:

```javascript
// src/services/calendarService.js
export const fetchReservations = async (date) => {
  // Implement your API call here
  const response = await fetch(`/api/reservations?date=${date}`);
  return response.json();
};
```

## Display Setup

### 4K TV Configuration

1. Set the TV to portrait orientation
2. Configure the browser to run in fullscreen mode
3. Set up auto-refresh or use a kiosk mode browser

### Browser Configuration

For optimal display, configure your browser with these settings:

- **Fullscreen Mode**: Press F11 or use browser kiosk mode
- **Auto-refresh**: Set up a browser extension or use the built-in refresh
- **Disable Sleep**: Configure system settings to prevent sleep mode

### CSS Customization

The display uses CSS custom properties for easy theming. Key variables in `src/App.css`:

```css
:root {
  --primary-color: #1a1a2e;
  --accent-color: #ff6b6b;
  --text-color: #fff;
  --background-gradient: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
}
```

## File Structure

```
src/
├── components/
│   ├── SignageDisplay.jsx    # Main display component
│   └── DailyCalendar.jsx     # Calendar view component
├── data/
│   └── sampleReservations.js # Sample reservation data
├── utils/
│   └── imageUtils.js         # Image handling utilities
├── App.jsx                   # Main app component
├── App.css                   # Main styles
└── index.css                 # Global styles
```

## Responsive Breakpoints

- **4K Displays** (3840px+): Optimized for large screens
- **Desktop** (1200px+): Standard desktop layout
- **Tablet** (768px+): Adjusted for tablet screens
- **Mobile** (480px+): Mobile-optimized layout
- **Portrait TV** (1920px+ portrait): Side-by-side layout

## Browser Support

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## Development

### Available Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run preview` - Preview production build
- `npm run lint` - Run ESLint

### Adding New Features

1. Create new components in `src/components/`
2. Add utility functions in `src/utils/`
3. Update styles in `src/App.css`
4. Test on different screen sizes

## Troubleshooting

### Image Not Displaying
- Check file path and permissions
- Ensure image format is supported (JPG, PNG, WebP)
- Verify aspect ratio is close to 16:9

### Calendar Not Updating
- Check reservation data format
- Verify date/time strings are valid ISO format
- Ensure component is re-rendering properly

### Display Scaling Issues
- Check browser zoom level (should be 100%)
- Verify CSS media queries are working
- Test on target display resolution

## License

MIT License - feel free to use and modify as needed.

