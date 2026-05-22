# Quick Start Guide

## ✅ Setup Complete!

Your EODHD API key has been configured. Everything is ready to run!

## Starting the Application

### 1. Start the Backend API Server

Open a terminal and run:

```bash
cd backend
./start-server.sh
```

The server will start on `http://localhost:8080`

**Or manually:**
```bash
cd backend
export $(cat .env | grep -v '^#' | xargs)
go run cmd/api/main.go
```

### 2. Start Data Ingestion (Optional - in separate terminal)

This fetches stock data and runs Shariah screening:

```bash
cd backend
./start-ingestion.sh
```

**Or manually:**
```bash
cd backend
export $(cat .env | grep -v '^#' | xargs)
go run cmd/ingest/main.go
```

**Note**: The first ingestion run may take a while as it fetches data for all regions.

### 3. Run the Flutter App

In a new terminal:

```bash
flutter run
```

## Testing the API

Once the server is running, you can test it:

```bash
# Get list of regions
curl http://localhost:8080/api/regions

# Register a new user
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123","country":"US"}'

# Login
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'
```

## Configuration

- **API Server**: `http://localhost:8080`
- **Database**: PostgreSQL (localhost:5432/halalstocks)
- **EODHD API Key**: ✅ Configured
- **JWT Secret**: ✅ Auto-generated

## Troubleshooting

### Server won't start
- Check that PostgreSQL is running: `psql -U $(whoami) -d halalstocks -c "SELECT 1"`
- Verify `.env` file exists in `backend/` directory
- Check that port 8080 is not in use: `lsof -i :8080`

### Data ingestion fails
- Verify EODHD API key is correct in `.env`
- Check your EODHD API quota/limits
- Review logs for specific error messages

### Flutter app can't connect
- Ensure backend server is running
- Check `lib/config/api_config.dart` has correct base URL
- For iOS simulator, use `http://localhost:8080`
- For Android emulator, use `http://10.0.2.2:8080`

## Next Steps

1. ✅ Start the backend server
2. ✅ Run data ingestion to populate stocks
3. ✅ Start Flutter app
4. ✅ Register/login and explore the app!

Enjoy your Halal Stock Scanner! 🚀

