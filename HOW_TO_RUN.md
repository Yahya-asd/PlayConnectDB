# PlayConnDB — How to Run

## What's in this folder

| File | What it is |
|---|---|
| `database.sql` | Full database: tables, triggers, stored procedures, views, seed data |
| `index.js` | Express API server (thin routing layer — all logic is now in SQL) |
| `frontend.html` | Frontend — open directly in a browser |
| `package.json` | Node dependencies |
| `.env` | Environment config (port) |

---

## Step 1 — Run the SQL

1. Open **SQL Server Management Studio (SSMS)**
2. Connect to your instance (`DESKTOP-UBFD8H3\SQLEXPRESS` or your own)
3. Open `database.sql`
4. Press **F5** to execute the entire file

This will:
- Drop and recreate `playconndb`
- Create all tables, views, triggers, and stored procedures
- Insert all seed data (sports, venues, 7 users, matches, teams, participants, scorecards, notifications)

---

## Step 2 — Update the server name (if needed)

Open `index.js` and find this line near the top:

```js
server: 'DESKTOP-UBFD8H3\\SQLEXPRESS',
```

Change it to match your own SQL Server instance name. You can find your instance name in SSMS — it's shown in the connection dialog.

---

## Step 3 — Install Node dependencies

Open a terminal in this folder and run:

```bash
npm install
```

> **Prerequisite:** You need Node.js installed. Download from https://nodejs.org if you don't have it.
> `msnodesqlv8` requires Windows and Visual C++ build tools. If the install fails, run:
> `npm install --global windows-build-tools` in an admin terminal first.

---

## Step 4 — Start the API server

```bash
npm start
```

You should see:

```
Server running on port 3000
Connected to playconndb
```

---

## Step 5 — Open the frontend

Open `frontend.html` directly in your browser (double-click it or drag it into Chrome/Edge). It connects to `http://localhost:3000/api` automatically.

---

## What the SQL now handles (was previously in Node.js)

**Triggers:**

| Trigger | Table | What it does |
|---|---|---|
| `trg_JoinMatch` | `matchparticipants` | Age check, schedule conflict check, auto-waitlist if full, auto-close match to `full` when capacity is reached |
| `trg_LeaveMatch` | `matchparticipants` | Auto-promotes first waitlist player on leave, decrements `currentplayers`, reopens match if it was `full` |
| `trg_TeamAssignNotify` | `matchparticipants` | Inserts a `team_assigned` notification whenever a player's team is updated |

**Stored Procedures:**

| Procedure | What it does |
|---|---|
| `sp_RecordResult(@matchId, @winnerteamlabel)` | Loops all confirmed participants, assigns win/loss/tie to scorecard, notifies each player, marks match as `completed` |
| `sp_GenerateTeams(@matchId)` | Creates Team A & B if missing, shuffles players randomly using `NEWID()`, assigns teams, marks match as `teamsgenerated` |

---

## Quick test queries (run in SSMS after setup)

```sql
USE playconndb;

SELECT * FROM vw_MatchRoster WHERE matchid = 1;
SELECT * FROM vw_UserWinLoss;
SELECT * FROM vw_VenueHeatmap;
SELECT * FROM vw_NeighborhoodLeaderboard;

EXEC sp_GenerateTeams @matchId = 3;
EXEC sp_RecordResult  @matchId = 1, @winnerteamlabel = 'a';
```
