/*
Generates tournament summary statistics 
for a specific competition and season.
*/
CREATE OR ALTER PROCEDURE sp_Tournament_Overview 
    @Competition_id INT, 
    @Season_id INT 
AS 
BEGIN
    /* --- Initial Validation --- */
    IF @Competition_id IS NULL OR @Season_id IS NULL
    BEGIN
        PRINT 'Error: Parameters cannot be NULL';
        RETURN;
    END

    BEGIN TRY 
        SET NOCOUNT ON;

        -- Variable declarations for metadata and execution timing
        DECLARE @Comp_Name VARCHAR(200), 
                @Total_Goals INT, 
                @Begin DATETIME2, 
                @End DATETIME2;

        SET @Begin = SYSDATETIME();

        PRINT 'Calculating match statistics...';
        PRINT 'Calculating event statistics...';

        -- Retrieve Competition and Season names for the header
        SELECT TOP 1
            @Comp_Name = c.competition_name + ' ' + s.season_name
        FROM Dim_Match m
        JOIN Dim_Season s ON s.season_id = m.season_id 
        JOIN Dim_Competition c ON c.competition_id = m.competition_id 
        WHERE m.competition_id = @Competition_id AND m.season_id = @Season_id;

        -- Calculate total goals scored in the tournament
        SELECT 
            @Total_Goals = SUM(away_score + home_score)
        FROM Dim_Match 
        WHERE competition_id = @Competition_id AND season_id = @Season_id;

        /* --- Aggregate Event Data using CTE --- */
        WITH cte_Basic_Statistics AS 
        (
            SELECT 
                COUNT(DISTINCT e.match_id) AS Total_Matches,
                
                -- Defensive and Scoreline metrics
                COUNT(DISTINCT CASE WHEN home_score = 0 OR away_score = 0 THEN e.match_id END) AS Clean_Sheets,
                COUNT(DISTINCT CASE WHEN ABS(home_score - away_score) = 1 THEN e.match_id END) AS Matches_Decided_By_1_Goal,
                COUNT(DISTINCT CASE WHEN ABS(home_score - away_score) >= 2 THEN e.match_id END) AS Matches_Decided_By_2Plus_Goals,
                
                -- Shot metrics (Event Type 16)
                COUNT(CASE WHEN event_type_id = 16 THEN 1 END) AS Total_Shots,
                COUNT(CASE WHEN event_type_id = 16 AND outcome IN ('Goal','Saved','Saved to Post') THEN 1 END) AS Shots_on_Target,
                COUNT(CASE WHEN event_type_id = 16 AND outcome = 'Post' THEN 1 END) AS Shots_on_Post,
                
                -- Passing metrics (Event Type 30)
                COUNT(CASE WHEN event_type_id = 30 THEN 1 END) AS Total_Passes,
                COUNT(CASE WHEN event_type_id = 30 AND outcome IS NULL THEN 1 END) AS Successful_Passes,
                
                -- Foul and Period metrics
                COUNT(CASE WHEN event_type_id = 22 THEN 1 END) AS Total_Fouls,
                COUNT(DISTINCT CASE WHEN period IN (3,4) THEN e.match_id END) AS Extra_Time_Matches,
                COUNT(DISTINCT CASE WHEN period = 5 THEN e.match_id END) AS Penalty_Shootouts
            FROM Fact_Events e 
            JOIN Dim_Match m ON e.match_id = m.match_id 
            WHERE m.competition_id = @Competition_id AND m.season_id = @Season_id
        )

        /* --- Final Result Set with Calculated Percentages --- */
        SELECT 
            @Comp_Name AS Competition,
            Total_Matches,
            @Total_Goals AS Total_Goals,
            TRY_CAST(@Total_Goals * 1.00 / NULLIF(Total_Matches, 0) AS DECIMAL(4,2)) AS Avg_Goals_Per_Match,
            Total_Shots,
            Shots_on_Target,
            Shots_on_Post,
            TRY_CAST(Shots_on_Target * 100.00 / NULLIF(Total_Shots, 0) AS DECIMAL(5,2)) AS Shot_Accuracy_Pct,
            Total_Passes,
            Successful_Passes,
            TRY_CAST(Successful_Passes * 100.00 / NULLIF(Total_Passes, 0) AS DECIMAL(5,2)) AS Pass_Accuracy_Pct,
            Total_Fouls,
            TRY_CAST(Total_Fouls * 1.00 / NULLIF(Total_Matches, 0) AS DECIMAL(5,2)) AS Fouls_Per_Match,
            Clean_Sheets,
            TRY_CAST(Clean_Sheets * 100.00 / NULLIF(Total_Matches, 0) AS DECIMAL(5,2)) AS Clean_Sheets_Pct,
            Matches_Decided_By_1_Goal,
            TRY_CAST(Matches_Decided_By_1_Goal * 100.00 / NULLIF(Total_Matches, 0) AS DECIMAL(5,2)) AS Matches_Decided_By_1_Goal_Pct,
            Matches_Decided_By_2Plus_Goals,
            TRY_CAST(Matches_Decided_By_2Plus_Goals * 100.00 / NULLIF(Total_Matches, 0) AS DECIMAL(5,2)) AS Matches_Decided_By_2Plus_Goals_Pct,
            Extra_Time_Matches,
            TRY_CAST(Extra_Time_Matches * 100.00 / NULLIF(Total_Matches, 0) AS DECIMAL(5,2)) AS Extra_Time_Pct,
            Penalty_Shootouts,
            TRY_CAST(Penalty_Shootouts * 100.00 / NULLIF(Total_Matches, 0) AS DECIMAL(5,2)) AS Penalty_Shootouts_Pct
        FROM cte_Basic_Statistics;

        -- Log execution completion time
        SET @End = SYSDATETIME();
        PRINT '======================================================';
        PRINT 'Execution Time: ' + CAST(DATEDIFF(MILLISECOND, @Begin, @End) AS VARCHAR) + ' ms';
        PRINT '======================================================';

    END TRY 
    BEGIN CATCH
        -- Error Handling Block
        PRINT '======================================================';
        PRINT 'ERROR: ' + ERROR_MESSAGE();
        PRINT 'Line: ' + CAST(ERROR_LINE() AS VARCHAR);
        PRINT 'Proc: ' + ERROR_PROCEDURE();
        PRINT '======================================================';
    END CATCH 
END;
