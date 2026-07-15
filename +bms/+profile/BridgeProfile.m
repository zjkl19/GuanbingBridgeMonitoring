classdef BridgeProfile
    %BRIDGEPROFILE Describes a bridge project's default runtime choices.

    properties
        BridgeId char = ''
        BridgeName char = ''
        DefaultConfig char = ''
        DefaultDataRoot char = ''
        DefaultReportTemplate char = ''
        DataLayout char = ''
        DefaultReportType char = ''
        ReportGuiType char = ''
        WimDefaultDir char = ''
        DefaultPeriodLabel char = ''
        DefaultMonitoringRange char = ''
        DefaultStartDate char = ''
        DefaultEndDate char = ''
        EnabledModuleHints cell = {}
        OptionalModuleHints cell = {}
    end

    methods
        function obj = BridgeProfile(bridgeId, bridgeName, defaultConfig, defaultTemplate, dataLayout, reportType, moduleHints)
            if nargin >= 1, obj.BridgeId = char(bridgeId); end
            if nargin >= 2, obj.BridgeName = char(bridgeName); end
            if nargin >= 3, obj.DefaultConfig = char(defaultConfig); end
            if nargin >= 4, obj.DefaultReportTemplate = char(defaultTemplate); end
            if nargin >= 5, obj.DataLayout = char(dataLayout); end
            if nargin >= 6, obj.DefaultReportType = char(reportType); end
            if nargin >= 7, obj.EnabledModuleHints = cellstr(string(moduleHints)); end
        end

        function s = toStruct(obj)
            s = struct();
            s.bridge_id = obj.BridgeId;
            s.bridge_name = obj.BridgeName;
            s.default_config = obj.DefaultConfig;
            s.default_data_root = obj.DefaultDataRoot;
            s.default_report_template = obj.DefaultReportTemplate;
            s.data_layout = obj.DataLayout;
            s.default_report_type = obj.DefaultReportType;
            s.report_gui_type = obj.ReportGuiType;
            s.wim_default_dir = obj.WimDefaultDir;
            s.default_period_label = obj.DefaultPeriodLabel;
            s.default_monitoring_range = obj.DefaultMonitoringRange;
            s.default_start_date = obj.DefaultStartDate;
            s.default_end_date = obj.DefaultEndDate;
            s.enabled_module_hints = obj.EnabledModuleHints;
            s.optional_module_hints = obj.OptionalModuleHints;
        end

        function tf = configExists(obj)
            tf = ~isempty(obj.DefaultConfig) && isfile(obj.DefaultConfig);
        end

        function text = displayName(obj)
            if isempty(obj.BridgeName)
                text = obj.BridgeId;
            else
                text = obj.BridgeName;
            end
        end

        function p = wimDirForRoot(obj, dataRoot)
            p = obj.WimDefaultDir;
            if isempty(p)
                p = fullfile(char(dataRoot), 'WIM', 'results', 'hongtang');
                return;
            end
            p = strrep(p, '<data_root>', char(dataRoot));
            p = strrep(p, '/', filesep);
        end
    end

    methods (Static)
        function obj = fromStruct(s, projectRoot)
            if nargin < 2 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            obj = bms.profile.BridgeProfile();
            obj.BridgeId = bms.profile.BridgeProfile.fieldText(s, 'bridge_id', '');
            obj.BridgeName = bms.profile.BridgeProfile.fieldText(s, 'bridge_name', obj.BridgeId);
            obj.DefaultConfig = bms.profile.BridgeProfile.resolvePath( ...
                bms.profile.BridgeProfile.fieldText(s, 'default_config', ''), projectRoot);

            defaultDataRoot = bms.profile.BridgeProfile.normalizePathText( ...
                bms.profile.BridgeProfile.fieldText(s, 'default_data_root', ''));
            obj.DefaultDataRoot = bms.profile.PathProfileResolver.resolveDataRoot( ...
                obj.BridgeId, defaultDataRoot, projectRoot);
            obj.DefaultReportTemplate = bms.profile.BridgeProfile.resolvePath( ...
                bms.profile.BridgeProfile.fieldText(s, 'report_template', ''), projectRoot);
            obj.DataLayout = bms.profile.BridgeProfile.fieldText(s, 'data_layout', '');
            obj.DefaultReportType = bms.profile.BridgeProfile.fieldText(s, 'report_type', '');
            obj.ReportGuiType = bms.profile.BridgeProfile.fieldText(s, 'report_gui_type', '');
            obj.WimDefaultDir = bms.profile.BridgeProfile.normalizePathText( ...
                bms.profile.BridgeProfile.fieldText(s, 'wim_default_dir', ''));
            obj.DefaultPeriodLabel = bms.profile.BridgeProfile.fieldText(s, 'default_period_label', '');
            obj.DefaultMonitoringRange = bms.profile.BridgeProfile.fieldText(s, 'default_monitoring_range', '');
            obj.DefaultStartDate = bms.profile.BridgeProfile.fieldText(s, 'default_start_date', '');
            obj.DefaultEndDate = bms.profile.BridgeProfile.fieldText(s, 'default_end_date', '');
            obj.EnabledModuleHints = bms.profile.BridgeProfile.fieldCellstr(s, 'enabled_modules');
            obj.OptionalModuleHints = bms.profile.BridgeProfile.fieldCellstr(s, 'optional_modules');
        end

        function value = fieldText(s, fieldName, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                value = char(string(s.(fieldName)));
            end
        end

        function value = fieldCellstr(s, fieldName)
            value = {};
            if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                raw = s.(fieldName);
                if iscell(raw)
                    value = cellstr(string(raw));
                else
                    value = cellstr(string(raw(:)));
                end
            end
        end

        function p = resolvePath(p, projectRoot)
            p = bms.profile.BridgeProfile.normalizePathText(p);
            if isempty(p) || contains(p, '<data_root>')
                return;
            end
            computerName = getenv('COMPUTERNAME');
            p = strrep(p, '<COMPUTERNAME>', computerName);
            if ~bms.profile.BridgeProfile.isAbsolutePath(p)
                p = fullfile(projectRoot, p);
            end
        end

        function p = normalizePathText(p)
            p = char(string(p));
            if isempty(p), return; end
            p = strrep(p, '/', filesep);
        end

        function tf = isAbsolutePath(p)
            p = char(string(p));
            tf = ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once')) || startsWith(p, filesep) || startsWith(p, '\\');
        end
    end
end
