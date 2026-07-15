classdef ModuleSpec
    %MODULESPEC Central metadata for one runnable or reportable module.

    properties
        Key char = ''
        OptField char = ''
        Label char = ''
        StatsFile char = ''
        Category char = 'analysis'
        SubfolderKey char = ''
        ReportEnabled logical = false
        HighMemoryRisk logical = false
        SupportsSpectrum logical = false
        BridgeScoped logical = true
        GuiField char = ''
        GuiLabel char = ''
        PresetField char = ''
        Description char = ''
    end

    methods
        function obj = ModuleSpec(key, optField, label, statsFile, category, varargin)
            if nargin >= 1, obj.Key = char(key); end
            if nargin >= 2, obj.OptField = char(optField); end
            if nargin >= 3, obj.Label = char(label); end
            if nargin >= 4, obj.StatsFile = char(statsFile); end
            if nargin >= 5, obj.Category = char(category); end
            if ~isempty(obj.Key)
                obj.SubfolderKey = obj.Key;
            end
            if ~isempty(obj.OptField)
                obj.GuiField = obj.OptField;
            end
            obj.GuiLabel = obj.Label;
            obj.PresetField = bms.module.ModuleSpec.defaultPresetField(obj.Key);

            if mod(numel(varargin), 2) ~= 0
                error('ModuleSpec name-value arguments must be paired.');
            end
            for i = 1:2:numel(varargin)
                name = char(varargin{i});
                value = varargin{i+1};
                switch lower(name)
                    case 'subfolderkey'
                        obj.SubfolderKey = char(value);
                    case 'reportenabled'
                        obj.ReportEnabled = logical(value);
                    case 'highmemoryrisk'
                        obj.HighMemoryRisk = logical(value);
                    case 'supportsspectrum'
                        obj.SupportsSpectrum = logical(value);
                    case 'bridgescoped'
                        obj.BridgeScoped = logical(value);
                    case 'guifield'
                        obj.GuiField = char(value);
                    case 'guilabel'
                        obj.GuiLabel = char(value);
                    case 'presetfield'
                        obj.PresetField = char(value);
                    case 'description'
                        obj.Description = char(value);
                    otherwise
                        error('Unknown ModuleSpec option: %s', name);
                end
            end
        end

        function tf = isEnabled(obj, opts)
            tf = false;
            if ~isstruct(opts) || isempty(obj.OptField)
                return;
            end
            if isfield(opts, obj.OptField) && ~isempty(opts.(obj.OptField))
                tf = logical(opts.(obj.OptField));
            end
        end

        function p = statsPath(obj, statsDir)
            p = '';
            if nargin < 2 || isempty(statsDir) || isempty(obj.StatsFile)
                return;
            end
            p = fullfile(statsDir, obj.StatsFile);
        end

        function s = toStruct(obj, statsDir)
            if nargin < 2, statsDir = ''; end
            s = struct();
            s.key = obj.Key;
            s.opt_field = obj.OptField;
            s.label = obj.Label;
            s.category = obj.Category;
            s.stats_file = obj.StatsFile;
            s.stats_path = obj.statsPath(statsDir);
            s.subfolder_key = obj.SubfolderKey;
            s.report_enabled = obj.ReportEnabled;
            s.high_memory_risk = obj.HighMemoryRisk;
            s.supports_spectrum = obj.SupportsSpectrum;
            s.bridge_scoped = obj.BridgeScoped;
            s.gui_field = obj.GuiField;
            s.gui_label = obj.GuiLabel;
            s.preset_field = obj.PresetField;
            s.description = obj.Description;
        end
    end

    methods (Static)
        function field = defaultPresetField(key)
            switch char(key)
                case 'temperature'
                    field = 'temp';
                case 'deflection'
                    field = 'deflect';
                case 'acceleration'
                    field = 'accel';
                case 'accel_spectrum'
                    field = 'spec';
                case 'cable_accel_spectrum'
                    field = 'cable_spec';
                case 'dynamic_strain_highpass'
                    field = 'dynbox';
                case 'dynamic_strain_lowpass'
                    field = 'dynlowpass';
                case 'earthquake'
                    field = 'eq';
                case 'bearing_displacement'
                    field = 'bearing_displacement';
                otherwise
                    field = char(key);
            end
        end
    end
end
