# Halal Stock Scanner & Investment Companion

A comprehensive Halal stock screening and investment management application with backend (Go + PostgreSQL) and mobile app (Flutter).

## Features

- **Shariah Compliance Screening**: Automated screening based on activity, debt ratio, and non-halal income
- **Region-Based Stock Lists**: Browse stocks by region (GCC, MENA, US, EU, ASIA, CN, GLOBAL)
- **Portfolio Management**: Track your stock holdings
- **Zakat Calculator**: Calculate zakat on your investments (2.5% on eligible positions)
- **DCA Calculator**: Dollar-cost averaging investment growth calculator
- **Notifications**: Get notified when stock Shariah status changes
- **Ad Space & Promo Codes**: Support for advertisers and promotional codes

## Architecture

### Backend
- **Language**: Go 1.21+
- **Framework**: Gin
- **Database**: PostgreSQL
- **External API**: EODHD (EOD Historical Data)
- **Authentication**: JWT

### Mobile App
- **Framework**: Flutter
- **State Management**: Provider
- **Platform-Adaptive**: Cupertino (iOS) and Material (Android)

## Setup Instructions

### Backend Setup

1. **Install Dependencies**
   ```bash
   cd backend
   go mod download
   ```

2. **Database Setup**
   - Install PostgreSQL
   - Create a database:
     ```sql
     CREATE DATABASE halalstocks;
     ```

3. **Environment Variables**
   - Copy `.env.example` to `.env` (or create it manually)
   - Set the following variables:
     ```
     DB_HOST=localhost
     DB_PORT=5432
     DB_USER=postgres
     DB_PASSWORD=your_password
     DB_NAME=halalstocks
     DB_SSLMODE=disable
     
     SERVER_PORT=8080
     SERVER_HOST=0.0.0.0
     
     JWT_SECRET=your_jwt_secret_key_min_32_chars
     JWT_EXPIRATION=24h
     
     EODHD_API_KEY=your_eodhd_api_key
     EODHD_BASE_URL=https://eodhistoricaldata.com/api
     
     INGESTION_BATCH_SIZE=200
     ```

4. **Run Migrations**
   - Install golang-migrate:
     ```bash
     go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest
     ```
   - Run migrations:
     ```bash
     migrate -path migrations -database "postgres://user:password@localhost:5432/halalstocks?sslmode=disable" up
     ```

5. **Run the API Server**
   ```bash
   go run cmd/api/main.go
   ```

6. **Run Data Ingestion Job**
   ```bash
   go run cmd/ingest/main.go
   ```

7. **Setup Cron Job** (Optional)
   - Add to crontab to run every 12 hours:
     ```
     0 1,13 * * * cd /path/to/backend && go run cmd/ingest/main.go
     ```

### Flutter App Setup

1. **Install Dependencies**
   ```bash
   flutter pub get
   ```

2. **Update API Configuration**
   - Edit `lib/config/api_config.dart`
   - Update `baseUrl` to point to your backend server

3. **Run the App**
   ```bash
   flutter run
   ```

## API Endpoints

### Public Endpoints
- `GET /api/regions` - Get list of supported regions
- `GET /api/regions/{code}/stocks` - Get stocks by region (with pagination, status/grade filters)
- `GET /api/shariah/check?ticker={ticker}` - Check Shariah status of a stock
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login user

### Protected Endpoints (Require JWT)
- `GET /api/user/profile` - Get user profile
- `GET /api/user/portfolio` - Get user portfolio
- `POST /api/user/portfolio` - Add/update holding
- `GET /api/user/notifications` - Get user notifications
- `GET /api/tools/zakat` - Calculate zakat
- `GET /api/tools/dca?monthly={amount}&years={n}&rate={rate}` - DCA calculator
- `GET /api/ads?region_code={code}` - Get ads for region
- `POST /api/promo/validate` - Validate promo code

## Shariah Screening Rules

1. **Activity Filter**: Checks for haram sectors/keywords (banking, gambling, alcohol, tobacco, etc.)
2. **Debt Ratio**: Must be ≤ 30% (total_debt / total_assets)
3. **Non-halal Income Ratio**: Must be ≤ 5% (interest_income / total_revenue)
4. **Grading**:
   - **Grade A**: Debt < 10%, Income < 1% (Very clean)
   - **Grade B**: Within thresholds (Acceptable)
   - **Grade C**: Mixed (Acceptable with purification)
   - **Grade F**: Failed one or more rules

## Testing

### Backend Tests
```bash
cd backend
go test ./internal/shariah/...
```

## Project Structure

```
halalstocks/
├── backend/
│   ├── cmd/
│   │   ├── api/          # HTTP server
│   │   └── ingest/        # Data ingestion CLI
│   ├── internal/
│   │   ├── config/        # Configuration
│   │   ├── db/            # Database connection
│   │   ├── handlers/      # HTTP handlers
│   │   ├── middleware/    # Middleware (auth, CORS)
│   │   ├── models/        # Domain models
│   │   ├── repositories/  # Data access layer
│   │   ├── services/      # Business logic
│   │   ├── marketdata/    # External API integration
│   │   └── shariah/       # Shariah screening engine
│   ├── migrations/        # Database migrations
│   └── pkg/               # Shared packages (JWT)
└── lib/
    ├── config/            # API configuration
    ├── models/            # Data models
    ├── services/          # API service
    ├── providers/         # State management
    ├── screens/           # App screens
    └── widgets/           # Reusable widgets
```

## License

[Your License Here]
