require('dotenv').config();
const express = require('express');
const cors    = require('cors');
const sql     = require('mssql/msnodesqlv8');

const app = express();
app.use(express.json());
app.use(cors());

const dbConfig = {
    server:   'DESKTOP-UBFD8H3\\SQLEXPRESS',
    database: 'playconndb',
    driver:   'msnodesqlv8',
    options: {
        trustedConnection:      true,
        trustServerCertificate: true
    }
};

sql.connect(dbConfig)
   .then(() => console.log('Connected to playconndb'))
   .catch(err => console.error('Connection failed:', err));


app.post('/api/users', async (req, res) => {
    try {
        const { fullname, email, dateofbirth, latitude, longitude, locationaddress } = req.body;
        if (!latitude || !longitude)
            return res.status(400).json({ error: 'User location (latitude & longitude) is required.' });

        const r = new sql.Request();
        r.input('fullname',        sql.NVarChar, fullname);
        r.input('email',           sql.NVarChar, email);
        r.input('dob',             sql.Date,     dateofbirth);
        r.input('latitude',        sql.Decimal,  latitude);
        r.input('longitude',       sql.Decimal,  longitude);
        r.input('locationaddress', sql.NVarChar, locationaddress || null);

        await r.query(`
            INSERT INTO users (fullname, email, dateofbirth, latitude, longitude, locationaddress)
            VALUES (@fullname, @email, @dob, @latitude, @longitude, @locationaddress)
        `);

        res.status(201).json({ message: 'User created successfully.' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/users/:userid/stats', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('userId', sql.Int, req.params.userid);
        const result = await r.query(`SELECT * FROM vw_UserWinLoss WHERE userid = @userId`);
        res.json(result.recordset[0] || { userid: req.params.userid, wins: 0, losses: 0, ties: 0, totalmatches: 0 });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/users/:userid/dashboard', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('targetUser', sql.Int, req.params.userid);
        const result = await r.query(`
            SELECT m.matchid, s.sportname, m.starttime, mp.status,
                   mp.teamassignment, t.teamname,
                   m.hostuserid, uh.fullname AS hostname, m.assignmentmode
            FROM matchparticipants mp
            JOIN matches m  ON mp.matchid   = m.matchid
            JOIN sports  s  ON m.sportid    = s.sportid
            JOIN users  uh  ON m.hostuserid = uh.userid
            LEFT JOIN teams t ON mp.teamid  = t.teamid
            WHERE mp.userid = @targetUser AND m.starttime > GETDATE()
        `);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/users/:userid/suggestions', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('targetUser', sql.Int, req.params.userid);
        const result = await r.query(`
            SELECT m.matchid, s.sportname, v.venuename, m.starttime, m.assignmentmode
            FROM matches m
            JOIN interests i ON m.sportid = i.sportid AND i.userid = @targetUser
            JOIN sports    s ON m.sportid = s.sportid
            JOIN venues    v ON m.venueid = v.venueid
            JOIN users     u ON u.userid  = @targetUser
            WHERE m.matchstatus = 'open'
              AND CAST(m.starttime AS TIME) >= u.preferredtimestart
        `);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/users/:userid/notifications', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('userId', sql.Int, req.params.userid);
        const result = await r.query(`
            SELECT notificationid, message, notificationtype, relatedmatchid, isread, createdat
            FROM notifications WHERE userid = @userId ORDER BY createdat DESC
        `);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/users/:userid/interests', async (req, res) => {
    try {
        const { sportid, skilllevel } = req.body;
        const r = new sql.Request();
        r.input('userId',     sql.Int,      req.params.userid);
        r.input('sportId',    sql.Int,      sportid);
        r.input('skilllevel', sql.NVarChar, skilllevel || 'casual');
        await r.query(`INSERT INTO interests (userid, sportid, skilllevel) VALUES (@userId, @sportId, @skilllevel)`);
        res.status(201).json({ message: 'Interest added.' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/users/:userid/interests', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('userId', sql.Int, req.params.userid);
        const result = await r.query(`
            SELECT i.interestid, s.sportname, i.skilllevel
            FROM interests i JOIN sports s ON i.sportid = s.sportid
            WHERE i.userid = @userId
        `);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/venues', async (req, res) => {
    try {
        const result = await sql.query(`SELECT * FROM venues`);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/matches', async (req, res) => {
    try {
        const { hostuserid, sportid, venueid, starttime, endtime, agecategory, maxplayers, assignmentmode } = req.body;
        const r = new sql.Request();
        r.input('host',           sql.Int,      hostuserid);
        r.input('sport',          sql.Int,      sportid);
        r.input('venue',          sql.Int,      venueid);
        r.input('start',          sql.DateTime, starttime);
        r.input('end',            sql.DateTime, endtime);
        r.input('age',            sql.NVarChar, agecategory);
        r.input('max',            sql.Int,      maxplayers);
        r.input('assignmentmode', sql.NVarChar, assignmentmode || 'random');
        await r.query(`
            INSERT INTO matches (hostuserid, sportid, venueid, starttime, endtime, agecategory, maxplayers, assignmentmode)
            VALUES (@host, @sport, @venue, @start, @end, @age, @max, @assignmentmode)
        `);
        res.status(201).json({ message: 'Match successfully broadcasted!' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/matches/open', async (req, res) => {
    try {
        const result = await sql.query(`
            SELECT m.matchid, s.sportname, v.venuename, v.neighborhood,
                   m.starttime, m.endtime, m.agecategory,
                   m.maxplayers, m.currentplayers, m.matchstatus, m.assignmentmode,
                   uh.fullname AS hostname
            FROM matches m
            JOIN sports s  ON m.sportid    = s.sportid
            JOIN venues v  ON m.venueid    = v.venueid
            JOIN users  uh ON m.hostuserid = uh.userid
            WHERE m.matchstatus = 'open'
            ORDER BY m.starttime ASC
        `);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/matches/:matchid/roster', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('matchId', sql.Int, req.params.matchid);
        const result = await r.query(`SELECT * FROM vw_MatchRoster WHERE matchid = @matchId`);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/search', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('kw', sql.NVarChar, `%${req.query.term}%`);
        const result = await r.query(`
            SELECT m.matchid, s.sportname, v.venuename, m.starttime,
                   m.currentplayers, m.maxplayers, m.assignmentmode,
                   m.hostuserid, uh.fullname AS hostname
            FROM matches m
            JOIN sports s  ON m.sportid    = s.sportid
            JOIN venues v  ON m.venueid    = v.venueid
            JOIN users  uh ON m.hostuserid = uh.userid
            WHERE s.sportname LIKE @kw OR v.neighborhood LIKE @kw
        `);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/matches/:matchid/join', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('matchId', sql.Int, req.params.matchid);
        r.input('userId',  sql.Int, req.body.userid);
        await r.query(`INSERT INTO matchparticipants (matchid, userid) VALUES (@matchId, @userId)`);
        res.status(200).json({ message: 'Successfully joined.' });
    } catch (err) {
        const msg = err.message || '';
        if (msg.includes('Age restriction'))          return res.status(403).json({ error: msg });
        if (msg.includes('Conflict'))                 return res.status(409).json({ error: msg });
        if (msg.includes('Violation of UNIQUE'))      return res.status(409).json({ error: 'Already joined this match.' });
        res.status(500).json({ error: msg });
    }
});

app.post('/api/matches/:matchid/leave', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('matchId', sql.Int, req.params.matchid);
        r.input('userId',  sql.Int, req.body.userid);
        const check = await r.query(`
            SELECT status FROM matchparticipants WHERE matchid = @matchId AND userid = @userId
        `);
        if (check.recordset.length === 0)
            return res.status(404).json({ error: 'Participant not found in this match.' });

        await r.query(`DELETE FROM matchparticipants WHERE matchid = @matchId AND userid = @userId`);
        res.json({ message: 'Left match.' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/matches/:matchid/teams', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('matchId', sql.Int, req.params.matchid);
        const result = await r.query(`
            SELECT t.teamid, t.teamname, t.teamlabel, u.userid, u.fullname
            FROM teams t
            JOIN matchparticipants mp ON t.teamid  = mp.teamid
            JOIN users             u  ON mp.userid = u.userid
            WHERE t.matchid = @matchId
        `);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/matches/:matchid/self-assign', async (req, res) => {
    try {
        const { userid, teamlabel } = req.body;
        const r = new sql.Request();
        r.input('matchId',   sql.Int,      req.params.matchid);
        r.input('userId',    sql.Int,      userid);
        r.input('teamlabel', sql.NVarChar, teamlabel);

        const modeResult = await r.query(`SELECT assignmentmode FROM matches WHERE matchid = @matchId`);
        if (modeResult.recordset[0].assignmentmode !== 'self')
            return res.status(403).json({ error: 'This match uses random assignment. Self-assignment is not allowed.' });

        const teamResult = await r.query(`SELECT teamid FROM teams WHERE matchid = @matchId AND teamlabel = @teamlabel`);
        if (teamResult.recordset.length === 0)
            return res.status(404).json({ error: 'Team not found for this match.' });

        const teamId = teamResult.recordset[0].teamid;
        const t = new sql.Request();
        t.input('matchId',   sql.Int,      req.params.matchid);
        t.input('userId',    sql.Int,      userid);
        t.input('teamId',    sql.Int,      teamId);
        t.input('teamlabel', sql.NVarChar, teamlabel);
        await t.query(`
            UPDATE matchparticipants
            SET teamid = @teamId, teamassignment = @teamlabel
            WHERE matchid = @matchId AND userid = @userId
        `);
        res.json({ message: `Assigned to Team ${teamlabel.toUpperCase()}.` });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/matches/:matchid/generate-teams', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('matchId', sql.Int, req.params.matchid);
        await r.execute('sp_GenerateTeams');
        res.json({ message: 'Teams randomly generated and players notified!' });
    } catch (err) {
        const msg = err.message || '';
        if (msg.includes('self-assignment')) return res.status(403).json({ error: msg });
        res.status(500).json({ error: msg });
    }
});

app.post('/api/matches/:matchid/result', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('matchId',         sql.Int,      req.params.matchid);
        r.input('winnerteamlabel', sql.NVarChar, req.body.winnerteamlabel);
        await r.execute('sp_RecordResult');
        const winner = req.body.winnerteamlabel;
        res.json({ message: `Result recorded. Winner: ${winner === 'tie' ? 'Tie' : 'Team ' + winner.toUpperCase()}` });
    } catch (err) {
        const msg = err.message || '';
        if (msg.includes('No teams')) return res.status(400).json({ error: msg });
        res.status(500).json({ error: msg });
    }
});

app.get('/api/matches/:matchid/scorecard', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('matchId', sql.Int, req.params.matchid);
        const result = await r.query(`
            SELECT sc.scorecardid, u.fullname, t.teamname, sc.result, sc.scorevalue, sc.recordedat
            FROM scorecard sc
            JOIN users u      ON sc.userid = u.userid
            LEFT JOIN teams t ON sc.teamid = t.teamid
            WHERE sc.matchid = @matchId
        `);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.patch('/api/notifications/:notificationid/read', async (req, res) => {
    try {
        const r = new sql.Request();
        r.input('notifId', sql.Int, req.params.notificationid);
        await r.query(`UPDATE notifications SET isread = 1 WHERE notificationid = @notifId`);
        res.json({ message: 'Notification marked as read.' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/matches/:matchid/equipment', async (req, res) => {
    try {
        const { userid, itemname } = req.body;
        const r = new sql.Request();
        r.input('matchId', sql.Int,      req.params.matchid);
        r.input('userId',  sql.Int,      userid);
        r.input('item',    sql.NVarChar, itemname);
        await r.query(`INSERT INTO equipment (matchid, userid, itemname) VALUES (@matchId, @userId, @item)`);
        res.status(201).json({ message: 'Equipment tagged for match.' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/analytics/heatmap', async (req, res) => {
    try {
        const result = await sql.query(`SELECT * FROM vw_VenueHeatmap ORDER BY TotalMatches DESC`);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/analytics/leaderboard', async (req, res) => {
    try {
        const result = await sql.query(`SELECT * FROM vw_NeighborhoodLeaderboard ORDER BY TotalMatchesPlayed DESC`);
        res.json(result.recordset);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
