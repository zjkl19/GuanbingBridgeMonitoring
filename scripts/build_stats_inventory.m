function paths = build_stats_inventory(root, configPathOrCfg, opts)
%BUILD_STATS_INVENTORY Build stats-file inventory JSON and Excel summary.

    if nargin < 3 || isempty(opts), opts = struct(); end
    if nargin < 2 || isempty(configPathOrCfg)
        cfg = struct();
    elseif isstruct(configPathOrCfg)
        cfg = configPathOrCfg;
    else
        cfg = load_config(char(string(configPathOrCfg)));
    end

    opts.buildStatsInventory = true;
    runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
    inventory = bms.io.StatsInventory.build(root, opts, cfg);
    jsonPath = bms.io.StatsInventory.write(root, inventory, runId);
    xlsxPath = bms.io.StatsInventory.writeSummary(root, inventory, runId);

    paths = struct();
    paths.json = jsonPath;
    paths.summary_xlsx = xlsxPath;
    paths.summary = inventory.summary;

    fprintf('Stats inventory JSON: %s\n', jsonPath);
    fprintf('Stats inventory summary: %s\n', xlsxPath);
    fprintf('expected=%d, existing=%d, missing=%d, empty=%d, read_failed=%d\n', ...
        inventory.summary.stats_expected_count, inventory.summary.stats_existing_count, ...
        inventory.summary.stats_missing_count, inventory.summary.stats_empty_count, ...
        inventory.summary.stats_read_failed_count);
end
