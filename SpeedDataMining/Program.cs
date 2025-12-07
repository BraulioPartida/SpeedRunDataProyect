using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Linq;
using System.Globalization;

namespace SpeedrunDataPuller
{
    class Program
    {
        private static readonly HttpClient client = new HttpClient();
        private const string BASE_URL = "https://www.speedrun.com/api/v1";
        private static List<RunRecord> allRuns = new List<RunRecord>();
        private static Dictionary<string, string> playerNameCache = new Dictionary<string, string>();

        static async Task Main(string[] args)
        {
            var gameIds = new List<string>
            {
                "j1npme6p", // Minecraft: Java Edition
                "3698my8d", // Roblox: DOORS
                "76rkv4d8", // Celeste
                "y65r7g81", // Portal
                "9d3rrxyd", // Hollow Knight
                "76r55vd8", // Super Mario Odyssey
                "pd0wq31e", // Super Mario 64
                "w6jmm26j", // Cuphead
                "n4d7jzd7", // Skyrim
                "nd28z0ed",  // Elden Ring
                "369p3p81",  // ULTRAKILL
                "4pd0n31e",  // Portal
                "pd0wx9w1",  // Getting Over It With Bennett Foddy
                "76rqmld8",  // Hollow Knight
                "76rqjqd8",  // The Legend of Zelda: Breath of the Wild
                "3698my8d",  // Roblox: DOORS
                "76r43l18",  // Outlast
                "w6j7vpx6",  // Poppy Playtime: Chapter 1
                "m1zjmz60",  // Resident Evil 2
                "o1y9okr6",  // Hades
                "3dxy5vv6",  // Hades2
                "o6gnpox1" // pizza tower
            };

            Console.WriteLine("Starting speedrun data collection for Stata analysis...\n");
            Console.WriteLine("This may take several minutes due to API rate limiting.\n");

            int gameCount = 0;
            foreach (var gameId in gameIds)
            {
                gameCount++;
                Console.WriteLine($"[{gameCount}/{gameIds.Count}] Processing game ID: {gameId}");

                try
                {
                    await ProcessGameForStata(gameId);
                    await Task.Delay(1500); // Conservative rate limiting
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"  ERROR: {ex.Message}");
                }

                Console.WriteLine($"  Total runs collected so far: {allRuns.Count}");
                Console.WriteLine($"  Unique players cached: {playerNameCache.Count}\n");
            }

            // Export to CSV
            string filename = $"speedrun_data_names.csv";
            ExportToCsv(filename);

            Console.WriteLine($"\n=== COMPLETE ===");
            Console.WriteLine($"Total runs collected: {allRuns.Count}");
            Console.WriteLine($"Exported to: {filename}");
            Console.WriteLine("\nPress any key to exit.");
            Console.ReadKey();
        }

        static async Task<string> GetPlayerName(string playerId)
        {
            // Check cache first
            if (playerNameCache.ContainsKey(playerId))
            {
                return playerNameCache[playerId];
            }

            try
            {
                // If it's a guest name (doesn't look like an ID), return as-is
                if (!playerId.Contains("x") && !playerId.Contains("j") && playerId.Length < 8)
                {
                    playerNameCache[playerId] = playerId;
                    return playerId;
                }

                var response = await client.GetStringAsync($"{BASE_URL}/users/{playerId}");
                var doc = JsonDocument.Parse(response);
                var data = doc.RootElement.GetProperty("data");

                string playerName = playerId; // Default fallback

                if (data.TryGetProperty("names", out var names))
                {
                    if (names.TryGetProperty("international", out var intlName))
                    {
                        playerName = intlName.GetString();
                    }
                }

                // Cache the result
                playerNameCache[playerId] = playerName;
                
                // Small delay to avoid rate limiting
                await Task.Delay(100);
                
                return playerName;
            }
            catch
            {
                // If lookup fails, cache the ID as the name
                playerNameCache[playerId] = playerId;
                return playerId;
            }
        }

        static async Task ProcessGameForStata(string gameId)
        {
            try
            {
                // Get game name and metadata
                var gameInfo = await GetGameInfo(gameId);
                Console.WriteLine($"  Game: {gameInfo.name}");

                // Get all categories
                var categories = await GetCategories(gameId);
                Console.WriteLine($"  Categories found: {categories.Count}");

                // Create category lookup
                var categoryLookup = categories.ToDictionary(c => c.id, c => c.name);

                // Get world records and leaderboards for each category
                var worldRecords = new Dictionary<string, string>();
                var leaderboardData = new Dictionary<string, List<LeaderboardEntry>>();

                foreach (var category in categories)
                {
                    try
                    {
                        var leaderboard = await GetLeaderboard(gameId, category.id);
                        leaderboardData[category.id] = leaderboard;

                        if (leaderboard.Count > 0)
                        {
                            worldRecords[category.id] = leaderboard[0].run_id;
                        }
                        await Task.Delay(500);
                    }
                    catch { }
                }

                // Get runs for the game
                var runs = await GetAllRunsForGame(gameId);
                Console.WriteLine($"  Runs retrieved: {runs.Count}");

                // Enrich runs with category names
                foreach (var run in runs)
                {
                    if (categoryLookup.ContainsKey(run.category_id))
                    {
                        run.category_name = categoryLookup[run.category_id];
                    }
                }

                // Fetch player names (with progress indicator)
                Console.WriteLine($"  Fetching player names...");
                var uniquePlayerIds = runs.Select(r => r.player_id).Distinct().ToList();
                int playerCount = 0;
                foreach (var playerId in uniquePlayerIds)
                {
                    if (!playerNameCache.ContainsKey(playerId))
                    {
                        await GetPlayerName(playerId);
                        playerCount++;
                        if (playerCount % 10 == 0)
                        {
                            Console.WriteLine($"    Resolved {playerCount}/{uniquePlayerIds.Count} player names...");
                        }
                    }
                }

                // Update runs with resolved player names
                foreach (var run in runs)
                {
                    if (playerNameCache.ContainsKey(run.player_id))
                    {
                        run.player_name = playerNameCache[run.player_id];
                    }
                }

                // Calculate player statistics
                var playerStats = CalculatePlayerStatistics(runs);

                // Process runs into records
                foreach (var run in runs)
                {
                    bool isWr = worldRecords.ContainsKey(run.category_id) &&
                                worldRecords[run.category_id] == run.id;

                    // Get rank in leaderboard
                    int rank = 0;
                    int total_in_category = 0;
                    if (leaderboardData.ContainsKey(run.category_id))
                    {
                        var lb = leaderboardData[run.category_id];
                        total_in_category = lb.Count;
                        for (int i = 0; i < lb.Count; i++)
                        {
                            if (lb[i].run_id == run.id)
                            {
                                rank = i + 1;
                                break;
                            }
                        }
                    }

                    // Get player statistics
                    var pStats = playerStats.ContainsKey(run.player_id)
                        ? playerStats[run.player_id]
                        : new PlayerStats();

                    allRuns.Add(new RunRecord
                    {
                        run_id = run.id,
                        game_id = gameId,
                        game_name = gameInfo.name,
                        game_release_year = gameInfo.release_year,
                        category_id = run.category_id,
                        category_name = run.category_name,
                        time_seconds = run.times.primary_t,
                        date_submitted = run.submitted,
                        player_id = run.player_id,
                        player_name = run.player_name,
                        is_wr = isWr ? 1 : 0,
                        rank = rank,
                        total_runners_in_category = total_in_category,
                        video_link = run.video_link,
                        has_video = string.IsNullOrEmpty(run.video_link) ? 0 : 1,
                        platform = run.platform,
                        emulated = run.emulated,
                        player_total_runs = pStats.total_runs,
                        player_total_games = pStats.unique_games,
                        player_total_categories = pStats.unique_categories,
                        player_avg_time_improvement = pStats.avg_time_improvement,
                        player_days_active = pStats.days_active,
                        run_comment_length = run.comment?.Length ?? 0,
                        has_comment = string.IsNullOrEmpty(run.comment) ? 0 : 1
                    });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  Error processing game: {ex.Message}");
            }
        }

        static async Task<GameInfo> GetGameInfo(string gameId)
        {
            try
            {
                var response = await client.GetStringAsync($"{BASE_URL}/games/{gameId}");
                var doc = JsonDocument.Parse(response);
                var data = doc.RootElement.GetProperty("data");

                int releaseYear = 0;
                if (data.TryGetProperty("released", out var released) &&
                    released.ValueKind != JsonValueKind.Null)
                {
                    releaseYear = released.GetInt32();
                }

                return new GameInfo
                {
                    name = data.GetProperty("names").GetProperty("international").GetString(),
                    release_year = releaseYear
                };
            }
            catch
            {
                return new GameInfo { name = "Unknown", release_year = 0 };
            }
        }

        static async Task<List<Category>> GetCategories(string gameId)
        {
            var response = await client.GetStringAsync($"{BASE_URL}/games/{gameId}/categories");
            var doc = JsonDocument.Parse(response);
            var data = doc.RootElement.GetProperty("data");

            var categories = new List<Category>();
            foreach (var cat in data.EnumerateArray())
            {
                categories.Add(new Category
                {
                    id = cat.GetProperty("id").GetString(),
                    name = cat.GetProperty("name").GetString()
                });
            }
            return categories;
        }

        static async Task<List<LeaderboardEntry>> GetLeaderboard(string gameId, string categoryId)
        {
            try
            {
                var response = await client.GetStringAsync(
                    $"{BASE_URL}/leaderboards/{gameId}/category/{categoryId}?top=100");
                var doc = JsonDocument.Parse(response);
                var runs = doc.RootElement.GetProperty("data").GetProperty("runs");

                var leaderboard = new List<LeaderboardEntry>();
                foreach (var runEntry in runs.EnumerateArray())
                {
                    var run = runEntry.GetProperty("run");
                    leaderboard.Add(new LeaderboardEntry
                    {
                        run_id = run.GetProperty("id").GetString(),
                        time = run.GetProperty("times").GetProperty("primary_t").GetDouble()
                    });
                }
                return leaderboard;
            }
            catch
            {
                return new List<LeaderboardEntry>();
            }
        }

        static async Task<List<RunData>> GetAllRunsForGame(string gameId)
        {
            var allRunsData = new List<RunData>();
            int offset = 0;
            int maxRuns = 100000;
            bool hasMore = true;

            while (hasMore && allRunsData.Count < maxRuns)
            {
                try
                {
                    var response = await client.GetStringAsync(
                        $"{BASE_URL}/runs?game={gameId}&max=200&offset={offset}&orderby=submitted&direction=desc");
                    var doc = JsonDocument.Parse(response);
                    var data = doc.RootElement.GetProperty("data");
                    var pagination = doc.RootElement.GetProperty("pagination");

                    int count = 0;
                    foreach (var runData in data.EnumerateArray())
                    {
                        count++;

                        // Extract player information
                        string playerId = "unknown";
                        string playerName = "Unknown";
                        var players = runData.GetProperty("players");
                        foreach (var player in players.EnumerateArray())
                        {
                            if (player.TryGetProperty("id", out var id))
                            {
                                playerId = id.GetString();
                                playerName = playerId; // Will be resolved later
                                break;
                            }
                            else if (player.TryGetProperty("name", out var name))
                            {
                                playerId = name.GetString();
                                playerName = name.GetString(); // Guest name
                                break;
                            }
                        }

                        // Extract category ID
                        string categoryId = "";
                        try
                        {
                            var catProp = runData.GetProperty("category");
                            if (catProp.ValueKind == JsonValueKind.String)
                            {
                                categoryId = catProp.GetString();
                            }
                            else if (catProp.ValueKind == JsonValueKind.Object)
                            {
                                categoryId = catProp.GetProperty("data").GetProperty("id").GetString();
                            }
                        }
                        catch
                        {
                            categoryId = "unknown";
                        }

                        // Category name will be enriched later
                        string categoryName = "Unknown";

                        // Extract platform
                        string platform = "Unknown";
                        if (runData.TryGetProperty("system", out var system))
                        {
                            if (system.TryGetProperty("platform", out var platId) &&
                                platId.ValueKind == JsonValueKind.String)
                            {
                                platform = platId.GetString();
                            }
                        }

                        // Extract emulated status
                        int emulated = 0;
                        if (runData.TryGetProperty("system", out var sys))
                        {
                            if (sys.TryGetProperty("emulated", out var emu))
                            {
                                emulated = emu.GetBoolean() ? 1 : 0;
                            }
                        }

                        // Extract video link
                        string videoLink = null;
                        if (runData.TryGetProperty("videos", out var videos) &&
                            videos.ValueKind != JsonValueKind.Null)
                        {
                            if (videos.TryGetProperty("links", out var links))
                            {
                                foreach (var link in links.EnumerateArray())
                                {
                                    if (link.TryGetProperty("uri", out var uri))
                                    {
                                        videoLink = uri.GetString();
                                        break;
                                    }
                                }
                            }
                        }

                        // Extract comment
                        string comment = null;
                        if (runData.TryGetProperty("comment", out var com) &&
                            com.ValueKind != JsonValueKind.Null)
                        {
                            comment = com.GetString();
                        }

                        // Extract submitted date
                        string submitted = null;
                        if (runData.TryGetProperty("submitted", out var subDate) &&
                            subDate.ValueKind != JsonValueKind.Null)
                        {
                            submitted = subDate.GetString();
                        }

                        allRunsData.Add(new RunData
                        {
                            id = runData.GetProperty("id").GetString(),
                            category_id = categoryId,
                            category_name = categoryName,
                            player_id = playerId,
                            player_name = playerName,
                            submitted = submitted,
                            platform = platform,
                            emulated = emulated,
                            video_link = videoLink,
                            comment = comment,
                            times = new RunTimes
                            {
                                primary_t = runData.GetProperty("times").GetProperty("primary_t").GetDouble()
                            }
                        });
                    }

                    hasMore = count == 200 &&
                             pagination.TryGetProperty("size", out var size) &&
                             size.GetInt32() == 200;
                    offset += 200;

                    await Task.Delay(500);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"    Error fetching runs at offset {offset}: {ex.Message}");
                    hasMore = false;
                }
            }

            return allRunsData;
        }

        static Dictionary<string, PlayerStats> CalculatePlayerStatistics(List<RunData> runs)
        {
            var playerStats = new Dictionary<string, PlayerStats>();

            // Group runs by player
            var runsByPlayer = runs.GroupBy(r => r.player_id);

            foreach (var playerRuns in runsByPlayer)
            {
                var orderedRuns = playerRuns.OrderBy(r => r.submitted).ToList();

                var stats = new PlayerStats
                {
                    total_runs = orderedRuns.Count,
                    unique_games = orderedRuns.Select(r => r.id).Distinct().Count(),
                    unique_categories = orderedRuns.Select(r => r.category_id).Distinct().Count()
                };

                // Calculate average time improvement (per category)
                var categoryGroups = orderedRuns.GroupBy(r => r.category_id);
                var improvements = new List<double>();

                foreach (var catGroup in categoryGroups)
                {
                    var catRuns = catGroup.OrderBy(r => r.submitted).ToList();
                    for (int i = 1; i < catRuns.Count; i++)
                    {
                        double improvement = catRuns[i - 1].times.primary_t - catRuns[i].times.primary_t;
                        if (improvement > 0) // Only count improvements, not regressions
                        {
                            improvements.Add(improvement);
                        }
                    }
                }

                stats.avg_time_improvement = improvements.Any() ? improvements.Average() : 0;

                // Calculate days active
                if (orderedRuns.Count > 1)
                {
                    try
                    {
                        var firstDate = DateTime.Parse(orderedRuns.First().submitted ?? DateTime.Now.ToString());
                        var lastDate = DateTime.Parse(orderedRuns.Last().submitted ?? DateTime.Now.ToString());
                        stats.days_active = (lastDate - firstDate).Days;
                    }
                    catch
                    {
                        stats.days_active = 0;
                    }
                }

                playerStats[playerRuns.Key] = stats;
            }

            return playerStats;
        }

        static void ExportToCsv(string filename)
        {
            using (var writer = new StreamWriter(filename, false, Encoding.UTF8))
            {
                // Write header with all new columns
                writer.WriteLine("run_id,game_id,game_name,game_release_year,category_id,category_name," +
                               "time_seconds,date_submitted,player_id,player_name,is_wr,rank," +
                               "total_runners_in_category,video_link,has_video,platform,emulated," +
                               "player_total_runs,player_total_games,player_total_categories," +
                               "player_avg_time_improvement,player_days_active," +
                               "run_comment_length,has_comment");

                // Write data
                foreach (var run in allRuns)
                {
                    writer.WriteLine($"{EscapeCsv(run.run_id)}," +
                                   $"{EscapeCsv(run.game_id)}," +
                                   $"{EscapeCsv(run.game_name)}," +
                                   $"{run.game_release_year}," +
                                   $"{EscapeCsv(run.category_id)}," +
                                   $"{EscapeCsv(run.category_name)}," +
                                   $"{run.time_seconds.ToString(CultureInfo.InvariantCulture)}," +
                                   $"{EscapeCsv(run.date_submitted ?? "")}," +
                                   $"{EscapeCsv(run.player_id)}," +
                                   $"{EscapeCsv(run.player_name)}," +
                                   $"{run.is_wr}," +
                                   $"{run.rank}," +
                                   $"{run.total_runners_in_category}," +
                                   $"{EscapeCsv(run.video_link ?? "")}," +
                                   $"{run.has_video}," +
                                   $"{EscapeCsv(run.platform)}," +
                                   $"{run.emulated}," +
                                   $"{run.player_total_runs}," +
                                   $"{run.player_total_games}," +
                                   $"{run.player_total_categories}," +
                                   $"{run.player_avg_time_improvement.ToString(CultureInfo.InvariantCulture)}," +
                                   $"{run.player_days_active}," +
                                   $"{run.run_comment_length}," +
                                   $"{run.has_comment}");
                }
            }
        }

        static string EscapeCsv(string value)
        {
            if (string.IsNullOrEmpty(value))
                return "";

            if (value.Contains(",") || value.Contains("\"") || value.Contains("\n"))
            {
                return "\"" + value.Replace("\"", "\"\"") + "\"";
            }
            return value;
        }
    }

    // Data models (same as before)
    class GameInfo
    {
        public string name { get; set; }
        public int release_year { get; set; }
    }

    class Category
    {
        public string id { get; set; }
        public string name { get; set; }
    }

    class LeaderboardEntry
    {
        public string run_id { get; set; }
        public double time { get; set; }
    }

    class RunData
    {
        public string id { get; set; }
        public string category_id { get; set; }
        public string category_name { get; set; }
        public string player_id { get; set; }
        public string player_name { get; set; }
        public string submitted { get; set; }
        public string platform { get; set; }
        public int emulated { get; set; }
        public string video_link { get; set; }
        public string comment { get; set; }
        public RunTimes times { get; set; }
    }

    class RunTimes
    {
        public double primary_t { get; set; }
    }

    class PlayerStats
    {
        public int total_runs { get; set; }
        public int unique_games { get; set; }
        public int unique_categories { get; set; }
        public double avg_time_improvement { get; set; }
        public int days_active { get; set; }
    }

    class RunRecord
    {
        public string run_id { get; set; }
        public string game_id { get; set; }
        public string game_name { get; set; }
        public int game_release_year { get; set; }
        public string category_id { get; set; }
        public string category_name { get; set; }
        public double time_seconds { get; set; }
        public string date_submitted { get; set; }
        public string player_id { get; set; }
        public string player_name { get; set; }
        public int is_wr { get; set; }
        public int rank { get; set; }
        public int total_runners_in_category { get; set; }
        public string video_link { get; set; }
        public int has_video { get; set; }
        public string platform { get; set; }
        public int emulated { get; set; }
        public int player_total_runs { get; set; }
        public int player_total_games { get; set; }
        public int player_total_categories { get; set; }
        public double player_avg_time_improvement { get; set; }
        public int player_days_active { get; set; }
        public int run_comment_length { get; set; }
        public int has_comment { get; set; }
    }
}