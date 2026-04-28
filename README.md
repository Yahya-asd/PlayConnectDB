# 🏟️ PlayConnDB

A **community sports matchmaking platform** — a full-stack web application that lets neighbourhood residents discover open sports matches, join or host games, get auto-assigned to teams, and track their win/loss record across sports.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Database Design](#database-design)
- [API Reference](#api-reference)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Views & Stored Procedures](#views--stored-procedures)
- [Seed Data](#seed-data)

---

## Overview

PlayConnDB connects local players to each other. A user registers with their location and sport interests, and the platform surfaces relevant open matches nearby. Match hosts can auto-generate balanced teams and record results — all enforced by SQL-level business logic (triggers and stored procedures), keeping the Node.js layer thin and stateless.

---

## ✨ Features

- **Match discovery** — browse open matches filtered by your sport interests and preferred play time
- **Join / leave matches** — automatic waitlist management when a match is full; waitlisted players are auto-promoted when someone leaves
- **Team generation** — random or self-assigned team modes; `sp_GenerateTeams` shuffles players via `NEWID()` for fair randomisation
- **Result recording** — `sp_RecordResult` loops all confirmed participants, assigns win/loss/tie to each scorecard, and fires notifications
- **Win/Loss stats** — per-user record visible through `vw_UserWinLoss`
- **Venue heatmap** — `vw_VenueHeatmap` shows match volume per venue
- **Neighbourhood leaderboard** — `vw_NeighborhoodLeaderboard` ranks areas by completed matches
- **Notifications** — in-app notifications for team assignments, match updates, cancellations, and result posts
- **Equipment tracking** — players can declare what equipment they're bringing to a match

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| Database | Microsoft SQL Server (Express) |
| Backend | Node.js + Express |
| Frontend | Vanilla HTML/CSS/JS (single file, no build step) |
| DB Driver | `mssql` + `msnodesqlv8` (Windows native, Trusted Connection) |

---

## 🗄 Database Design

### Tables

| Table | Purpose |
|---|---|
| `users` | Registered players with location coordinates and preferred play times |
| `sports` | Sports catalogue (Football, Basketball, Cricket, etc.) |
| `venues` | Venues with geolocation (park, street, complex) |
| `interests` | User ↔ sport junction with skill level |
| `matches` | Games hosted by a user at a venue |
| `teams` | Team A & B for a match |
| `matchparticipants` | Player registrations — confirmed, waitlist, or canceled |
| `scorecard` | Per-player match result (win / loss / tie) |
| `equipment` | Equipment items brought by a player to a match |
| `notifications` | In-app notification inbox per user |

### Key Constraints

- A user can only register once per match (`UNIQUE (matchid, userid)`)
- Age category is enforced at the trigger level before any participant can join
- `currentplayers` is always non-negative (`CHECK (currentplayers >= 0)`)
- Team labels are strictly `'a'` or `'b'`; only one of each allowed per match

---

## 📡 API Reference

All routes are served at `http://localhost:3000/api`.

### Users

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/users` | Register a new user |
| `GET` | `/api/users/:userid/stats` | Win/loss stats (from `vw_UserWinLoss`) |
| `GET` | `/api/users/:userid/dashboard` | Upcoming matches for a user |
| `GET` | `/api/users/:userid/suggestions` | Recommended open matches by sport interest & preferred time |
| `GET` | `/api/users/:userid/notifications` | Notification inbox |

### Matches

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/matches` | Create a new match |
| `GET` | `/api/matches` | List all open matches |
| `POST` | `/api/matches/:matchid/join` | Join a match (triggers `trg_JoinMatch`) |
| `POST` | `/api/matches/:matchid/leave` | Leave a match (triggers `trg_LeaveMatch`) |
| `POST` | `/api/matches/:matchid/generate-teams` | Run `sp_GenerateTeams` |
| `POST` | `/api/matches/:matchid/record-result` | Run `sp_RecordResult` |
| `GET` | `/api/matches/:matchid/roster` | Full roster from `vw_MatchRoster` |

### Analytics

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/analytics/heatmap` | Venue activity from `vw_VenueHeatmap` |
| `GET` | `/api/analytics/leaderboard` | Neighbourhood leaderboard |

---

## 📁 Project Structure

```
playconndb/
├── database.sql        # Complete DB: tables, views, triggers, procs, seed data
├── index.js            # Express API — thin routing layer, all logic in SQL
├── frontend.html       # Single-file frontend, open directly in browser
├── package.json        # Node dependencies
├── .env                # Server port (PORT=3000)
├── HOW_TO_RUN.md       # Setup guide
└── node_modules/       # npm packages (not committed to git)
```

> **Note:** Add `node_modules/` to your `.gitignore` — it's included in this zip for convenience but should not be committed.

---

## 🚀 Getting Started

### Prerequisites
- **SQL Server** (Express or full edition) with SSMS installed
- **Node.js** v16+
- **Windows** (required — `msnodesqlv8` is Windows-only)

### Step 1 — Set up the database

1. Open **SQL Server Management Studio (SSMS)**
2. Connect to your instance
3. Open `database.sql` and press **F5**

This drops and recreates `playconndb` from scratch, including all tables, views, triggers, stored procedures, and seed data.

### Step 2 — Configure the server name

Open `index.js` and update the connection config to match your SQL Server instance name:

```js
const dbConfig = {
    server: 'YOUR_INSTANCE_NAME\\SQLEXPRESS',   // ← change this
    database: 'playconndb',
    driver: 'msnodesqlv8',
    options: {
        trustedConnection: true,
        trustServerCertificate: true
    }
};
```

### Step 3 — Install dependencies

```bash
npm install
```

> If `msnodesqlv8` fails to build, run `npm install --global windows-build-tools` in an **administrator** terminal first.

### Step 4 — Start the server

```bash
npm start
```

You should see:
```
Server running on port 3000
Connected to playconndb
```

### Step 5 — Open the frontend

Open `frontend.html` directly in your browser (Chrome or Edge recommended). It connects to `http://localhost:3000/api` automatically — no server needed to serve the HTML file.

---

## ⚙️ Views & Stored Procedures

### Views

| View | Description |
|---|---|
| `vw_MatchRoster` | Full roster per match: players, teams, status, host info |
| `vw_UserWinLoss` | Per-user wins, losses, ties, and total matches from scorecard |
| `vw_VenueHeatmap` | Total matches hosted per venue and neighbourhood |
| `vw_NeighborhoodLeaderboard` | Completed match count ranked by neighbourhood |

### Triggers

| Trigger | Table | Behaviour |
|---|---|---|
| `trg_JoinMatch` | `matchparticipants` | Age check, schedule conflict check, auto-waitlist if full, auto-close to `full` when capacity is reached |
| `trg_LeaveMatch` | `matchparticipants` | Auto-promotes first waitlisted player, decrements `currentplayers`, reopens match if it was `full` |
| `trg_TeamAssignNotify` | `matchparticipants` | Inserts a `team_assigned` notification whenever a player's team is updated |

### Stored Procedures

| Procedure | Description |
|---|---|
| `sp_GenerateTeams(@matchId)` | Creates Team A & B if missing, randomly shuffles players using `NEWID()`, assigns teams, marks match as `teamsgenerated` |
| `sp_RecordResult(@matchId, @winnerteamlabel)` | Loops all confirmed participants, assigns win/loss/tie to scorecard, notifies each player, marks match as `completed` |

---

## 🌱 Seed Data

The `database.sql` file includes seed data so you can explore the app immediately after setup:

- **7 users** with varied locations, sport interests, and preferred play times
- **Multiple sports**: Football, Basketball, Cricket, Tennis, Badminton
- **Venues** across different neighbourhoods (parks, street courts, complexes)
- **Matches** in various states: open, full, teamsgenerated, completed
- **Participants, teams, scorecards, and notifications** pre-populated

### Quick test queries (run in SSMS after setup)

```sql
USE playconndb;

-- Full roster for match 1
SELECT * FROM vw_MatchRoster WHERE matchid = 1;

-- Win/loss records for all users
SELECT * FROM vw_UserWinLoss;

-- Venue activity heatmap
SELECT * FROM vw_VenueHeatmap;

-- Neighbourhood leaderboard
SELECT * FROM vw_NeighborhoodLeaderboard;

-- Generate teams for match 3
EXEC sp_GenerateTeams @matchId = 3;

-- Record result for match 1 (Team A wins)
EXEC sp_RecordResult @matchId = 1, @winnerteamlabel = 'a';
```

---

## 🛠 Built With

- **Microsoft SQL Server** — relational database, triggers, stored procedures, views
- **Node.js / Express** — REST API layer
- **Vanilla JS** — frontend (no framework, no build step)
- **mssql + msnodesqlv8** — Windows-native SQL Server driver with Trusted Connection****
