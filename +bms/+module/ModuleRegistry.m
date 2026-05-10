classdef ModuleRegistry
    %MODULEREGISTRY Single source of truth for analysis module metadata.

    methods (Static)
        function specs = catalog()
            S = @bms.module.ModuleSpec;
            specs = [ ...
                S('zip_precheck','precheck_zip_count',char([39044 26816 26597 21387 32553 21253 25968 37327]),'', 'preprocess', 'BridgeScoped', false, 'GuiLabel', char([39044 26816 26597 21387 32553 21253 25968 37327]), 'PresetField', 'precheck'), ...
                S('unzip','doUnzip',char([25209 37327 35299 21387]),'', 'preprocess', 'BridgeScoped', false, 'PresetField', 'unzip'), ...
                S('rename_csv','doRenameCsv',char([25209 37327 37325 21629 21517 67 83 86]),'', 'preprocess', 'BridgeScoped', false, 'PresetField', 'rename'), ...
                S('remove_header','doRemoveHeader',char([25209 37327 21435 38500 34920 22836]),'', 'preprocess', 'BridgeScoped', false, 'PresetField', 'rmheader'), ...
                S('resample','doResample',char([25209 37327 37325 37319 26679]),'', 'preprocess', 'BridgeScoped', false, 'PresetField', 'resample'), ...
                S('temperature','doTemp',char([28201 24230 20998 26512]),'temp_stats.xlsx', 'analysis', 'SubfolderKey', 'temperature', 'ReportEnabled', true, 'GuiLabel', '🌡 温度分析'), ...
                S('humidity','doHumidity',char([28287 24230 20998 26512]),'humidity_stats.xlsx', 'analysis', 'SubfolderKey', 'humidity', 'ReportEnabled', true, 'GuiLabel', '💧 湿度分析'), ...
                S('rainfall','doRainfall',char([38632 37327 20998 26512]),'rainfall_stats.xlsx', 'analysis', 'SubfolderKey', 'rainfall', 'ReportEnabled', true, 'GuiLabel', '🌧 雨量分析'), ...
                S('gnss','doGNSS',char([71 78 83 83 20998 26512]),'gnss_stats.xlsx', 'analysis', 'SubfolderKey', 'gnss', 'ReportEnabled', true, 'GuiLabel', '📍 GNSS分析'), ...
                S('wind','doWind',char([39118 36895 39118 21521 20998 26512]),'wind_stats.xlsx', 'analysis', 'SubfolderKey', 'wind_raw', 'ReportEnabled', true, 'GuiLabel', '🌬 风速风向分析'), ...
                S('earthquake','doEq',char([22320 38663 21160 20998 26512]),'eq_stats.xlsx', 'analysis', 'SubfolderKey', 'eq_raw', 'ReportEnabled', true, 'PresetField', 'eq', 'GuiLabel', '📳 地震动分析'), ...
                S('wim','doWIM',char([87 73 77]),'', 'analysis', 'SubfolderKey', 'wim', 'ReportEnabled', true, 'GuiLabel', '🚚 WIM'), ...
                S('deflection','doDeflect',char([25376 24230 20998 26512]),'deflection_stats.xlsx', 'analysis', 'SubfolderKey', 'deflection', 'ReportEnabled', true, 'PresetField', 'deflect', 'GuiLabel', '↕ 挠度分析'), ...
                S('bearing_displacement','doBearingDisplacement',char([25903 24231 20301 31227 20998 26512]),'bearing_displacement_stats.xlsx', 'analysis', 'SubfolderKey', 'bearing_displacement', 'ReportEnabled', true, 'GuiLabel', '↔ 支座位移分析'), ...
                S('tilt','doTilt',char([20542 35282 20998 26512]),'tilt_stats.xlsx', 'analysis', 'SubfolderKey', 'tilt', 'ReportEnabled', true, 'GuiLabel', '📐 倾角分析'), ...
                S('acceleration','doAccel',char([21152 36895 24230 20998 26512]),'accel_stats.xlsx', 'analysis', 'SubfolderKey', 'acceleration', 'ReportEnabled', true, 'HighMemoryRisk', true, 'PresetField', 'accel', 'GuiLabel', '📈 加速度分析'), ...
                S('cable_accel','doCableAccel',char([32034 21147 21152 36895 24230 20998 26512]),'cable_accel_stats.xlsx', 'analysis', 'SubfolderKey', 'cable_accel', 'ReportEnabled', true, 'HighMemoryRisk', true, 'GuiLabel', '〰 索力加速度分析'), ...
                S('accel_spectrum','doAccelSpectrum',char([21152 36895 24230 39057 35889]),'accel_spec_stats.xlsx', 'analysis', 'SubfolderKey', 'acceleration_raw', 'ReportEnabled', true, 'HighMemoryRisk', true, 'SupportsSpectrum', true, 'PresetField', 'spec', 'GuiLabel', '📶 加速度频谱'), ...
                S('cable_accel_spectrum','doCableAccelSpectrum',char([32034 21147 21152 36895 24230 39057 35889]),'cable_accel_spec_stats.xlsx', 'analysis', 'SubfolderKey', 'cable_accel_raw', 'ReportEnabled', true, 'HighMemoryRisk', true, 'SupportsSpectrum', true, 'PresetField', 'cable_spec', 'GuiLabel', '📶 索力加速度频谱'), ...
                S('rename_crk','doRenameCrk',char([35010 32541 37325 21629 21517]),'', 'preprocess', 'BridgeScoped', false), ...
                S('crack','doCrack',char([35010 32541 20998 26512]),'crack_stats.xlsx', 'analysis', 'SubfolderKey', 'crack', 'ReportEnabled', true, 'GuiLabel', '⚡ 裂缝分析'), ...
                S('strain','doStrain',char([24212 21464 20998 26512]),'strain_stats.xlsx', 'analysis', 'SubfolderKey', 'strain', 'ReportEnabled', true, 'GuiLabel', 'ε 应变分析'), ...
                S('dynamic_strain_highpass','doDynStrainBoxplot',char([21160 24212 21464 20998 26512 65288 39640 36890 43 21547 31665 32447 22270 65289]),'dynamic_strain_highpass_stats.xlsx', 'analysis', 'SubfolderKey', 'strain', 'ReportEnabled', true, 'GuiLabel', 'ε~ 动应变分析（高通+箱线图）', 'PresetField', 'dynbox'), ...
                S('dynamic_strain_lowpass','doDynStrainLowpassBoxplot',char([21160 24212 21464 20998 26512 65288 20302 36890 43 21547 31665 32447 22270 65289]),'dynamic_strain_lowpass_stats.xlsx', 'analysis', 'SubfolderKey', 'strain', 'ReportEnabled', true, 'GuiLabel', 'ε~ 动应变分析（低通+箱线图）', 'PresetField', 'dynlowpass'), ...
                S('offset_correction_report','', 'offset_correction_report','', 'postprocess', 'BridgeScoped', false) ...
                ];
        end

        function specs = enabledFromOptions(opts)
            all = bms.module.ModuleRegistry.catalog();
            specs = bms.module.ModuleSpec.empty();
            for i = 1:numel(all)
                if all(i).isEnabled(opts)
                    specs(end+1) = all(i); %#ok<AGROW>
                end
            end
        end

        function names = enabledKeys(opts)
            specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
            names = arrayfun(@(s) s.Key, specs, 'UniformOutput', false);
        end

        function spec = fromKey(key)
            key = char(key);
            specs = bms.module.ModuleRegistry.catalog();
            spec = bms.module.ModuleSpec(key, '', key, '', 'analysis');
            for i = 1:numel(specs)
                if strcmp(specs(i).Key, key)
                    spec = specs(i);
                    return;
                end
            end
        end

        function spec = fromLabel(label)
            label = char(label);
            specs = bms.module.ModuleRegistry.catalog();
            spec = bms.module.ModuleSpec('', '', label, '', 'analysis');
            for i = 1:numel(specs)
                if strcmp(specs(i).Label, label)
                    spec = specs(i);
                    return;
                end
            end
        end

        function spec = fromOptField(optField)
            optField = char(optField);
            specs = bms.module.ModuleRegistry.catalog();
            spec = bms.module.ModuleSpec('', optField, optField, '', 'analysis');
            for i = 1:numel(specs)
                if strcmp(specs(i).OptField, optField)
                    spec = specs(i);
                    return;
                end
            end
        end

        function specs = forCategory(category)
            all = bms.module.ModuleRegistry.catalog();
            specs = bms.module.ModuleSpec.empty();
            for i = 1:numel(all)
                if strcmp(all(i).Category, category)
                    specs(end+1) = all(i); %#ok<AGROW>
                end
            end
        end

        function paths = expectedStatsFiles(statsDir, opts)
            specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
            paths = {};
            for i = 1:numel(specs)
                p = specs(i).statsPath(statsDir);
                if ~isempty(p)
                    paths{end+1} = p; %#ok<AGROW>
                end
            end
        end

        function report = preflight(statsDir, opts)
            specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
            report = {};
            for i = 1:numel(specs)
                p = specs(i).statsPath(statsDir);
                if isempty(p)
                    continue;
                end
                rec = specs(i).toStruct(statsDir);
                rec.exists = isfile(p);
                if rec.exists
                    rec.status = 'ok';
                    rec.message = '';
                else
                    rec.status = 'missing';
                    rec.message = ['Expected stats file not found: ' p];
                end
                report{end+1} = rec; %#ok<AGROW>
            end
        end

        function rows = guiRows(category)
            specs = bms.module.ModuleRegistry.forCategory(category);
            rows = {};
            for i = 1:numel(specs)
                if isempty(specs(i).OptField)
                    continue;
                end
                rows{end+1} = specs(i).toStruct(''); %#ok<AGROW>
            end
        end

        function opts = optsFromHandles(handleMap)
            opts = struct();
            specs = bms.module.ModuleRegistry.catalog();
            for i = 1:numel(specs)
                opt = specs(i).OptField;
                guiField = specs(i).GuiField;
                if isempty(opt) || isempty(guiField)
                    continue;
                end
                opts.(opt) = false;
                if isstruct(handleMap) && isfield(handleMap, guiField)
                    h = handleMap.(guiField);
                    if isvalid(h)
                        opts.(opt) = logical(h.Value);
                    end
                end
            end
        end

        function fields = knownConfigKeys()
            specs = bms.module.ModuleRegistry.catalog();
            fields = {};
            for i = 1:numel(specs)
                fields = [fields, {specs(i).Key, specs(i).SubfolderKey}]; %#ok<AGROW>
            end
            fields = [fields, {'temp_humidity','acceleration_raw','cable_force','cable_accel_raw','wind_raw','eq_raw','eq','dynamic_strain','accel_spectrum','cable_accel_spectrum'}];
            fields = unique(fields(~cellfun(@isempty, fields)), 'stable');
        end

        function structs = toStructArray(specs, statsDir)
            if nargin < 2, statsDir = ''; end
            structs = {};
            for i = 1:numel(specs)
                structs{end+1} = specs(i).toStruct(statsDir); %#ok<AGROW>
            end
        end
    end
end
