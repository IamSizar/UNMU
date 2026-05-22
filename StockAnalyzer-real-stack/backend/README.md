# Halal Stocks Backend

Backend API for the Halal Stock Scanner & Investment Companion app.

## Features

- **Stock Data Integration**: Fetches stock data from Financial Modeling Prep (FMP) API
- **Sharia Screening**: Automated screening engine that classifies stocks as HALAL, HARAM, MIXED, or UNKNOWN
- **User Management**: JWT-based authentication, user portfolios, notifications
- **Tools**: Zakat calculator, DCA (Dollar Cost Averaging) investment simulator
- **Ads & Promo Codes**: Support for regional ads and discount codes

## Tech Stack

- **Language**: Go 1.21+
- **Framework**: Gin (HTTP web framework)
- **Database**: PostgreSQL
- **Migrations**: golang-migrate
- **Authentication**: JWT (golang-jwt/jwt/v5)
- **External API**: Financial Modeling Prep (FMP)

## Setup

### Prerequisites

- Go 1.21 or higher
- PostgreSQL 12+
- golang-migrate (for database migrations)

### Installation

1. **Install dependencies**:
   ```bash
   go mod download
   ```

2. **Set up environment variables**:
   Create a `.env` file in the `backend/` directory:
   ```env
   # Database Configuration
   DB_HOST=localhost
   DB_PORT=5432
   DB_USER=your_username
   DB_PASSWORD=
   DB_NAME=halalstocks
   DB_SSLMODE=disable

   # Server Configuration
   SERVER_PORT=8080
   JWT_SECRET=your-secret-key-change-in-production

   # Stock Data API (Financial Modeling Prep)
   STOCK_API_KEY=your_fmp_api_key
   STOCK_API_BASE_URL=https://financialmodelingprep.com/api/v3
   STOCK_API_PROVIDER=fmp
   ```

3. **Run setup script**:
   ```bash
   ./setup.sh
   ```
   
   Or manually:
   ```bash
   # Create database
   createdb halalstocks
   
   # Run migrations
   migrate -path migrations -database "postgres://$USER@localhost/halalstocks?sslmode=disable" up
   ```

## Running

### Start the API Server

**Option 1: Using the helper script (recommended)**
```bash
./start-server.sh
```

**Option 2: Direct command**
```bash
go run cmd/api/main.go
```

**Option 3: Stop the server**
```bash
./stop-server.sh
```

The server will start on port 8080 (or the port specified in `SERVER_PORT`). If port 8080 is already in use, the start script will automatically kill the existing process.

### Run Data Ingestion

To fetch and process stock data:

```bash
go run cmd/ingest/main.go
```

This will:
- Fetch stocks from FMP API for all regions (US, GCC, MENA, EU, ASIA, CN, GLOBAL)
- Store stock data in the database
- Fetch financial fundamentals
- Run Sharia screening on each stock
- Generate notifications for status changes

## API Endpoints

### Public Endpoints

- `POST /api/auth/register` - Register a new user
- `POST /api/auth/login` - Login and get JWT token
- `GET /api/search?q={query}` - Search stocks by name or ticker
- `GET /api/stocks/:ticker?exchange={exchange}` - Get stock details with Sharia status
- `GET /api/ads?region_code={code}` - Get active ads for a region

### Protected Endpoints (Require JWT token in Authorization header)

- `GET /api/user/portfolio` - Get user's portfolio
- `POST /api/user/portfolio` - Add stock to portfolio
- `DELETE /api/user/portfolio/:stock_id` - Remove stock from portfolio
- `GET /api/user/notifications` - Get user notifications
- `PUT /api/user/notifications/:id/read` - Mark notification as read
- `GET /api/tools/zakat` - Calculate Zakat on portfolio
- `GET /api/tools/dca?monthly={amount}&years={n}&rate={rate}` - DCA calculator
- `POST /api/promo/validate` - Validate promo code

## Project Structure

```
backend/
├── cmd/
│   ├── api/          # HTTP API server entry point
│   └── ingest/       # Data ingestion CLI job
├── internal/
│   ├── config/       # Configuration management
│   ├── db/           # Database connection
│   ├── handlers/     # HTTP handlers (Gin)
│   ├── middleware/   # Auth, CORS middleware
│   ├── models/       # Domain models
│   ├── repositories/ # Data access layer
│   ├── services/     # Business logic (ingestion)
│   ├── marketdata/   # External API integration (FMP)
│   └── shariah/      # Sharia screening engine
├── migrations/       # SQL migration files
├── pkg/
│   └── jwt/          # JWT token utilities
└── go.mod
```

## Sharia Screening

The screening engine evaluates stocks based on:

1. **Activity Screening**: Checks if the company's business activities are halal (no alcohol, gambling, pork, etc.)
2. **Financial Ratios**:
   - Debt Ratio: Must be ≤ 30%
   - Haram Income Ratio: Must be ≤ 5%
   - Cash + Receivables Rule: Must be ≤ 33% of market cap

**Grades**:
- **A**: Fully compliant (HALAL)
- **B**: Acceptable with minor issues (HALAL)
- **C**: Mixed, requires purification (MIXED)
- **F**: Non-compliant (HARAM)

## Database Schema

See `migrations/000001_initial_schema.up.sql` for the complete database schema.

Key tables:
- `stocks` - Stock information
- `fundamentals` - Financial data
- `shariah_status` - Sharia compliance status
- `users` - User accounts
- `user_portfolios` - User stock holdings
- `notifications` - User notifications
- `analyst_ratings` - Analyst ratings for stocks
- `ads` - Advertisement data
- `promo_codes` - Promo code management

## Development

### Running Tests

```bash
go test ./...
```

### Building

```bash
# Build API server
go build -o bin/api cmd/api/main.go

# Build ingestion job
go build -o bin/ingest cmd/ingest/main.go
```

## License

[Your License Here]
