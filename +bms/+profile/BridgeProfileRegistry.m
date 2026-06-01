classdef BridgeProfileRegistry
    %BRIDGEPROFILEREGISTRY Known bridge project defaults.

    methods (Static)
        function profiles = catalog(projectRoot)
            if nargin < 1 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            jsonPath = fullfile(projectRoot, 'config', 'bridge_profiles.json');
            if exist(jsonPath, 'file')
                profiles = bms.profile.BridgeProfileRegistry.loadJson(jsonPath, projectRoot);
                if ~isempty(profiles)
                    return;
                end
            end
            profiles = bms.profile.BridgeProfileRegistry.fallback(projectRoot);
        end

        function profiles = loadJson(jsonPath, projectRoot)
            profiles = bms.profile.BridgeProfile.empty();
            try
                data = jsondecode(fileread(jsonPath));
                if ~isfield(data, 'profiles')
                    return;
                end
                rows = data.profiles;
                for i = 1:numel(rows)
                    if iscell(rows)
                        row = rows{i};
                    else
                        row = rows(i);
                    end
                    profiles(end+1) = bms.profile.BridgeProfile.fromStruct(row, projectRoot); %#ok<AGROW>
                end
            catch
                profiles = bms.profile.BridgeProfile.empty();
            end
        end

        function profiles = fallback(projectRoot)
            P = @bms.profile.BridgeProfile;
            profiles = [ ...
                P('guanbing', '管柄大桥', fullfile(projectRoot, 'config', 'default_config.json'), fullfile(projectRoot, 'reports', 'G104线管柄大桥监测月报模板-自动报告.docx'), 'dated_folders', 'monthly', {'temperature','humidity','deflection','tilt','acceleration','crack','strain'}), ...
                P('hongtang', '洪塘大桥', fullfile(projectRoot, 'config', 'hongtang_config.json'), fullfile(projectRoot, 'reports', '洪塘大桥健康监测2026年第一季季报-改4.docx'), 'hongtang_period', 'period', {'strain','tilt','bearing_displacement','cable_accel','acceleration','wind','earthquake','wim'}), ...
                P('jiulongjiang', '九龙江大桥', fullfile(projectRoot, 'config', 'jiulongjiang_config.json'), fullfile(projectRoot, 'reports', '九龙江大桥健康监测2026年3月份月报_修订5.docx'), 'jlj_daily_export', 'monthly', {'temperature','humidity','rainfall','wind','earthquake','deflection','bearing_displacement','tilt','acceleration','cable_accel','crack','gnss'}), ...
                P('shuixianhua', '水仙花大桥', fullfile(projectRoot, 'config', 'shuixianhua_config.json'), '', 'jlj_daily_export', 'monthly', {'temperature','humidity','wind','earthquake','deflection','bearing_displacement','acceleration','accel_spectrum','cable_accel','cable_accel_spectrum','strain','dynamic_strain_highpass','dynamic_strain_lowpass'}), ...
                P('zhishan', '芝山大桥', fullfile(projectRoot, 'config', 'zhishan_config.json'), '', 'dated_folders', 'analysis_only', {'strain','dynamic_strain_highpass','bearing_displacement','acceleration','accel_spectrum','cable_accel','cable_accel_spectrum'}) ...
            ];
        end

        function profile = fromId(bridgeId, projectRoot)
            if nargin < 2, projectRoot = []; end
            bridgeId = lower(char(bridgeId));
            profiles = bms.profile.BridgeProfileRegistry.catalog(projectRoot);
            profile = bms.profile.BridgeProfile();
            for i = 1:numel(profiles)
                if strcmpi(profiles(i).BridgeId, bridgeId)
                    profile = profiles(i);
                    return;
                end
            end
        end

        function profile = infer(cfg, dataRoot)
            if nargin < 1, cfg = struct(); end
            if nargin < 2, dataRoot = ''; end
            source = '';
            if isstruct(cfg) && isfield(cfg, 'source') && ~isempty(cfg.source)
                source = lower(char(cfg.source));
            end
            vendor = '';
            if isstruct(cfg) && isfield(cfg, 'vendor') && ~isempty(cfg.vendor)
                vendor = lower(char(string(cfg.vendor)));
            end
            rootText = lower(char(string(dataRoot)));
            if contains(source, 'zhishan') || contains(source, 'zishan') || contains(source, '芝山') || ...
                    contains(vendor, 'zhishan') || contains(vendor, 'zishan') || contains(rootText, '芝山')
                profile = bms.profile.BridgeProfileRegistry.fromId('zhishan');
            elseif contains(source, 'shuixianhua') || contains(source, 'sxh') || contains(source, '水仙花') || ...
                    contains(vendor, 'shuixianhua') || contains(vendor, 'sxh') || contains(rootText, '水仙花')
                profile = bms.profile.BridgeProfileRegistry.fromId('shuixianhua');
            elseif contains(source, 'hongtang') || contains(source, '洪塘') || contains(rootText, '洪塘')
                profile = bms.profile.BridgeProfileRegistry.fromId('hongtang');
            elseif contains(source, 'jiulongjiang') || contains(source, 'jlj') || contains(source, '九龙江') || contains(rootText, '九龙江')
                profile = bms.profile.BridgeProfileRegistry.fromId('jiulongjiang');
            else
                profile = bms.profile.BridgeProfileRegistry.fromId('guanbing');
            end
        end


        function validation = validateCatalog(projectRoot)
            if nargin < 1 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            profiles = bms.profile.BridgeProfileRegistry.catalog(projectRoot);
            validation = struct();
            validation.status = 'ok';
            validation.errors = {};
            validation.warnings = {};
            validation.profile_count = numel(profiles);
            validation.profile_ids = arrayfun(@(p) p.BridgeId, profiles, 'UniformOutput', false);
            seen = containers.Map('KeyType','char','ValueType','logical');
            allowedLayouts = {'dated_folders','hongtang_period','jlj_daily_export'};
            for i = 1:numel(profiles)
                p = profiles(i);
                prefix = sprintf('profile[%d:%s]', i, p.BridgeId);
                required = {'BridgeId','BridgeName','DefaultConfig','DefaultDataRoot','DataLayout'};
                for k = 1:numel(required)
                    if isempty(p.(required{k}))
                        validation.errors{end+1} = sprintf('%s missing %s', prefix, required{k}); %#ok<AGROW>
                    end
                end
                id = lower(char(p.BridgeId));
                if ~isempty(id)
                    if isKey(seen, id)
                        validation.errors{end+1} = sprintf('%s duplicate bridge_id', prefix); %#ok<AGROW>
                    else
                        seen(id) = true;
                    end
                end
                if ~isempty(p.DefaultConfig) && ~isfile(p.DefaultConfig)
                    validation.errors{end+1} = sprintf('%s default_config not found: %s', prefix, p.DefaultConfig); %#ok<AGROW>
                end
                if ~isempty(p.DefaultReportTemplate) && ~contains(p.DefaultReportTemplate, '<data_root>') && ~isfile(p.DefaultReportTemplate)
                    validation.warnings{end+1} = sprintf('%s report_template not found: %s', prefix, p.DefaultReportTemplate); %#ok<AGROW>
                end
                if ~isempty(p.DataLayout) && ~any(strcmp(allowedLayouts, p.DataLayout))
                    validation.errors{end+1} = sprintf('%s unsupported data_layout: %s', prefix, p.DataLayout); %#ok<AGROW>
                end
                if isempty(p.EnabledModuleHints)
                    validation.warnings{end+1} = sprintf('%s enabled_modules is empty', prefix); %#ok<AGROW>
                end
                if ~isempty(p.DefaultStartDate) && ~isempty(p.DefaultEndDate)
                    try
                        bms.data.TimeRangeResolver.parseRange(p.DefaultStartDate, p.DefaultEndDate);
                    catch ME
                        validation.errors{end+1} = sprintf('%s invalid default date range: %s', prefix, ME.message); %#ok<AGROW>
                    end
                end
            end
            if ~isempty(validation.errors)
                validation.status = 'failed';
            elseif ~isempty(validation.warnings)
                validation.status = 'warning';
            end
        end

        function rows = toStructArray(profiles)
            rows = {};
            for i = 1:numel(profiles)
                rows{end+1} = profiles(i).toStruct(); %#ok<AGROW>
            end
        end

        function idx = indexOf(profiles, bridgeId)
            idx = 0;
            for i = 1:numel(profiles)
                if strcmpi(profiles(i).BridgeId, bridgeId)
                    idx = i;
                    return;
                end
            end
        end
    end
end
