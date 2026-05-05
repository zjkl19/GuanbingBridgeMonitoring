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
                P('jiulongjiang', '九龙江大桥', fullfile(projectRoot, 'config', 'jiulongjiang_config.json'), fullfile(projectRoot, 'reports', '九龙江大桥健康监测2026年3月份月报_修订5.docx'), 'jlj_daily_export', 'monthly', {'temperature','humidity','rainfall','wind','earthquake','deflection','tilt','acceleration','cable_accel','crack','gnss'}) ...
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
            rootText = lower(char(string(dataRoot)));
            if contains(source, 'hongtang') || contains(source, '洪塘') || contains(rootText, '洪塘')
                profile = bms.profile.BridgeProfileRegistry.fromId('hongtang');
            elseif contains(source, 'jiulongjiang') || contains(source, 'jlj') || contains(source, '九龙江') || contains(rootText, '九龙江')
                profile = bms.profile.BridgeProfileRegistry.fromId('jiulongjiang');
            else
                profile = bms.profile.BridgeProfileRegistry.fromId('guanbing');
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
