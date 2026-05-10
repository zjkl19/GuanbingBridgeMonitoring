classdef WimConfigService
    %WIMCONFIGSERVICE Configuration and input resolution helpers for WIM reports.

    methods (Static)
        function [monthStarts, monthEnds] = splitMonthRanges(startDate, endDate)
            startDt = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
            endDt = datetime(endDate, 'InputFormat', 'yyyy-MM-dd');
            if endDt < startDt
                error('end_date must be on or after start_date.');
            end

            cursor = dateshift(startDt, 'start', 'month');
            lastMonth = dateshift(endDt, 'start', 'month');
            monthStarts = datetime.empty(0, 1);
            monthEnds = datetime.empty(0, 1);
            while cursor <= lastMonth
                segStart = max(cursor, startDt);
                segEnd = min(dateshift(cursor, 'end', 'month'), endDt);
                monthStarts(end+1, 1) = segStart; %#ok<AGROW>
                monthEnds(end+1, 1) = segEnd; %#ok<AGROW>
                cursor = cursor + calmonths(1);
            end
        end

        function wim = getWimConfig(cfg)
            wim = struct();
            if isfield(cfg, 'wim') && isstruct(cfg.wim)
                wim = cfg.wim;
            end
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'vendor', 'auto');
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'bridge', 'bridge');
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'pipeline', 'direct');
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'design_total_kg', 55000);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'design_axle_kg', 28000);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'overload_factors', [1.5, 2.0]);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'topn', 10);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'lanes', 1:8);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'up_lanes', 1:4);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'speed_bins', [0, 30, 50, 70, 9999]);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'gross_bins', [0, 10000, 30000, 50000, 999999]);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'hour_bins', [0,2,4,6,8,10,12,14,16,18,20,22,24]);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'custom_weights', [30000, 50000]);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'critical_lanes', 1:8);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'hourly_critical_weight_kg', 50000);
            wim = bms.analyzer.WimConfigService.fillDefault(wim, 'excel_name', 'WIM_Report_{bridge}_{yyyymm}.xlsx');
        end

        function vendor = resolveVendor(wim)
            vendor = bms.analyzer.WimConfigService.fieldDefault(wim, 'vendor', 'auto');
            if isempty(vendor) || strcmpi(vendor, 'auto')
                vendors = {};
                if isfield(wim, 'input') && isstruct(wim.input)
                    if isfield(wim.input, 'zhichen'), vendors{end+1} = 'zhichen'; end %#ok<AGROW>
                    if isfield(wim.input, 'jiulongjiang'), vendors{end+1} = 'jiulongjiang'; end %#ok<AGROW>
                end
                if numel(vendors) == 1
                    vendor = vendors{1};
                else
                    error('wim.vendor is required when multiple vendors are configured.');
                end
            end
        end

        function inputCfg = getVendorInput(wim, name)
            inputCfg = struct();
            if isfield(wim, 'input') && isstruct(wim.input) && isfield(wim.input, name)
                inputCfg = wim.input.(name);
            end
        end

        function [fmtPath, bcpPath] = resolveZhichenPaths(inputCfg, base, yyyymm, rootDir)
            fmtName = bms.analyzer.WimConfigService.fieldDefault(inputCfg, 'fmt', ['HS_Data_' yyyymm '.fmt']);
            bcpName = bms.analyzer.WimConfigService.fieldDefault(inputCfg, 'bcp', ['HS_Data_' yyyymm '.bcp']);
            fmtName = strrep(fmtName, '{yyyymm}', yyyymm);
            bcpName = strrep(bcpName, '{yyyymm}', yyyymm);

            candidateDirs = {};
            inputDir = bms.analyzer.WimConfigService.fieldDefault(inputCfg, 'dir', '');
            if ~isempty(inputDir)
                if bms.analyzer.WimConfigService.isAbsolutePath(inputDir)
                    candidateDirs{end+1} = inputDir; %#ok<AGROW>
                elseif nargin >= 4 && ~isempty(rootDir)
                    candidateDirs{end+1} = bms.analyzer.WimConfigService.resolvePath(rootDir, inputDir); %#ok<AGROW>
                else
                    candidateDirs{end+1} = bms.analyzer.WimConfigService.resolvePath(base, inputDir); %#ok<AGROW>
                end
            end
            if nargin >= 4 && ~isempty(rootDir)
                candidateDirs{end+1} = fullfile(rootDir, 'WIM'); %#ok<AGROW>
            end
            candidateDirs = unique(candidateDirs, 'stable');

            fmtPath = '';
            bcpPath = '';
            fmtCandidates = {};
            bcpCandidates = {};
            for i = 1:numel(candidateDirs)
                fmtI = fullfile(candidateDirs{i}, fmtName);
                bcpI = fullfile(candidateDirs{i}, bcpName);
                fmtCandidates{end+1} = fmtI; %#ok<AGROW>
                bcpCandidates{end+1} = bcpI; %#ok<AGROW>
                if exist(fmtI, 'file') && exist(bcpI, 'file')
                    fmtPath = fmtI;
                    bcpPath = bcpI;
                    return;
                end
            end

            for i = 1:numel(fmtCandidates)
                if exist(fmtCandidates{i}, 'file')
                    error('WIM:Input:MissingBcp', ...
                        'WIM input file missing for %s: bcp file not found: %s', yyyymm, bcpCandidates{i});
                end
            end

            for i = 1:numel(bcpCandidates)
                if exist(bcpCandidates{i}, 'file')
                    error('WIM:Input:MissingFmt', ...
                        'WIM input file missing for %s: fmt file not found: %s', yyyymm, fmtCandidates{i});
                end
            end

            if isempty(fmtCandidates)
                error('WIM:Input:MissingFmt', ...
                    'WIM input file missing for %s: no candidate input directory resolved.', yyyymm);
            end

            error('WIM:Input:MissingFmt', ...
                'WIM input file missing for %s: fmt file not found. Searched: %s', ...
                yyyymm, strjoin(fmtCandidates, '; '));
        end

        function files = resolveJiulongjiangFiles(inputCfg, base)
            files = {};
            if isfield(inputCfg, 'files') && ~isempty(inputCfg.files)
                if ischar(inputCfg.files) || isstring(inputCfg.files)
                    files = cellstr(inputCfg.files);
                elseif iscell(inputCfg.files)
                    files = inputCfg.files;
                end
            end
            for i = 1:numel(files)
                files{i} = bms.analyzer.WimConfigService.resolvePath(base, files{i});
            end
            if isempty(files)
                error('No jiulongjiang input files configured (wim.input.jiulongjiang.files).');
            end
        end

        function db = getDbConfig(wim, cfg, projRoot)
            db = struct();
            if isfield(cfg, 'wim_db') && isstruct(cfg.wim_db)
                db = cfg.wim_db;
            end
            if isfield(wim, 'db') && isstruct(wim.db)
                db = bms.analyzer.WimConfigService.mergeStruct(db, wim.db);
            end
            db = bms.analyzer.WimConfigService.fillDefault(db, 'server', '.\SQLEXPRESS');
            db = bms.analyzer.WimConfigService.fillDefault(db, 'database', 'HighSpeed_PROC');
            db = bms.analyzer.WimConfigService.fillDefault(db, 'schema', 'dbo');
            db = bms.analyzer.WimConfigService.fillDefault(db, 'table_prefix', 'HS_Data_');
            db = bms.analyzer.WimConfigService.fillDefault(db, 'raw_table_prefix', 'WIM_Raw_');
            db = bms.analyzer.WimConfigService.fillDefault(db, 'import_mode', 'truncate');
            db = bms.analyzer.WimConfigService.fillDefault(db, 'scripts_dir', fullfile('scripts', 'wim_sql'));
            db = bms.analyzer.WimConfigService.fillDefault(db, 'service_name', 'MSSQLSERVER');
            db = bms.analyzer.WimConfigService.fillDefault(db, 'auth', 'windows');
            db = bms.analyzer.WimConfigService.fillDefault(db, 'sqlcmd_utf8', true);
            db = bms.analyzer.WimConfigService.fillDefault(db, 'trust_server_cert', true);
            db.scripts_dir = bms.analyzer.WimConfigService.resolvePath(projRoot, db.scripts_dir);
        end

        function outputRoot = resolveOutputRoot(rootDir, wim, projRoot)
            configured = bms.analyzer.WimConfigService.fieldDefault(wim, 'output_root', '');
            if isempty(configured)
                outputRoot = fullfile(rootDir, 'WIM', 'results');
                return;
            end
            if bms.analyzer.WimConfigService.isAbsolutePath(configured)
                outputRoot = configured;
                return;
            end
            outputRoot = bms.analyzer.WimConfigService.resolvePath(rootDir, configured);
            if strcmp(outputRoot, configured)
                outputRoot = bms.analyzer.WimConfigService.resolvePath(projRoot, configured);
            end
        end

        function path = resolvePath(base, path)
            if isempty(path), return; end
            if isstring(path), path = char(path); end
            if ~ischar(path), return; end
            if ~bms.analyzer.WimConfigService.isAbsolutePath(path)
                path = fullfile(base, path);
            end
        end

        function tf = isAbsolutePath(path)
            tf = false;
            if isempty(path)
                return;
            end
            if isstring(path), path = char(path); end
            if ~ischar(path)
                return;
            end
            tf = (numel(path) >= 2 && path(2) == ':') || startsWith(path, filesep) || startsWith(path, '\\');
        end

        function value = fieldDefault(s, field, defaultValue)
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = s.(field);
            else
                value = defaultValue;
            end
        end

        function s = fillDefault(s, field, defaultValue)
            if ~isfield(s, field) || isempty(s.(field))
                s.(field) = defaultValue;
            end
        end

        function out = mergeStruct(a, b)
            out = a;
            if ~isstruct(b), return; end
            f = fieldnames(b);
            for i = 1:numel(f)
                out.(f{i}) = b.(f{i});
            end
        end
    end
end
