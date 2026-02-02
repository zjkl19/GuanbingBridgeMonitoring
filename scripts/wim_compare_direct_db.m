function diffs = wim_compare_direct_db()
% wim_compare_direct_db  Compare direct vs database WIM outputs using sample data.
% Returns a struct with per-report comparison results.

    proj_root = fileparts(fileparts(mfilename('fullpath')));
    addpath(proj_root, fullfile(proj_root,'analysis'), fullfile(proj_root,'config'));

    cfg = load_config(fullfile(proj_root,'config','hongtang_config.json'));
    sample_dir = fullfile(proj_root, 'data', '_samples', 'wim', 'zhichen', '202512');

    base_cfg = cfg;
    base_cfg.wim.vendor = 'zhichen';
    base_cfg.wim.bridge = 'hongtang';
    base_cfg.wim.input.zhichen.dir = sample_dir;
    base_cfg.wim.input.zhichen.bcp = 'HS_Data_202512_sample_1000.bcp';
    base_cfg.wim.input.zhichen.fmt = 'HS_Data_202512_sample_1000.fmt';

    compare_root = fullfile(proj_root, 'tests', 'tmp', 'wim_compare');
    direct_root = fullfile(compare_root, 'direct');
    db_root = fullfile(compare_root, 'database');
    if ~exist(direct_root, 'dir'), mkdir(direct_root); end
    if ~exist(db_root, 'dir'), mkdir(db_root); end

    cfg_direct = base_cfg;
    cfg_direct.wim.pipeline = 'direct';
    cfg_direct.wim.output_root = direct_root;

    cfg_db = base_cfg;
    cfg_db.wim.pipeline = 'database';
    cfg_db.wim.output_root = db_root;
    if isfield(cfg_db, 'wim_db')
        cfg_db.wim_db.server = '.';
        cfg_db.wim_db.table_prefix = 'HS_Data_Sample_';
        cfg_db.wim_db.raw_table_prefix = 'WIM_Raw_Sample_';
        cfg_db.wim_db.import_mode = 'truncate'; % ensure clean comparison
    end

    analyze_wim_reports(proj_root, '2025-12-01', '2025-12-31', cfg_direct);
    analyze_wim_reports(proj_root, '2025-12-01', '2025-12-31', cfg_db);

    out_direct = fullfile(cfg_direct.wim.output_root, cfg_direct.wim.bridge, '202512');
    out_db = fullfile(cfg_db.wim.output_root, cfg_db.wim.bridge, '202512');

    report_names = {
        'DailyTraffic',
        'LaneSpeedWeight_Lane',
        'LaneSpeedWeight_Speed',
        'LaneSpeedWeight_Gross',
        'Hourly_Count',
        'Hourly_AvgSpeed',
        'Hourly_Over',
        'CustomThresholds_Overall',
        'CustomThresholds_PerLane',
        'TopN',
        'TopN_MaxAxle',
        'Overload_Summary'
        };

    diffs = struct();
    for i = 1:numel(report_names)
        name = report_names{i};
        f1 = fullfile(out_direct, sprintf('202512_%s.csv', name));
        f2 = fullfile(out_db, sprintf('202512_%s.csv', name));
        if ~isfile(f1) || ~isfile(f2)
            diffs.(name) = struct('ok', false, 'reason', 'missing csv');
            continue;
        end
        T1 = readtable(f1, 'TextType','string', 'Encoding','UTF-8');
        T2 = readtable(f2, 'TextType','string', 'Encoding','UTF-8');
        [ok, detail] = compare_tables(T1, T2, 1e-6);
        detail.ok = ok;
        diffs.(name) = detail;
        if ~ok
            fprintf('[Mismatch] %s: %s\n', name, detail.reason);
            if isfield(detail, 'col')
                fprintf('  column: %s\n', detail.col);
            end
            if isfield(detail, 'idx')
                fprintf('  row: %d\n', detail.idx);
            end
            if isfield(detail, 'a') && isfield(detail, 'b')
                fprintf('  direct=%s, db=%s\n', detail.a, detail.b);
            end
        end
    end

    names = fieldnames(diffs);
    bad = {};
    for i = 1:numel(names)
        if ~diffs.(names{i}).ok
            bad{end+1} = names{i}; %#ok<AGROW>
        end
    end
    if isempty(bad)
        fprintf('Direct vs DB: all reports match.\n');
    else
        fprintf('Direct vs DB: mismatches in: %s\n', strjoin(bad, ', '));
        fprintf('Direct output: %s\n', out_direct);
        fprintf('DB output: %s\n', out_db);
    end
end

function [ok, detail] = compare_tables(T1, T2, tol)
    detail = struct();
    ok = true;
    if width(T1) ~= width(T2)
        ok = false;
        detail.reason = 'column count mismatch';
        return;
    end

    % align columns by name
    v1 = string(T1.Properties.VariableNames);
    v2 = string(T2.Properties.VariableNames);
    if ~isequal(v1, v2)
        [common, ia, ib] = intersect(v1, v2, 'stable');
        T1 = T1(:, ia);
        T2 = T2(:, ib);
        v1 = common;
        v2 = common;
    end

    T1n = normalize_table(T1);
    T2n = normalize_table(T2);

    % sort by all columns for stable comparison
    try
        T1n = sortrows(T1n, 1:width(T1n));
        T2n = sortrows(T2n, 1:width(T2n));
    catch
        % if sort fails, skip sorting
    end

    if height(T1n) ~= height(T2n)
        ok = false;
        detail.reason = 'row count mismatch';
        detail.h1 = height(T1n);
        detail.h2 = height(T2n);
        return;
    end

    % compare column-wise
    for c = 1:width(T1n)
        a = T1n{:,c};
        b = T2n{:,c};
        if isnumeric(a) && isnumeric(b)
            d = abs(a - b);
            mask = (d > tol) | (isnan(a) ~= isnan(b));
            if any(mask)
                ok = false;
                detail.reason = 'numeric mismatch';
                detail.col = v1(c);
                detail.max_diff = max(d(~isnan(d)));
                idx = find(mask, 1, 'first');
                detail.idx = idx;
                detail.a = num2str(a(idx));
                detail.b = num2str(b(idx));
                return;
            end
        else
            sa = string(a);
            sb = string(b);
            if any(sa ~= sb)
                ok = false;
                detail.reason = 'string mismatch';
                detail.col = v1(c);
                idx = find(sa ~= sb, 1, 'first');
                detail.idx = idx;
                detail.a = char(sa(idx));
                detail.b = char(sb(idx));
                return;
            end
        end
    end
end

function Tn = normalize_table(T)
    Tn = T;
    for c = 1:width(T)
        col = T{:,c};
        if isdatetime(col)
            s = string(col);
            Tn{:,c} = s;
        elseif iscell(col)
            Tn{:,c} = string(col);
        elseif isstring(col)
            Tn{:,c} = col;
        elseif iscategorical(col)
            Tn{:,c} = string(col);
        else
            Tn{:,c} = double(col);
        end
    end
end
