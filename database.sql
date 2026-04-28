IF EXISTS (SELECT name FROM sys.databases WHERE name = 'playconndb')
BEGIN
    ALTER DATABASE playconndb SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE playconndb;
END
GO

CREATE DATABASE playconndb;
GO
USE playconndb;
GO

CREATE TABLE sports (
    sportid            INT PRIMARY KEY IDENTITY(1,1),
    sportname          NVARCHAR(50) NOT NULL UNIQUE,
    minplayersrequired INT DEFAULT 2
);

CREATE TABLE venues (
    venueid         INT PRIMARY KEY IDENTITY(1,1),
    venuename       NVARCHAR(100) NOT NULL,
    venuetype       NVARCHAR(20) CHECK (venuetype IN ('park', 'street', 'complex')),
    neighborhood    NVARCHAR(100) NOT NULL,
    locationaddress NVARCHAR(255),
    latitude        DECIMAL(9,6),
    longitude       DECIMAL(9,6)
);

CREATE TABLE users (
    userid             INT PRIMARY KEY IDENTITY(1,1),
    fullname           NVARCHAR(100) NOT NULL,
    email              NVARCHAR(100) UNIQUE NOT NULL,
    dateofbirth        DATE NOT NULL,
    residentstatus     NVARCHAR(20) DEFAULT 'unverified'
                       CHECK (residentstatus IN ('verified', 'unverified')),
    latitude           DECIMAL(9,6) NOT NULL,
    longitude          DECIMAL(9,6) NOT NULL,
    locationaddress    NVARCHAR(255),
    preferredtimestart TIME DEFAULT '00:00:00',
    preferredtimeend   TIME DEFAULT '23:59:00'
);

CREATE TABLE interests (
    interestid  INT PRIMARY KEY IDENTITY(1,1),
    userid      INT NOT NULL FOREIGN KEY REFERENCES users(userid),
    sportid     INT NOT NULL FOREIGN KEY REFERENCES sports(sportid),
    skilllevel  NVARCHAR(20) DEFAULT 'casual'
                CHECK (skilllevel IN ('casual', 'intermediate', 'competitive')),
    UNIQUE (userid, sportid)
);

CREATE TABLE matches (
    matchid          INT PRIMARY KEY IDENTITY(1,1),
    hostuserid       INT NOT NULL FOREIGN KEY REFERENCES users(userid),
    sportid          INT NOT NULL FOREIGN KEY REFERENCES sports(sportid),
    venueid          INT NOT NULL FOREIGN KEY REFERENCES venues(venueid),
    starttime        DATETIME NOT NULL,
    endtime          DATETIME NOT NULL,
    agecategory      NVARCHAR(10) CHECK (agecategory IN ('u16', 'u19', '19+')),
    maxplayers       INT NOT NULL,
    currentplayers   INT DEFAULT 0,
    matchstatus      NVARCHAR(20) DEFAULT 'open'
                     CHECK (matchstatus IN ('open','full','teamsgenerated','canceled','completed')),
    assignmentmode   NVARCHAR(20) DEFAULT 'random'
                     CHECK (assignmentmode IN ('random', 'self')),
    CONSTRAINT chk_timeorder             CHECK (endtime > starttime),
    CONSTRAINT chk_currentplayers_nonneg CHECK (currentplayers >= 0)
);

CREATE TABLE teams (
    teamid     INT PRIMARY KEY IDENTITY(1,1),
    matchid    INT NOT NULL FOREIGN KEY REFERENCES matches(matchid),
    teamname   NVARCHAR(50) NOT NULL,
    teamlabel  NVARCHAR(1) NOT NULL CHECK (teamlabel IN ('a','b')),
    UNIQUE (matchid, teamlabel)
);

CREATE TABLE matchparticipants (
    participationid INT PRIMARY KEY IDENTITY(1,1),
    matchid         INT NOT NULL FOREIGN KEY REFERENCES matches(matchid),
    userid          INT NOT NULL FOREIGN KEY REFERENCES users(userid),
    teamid          INT FOREIGN KEY REFERENCES teams(teamid),
    status          NVARCHAR(20) DEFAULT 'confirmed'
                    CHECK (status IN ('confirmed', 'waitlist', 'canceled')),
    teamassignment  NVARCHAR(1) DEFAULT NULL
                    CHECK (teamassignment IS NULL OR teamassignment IN ('a','b')),
    joinedat        DATETIME DEFAULT GETDATE(),
    UNIQUE (matchid, userid)
);

CREATE TABLE scorecard (
    scorecardid INT PRIMARY KEY IDENTITY(1,1),
    matchid     INT NOT NULL FOREIGN KEY REFERENCES matches(matchid),
    teamid      INT FOREIGN KEY REFERENCES teams(teamid),
    userid      INT NOT NULL FOREIGN KEY REFERENCES users(userid),
    result      NVARCHAR(10) NOT NULL
                CHECK (result IN ('win', 'loss', 'tie')),
    scorevalue  INT DEFAULT 0,
    recordedat  DATETIME DEFAULT GETDATE(),
    CONSTRAINT uq_scorecard_match_user UNIQUE (matchid, userid)
);

CREATE TABLE equipment (
    equipmentid INT PRIMARY KEY IDENTITY(1,1),
    matchid     INT FOREIGN KEY REFERENCES matches(matchid),
    userid      INT FOREIGN KEY REFERENCES users(userid),
    itemname    NVARCHAR(50) NOT NULL
);

CREATE TABLE notifications (
    notificationid   INT PRIMARY KEY IDENTITY(1,1),
    userid           INT NOT NULL FOREIGN KEY REFERENCES users(userid),
    message          NVARCHAR(255),
    notificationtype NVARCHAR(30) DEFAULT 'general'
                     CHECK (notificationtype IN (
                         'general', 'match_invite', 'team_assigned',
                         'match_update', 'match_canceled', 'result_posted')),
    relatedmatchid   INT FOREIGN KEY REFERENCES matches(matchid),
    isread           BIT DEFAULT 0,
    createdat        DATETIME DEFAULT GETDATE()
);
GO

CREATE VIEW vw_VenueHeatmap AS
SELECT
    v.venuename,
    v.neighborhood,
    COUNT(m.matchid) AS TotalMatches
FROM venues v
LEFT JOIN matches m ON v.venueid = m.venueid
GROUP BY v.venuename, v.neighborhood;
GO

CREATE VIEW vw_NeighborhoodLeaderboard AS
SELECT
    v.neighborhood,
    COUNT(m.matchid) AS TotalMatchesPlayed
FROM venues v
JOIN matches m ON v.venueid = m.venueid
WHERE m.matchstatus = 'completed'
GROUP BY v.neighborhood;
GO

CREATE VIEW vw_UserWinLoss AS
SELECT
    userid,
    SUM(CASE WHEN result = 'win'  THEN 1 ELSE 0 END) AS wins,
    SUM(CASE WHEN result = 'loss' THEN 1 ELSE 0 END) AS losses,
    SUM(CASE WHEN result = 'tie'  THEN 1 ELSE 0 END) AS ties,
    COUNT(*) AS totalmatches
FROM scorecard
GROUP BY userid;
GO

CREATE VIEW vw_MatchRoster AS
SELECT
    m.matchid,
    m.hostuserid,
    uh.fullname       AS hostname,
    s.sportname,
    v.venuename,
    m.starttime,
    m.maxplayers,
    m.currentplayers,
    m.assignmentmode,
    m.matchstatus,
    mp.userid,
    u.fullname        AS playername,
    t.teamname,
    t.teamlabel,
    mp.status         AS participantstatus,
    mp.joinedat
FROM matches m
JOIN users  uh ON m.hostuserid = uh.userid
JOIN sports s  ON m.sportid    = s.sportid
JOIN venues v  ON m.venueid    = v.venueid
LEFT JOIN matchparticipants mp ON m.matchid  = mp.matchid
LEFT JOIN users u              ON mp.userid  = u.userid
LEFT JOIN teams t              ON mp.teamid  = t.teamid;
GO

CREATE TRIGGER trg_JoinMatch
ON matchparticipants
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @userId         INT;
    DECLARE @matchId        INT;
    DECLARE @dob            DATE;
    DECLARE @starttime      DATETIME;
    DECLARE @endtime        DATETIME;
    DECLARE @agecategory    NVARCHAR(10);
    DECLARE @maxplayers     INT;
    DECLARE @currentplayers INT;
    DECLARE @age            INT;
    DECLARE @assignStatus   NVARCHAR(20);

    SELECT @userId  = userid,
           @matchId = matchid
    FROM inserted;

    SELECT @dob = dateofbirth
    FROM users WHERE userid = @userId;

    SELECT
        @starttime      = starttime,
        @endtime        = endtime,
        @agecategory    = agecategory,
        @maxplayers     = maxplayers,
        @currentplayers = currentplayers
    FROM matches WHERE matchid = @matchId;

    SET @age = DATEDIFF(YEAR, @dob, GETDATE())
        - CASE WHEN MONTH(@dob)*100+DAY(@dob) > MONTH(GETDATE())*100+DAY(GETDATE()) THEN 1 ELSE 0 END;

    IF @agecategory = 'u16' AND @age > 16
    BEGIN
        RAISERROR('Age restriction: must be 16 or under.', 16, 1);
        RETURN;
    END

    IF @agecategory = 'u19' AND @age > 19
    BEGIN
        RAISERROR('Age restriction: must be 19 or under.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1 FROM matchparticipants mp
        JOIN matches m ON mp.matchid = m.matchid
        WHERE mp.userid   = @userId
          AND mp.status   = 'confirmed'
          AND mp.matchid <> @matchId
          AND (
              (@starttime >= m.starttime AND @starttime < m.endtime)
           OR (@endtime   >  m.starttime AND @endtime  <= m.endtime)
          )
    )
    BEGIN
        RAISERROR('Conflict: already confirmed for another match at this time.', 16, 1);
        RETURN;
    END

    SET @assignStatus = CASE WHEN @currentplayers >= @maxplayers THEN 'waitlist' ELSE 'confirmed' END;

    INSERT INTO matchparticipants (matchid, userid, status)
    VALUES (@matchId, @userId, @assignStatus);

    IF @assignStatus = 'confirmed'
    BEGIN
        UPDATE matches
        SET currentplayers = currentplayers + 1
        WHERE matchid = @matchId;

        IF @currentplayers + 1 >= @maxplayers
            UPDATE matches SET matchstatus = 'full' WHERE matchid = @matchId;
    END
END;
GO

CREATE TRIGGER trg_LeaveMatch
ON matchparticipants
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @userId       INT;
    DECLARE @matchId      INT;
    DECLARE @wasConfirmed NVARCHAR(20);
    DECLARE @promotedUser INT;

    SELECT @userId       = userid,
           @matchId      = matchid,
           @wasConfirmed = status
    FROM deleted;

    IF @wasConfirmed = 'confirmed'
    BEGIN
        SELECT TOP 1 @promotedUser = userid
        FROM matchparticipants
        WHERE matchid = @matchId AND status = 'waitlist'
        ORDER BY joinedat ASC;

        IF @promotedUser IS NOT NULL
        BEGIN
            UPDATE matchparticipants
            SET status = 'confirmed'
            WHERE matchid = @matchId AND userid = @promotedUser;

            INSERT INTO notifications (userid, message, notificationtype, relatedmatchid)
            VALUES (@promotedUser, 'You have been promoted from the waitlist!', 'match_update', @matchId);
        END
        ELSE
        BEGIN
            UPDATE matches
            SET currentplayers = currentplayers - 1,
                matchstatus = CASE WHEN matchstatus = 'full' THEN 'open' ELSE matchstatus END
            WHERE matchid = @matchId;
        END
    END
END;
GO

CREATE TRIGGER trg_TeamAssignNotify
ON matchparticipants
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF UPDATE(teamassignment)
    BEGIN
        DECLARE @userId       INT;
        DECLARE @matchId      INT;
        DECLARE @teamLabel    NVARCHAR(1);
        DECLARE @oldTeamLabel NVARCHAR(1);

        SELECT
            @userId       = i.userid,
            @matchId      = i.matchid,
            @teamLabel    = i.teamassignment,
            @oldTeamLabel = d.teamassignment
        FROM inserted i
        JOIN deleted d ON i.participationid = d.participationid;

        IF @teamLabel IS NOT NULL AND (@oldTeamLabel IS NULL OR @oldTeamLabel <> @teamLabel)
        BEGIN
            INSERT INTO notifications (userid, message, notificationtype, relatedmatchid)
            VALUES (
                @userId,
                CONCAT('You have been assigned to Team ', UPPER(@teamLabel), '.'),
                'team_assigned',
                @matchId
            );
        END
    END
END;
GO

CREATE PROCEDURE sp_RecordResult
    @matchId         INT,
    @winnerteamlabel NVARCHAR(1)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM teams WHERE matchid = @matchId)
    BEGIN
        RAISERROR('No teams found for this match.', 16, 1);
        RETURN;
    END

    DECLARE @userId     INT;
    DECLARE @teamId     INT;
    DECLARE @teamAssign NVARCHAR(1);
    DECLARE @result     NVARCHAR(10);

    DECLARE cur CURSOR FOR
        SELECT userid, teamid, teamassignment
        FROM matchparticipants
        WHERE matchid = @matchId AND status = 'confirmed';

    OPEN cur;
    FETCH NEXT FROM cur INTO @userId, @teamId, @teamAssign;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @winnerteamlabel = 'tie'
            SET @result = 'tie';
        ELSE IF @teamAssign = @winnerteamlabel
            SET @result = 'win';
        ELSE
            SET @result = 'loss';

        INSERT INTO scorecard (matchid, teamid, userid, result)
        VALUES (@matchId, @teamId, @userId, @result);

        INSERT INTO notifications (userid, message, notificationtype, relatedmatchid)
        VALUES (
            @userId,
            CONCAT('Match result recorded: ', @result, '.'),
            'result_posted',
            @matchId
        );

        FETCH NEXT FROM cur INTO @userId, @teamId, @teamAssign;
    END

    CLOSE cur;
    DEALLOCATE cur;

    UPDATE matches SET matchstatus = 'completed' WHERE matchid = @matchId;
END;
GO

CREATE PROCEDURE sp_GenerateTeams
    @matchId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @mode NVARCHAR(20);
    SELECT @mode = assignmentmode FROM matches WHERE matchid = @matchId;

    IF @mode <> 'random'
    BEGIN
        RAISERROR('This match uses self-assignment. Use /self-assign instead.', 16, 1);
        RETURN;
    END

    DECLARE @teamAId INT;
    DECLARE @teamBId INT;

    IF NOT EXISTS (SELECT 1 FROM teams WHERE matchid = @matchId)
    BEGIN
        INSERT INTO teams (matchid, teamname, teamlabel) VALUES (@matchId, 'Team A', 'a');
        INSERT INTO teams (matchid, teamname, teamlabel) VALUES (@matchId, 'Team B', 'b');
    END

    SELECT @teamAId = teamid FROM teams WHERE matchid = @matchId AND teamlabel = 'a';
    SELECT @teamBId = teamid FROM teams WHERE matchid = @matchId AND teamlabel = 'b';

    DECLARE @shuffled TABLE (rownum INT IDENTITY(1,1), userid INT);

    INSERT INTO @shuffled (userid)
    SELECT userid
    FROM matchparticipants
    WHERE matchid = @matchId AND status = 'confirmed'
    ORDER BY NEWID();

    DECLARE @i     INT = 1;
    DECLARE @total INT;
    DECLARE @uid   INT;
    DECLARE @tid   INT;
    DECLARE @tlabel NVARCHAR(1);

    SELECT @total = COUNT(*) FROM @shuffled;

    WHILE @i <= @total
    BEGIN
        SELECT @uid = userid FROM @shuffled WHERE rownum = @i;

        IF @i % 2 = 1
        BEGIN
            SET @tid    = @teamAId;
            SET @tlabel = 'a';
        END
        ELSE
        BEGIN
            SET @tid    = @teamBId;
            SET @tlabel = 'b';
        END

        UPDATE matchparticipants
        SET teamid = @tid, teamassignment = @tlabel
        WHERE matchid = @matchId AND userid = @uid;

        SET @i = @i + 1;
    END

    UPDATE matches SET matchstatus = 'teamsgenerated' WHERE matchid = @matchId;
END;
GO

INSERT INTO sports (sportname, minplayersrequired) VALUES
('Cricket',    11),
('Football',   10),
('Basketball',  5),
('Badminton',   2);

INSERT INTO venues (venuename, venuetype, neighborhood, locationaddress, latitude, longitude) VALUES
('Model Town Park',     'park',    'Model Town', 'Circular Rd, Model Town', 31.4900, 74.3200),
('Street 5 Ground',     'street',  'Johar Town', 'Block G, Johar Town',     31.4690, 74.2710),
('DHA Phase 6 Complex', 'complex', 'DHA',        'Main Blvd, Phase 6',      31.4780, 74.4010),
('Gulberg Sports Area', 'park',    'Gulberg',    'Hali Road',               31.5120, 74.3370);

INSERT INTO users (fullname, email, dateofbirth, residentstatus, latitude, longitude, locationaddress) VALUES
('Ahad Hassan',      'ahad@test.com',    '2004-05-15', 'verified',   31.4901, 74.3201, 'Model Town, Lahore'),
('M. Yahya Ahmad',   'yahya@test.com',   '2003-08-22', 'verified',   31.4700, 74.2720, 'Johar Town, Lahore'),
('Muhammad Khubaib', 'khubaib@test.com', '2004-11-10', 'unverified', 31.4780, 74.4010, 'DHA, Lahore'),
('Zaid Ahmed',       'zaid@test.com',    '2010-01-01', 'unverified', 31.4690, 74.2700, 'Johar Town, Lahore'),
('Ali Raza',         'ali@test.com',     '2007-01-01', 'verified',   31.5120, 74.3380, 'Gulberg, Lahore'),
('Sara Khan',        'sara@test.com',    '1995-12-12', 'verified',   31.5000, 74.3300, 'Gulberg, Lahore'),
('Omar Malik',       'omar@test.com',    '2000-05-05', 'unverified', 31.4850, 74.3150, 'Model Town, Lahore');

INSERT INTO interests (userid, sportid, skilllevel) VALUES
(1, 1, 'competitive'),
(1, 2, 'casual'),
(2, 1, 'intermediate'),
(3, 2, 'casual'),
(4, 2, 'casual'),
(5, 1, 'competitive'),
(6, 3, 'intermediate'),
(7, 2, 'casual');

INSERT INTO matches (hostuserid, sportid, venueid, starttime, endtime, agecategory, maxplayers, currentplayers, matchstatus, assignmentmode) VALUES
(1, 1, 1,
    DATEADD(day,1,GETDATE()), DATEADD(hour,2,DATEADD(day,1,GETDATE())),
    '19+', 12, 4, 'open', 'random'),
(3, 2, 2,
    '2026-02-15 17:00:00', '2026-02-15 19:00:00',
    '19+', 10, 10, 'completed', 'self'),
(4, 2, 2,
    DATEADD(day,2,GETDATE()), DATEADD(hour,2,DATEADD(day,2,GETDATE())),
    'u16', 6, 2, 'open', 'random'),
(1, 1, 3,
    '2026-02-10 18:00:00', '2026-02-10 20:00:00',
    '19+', 11, 11, 'completed', 'self');

INSERT INTO teams (matchid, teamname, teamlabel) VALUES
(1, 'Team A', 'a'),
(1, 'Team B', 'b'),
(4, 'Team A', 'a'),
(4, 'Team B', 'b');

ALTER TABLE matchparticipants DISABLE TRIGGER trg_JoinMatch;
INSERT INTO matchparticipants (matchid, userid, teamid, status, teamassignment) VALUES
(1, 1, 1, 'confirmed', 'a'),
(1, 2, 2, 'confirmed', 'b'),
(1, 6, 1, 'confirmed', 'a'),
(1, 7, 2, 'confirmed', 'b'),
(2, 3, NULL, 'confirmed', NULL),
(3, 4, NULL, 'confirmed', NULL),
(4, 1, 3, 'confirmed', 'a');
ALTER TABLE matchparticipants ENABLE TRIGGER trg_JoinMatch;

INSERT INTO scorecard (matchid, teamid, userid, result, scorevalue) VALUES
(2, NULL, 3, 'tie',  5),
(4, 3,    1, 'win',  3),
(4, 4,    5, 'loss', 1);

INSERT INTO equipment (matchid, userid, itemname) VALUES
(1, 1, 'Cricket Bat'),
(1, 2, 'Stumps');

INSERT INTO notifications (userid, message, notificationtype, relatedmatchid) VALUES
(1, 'Your match in Model Town is tomorrow!', 'match_update',  1),
(2, 'You have been assigned to Team B.',     'team_assigned', 1),
(3, 'Match result recorded - it was a tie!', 'result_posted', 2);
GO
