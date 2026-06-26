classdef ModuleRegistry
    %MODULEREGISTRY Single source of truth for analysis module metadata.

    methods (Static)
        function specs = catalog()
            S = @bms.module.ModuleSpec;
            specs = [ ...
                S('zip_precheck','precheck_zip_count','预检查压缩包数量','', 'preprocess', 'BridgeScoped', false, 'GuiLabel', '预检查压缩包数量', 'PresetField', 'precheck'), ...
                S('unzip','doUnzip','批量解压','', 'preprocess', 'BridgeScoped', false, 'PresetField', 'unzip'), ...
                S('rename_csv','doRenameCsv','批量重命名CSV','', 'preprocess', 'BridgeScoped', false, 'PresetField', 'rename'), ...
                S('remove_header','doRemoveHeader','批量去除表头','', 'preprocess', 'BridgeScoped', false, 'PresetField', 'rmheader'), ...
                S('resample','doResample','批量重采样','', 'preprocess', 'BridgeScoped', false, 'PresetField', 'resample'), ...
                S('temperature','doTemp','温度分析','temp_stats.xlsx', 'analysis', 'SubfolderKey', 'temperature', 'ReportEnabled', true, 'GuiLabel', '🌡 温度分析'), ...
                S('humidity','doHumidity','湿度分析','humidity_stats.xlsx', 'analysis', 'SubfolderKey', 'humidity', 'ReportEnabled', true, 'GuiLabel', '💧 湿度分析'), ...
                S('rainfall','doRainfall','雨量分析','rainfall_stats.xlsx', 'analysis', 'SubfolderKey', 'rainfall', 'ReportEnabled', true, 'GuiLabel', '🌧 雨量分析'), ...
                S('gnss','doGNSS','GNSS分析','gnss_stats.xlsx', 'analysis', 'SubfolderKey', 'gnss', 'ReportEnabled', true, 'GuiLabel', '🛰️ GNSS分析'), ...
                S('wind','doWind','风速风向分析','wind_stats.xlsx', 'analysis', 'SubfolderKey', 'wind_raw', 'ReportEnabled', true, 'GuiLabel', '🌀 风速风向分析'), ...
                S('earthquake','doEq','地震动分析','eq_stats.xlsx', 'analysis', 'SubfolderKey', 'eq_raw', 'ReportEnabled', true, 'PresetField', 'eq', 'GuiLabel', '📳 地震动分析'), ...
                S('wim','doWIM','WIM','', 'analysis', 'SubfolderKey', 'wim', 'ReportEnabled', true, 'GuiLabel', '🚚 WIM'), ...
                S('deflection','doDeflect','挠度分析','deflection_stats.xlsx', 'analysis', 'SubfolderKey', 'deflection', 'ReportEnabled', true, 'PresetField', 'deflect', 'GuiLabel', '↕ 挠度分析'), ...
                S('bearing_displacement','doBearingDisplacement','支座位移分析','bearing_displacement_stats.xlsx', 'analysis', 'SubfolderKey', 'bearing_displacement', 'ReportEnabled', true, 'GuiLabel', '↔ 支座位移分析'), ...
                S('tilt','doTilt','倾角分析','tilt_stats.xlsx', 'analysis', 'SubfolderKey', 'tilt', 'ReportEnabled', true, 'GuiLabel', '📐 倾角分析'), ...
                S('acceleration','doAccel','加速度分析','accel_stats.xlsx', 'analysis', 'SubfolderKey', 'acceleration', 'ReportEnabled', true, 'HighMemoryRisk', true, 'PresetField', 'accel', 'GuiLabel', '📈 加速度分析'), ...
                S('cable_accel','doCableAccel','索力加速度分析','cable_accel_stats.xlsx', 'analysis', 'SubfolderKey', 'cable_accel', 'ReportEnabled', true, 'HighMemoryRisk', true, 'GuiLabel', '〰 索力加速度分析'), ...
                S('accel_spectrum','doAccelSpectrum','加速度频谱','accel_spec_stats.xlsx', 'analysis', 'SubfolderKey', 'acceleration_raw', 'ReportEnabled', true, 'HighMemoryRisk', true, 'SupportsSpectrum', true, 'PresetField', 'spec', 'GuiLabel', '📶 加速度频谱'), ...
                S('cable_accel_spectrum','doCableAccelSpectrum','索力加速度频谱','cable_accel_spec_stats.xlsx', 'analysis', 'SubfolderKey', 'cable_accel_raw', 'ReportEnabled', true, 'HighMemoryRisk', true, 'SupportsSpectrum', true, 'PresetField', 'cable_spec', 'GuiLabel', '📶 索力加速度频谱'), ...
                S('rename_crk','doRenameCrk','裂缝重命名','', 'preprocess', 'BridgeScoped', false), ...
                S('crack','doCrack','裂缝分析','crack_stats.xlsx', 'analysis', 'SubfolderKey', 'crack', 'ReportEnabled', true, 'GuiLabel', '⚡ 裂缝分析'), ...
                S('strain','doStrain','应变分析','strain_stats.xlsx', 'analysis', 'SubfolderKey', 'strain', 'ReportEnabled', true, 'GuiLabel', 'ε 应变分析'), ...
                S('dynamic_strain_highpass','doDynStrainBoxplot','动应变分析（高通+箱线图）','dynamic_strain_highpass_stats.xlsx', 'analysis', 'SubfolderKey', 'strain', 'ReportEnabled', true, 'GuiLabel', 'ε~ 动应变分析（高通+箱线图）', 'PresetField', 'dynbox'), ...
                S('dynamic_strain_lowpass','doDynStrainLowpassBoxplot','动应变分析（低通+箱线图）','dynamic_strain_lowpass_stats.xlsx', 'analysis', 'SubfolderKey', 'strain', 'ReportEnabled', true, 'GuiLabel', 'ε~ 动应变分析（低通+箱线图）', 'PresetField', 'dynlowpass'), ...
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
