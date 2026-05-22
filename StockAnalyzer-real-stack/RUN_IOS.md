# Running on iOS Simulator

## Quick Start

### Option 1: Use the automated script
```bash
./run-ios.sh
```

### Option 2: Manual steps

**Step 1: Start Backend Server** (Terminal 1)
```bash
cd backend
./start-server.sh
```

**Step 2: Start iOS Simulator** (Terminal 2)
```bash
open -a Simulator
```

**Step 3: Run Flutter App** (Terminal 2)
```bash
flutter run -d ios
```

Or simply:
```bash
flutter run
```
(Flutter will automatically detect and use the iOS simulator)

## Verify Backend is Running

Before running the app, make sure the backend is accessible:

```bash
curl http://localhost:8080/api/regions
```

You should see: `{"regions":["GCC","MENA","US","EU","ASIA","CN","GLOBAL"]}`

## Troubleshooting

### Backend not responding
- Check if server is running: `lsof -i :8080`
- Check backend logs in the terminal where you started it
- Verify `.env` file has correct configuration

### iOS Simulator not starting
- Make sure Xcode is installed: `xcode-select -p`
- List available simulators: `xcrun simctl list devices`
- Boot a specific simulator: `xcrun simctl boot "iPhone 16e"`

### Flutter build errors
- Clean build: `flutter clean && flutter pub get`
- Check iOS setup: `flutter doctor`
- Verify CocoaPods: `cd ios && pod install`

## API Configuration

The app is configured to connect to `http://localhost:8080/api` which works perfectly with iOS Simulator since it shares the host network.

If you need to connect to a different backend:
1. Edit `lib/config/api_config.dart`
2. Change `baseUrl` to your backend URL
3. Hot reload: Press `r` in the Flutter terminal

## Current Setup

- ✅ Backend configured with EODHD API key
- ✅ Database migrations completed
- ✅ iOS Simulator available
- ✅ Flutter dependencies installed

You're all set! 🚀

