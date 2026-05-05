classdef GuiState
    %GUISTATE Value object for run-page GUI selections.

    properties
        Root char = ''
        StartDate char = ''
        EndDate char = ''
        ConfigPath char = ''
        LogDir char = ''
        ShowWarnings logical = false
        Preproc struct = struct()
        Modules struct = struct()
    end

    methods
        function obj = GuiState(varargin)
            if nargin == 1 && isstruct(varargin{1})
                obj = bms.gui.GuiState.fromPreset(varargin{1});
                return;
            end
            if mod(nargin, 2) ~= 0
                error('BMS:GuiState:InvalidArguments', 'GuiState arguments must be name-value pairs.');
            end
            for i = 1:2:nargin
                key = lower(char(varargin{i}));
                value = varargin{i+1};
                switch key
                    case 'root'
                        obj.Root = char(value);
                    case 'startdate'
                        obj.StartDate = bms.gui.GuiState.dateText(value);
                    case 'enddate'
                        obj.EndDate = bms.gui.GuiState.dateText(value);
                    case 'configpath'
                        obj.ConfigPath = char(value);
                    case 'logdir'
                        obj.LogDir = char(value);
                    case 'showwarnings'
                        obj.ShowWarnings = logical(value);
                    case 'preproc'
                        if isstruct(value), obj.Preproc = value; end
                    case 'modules'
                        if isstruct(value), obj.Modules = value; end
                    otherwise
                        error('BMS:GuiState:InvalidArgument', 'Unknown GuiState argument: %s', key);
                end
            end
        end

        function opts = toOptions(obj)
            preset = obj.toPreset();
            opts = bms.gui.GuiRunController.optsFromPreset(preset);
        end

        function request = toRunRequest(obj, cfg)
            request = bms.app.RunRequest.fromLegacy(obj.Root, obj.StartDate, obj.EndDate, obj.toOptions(), cfg);
        end

        function preset = toPreset(obj)
            preset = struct();
            preset.root = obj.Root;
            preset.start_date = obj.StartDate;
            preset.end_date = obj.EndDate;
            preset.cfg = obj.ConfigPath;
            preset.logdir = obj.LogDir;
            preset.show_warnings = logical(obj.ShowWarnings);
            preset.preproc = obj.Preproc;
            preset.modules = obj.Modules;
        end
    end

    methods (Static)
        function obj = fromValues(root, startDate, endDate, cfgPath, logDir, showWarnings, preproc, modules)
            if nargin < 7 || isempty(preproc), preproc = struct(); end
            if nargin < 8 || isempty(modules), modules = struct(); end
            obj = bms.gui.GuiState( ...
                'Root', root, ...
                'StartDate', startDate, ...
                'EndDate', endDate, ...
                'ConfigPath', cfgPath, ...
                'LogDir', logDir, ...
                'ShowWarnings', showWarnings, ...
                'Preproc', preproc, ...
                'Modules', modules);
        end

        function obj = fromPreset(preset)
            if nargin < 1 || isempty(preset) || ~isstruct(preset)
                preset = struct();
            end
            root = bms.gui.GuiState.fieldText(preset, 'root', '');
            startDate = bms.gui.GuiState.fieldText(preset, 'start_date', '');
            endDate = bms.gui.GuiState.fieldText(preset, 'end_date', '');
            cfgPath = bms.gui.GuiState.fieldText(preset, 'cfg', '');
            logDir = bms.gui.GuiState.fieldText(preset, 'logdir', '');
            showWarnings = bms.gui.GuiState.fieldBool(preset, 'show_warnings', false);
            preproc = bms.gui.GuiState.fieldStruct(preset, 'preproc');
            modules = bms.gui.GuiState.fieldStruct(preset, 'modules');
            obj = bms.gui.GuiState.fromValues(root, startDate, endDate, cfgPath, logDir, showWarnings, preproc, modules);
        end

        function txt = dateText(value)
            if isa(value, 'datetime')
                txt = datestr(value, 'yyyy-mm-dd');
            elseif isempty(value)
                txt = '';
            else
                txt = char(string(value));
            end
        end

        function value = fieldText(s, field, defaultValue)
            value = defaultValue;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = char(string(s.(field)));
            end
        end

        function value = fieldBool(s, field, defaultValue)
            value = defaultValue;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = bms.config.ConfigReader.boolValue(s.(field), defaultValue);
            end
        end

        function value = fieldStruct(s, field)
            value = struct();
            if isstruct(s) && isfield(s, field) && isstruct(s.(field))
                value = s.(field);
            end
        end
    end
end
