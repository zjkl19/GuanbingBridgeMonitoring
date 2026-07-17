classdef CacheSourceCleanupProvider
    %CACHESOURCECLEANUPPROVIDER Layout-neutral cleanup validation contract.
    %   The provider does not delete files. It centralises the layout-specific
    %   cache identity and standalone-read gates used before a cleanup receipt
    %   may be committed.

    methods (Static)
        function provider = resolve(root, cfg)
            if nargin < 2, cfg = struct(); end
            layout = '';
            if isstruct(cfg) && isfield(cfg, 'data_layout') ...
                    && ~isempty(cfg.data_layout)
                explicit = char(string(cfg.data_layout));
                if bms.data.CacheSourceCleanupProvider.supportsLayout(explicit)
                    layout = explicit;
                else
                    error('BMS:CacheSourceCleanup:UnsupportedLayout', ...
                        'Verified CSV cleanup does not support explicit data layout: %s', ...
                        explicit);
                end
            end
            if isempty(layout)
                layout = char(string( ...
                    bms.data.DataLayoutResolver.inferLayout(root, cfg)));
            end
            provider = struct('layout', layout, 'id', '', 'cache_version', '', ...
                'receipt_schema_version', 3);
            switch layout
                case 'jlj_daily_export'
                    provider.id = 'daily_export_v2';
                    provider.cache_version = 'jlj_csv_v2';
                    provider.receipt_schema_version = 2;
                case {'dated_folders', 'hongtang_period'}
                    provider.id = 'standard_timeseries_v1';
                    provider.cache_version = ...
                        bms.data.TimeSeriesLoader.seriesCacheVersion(cfg);
                otherwise
                    error('BMS:CacheSourceCleanup:UnsupportedLayout', ...
                        'Verified CSV cleanup does not support data layout: %s', layout);
            end
        end

        function tf = supportsLayout(layout)
            tf = any(strcmp(char(string(layout)), ...
                {'jlj_daily_export','dated_folders','hongtang_period'}));
        end

        function pathValue = standardReceiptPath(root, day)
            dayText = bms.data.TimeRangeResolver.toDateString(day);
            pathValue = fullfile(char(string(root)), 'run_logs', ...
                'cache_source_cleanup_receipts', ...
                ['standard_' strrep(dayText, '-', '') '.json']);
        end

        function cachePath = expectedCachePath(sourcePath, provider)
            sourcePath = char(string(sourcePath));
            [folder, base] = fileparts(sourcePath);
            switch char(string(provider.id))
                case 'standard_timeseries_v1'
                    cachePath = fullfile(bms.data.CacheManager.cacheDir(folder), ...
                        [base '.mat']);
                otherwise
                    error('BMS:CacheSourceCleanup:ProviderMismatch', ...
                        'expectedCachePath is not implemented for provider %s.', ...
                        char(string(provider.id)));
            end
        end

        function identity = validateStandardCache(sourcePath, cachePath, cfg)
            %VALIDATESTANDARDCACHE Close source/meta/pair/payload identity.
            sourcePath = char(string(sourcePath));
            cachePath = char(string(cachePath));
            provider = struct('id', 'standard_timeseries_v1', ...
                'cache_version', ...
                    bms.data.TimeSeriesLoader.seriesCacheVersion(cfg));
            expected = bms.data.CacheSourceCleanupProvider. ...
                expectedCachePath(sourcePath, provider);
            if ~strcmpi(bms.data.CacheSourceCleanupProvider.canonicalPath(cachePath), ...
                    bms.data.CacheSourceCleanupProvider.canonicalPath(expected))
                error('BMS:CacheSourceCleanup:UnexpectedCachePath', ...
                    'Cache path is not the source CSV''s configured cache path: %s', ...
                    cachePath);
            end
            metaPath = bms.data.CacheManager.metadataPath(cachePath);
            if ~isfile(sourcePath) || ~isfile(cachePath) || ~isfile(metaPath)
                error('BMS:CacheSourceCleanup:CachePairMissing', ...
                    'Source/cache/metadata triple is incomplete: %s', sourcePath);
            end
            version = bms.data.TimeSeriesLoader.seriesCacheVersion(cfg);
            % The explicit readMatSeries call below is the one authoritative
            % full MAT load.  Reuse metadata and pair integrity are checked
            % separately here so preparation does not load the payload twice.
            if ~bms.data.CacheManager.metadataMatchesFull( ...
                    cachePath, {sourcePath}, struct(), version) ...
                    || ~bms.data.CacheManager.cachePairIntegrityMatches(cachePath)
                error('BMS:CacheSourceCleanup:CacheValidationFailed', ...
                    'Standard MAT cache pair is not independently reusable: %s', ...
                    cachePath);
            end
            meta = bms.io.JsonFile.read(metaPath);
            if ~isfield(meta, 'source_records') ...
                    || ~isfield(meta, 'pair_id') || isempty(meta.pair_id) ...
                    || ~isfield(meta, 'mat_bytes')
                error('BMS:CacheSourceCleanup:CacheSourceIdentityMissing', ...
                    'Standard cache metadata lacks source/pair identity: %s', metaPath);
            end
            records = bms.data.CacheManager.normalizeSourceRecords(meta.source_records);
            actual = bms.data.CacheManager.buildSourceRecords({sourcePath});
            actual = bms.data.CacheManager.normalizeSourceRecords(actual);
            if numel(records) ~= 1 ...
                    || ~strcmpi(bms.data.CacheSourceCleanupProvider.canonicalPath( ...
                        records(1).path), ...
                        bms.data.CacheSourceCleanupProvider.canonicalPath(sourcePath)) ...
                    || ~isequal(logical(records(1).exists), true) ...
                    || double(records(1).bytes) ~= double(actual(1).bytes) ...
                    || ~strcmp(char(string(records(1).modified_at)), ...
                        char(string(actual(1).modified_at)))
                error('BMS:CacheSourceCleanup:CacheSourceIdentityMismatch', ...
                    'Standard cache metadata is not bound to the current CSV: %s', ...
                    cachePath);
            end
            info = dir(cachePath);
            if isempty(info) || double(info(1).bytes) ~= double(meta.mat_bytes)
                error('BMS:CacheSourceCleanup:CachePairChanged', ...
                    'Standard MAT cache byte identity changed: %s', cachePath);
            end
            pairPayload = load(cachePath, 'cache_pair_id');
            if ~isfield(pairPayload, 'cache_pair_id') ...
                    || ~strcmp(char(string(pairPayload.cache_pair_id)), ...
                        char(string(meta.pair_id)))
                error('BMS:CacheSourceCleanup:CachePairChanged', ...
                    'Standard MAT/metadata pair identifiers do not match: %s', ...
                    cachePath);
            end
            opts = struct('cache_version', version, 'require_metadata', true);
            [times, vals, loaded] = bms.data.TimeSeriesLoader.readMatSeries( ...
                cachePath, opts);
            if ~logical(loaded.read_ok) || isempty(times) ...
                    || numel(times) ~= numel(vals)
                error('BMS:CacheSourceCleanup:CacheLoadFailed', ...
                    'Standard MAT cache failed an actual standalone load: %s', ...
                    cachePath);
            end
            identity = struct( ...
                'source_path', sourcePath, ...
                'source_bytes', double(actual(1).bytes), ...
                'source_modified_at', char(string(actual(1).modified_at)), ...
                'cache_path', cachePath, ...
                'metadata_path', metaPath, ...
                'pair_id', char(string(meta.pair_id)), ...
                'mat_bytes', double(meta.mat_bytes), ...
                'cache_bytes', bms.data.CacheSourceCleanupProvider. ...
                    cachePairBytes(cachePath), ...
                'sample_count', numel(vals));
        end

        function hash = standardScopeHash(cfg, layout, cacheVersion)
            % Bind every source-resolution input, not only point identifiers.
            scope = struct('provider', 'standard_timeseries_v1', ...
                'layout', char(string(layout)), ...
                'cache_version', char(string(cacheVersion)), ...
                'config_hash', bms.data.CacheManager.configHash(cfg), ...
                'requests', bms.data.CacheSourceCleanupProvider. ...
                    configuredRequests(cfg));
            hash = bms.data.CacheManager.configHash(scope);
        end

        function requests = configuredRequests(cfg)
            specs = bms.module.ModuleRegistry.forCategory('analysis');
            rows = {};
            for i = 1:numel(specs)
                spec = specs(i);
                if strcmp(spec.Key, 'wim') || isempty(spec.SubfolderKey)
                    continue;
                end
                points = bms.app.RunPreflight.configuredPoints(cfg, spec.Key);
                sourceRequests = bms.data.DataIndex.sourceRequestsForModule( ...
                    spec.Key, points, cfg);
                for j = 1:numel(sourceRequests)
                    rows{end+1} = sprintf('%s|%s|%s', spec.Key, ... %#ok<AGROW>
                        char(string(sourceRequests(j).point_id)), ...
                        char(string(sourceRequests(j).sensor_type)));
                end
            end
            requests = sort(unique(cellstr(string(rows))));
        end

        function pathValue = canonicalPath(pathValue)
            pathValue = char(string(pathValue));
            try
                pathValue = char(java.io.File(pathValue).getCanonicalPath());
            catch
            end
        end

        function tf = isPathInside(pathValue, root)
            value = lower(strrep(bms.data.CacheSourceCleanupProvider. ...
                canonicalPath(pathValue), '/', filesep));
            root = lower(strrep(bms.data.CacheSourceCleanupProvider. ...
                canonicalPath(root), '/', filesep));
            root = regexprep(root, '[\\/]+$', '');
            tf = strcmp(value, root) || startsWith(value, [root filesep]);
        end
    end

    methods (Static, Access = private)
        function bytes = cachePairBytes(cachePath)
            bytes = 0;
            paths = {cachePath, bms.data.CacheManager.metadataPath(cachePath)};
            for i = 1:numel(paths)
                d = dir(paths{i});
                if ~isempty(d), bytes = bytes + double(d(1).bytes); end
            end
        end

    end
end
