classdef BridgeProfile
    %BRIDGEPROFILE Describes a bridge project's default runtime choices.

    properties
        BridgeId char = ''
        BridgeName char = ''
        DefaultConfig char = ''
        DefaultReportTemplate char = ''
        DataLayout char = ''
        DefaultReportType char = ''
        EnabledModuleHints cell = {}
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
            s.default_report_template = obj.DefaultReportTemplate;
            s.data_layout = obj.DataLayout;
            s.default_report_type = obj.DefaultReportType;
            s.enabled_module_hints = obj.EnabledModuleHints;
        end

        function tf = configExists(obj)
            tf = ~isempty(obj.DefaultConfig) && isfile(obj.DefaultConfig);
        end
    end
end
