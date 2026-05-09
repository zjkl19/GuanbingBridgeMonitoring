function paths = build_data_index(root, startDate, endDate, configPathOrCfg, opts)
%BUILD_DATA_INDEX Build source-file index JSON and Excel summary.
%   paths = scripts.build_data_index(root, startDate, endDate, configPath)

    if nargin < 5 || isempty(opts), opts = struct(); end
    if nargin < 4 || isempty(configPathOrCfg)
        cfg = struct();
    elseif isstruct(configPathOrCfg)
        cfg = configPathOrCfg;
    else
        cfg = load_config(char(string(configPathOrCfg)));
    end

    opts.buildDataIndex = true;
    runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
    index = bms.data.DataIndex.build(root, startDate, endDate, cfg, opts);
    jsonPath = bms.data.DataIndex.write(root, index, runId);
    xlsxPath = bms.data.DataIndex.writeSummary(root, index, runId);

    paths = struct();
    paths.json = jsonPath;
    paths.summary_xlsx = xlsxPath;
    paths.summary = index.summary;

    fprintf('Data index JSON: %s\n', jsonPath);
    fprintf('Data index summary: %s\n', xlsxPath);
    fprintf('modules=%d, points=%d, found=%d, missing=%d, files=%d\n', ...
        index.summary.module_count, index.summary.point_count, ...
        index.summary.found_point_count, index.summary.missing_point_count, ...
        index.summary.file_count);
end
